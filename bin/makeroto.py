#!/usr/bin/env python3
"""makeroto.py — scene 3B assets.

build/art/floppytex.chk — 128x128 chunky (1 byte/px, values 0-15):
  the floppy print quantized to the scene-2 palette (floppy.i), so the
  rotozoomed world shares palette banks with the Warhol grid (BPLCON4
  variant flashes work on it unchanged).
build/art/sinw.i — 256-entry signed word sine, -256..256 (rotozoom
  delta math, 8.8 fixed point).
"""

import math

from PIL import Image

# scene-2 palette from floppy.i
pal = []
for line in open("build/art/floppy.i"):
    if line.strip().startswith("dc.w"):
        pal += [int(v.strip().lstrip("$"), 16)
                for v in line.split("dc.w")[1].split(",")]
pal_rgb = [((v >> 8 & 15) * 17, (v >> 4 & 15) * 17, (v & 15) * 17)
           for v in pal]

img = Image.open("assets/floppy-src.png").convert("RGB").resize(
    (128, 128), Image.LANCZOS)
px = img.load()
# 256-byte row stride, each row stored TWICE side by side: u wraps for
# free via its 8-bit int part, v row base is (v & $7f00) — no shifts
# in the rotozoom inner loop.
out = bytearray()
for y in range(128):
    row = bytes(min(range(16), key=lambda i: sum(
        (a - c) ** 2 for a, c in zip(pal_rgb[i], px[x, y])))
        for x in range(128))
    out += row + row
open("build/art/floppytex.chk", "wb").write(out)

with open("build/art/sinw.i", "w") as f:
    f.write("; 256-entry signed sine, -256..256 (makeroto.py)\nsinw:\n")
    vals = [round(256 * math.sin(i * 2 * math.pi / 256)) for i in range(256)]
    for i in range(0, 256, 8):
        f.write("\tdc.w\t" + ",".join(str(v) for v in vals[i:i + 8]) + "\n")

print("floppytex.chk (16384 bytes), sinw.i written")
