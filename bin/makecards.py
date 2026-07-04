#!/usr/bin/env python3
"""makecards.py — scene 6 credit cards: 3x 320x256 1-bit pages.

Silkscreen-style credit typography; the 2px/1px misregistration halo is
done in HARDWARE at runtime (two bitplane pointers into the same plane,
odd/even BPLCON1 scroll), so cards are single-plane. Output:
build/art/cards.bpl (3 pages concatenated) + cards.i.
"""

from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
W, H = 320, 256

CARDS = [
    [(46, "POPART", 60),
     (13, "A DEMO IN NINE PRINT RUNS", 150)],
    [(17, "MUSIC", 20),
     (13, '"DANCINONAMIGA" BY KATIE CADET', 48),
     (11, "PUBLIC DOMAIN - THE MOD ARCHIVE", 68),
     (17, "CODE + DIRECTION", 98),
     (13, "CLAUDE (FABLE 5)", 126),
     (17, "PRODUCER", 156),
     (13, "MICHAEL WULFF NIELSEN", 184),
     (9, "PRESS: VASM VLINK PTPLAYER (FRANK WILLE)", 220)],
    [(15, "THE IMAGE IS THE COPY", 60),
     (15, "THE COPY IS THE IMAGE", 92),
     (21, "POPART  2026", 150),
     (9, "MASS-PRODUCED ON ONE FLOPPY - RESET TO EXIT", 224)],
]

out = bytearray()
for card in CARDS:
    img = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(img)
    for size, text, y in card:
        f = ImageFont.truetype(FONT, size)
        bbox = d.textbbox((0, 0), text, font=f)
        d.text(((W - bbox[2] + bbox[0]) // 2 - bbox[0], y - bbox[1]),
               text, font=f, fill=1)
    px = img.load()
    for y in range(H):
        for xb in range(W // 8):
            b = 0
            for i in range(8):
                if px[xb * 8 + i, y]:
                    b |= 0x80 >> i
            out.append(b)

open("build/art/cards.bpl", "wb").write(out)
with open("build/art/cards.i", "w") as f:
    f.write("CARD_SIZE\tequ\t40*256\nNCARDS\t\tequ\t3\n")
print(f"cards.bpl: {len(out)} bytes")
