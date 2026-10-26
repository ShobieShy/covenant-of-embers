#!/usr/bin/env python3
"""Draw the six brand logos (step 140, Brands B6) as 32 px PNGs in assets/original/brands/.

Original geometric marks made for this project (CC0-1.0, see ASSETS.toml): simple shapes in
each brand's colour on a dark disc, drawn at 128 px and downsampled. Re-run to regenerate.
Needs Pillow (python3-pil).
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets/original/brands"
S = 128


def rgb(h):
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


def base(col):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((4, 4, S - 4, S - 4), fill=(24, 20, 28, 235), outline=col, width=8)
    return im, d


def pyrowning(d, c):  # three-tongue flame
    d.polygon([(64, 18), (88, 62), (80, 104), (48, 104), (40, 62)], fill=c)
    d.polygon([(64, 50), (74, 76), (68, 98), (60, 98), (54, 76)], fill=(24, 20, 28, 255))


def sigil_sauer(d, c):  # drop inside a ring of sigil ticks
    d.polygon([(64, 26), (86, 70), (42, 70)], fill=c)
    d.ellipse((42, 52, 86, 98), fill=c)
    for i in range(8):
        a = i * math.pi / 4
        x, y = 64 + 46 * math.cos(a), 64 + 46 * math.sin(a)
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=c)


def moss_and_berg(d, c):  # twin peaks over a bar
    d.polygon([(22, 92), (50, 36), (66, 66), (80, 46), (106, 92)], fill=c)
    d.rectangle((22, 98, 106, 106), fill=c)


def windchester(d, c):  # three swept stripes
    for i, y in enumerate((40, 62, 84)):
        d.rounded_rectangle((26 + i * 8, y - 6, 102 - i * 4, y + 6), radius=6, fill=c)


def coltara_halo(d, c):  # halo ring over a star point
    d.ellipse((30, 22, 98, 54), outline=c, width=9)
    d.polygon([(64, 58), (74, 82), (98, 84), (78, 96), (64, 112), (50, 96), (30, 84), (54, 82)], fill=c)


def hexler_and_koch(d, c):  # hexagon with a crosshair notch
    pts = [(64 + 40 * math.cos(math.pi / 6 + i * math.pi / 3), 64 + 40 * math.sin(math.pi / 6 + i * math.pi / 3)) for i in range(6)]
    d.polygon(pts, outline=c, width=10)
    d.ellipse((54, 54, 74, 74), fill=c)
    for a, b in (((64, 18), (64, 40)), ((64, 88), (64, 110)), ((18, 64), (40, 64)), ((88, 64), (110, 64))):
        d.line((a, b), fill=c, width=6)


BRANDS = {
    "pyrowning_arms": ("ff6a1f", pyrowning),
    "sigil_sauer": ("3fa9ff", sigil_sauer),
    "moss_and_berg": ("8bbf4a", moss_and_berg),
    "windchester": ("dff6ff", windchester),
    "coltara_halo": ("ffe07a", coltara_halo),
    "hexler_and_koch": ("b067ff", hexler_and_koch),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (col, draw) in BRANDS.items():
        c = rgb(col)
        im, d = base(c)
        draw(d, c)
        im.resize((32, 32), Image.LANCZOS).save(OUT / f"{name}.png")
        print("wrote", OUT / f"{name}.png")


if __name__ == "__main__":
    main()
