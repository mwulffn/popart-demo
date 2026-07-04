# mcp-gdb — Amiga demo debug MCP server

Manages the FS-UAE + GDB-remote debug session lifecycle for this project.
Adapted from `mariposa-2/tools/mcp-gdb` (QEMU m68k kernel version).

## Why speak RSP directly (no gdb binary)?

The FS-UAE gdbserver (`barto_gdbserver.cpp`, built for VSCode's JS debug
clients) violates the GDB Remote Serial Protocol: it replies `E01` to
`vMustReplyEmpty`, which makes real GDB >= 8 abort the connection
("Remote replied unexpectedly"). A packet-fixing proxy was tried and hit
further incompatibilities. This server therefore implements a minimal RSP
client over a plain socket — every needed operation (registers, memory,
breakpoints, step, monitor commands) was verified working raw.

Inherited from the mariposa version: process lifecycle management
(atexit/signal cleanup, PID file), lock-serialised command cycles,
background reader thread, timeouts that return partial output without
killing the session.

## Why a persistent server matters here

The FS-UAE gdbserver accepts **one connection per emulator launch** and
never re-listens after disconnect. This MCP server holds that single
connection open across tool calls — including screenshots, which go
through the same channel (`monitor screenshot`).

## Tools

| Tool | Description |
|------|-------------|
| `debug_start(boot, extra_args)` | Launch FS-UAE (gdbserver :2345), connect; `boot=True` resumes CPU |
| `debug_stop()` | Kill session. Idempotent. |
| `registers()` | d0-d7, a0-a7, sr, pc (halts target first) |
| `read_memory(address, length)` | Hex dump (max 512 bytes/call) |
| `write_memory(address, hex_bytes)` | Poke memory |
| `breakpoint(address, remove)` | Set/clear software breakpoint |
| `step()` | Single instruction step |
| `cont(wait_stop)` | Resume; optionally wait for breakpoint hit |
| `interrupt()` | Halt running target (0x03 break byte) |
| `monitor(command)` | `screenshot <path>` / `profile` / `console <uae-dbg-cmd>` / `dumpdma` |
| `wait_beacon(value, address, timeout)` | Run until word `value` written to `address` (default $664 songpos beacon). UAE memory watchpoint with value match — deterministic scene-position capture, no wall-clock polling. Halt lands before that frame's scene update. |
| `screenshot(path)` | Display → PNG, works while target runs |
| `emulator_log(lines, grep)` | Tail FS-UAE log (`grep='GDBSERVER'` = packet trace) |

## Setup

```sh
uv sync --directory tools/mcp-gdb

claude mcp add --scope local gdb -- \
  uv run --directory /Users/wulff/Projects/demo-fable/tools/mcp-gdb python server.py
```

## Stub quirks learned the hard way

- `vMustReplyEmpty` → `E01` (spec violation; why real GDB is unusable)
- Non-monitor packets (`g` etc.) sent while the target **runs** confuse
  the stub state machine → disconnect. Tools halt the target first.
  `qRcmd` (monitor/screenshot) is safe while running.
- Interrupt = raw `0x03` byte, replied with `S05`.
- The stub processes one request per TCP chunk — never batch packets.
- Client sockets must not be in Python timeout mode (the rx thread dies
  on `socket.timeout`); `settimeout(None)` after `create_connection`.
