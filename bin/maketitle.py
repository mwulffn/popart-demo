#!/usr/bin/env python3
"""maketitle.py — scene 1 assets: title stencil plane + halftone pass data.

Outputs:
  build/art/title.bpl   320x256 1-plane stencil: POP / ART + small print
  build/art/title.i     constants
  build/art/dotpass.i   8 print passes x 16 words: one 16px-pitch halftone
                        dot row pattern per screen row (mod 16). Passes
                        ordered coarse->fine (Bayer-ish) so the title
                        emerges like a silkscreen being worked.
"""

from PIL import Image, ImageDraw, ImageFont

W, H = 320, 256
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"

img = Image.new("1", (W, H), 0)
d = ImageDraw.Draw(img)

f_big = ImageFont.truetype(FONT, 118)
for text, y in (("POP", 8), ("ART", 116)):
    bbox = d.textbbox((0, 0), text, font=f_big)
    d.text(((W - bbox[2] + bbox[0]) // 2 - bbox[0], y - bbox[1]),
           text, font=f_big, fill=1)

f_small = ImageFont.truetype(FONT, 11)
line = "A MASS-PRODUCED AUDIOVISUAL PRODUCT"
bbox = d.textbbox((0, 0), line, font=f_small)
d.text(((W - bbox[2] + bbox[0]) // 2, 238), line, font=f_small, fill=1)

# pack to 1 bitplane
rowbytes = W // 8
data = bytearray()
px = img.load()
for y in range(H):
    for xb in range(rowbytes):
        b = 0
        for i in range(8):
            if px[xb * 8 + i, y]:
                b |= 0x80 >> i
        data.append(b)
open("build/art/title.bpl", "wb").write(data)

with open("build/art/title.i", "w") as f:
    f.write("TITLE_W\t\tequ\t320\nTITLE_H\t\tequ\t256\n"
            "TITLE_BPR\tequ\t40\nTITLE_SIZE\tequ\t40*256\n")

# halftone passes: 16x16 cell, dot at (ox,oy), radius grows over passes
ORDER = [(0, 0), (8, 8), (8, 0), (0, 8), (4, 4), (12, 12), (12, 4), (4, 12)]
R = [5.5, 5.0, 4.5, 4.5, 4.0, 4.0, 3.5, 3.5]

with open("build/art/dotpass.i", "w") as f:
    f.write("; 8 passes x 16 rows, one word per row (16px pitch pattern)\n"
            "dotpass_tab:\n")
    for p, (ox, oy) in enumerate(ORDER):
        words = []
        r = R[p]
        for row in range(16):
            w = 0
            for x in range(16):
                dx = min(abs(x - ox), 16 - abs(x - ox))
                dy = min(abs(row - oy), 16 - abs(row - oy))
                if dx * dx + dy * dy <= r * r:
                    w |= 0x8000 >> x
            words.append(w)
        f.write(f"\tdc.w\t" + ",".join(f"${w:04x}" for w in words) +
                f"\t; pass {p}\n")
print("title.bpl, title.i, dotpass.i written")
