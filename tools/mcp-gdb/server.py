"""
GDB-RSP MCP server for Amiga demo debugging with GDB-patched FS-UAE.

Adapted from mariposa-2 tools/mcp-gdb, but speaks the GDB Remote Serial
Protocol directly over a socket instead of driving a gdb binary: the
FS-UAE gdbserver (barto_gdbserver, built for VSCode's JS debug clients)
violates the RSP spec — it replies E01 to vMustReplyEmpty — which makes
real GDB >= 8 abort the connection.

Tools:
  debug_start    - Launch FS-UAE (gdbserver :2345), connect, optionally boot
  debug_stop     - Kill session. Idempotent.
  registers      - Read CPU registers (d0-d7, a0-a7, sr, pc)
  read_memory    - Hex dump of emulated memory
  write_memory   - Write hex bytes to emulated memory
  breakpoint     - Set/clear breakpoint at address
  step           - Single-step one instruction
  cont           - Resume execution
  interrupt      - Halt a running target
  monitor        - gdbserver monitor command (screenshot/profile/console/dumpdma)
  screenshot     - Capture display to PNG (wraps monitor screenshot)
  emulator_log   - Tail the FS-UAE log

FS-UAE gdbserver quirks (see project journal.md):
  - ONE session per emulator launch; server never re-listens after
    disconnect. Everything must flow through this persistent connection.
  - Emulator starts halted waiting for GDB (up to 200s); continue boots.
"""

import atexit
import binascii
import os
import queue
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Paths & constants
# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).parent.parent.parent
FSUAE_BIN = PROJECT_ROOT / "tools" / "fs-uae-gdb" / "fs-uae-darwin_x64"
KICKSTART = (
    PROJECT_ROOT / "kickstart" / "Kickstart v3.1 rev 40.68 (1993)(Commodore)(A1200).rom"
)
GDB_PORT = 2345
PID_FILE = Path("/tmp/fsuae_debug.pid")
FSUAE_LOG = Path.home() / "Documents" / "FS-UAE" / "Cache" / "Logs" / "fs-uae.log.txt"

REG_NAMES = [
    "d0",
    "d1",
    "d2",
    "d3",
    "d4",
    "d5",
    "d6",
    "d7",
    "a0",
    "a1",
    "a2",
    "a3",
    "a4",
    "a5",
    "a6",
    "a7",
    "sr",
    "pc",
]

mcp = FastMCP("demo-fable-gdb")

# ---------------------------------------------------------------------------
# Global session state
# ---------------------------------------------------------------------------

_emu_proc: subprocess.Popen | None = None
_sock: socket.socket | None = None
_rx_queue: queue.Queue = queue.Queue()  # parsed packet payloads (str)
_rx_thread: threading.Thread | None = None
_lock = threading.Lock()  # serialises command/response cycles
_running = False  # target running (no stop reply yet)


# ---------------------------------------------------------------------------
# RSP framing
# ---------------------------------------------------------------------------


def _checksum(payload: bytes) -> bytes:
    return f"{sum(payload) % 256:02x}".encode()


def _frame(payload: str) -> bytes:
    p = payload.encode()
    return b"$" + p + b"#" + _checksum(p)


def _rx_loop(sock: socket.socket, q: queue.Queue) -> None:
    """Parse $...#xx frames from the socket into the queue until EOF."""
    buf = b""
    try:
        while True:
            data = sock.recv(4096)
            if not data:
                break
            buf += data
            while True:
                start = buf.find(b"$")
                if start < 0:
                    buf = b""
                    break
                hash_pos = buf.find(b"#", start)
                if hash_pos < 0 or len(buf) < hash_pos + 3:
                    buf = buf[start:]
                    break
                payload = buf[start + 1 : hash_pos]
                buf = buf[hash_pos + 3 :]
                try:
                    sock.sendall(b"+")  # ack
                except OSError:
                    pass
                q.put(payload.decode(errors="replace"))
    except Exception:
        pass
    finally:
        q.put(None)  # EOF sentinel


def _drain_rx(wait: float = 0.1) -> list[str]:
    got = []
    deadline = time.monotonic() + wait
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            item = _rx_queue.get(timeout=remaining)
        except queue.Empty:
            break
        if item is None:
            _rx_queue.put(None)
            break
        got.append(item)
    return got


def _decode_o_packet(p: str) -> str:
    """O<hex> = console output from the stub."""
    try:
        return binascii.unhexlify(p[1:]).decode(errors="replace")
    except Exception:
        return p


def _send_packet(payload: str, timeout: float = 10.0, expect_reply: bool = True) -> str:
    """
    Send one RSP packet, return first non-'O' reply payload.
    Interleaved O packets (console output) are prepended, hex-decoded.
    Must be called with _lock held.
    """
    if _sock is None:
        raise RuntimeError("Not connected. Call debug_start first.")
    _sock.sendall(_frame(payload))
    if not expect_reply:
        return ""
    console: list[str] = []
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            text = "".join(console)
            return (text + f"\n[timed out after {timeout:.0f}s]").strip()
        try:
            item = _rx_queue.get(timeout=min(remaining, 0.5))
        except queue.Empty:
            continue
        if item is None:
            _rx_queue.put(None)
            raise RuntimeError("Connection closed by emulator")
        if item.startswith("O") and item != "OK":
            console.append(_decode_o_packet(item))
            continue
        prefix = "".join(console)
        return (prefix + item) if prefix else item


def _stop_reply_pending(timeout: float) -> str | None:
    """Wait for a stop reply (S/T/W packet). Returns payload or None."""
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None
        try:
            item = _rx_queue.get(timeout=min(remaining, 0.5))
        except queue.Empty:
            continue
        if item is None:
            _rx_queue.put(None)
            return None
        if item and item[0] in "STW":
            return item
        # ignore O packets etc. while waiting


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------


def _kill_emu_pid_file() -> None:
    if not PID_FILE.exists():
        return
    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, signal.SIGTERM)
        time.sleep(0.3)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    except (ValueError, ProcessLookupError, PermissionError):
        pass
    try:
        PID_FILE.unlink()
    except FileNotFoundError:
        pass


def _cleanup_all() -> None:
    global _emu_proc, _sock, _rx_thread, _running
    if _sock is not None:
        try:
            _sock.close()
        except OSError:
            pass
        _sock = None
    if _emu_proc is not None and _emu_proc.poll() is None:
        _emu_proc.terminate()
        try:
            _emu_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            _emu_proc.kill()
            _emu_proc.wait()
    _emu_proc = None
    _rx_thread = None
    _running = False
    _kill_emu_pid_file()
    while not _rx_queue.empty():
        try:
            _rx_queue.get_nowait()
        except queue.Empty:
            break


atexit.register(_cleanup_all)


def _signal_handler(sig, frame):  # noqa: ANN001
    _cleanup_all()
    sys.exit(0)


signal.signal(signal.SIGTERM, _signal_handler)
signal.signal(signal.SIGINT, _signal_handler)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _require_connected() -> str | None:
    if _sock is None:
        return "Error: no session. Call debug_start first."
    return None


def _parse_addr(addr: str) -> int:
    return int(addr, 16) if addr.lower().startswith("0x") else int(addr, 0)


def _halt_if_running() -> str | None:
    """Send break (0x03) if target running. Returns stop reply or None."""
    global _running
    if not _running or _sock is None:
        return None
    _sock.sendall(b"\x03")
    reply = _stop_reply_pending(timeout=5.0)
    if reply is not None:
        _running = False
    return reply


# ---------------------------------------------------------------------------
# MCP tools
# ---------------------------------------------------------------------------


@mcp.tool()
def debug_start(boot: bool = True, extra_args: str = "") -> str:
    """
    Launch FS-UAE (A1200 kickstart, gdbserver on :2345) and connect.

    Args:
        boot: If True (default), resume CPU after connecting so kickstart
              boots. If False, leave CPU halted at reset entry.
        extra_args: Extra FS-UAE CLI args, space-separated
                    (e.g. '--floppy_drive_0=/abs/demo.adf')
    """
    global _emu_proc, _sock, _rx_thread, _running

    if not FSUAE_BIN.exists():
        return f"Error: emulator not found: {FSUAE_BIN}"
    if not KICKSTART.exists():
        return f"Error: kickstart ROM not found: {KICKSTART}"

    _cleanup_all()

    emu_cmd = [
        str(FSUAE_BIN),
        "--amiga_model=A1200",
        f"--kickstart_file={KICKSTART}",
        "--fast_memory=4096",
        "--floppy_drive_speed=0",
        "--remote_debugger=200",
        f"--remote_debugger_port={GDB_PORT}",
    ]
    if extra_args:
        emu_cmd += extra_args.split()

    _emu_proc = subprocess.Popen(
        emu_cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=str(FSUAE_BIN.parent),
    )
    PID_FILE.write_text(str(_emu_proc.pid))

    # Wait for the gdbserver to bind (Rosetta startup is slow)
    last_err = None
    for _ in range(30):
        time.sleep(0.5)
        if _emu_proc.poll() is not None:
            return f"Error: FS-UAE exited immediately (rc={_emu_proc.returncode})"
        try:
            _sock = socket.create_connection(("127.0.0.1", GDB_PORT), timeout=2)
            break
        except OSError as e:
            last_err = e
    else:
        _cleanup_all()
        return f"Error: could not connect to gdbserver :{GDB_PORT}: {last_err}"

    _sock.settimeout(None)  # connect-timeout mode would kill the rx thread
    _sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    _rx_thread = threading.Thread(target=_rx_loop, args=(_sock, _rx_queue), daemon=True)
    _rx_thread.start()

    with _lock:
        supported = _send_packet("qSupported", timeout=5.0)
        status = _send_packet("?", timeout=5.0)
        boot_note = ""
        if boot:
            _sock.sendall(_frame("vCont;c"))
            _running = True
            boot_note = "\nBooting kickstart (target running)"

    return (
        f"Session started: FS-UAE PID={_emu_proc.pid}, connected on :{GDB_PORT}\n"
        f"Stub: {supported}\nInitial status: {status}{boot_note}"
    )


@mcp.tool()
def debug_stop() -> str:
    """Stop the FS-UAE debug session. Idempotent."""
    was_active = _sock is not None or (
        _emu_proc is not None and _emu_proc.poll() is None
    )
    _cleanup_all()
    return "Session stopped" if was_active else "No session was running"


@mcp.tool()
def registers() -> str:
    """Read CPU registers (halts a running target first, stays halted)."""
    err = _require_connected()
    if err:
        return err
    with _lock:
        _halt_if_running()
        raw = _send_packet("g", timeout=5.0)
    if raw.startswith("E") and len(raw) <= 3:
        return f"Error: stub replied {raw}"
    out = []
    for i in range(0, min(len(raw) // 8, len(REG_NAMES))):
        val = raw[i * 8 : (i + 1) * 8]
        out.append(f"{REG_NAMES[i]} = 0x{val}")
    extra = len(raw) // 8 - len(REG_NAMES)
    if extra > 0:
        out.append(f"(+{extra} additional stub registers)")
    return "\n".join(out) if out else f"(unparsed: {raw[:64]}...)"


@mcp.tool()
def read_memory(address: str, length: int = 64) -> str:
    """
    Read emulated memory, hex dump.

    Args:
        address: Hex address (e.g. '0xdff000', '0x400')
        length:  Bytes to read (max 512 per stub PacketSize)
    """
    err = _require_connected()
    if err:
        return err
    addr = _parse_addr(address)
    length = min(max(1, length), 512)
    with _lock:
        _halt_if_running()
        raw = _send_packet(f"m{addr:x},{length:x}", timeout=5.0)
    if raw.startswith("E") and len(raw) <= 3:
        return f"Error: stub replied {raw}"
    lines = []
    for off in range(0, len(raw), 32):  # 16 bytes/line
        chunk = raw[off : off + 32]
        pairs = " ".join(chunk[i : i + 2] for i in range(0, len(chunk), 2))
        lines.append(f"{addr + off // 2:08x}: {pairs}")
    return "\n".join(lines)


@mcp.tool()
def write_memory(address: str, hex_bytes: str) -> str:
    """
    Write bytes to emulated memory.

    Args:
        address:   Hex address
        hex_bytes: Hex string, no spaces (e.g. '4e75' = RTS)
    """
    err = _require_connected()
    if err:
        return err
    addr = _parse_addr(address)
    hex_bytes = hex_bytes.replace(" ", "").lower()
    n = len(hex_bytes) // 2
    with _lock:
        _halt_if_running()
        reply = _send_packet(f"M{addr:x},{n:x}:{hex_bytes}", timeout=5.0)
    return f"wrote {n} bytes at 0x{addr:x}: {reply}"


@mcp.tool()
def breakpoint(address: str, remove: bool = False) -> str:
    """
    Set or clear a software breakpoint.

    Args:
        address: Hex address
        remove:  True to clear instead of set
    """
    err = _require_connected()
    if err:
        return err
    addr = _parse_addr(address)
    cmd = "z0" if remove else "Z0"
    with _lock:
        reply = _send_packet(f"{cmd},{addr:x},2", timeout=5.0)
    verb = "cleared" if remove else "set"
    return f"breakpoint {verb} at 0x{addr:x}: {reply}"


@mcp.tool()
def step() -> str:
    """Single-step one instruction (halts a running target first)."""
    global _running
    err = _require_connected()
    if err:
        return err
    with _lock:
        _halt_if_running()
        _sock.sendall(_frame("vCont;s"))
        reply = _stop_reply_pending(timeout=5.0)
        if reply is None:
            _running = True
            return "[no stop reply — target may be running]"
        pc = _send_packet("p11", timeout=3.0)  # reg 17 = pc
    return f"stepped: {reply}, pc = 0x{pc}"


@mcp.tool()
def cont(wait_stop: int = 0) -> str:
    """
    Resume execution.

    Args:
        wait_stop: Seconds to wait for a stop event (breakpoint hit).
                   0 = return immediately, target keeps running.
    """
    global _running
    err = _require_connected()
    if err:
        return err
    with _lock:
        _sock.sendall(_frame("vCont;c"))
        _running = True
        if wait_stop > 0:
            reply = _stop_reply_pending(timeout=float(min(wait_stop, 300)))
            if reply is not None:
                _running = False
                return f"stopped: {reply}"
            return f"[still running after {wait_stop}s]"
    return "running"


@mcp.tool()
def interrupt() -> str:
    """Halt a running target (like Ctrl-C in gdb)."""
    err = _require_connected()
    if err:
        return err
    with _lock:
        reply = _halt_if_running()
    if reply is None:
        return "target was not running (or no stop reply)"
    return f"halted: {reply}"


@mcp.tool()
def monitor(command: str) -> str:
    """
    Send a gdbserver monitor command.

    Known commands: 'screenshot <abs-path.png>', 'profile', 'console <cmd>',
    'dumpdma'. 'console' gives access to the full WinUAE debugger command
    set (memory search, copper disassembly, custom chip state, etc.).
    """
    err = _require_connected()
    if err:
        return err
    hexed = binascii.hexlify(command.encode()).decode()
    with _lock:
        reply = _send_packet(f"qRcmd,{hexed}", timeout=15.0)
    return reply or "(no reply)"


@mcp.tool()
def screenshot(path: str = "") -> str:
    """
    Capture the emulator display to a PNG.

    Args:
        path: Absolute output path. Empty = screenshots/capture.png
              in the project root.
    """
    err = _require_connected()
    if err:
        return err
    out_path = Path(path) if path else PROJECT_ROOT / "screenshots" / "capture.png"
    if not out_path.is_absolute():
        out_path = PROJECT_ROOT / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    hexed = binascii.hexlify(f"screenshot {out_path}".encode()).decode()
    with _lock:
        reply = _send_packet(f"qRcmd,{hexed}", timeout=10.0)
    if "OK" not in reply:
        return f"Error: stub replied {reply!r}"
    for _ in range(20):
        if out_path.exists():
            return f"saved: {out_path}"
        time.sleep(0.2)
    return f"Error: stub said OK but no file at {out_path}"


@mcp.tool()
def emulator_log(lines: int = 50, grep: str = "") -> str:
    """
    Return the last N lines of the FS-UAE log.

    Args:
        lines: Number of lines to return (default 50)
        grep:  Optional case-insensitive substring filter
               (e.g. 'GDBSERVER' for the packet trace)
    """
    if not FSUAE_LOG.exists():
        return f"(log not found: {FSUAE_LOG})"
    content = FSUAE_LOG.read_text(errors="replace")
    all_lines = content.splitlines()
    if grep:
        all_lines = [ln for ln in all_lines if grep.lower() in ln.lower()]
    if not all_lines:
        return "(no matching lines)"
    return "\n".join(all_lines[-lines:])


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run()
