#!/usr/bin/env python3
"""Take a screenshot from a running GDB-patched FS-UAE.

Connects to the emulator's GDB server and issues the `screenshot`
monitor command. NOTE: the server accepts only ONE session per emulator
launch — do not use this while another GDB client (e.g. gdb itself) is
attached; issue `monitor screenshot <path>` from that client instead.

Usage: screenshot.py <output.png> [--port 2345] [--boot-wait 0]
"""

import argparse
import binascii
import socket
import time


def packet(payload: str) -> bytes:
    checksum = sum(payload.encode()) % 256
    return b"$" + payload.encode() + b"#" + f"{checksum:02x}".encode()


def send(sock: socket.socket, payload: str) -> bytes:
    sock.sendall(b"+" + packet(payload))
    time.sleep(0.5)
    try:
        return sock.recv(8192)
    except TimeoutError:
        return b""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", help="absolute path for the PNG")
    parser.add_argument("--port", type=int, default=2345)
    parser.add_argument(
        "--boot-wait",
        type=float,
        default=0,
        help="seconds to let emulation run before capturing",
    )
    args = parser.parse_args()

    sock = socket.create_connection(("localhost", args.port), timeout=5)
    sock.settimeout(4)
    send(sock, "qSupported")
    send(sock, "vCont;c")  # resume — emulator halts while awaiting GDB
    if args.boot_wait:
        time.sleep(args.boot_wait)
    cmd = f"screenshot {args.output}"
    reply = send(sock, "qRcmd," + binascii.hexlify(cmd.encode()).decode())
    if b"OK" in reply:
        print(f"saved: {args.output}")
    else:
        raise SystemExit(f"screenshot failed, reply: {reply!r}")
    sock.close()


if __name__ == "__main__":
    main()
