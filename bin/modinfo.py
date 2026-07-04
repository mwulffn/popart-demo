#!/usr/bin/env python3
"""modinfo.py — ProTracker MOD analyzer.

Prints title, format, channels, sample table, pattern count, song length,
and estimated playtime (simulates speed/tempo/jump/break commands).
Used to vet music candidates and to plan demo sync points.

Usage: modinfo.py file.mod [--rows] [--sync]
  --rows  dump per-position pattern numbers
  --sync  print cumulative time at each song position (for scene sync)
"""

import struct
import sys


def parse(path: str) -> dict:
    data = open(path, "rb").read()
    magic = data[1080:1084]
    if magic not in (b"M.K.", b"M!K!", b"4CHN", b"FLT4"):
        raise SystemExit(f"{path}: not a 4-channel ProTracker MOD (magic={magic!r})")
    title = data[0:20].rstrip(b"\0").decode("latin-1")
    samples = []
    off = 20
    for _ in range(31):
        name = data[off : off + 22].rstrip(b"\0 ").decode("latin-1", "replace")
        length = struct.unpack(">H", data[off + 22 : off + 24])[0] * 2
        finetune = data[off + 24] & 0x0F
        volume = data[off + 25]
        rep_start = struct.unpack(">H", data[off + 26 : off + 28])[0] * 2
        rep_len = struct.unpack(">H", data[off + 28 : off + 30])[0] * 2
        samples.append((name, length, finetune, volume, rep_start, rep_len))
        off += 30
    song_len = data[950]
    positions = list(data[952 : 952 + 128])[:song_len]
    npat = max(positions) + 1 if positions else 0
    return {
        "title": title,
        "magic": magic.decode(),
        "samples": samples,
        "song_len": song_len,
        "positions": positions,
        "npat": npat,
        "patterns": data[1084 : 1084 + npat * 1024],
        "sample_bytes": sum(s[1] for s in samples),
        "file_size": len(data),
    }


def playtime(mod: dict) -> tuple[float, list[float]]:
    """Simulate playback order. Returns (total_seconds, seconds_at_position[])."""
    speed, bpm = 6, 125
    pos, row = 0, 0
    t = 0.0
    pos_times = [0.0] * len(mod["positions"])
    visited = set()
    while pos < len(mod["positions"]):
        if (pos, row) in visited:  # loop detected
            break
        visited.add((pos, row))
        if row == 0:
            pos_times[pos] = t
        pat = mod["positions"][pos]
        base = pat * 1024 + row * 16
        jump_pos, jump_row = None, None
        for ch in range(4):
            cell = mod["patterns"][base + ch * 4 : base + ch * 4 + 4]
            if len(cell) < 4:
                return t, pos_times
            eff = ((cell[2] & 0x0F) << 8) | cell[3]
            cmd, arg = eff >> 8, eff & 0xFF
            if cmd == 0xF:
                if arg == 0:
                    pass
                elif arg <= 0x1F:
                    speed = arg
                else:
                    bpm = arg
            elif cmd == 0xB:
                jump_pos, jump_row = arg, 0
            elif cmd == 0xD:
                jump_pos = pos + 1 if jump_pos is None else jump_pos
                jump_row = (arg >> 4) * 10 + (arg & 0x0F)
        t += speed * 2.5 / bpm  # one row = speed ticks, tick = 2.5/bpm s
        if jump_pos is not None:
            pos, row = jump_pos, min(jump_row or 0, 63)
        else:
            row += 1
            if row == 64:
                row, pos = 0, pos + 1
    return t, pos_times


def main() -> None:
    path = sys.argv[1]
    mod = parse(path)
    total, pos_times = playtime(mod)
    print(f"title    : {mod['title']!r}")
    print(f"format   : {mod['magic']} (4ch)")
    print(f"file     : {mod['file_size']} bytes ({mod['file_size'] / 1024:.1f} KB)")
    print(f"samples  : {mod['sample_bytes']} bytes in "
          f"{sum(1 for s in mod['samples'] if s[1] > 0)} used slots")
    print(f"song     : {mod['song_len']} positions, {mod['npat']} patterns")
    print(f"playtime : {total:.1f} s ({int(total // 60)}:{int(total % 60):02d})")
    if "--rows" in sys.argv:
        print("order    :", " ".join(str(p) for p in mod["positions"]))
    if "--sync" in sys.argv:
        for i, (p, tt) in enumerate(zip(mod["positions"], pos_times)):
            print(f"  pos {i:3d}  pat {p:3d}  t={tt:7.2f}s")
    if "--samples" in sys.argv:
        for i, (name, length, ft, vol, rs, rl) in enumerate(mod["samples"]):
            if length:
                print(f"  s{i + 1:02d} {length:6d}b vol={vol:2d} "
                      f"loop={rs}+{rl} {name!r}")


if __name__ == "__main__":
    main()
