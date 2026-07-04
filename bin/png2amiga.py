#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""PNG -> Amiga planar assets (fullscreen art, logos, fonts, sprites).

Outputs, for -o build/logo:
    logo.bpl      raw bitplane data (interleaved per row by default)
    logo.msk      blitter mask plane (only with --mask)
    logo.i        asm include: constants + palette (INCBIN the .bpl)
    logo_prev.png quantized preview (only with --preview)

Examples:
    png2amiga.py art.png -o build/art --colors 32 --scale 320x256
    png2amiga.py logo.png -o build/logo --colors 16 --mask --preview
    png2amiga.py font.png -o build/font --colors 4 --tile 16x16
"""

import argparse
import sys
import warnings
from pathlib import Path

from PIL import Image

warnings.filterwarnings("ignore", category=DeprecationWarning)  # Pillow getdata


def parse_wh(s: str) -> tuple[int, int]:
    w, _, h = s.lower().partition("x")
    return int(w), int(h)


def quantize(img: Image.Image, colors: int, dither: bool,
             reserve0: bool) -> tuple[Image.Image, list[tuple[int, int, int]], list[list[bool]] | None]:
    """Return (indexed image, palette, mask). reserve0: alpha -> index 0."""
    alpha = None
    if reserve0:
        alpha = []
        adata = list(img.convert("RGBA").getdata(3))
        for y in range(img.height):
            alpha.append([a >= 128 for a in adata[y * img.width:(y + 1) * img.width]])

    rgb = img.convert("RGB")
    ncols = colors - 1 if reserve0 else colors
    dith = Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE
    q = rgb.quantize(colors=ncols, method=Image.Quantize.MEDIANCUT, dither=dith)
    pal = q.getpalette()[: ncols * 3]
    palette = [tuple(pal[i:i + 3]) for i in range(0, len(pal), 3)]

    idx = list(q.getdata())
    pixels = [idx[y * img.width:(y + 1) * img.width] for y in range(img.height)]

    if reserve0:
        pixels = [[(p + 1) if alpha[y][x] else 0 for x, p in enumerate(row)]
                  for y, row in enumerate(pixels)]
        palette = [(0, 0, 0)] + palette
    return pixels, palette, alpha


def to_planes(pixels: list[list[int]], width: int, nplanes: int) -> list[list[bytes]]:
    """Per row, per plane, packed words. Width padded to multiple of 16."""
    wpad = (width + 15) & ~15
    rows = []
    for row in pixels:
        row = row + [0] * (wpad - width)
        planes = []
        for p in range(nplanes):
            bits = bytearray()
            for wx in range(0, wpad, 8):
                b = 0
                for i in range(8):
                    b = (b << 1) | ((row[wx + i] >> p) & 1)
                bits.append(b)
            planes.append(bytes(bits))
        rows.append(planes)
    return rows


def pack(rows: list[list[bytes]], interleaved: bool) -> bytes:
    if interleaved:
        return b"".join(b"".join(planes) for planes in rows)
    nplanes = len(rows[0])
    return b"".join(b"".join(r[p] for r in rows) for p in range(nplanes))


def mask_plane(alpha: list[list[bool]], width: int) -> bytes:
    wpad = (width + 15) & ~15
    out = bytearray()
    for row in alpha:
        row = list(row) + [False] * (wpad - width)
        for wx in range(0, wpad, 8):
            b = 0
            for i in range(8):
                b = (b << 1) | (1 if row[wx + i] else 0)
            out.append(b)
    return bytes(out)


def tile_reorder(pixels: list[list[int]], w: int, h: int,
                 tw: int, th: int) -> tuple[list[list[int]], int]:
    """Slice grid left-right top-bottom; stack tiles vertically."""
    if w % tw or h % th:
        sys.exit(f"image {w}x{h} not divisible by tile {tw}x{th}")
    out = []
    for ty in range(h // th):
        for tx in range(w // tw):
            for y in range(th):
                out.append(pixels[ty * th + y][tx * tw:(tx + 1) * tw])
    return out, (w // tw) * (h // th)


def rgb12(c: tuple[int, int, int]) -> int:
    return ((c[0] >> 4) << 8) | ((c[1] >> 4) << 4) | (c[2] >> 4)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("input")
    ap.add_argument("-o", "--output", required=True, help="output path prefix")
    ap.add_argument("--colors", type=int, default=32,
                    help="palette size, power of 2, max 256 (default 32)")
    ap.add_argument("--scale", type=parse_wh, help="resize to WxH (lanczos)")
    ap.add_argument("--crop", help="crop X,Y,W,H before scaling")
    ap.add_argument("--tile", type=parse_wh, metavar="WxH",
                    help="font/sprite sheet: slice into tiles, each tile a "
                         "contiguous block (tile W multiple of 16 recommended)")
    ap.add_argument("--mask", action="store_true",
                    help="alpha -> .msk blitter mask; index 0 = transparent")
    ap.add_argument("--planar", dest="interleaved", action="store_false",
                    help="contiguous planes instead of interleaved rows")
    ap.add_argument("--no-dither", dest="dither", action="store_false")
    ap.add_argument("--preview", action="store_true",
                    help="write quantized preview PNG")
    args = ap.parse_args()

    if args.colors < 2 or args.colors > 256 or args.colors & (args.colors - 1):
        sys.exit("--colors must be a power of 2 in 2..256")
    nplanes = args.colors.bit_length() - 1

    img = Image.open(args.input)
    if args.crop:
        x, y, w, h = map(int, args.crop.split(","))
        img = img.crop((x, y, x + w, y + h))
    if args.scale:
        img = img.resize(args.scale, Image.LANCZOS)

    w, h = img.size
    pixels, palette, alpha = quantize(img, args.colors, args.dither, args.mask)
    palette += [(0, 0, 0)] * (args.colors - len(palette))  # quantizer may return fewer

    tiles = 0
    tw, th = w, h
    if args.tile:
        tw, th = args.tile
        pixels, tiles = tile_reorder(pixels, w, h, tw, th)

    wpad = (tw + 15) & ~15
    bpl = pack(to_planes(pixels, tw, nplanes), args.interleaved)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.with_suffix(".bpl").write_bytes(bpl)

    if args.mask:
        mrows = alpha
        if args.tile:
            mrows, _ = tile_reorder(alpha, w, h, tw, th)
        out.with_suffix(".msk").write_bytes(mask_plane(mrows, tw))

    name = out.stem.upper().replace("-", "_")
    bpr = wpad // 8
    lines = [
        f"; generated by png2amiga.py from {Path(args.input).name} — do not edit",
        f"{name}_W        equ {tw}",
        f"{name}_H        equ {th}",
        f"{name}_PLANES   equ {nplanes}",
        f"{name}_BPR      equ {bpr}        ; bytes per row (padded)",
        f"{name}_MODULO   equ {bpr * (nplanes - 1) if args.interleaved else 0}"
        f"        ; bitplane modulo ({'interleaved' if args.interleaved else 'contiguous'})",
    ]
    if args.tile:
        lines += [
            f"{name}_TILES    equ {tiles}",
            f"{name}_TILEBYTES equ {bpr * th * nplanes}   ; tile n = base+n*this",
        ]
    lines.append("")
    if args.colors <= 32:
        lines.append(f"{name}_PAL:     ; {args.colors} colors, OCS 12-bit")
        for i in range(0, args.colors, 8):
            vals = ",".join(f"${rgb12(c):04x}" for c in palette[i:i + 8])
            lines.append(f"        dc.w    {vals}")
    else:
        lines.append(f"{name}_PAL:     ; {args.colors} colors, AGA 24-bit")
        for i in range(0, args.colors, 4):
            vals = ",".join(f"${c[0]:02x}{c[1]:02x}{c[2]:02x}" for c in palette[i:i + 4])
            lines.append(f"        dc.l    {vals}")
    lines.append("")
    out.with_suffix(".i").write_text("\n".join(lines))

    if args.preview:
        prev = Image.new("RGB", (tw, len(pixels)))
        prev.putdata([palette[p] for row in pixels for p in row])
        prev.save(f"{out}_prev.png")

    kb = len(bpl) / 1024
    print(f"{out}.bpl  {len(bpl)} bytes ({kb:.1f} KB)  "
          f"{tw}x{th}x{nplanes}{f' x{tiles} tiles' if tiles else ''}")


if __name__ == "__main__":
    main()
