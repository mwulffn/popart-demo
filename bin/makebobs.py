#!/usr/bin/env python3
"""makebobs.py — scene 4 burst bobs (POP! BANG! ZAP! WHAAM!).

Draws 4 comic starbursts at 96x64, quantized to the comic background's
own 32-color palette (parsed from build/art/comic.i) so cookie-cut
blits into the 5-plane screen look native. Emits:
  build/art/bobs.bpl   4 bobs, each 64 rows x 5 planes interleaved,
                       12 bytes/row  (3840 bytes per bob)
  build/art/bobs.msk   4 masks, 64 rows x 12 bytes (768 bytes per bob),
                       one mask row per PIXEL row (repeated per plane
                       at blit time via the A-channel? no — expanded:
                       stored interleaved x5 to match, 3840 per bob)
  build/art/bobs.i     constants
"""

import math
import re

from PIL import Image, ImageDraw, ImageFont

W, H = 96, 64
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
WORDS = ["POP!", "BANG!", "ZAP!", "WHAAM!"]

# parse comic palette
pal = []
for line in open("build/art/comic.i"):
    if line.strip().startswith("dc.w"):
        pal += [int(v.strip().lstrip("$"), 16)
                for v in line.split("dc.w")[1].split(",")]
pal_rgb = [((v >> 8 & 15) * 17, (v >> 4 & 15) * 17, (v & 15) * 17)
           for v in pal]


def nearest(rgb):
    return min(range(32), key=lambda i: sum(
        (a - b) ** 2 for a, b in zip(pal_rgb[i], rgb)))


IDX_BLACK = nearest((0, 0, 0))
IDX_WHITE = nearest((255, 255, 255))
IDX_YELLOW = nearest((255, 224, 0))
IDX_RED = nearest((221, 17, 17))

bpl_out = bytearray()
msk_out = bytearray()

for word in WORDS:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = W // 2, H // 2
    spikes = 13
    pts = []
    for i in range(spikes * 2):
        ang = i * math.pi / spikes - math.pi / 2
        rx, ry = (46, 30) if i % 2 == 0 else (30, 18)
        pts.append((cx + rx * math.cos(ang), cy + ry * math.sin(ang)))
    d.polygon(pts, fill=(255, 224, 0, 255), outline=(0, 0, 0, 255), width=3)
    size = 26 if len(word) <= 4 else (20 if len(word) <= 5 else 17)
    f = ImageFont.truetype(FONT, size)
    bbox = d.textbbox((0, 0), word, font=f)
    tx = cx - (bbox[2] - bbox[0]) // 2 - bbox[0]
    ty = cy - (bbox[3] - bbox[1]) // 2 - bbox[1]
    d.text((tx, ty), word, font=f, fill=(221, 17, 17, 255),
           stroke_width=2, stroke_fill=(0, 0, 0, 255))

    px = img.load()
    idx = [[None] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a >= 128:
                idx[y][x] = nearest((r, g, b))

    # interleaved 5-plane bob + matching interleaved mask
    for y in range(H):
        maskrow = bytearray(W // 8)
        planes = [bytearray(W // 8) for _ in range(5)]
        for x in range(W):
            v = idx[y][x]
            if v is None:
                continue
            maskrow[x // 8] |= 0x80 >> (x & 7)
            for p in range(5):
                if v >> p & 1:
                    planes[p][x // 8] |= 0x80 >> (x & 7)
        for p in range(5):
            bpl_out += planes[p]
            msk_out += maskrow      # same mask for every plane row

open("build/art/bobs.bpl", "wb").write(bpl_out)
open("build/art/bobs.msk", "wb").write(msk_out)
with open("build/art/bobs.i", "w") as f:
    f.write("BOB_W\t\tequ\t96\nBOB_H\t\tequ\t64\nBOB_BPR\t\tequ\t12\n"
            "BOB_BYTES\tequ\t12*64*5\t; interleaved 5 planes\n")
print(f"bobs: {len(bpl_out)} bytes, masks: {len(msk_out)} bytes, "
      f"idx black={IDX_BLACK} white={IDX_WHITE} yel={IDX_YELLOW} "
      f"red={IDX_RED}")
