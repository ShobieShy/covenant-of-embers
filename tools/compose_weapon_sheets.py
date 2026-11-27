#!/usr/bin/env python3
"""Overlay weapon renders on the concept sheets and write contact sheets.

  python3 tools/compose_weapon_sheets.py <render_dir> <out_dir>
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SHEETS = ROOT / "docs" / "concepts" / "weapons"
PARTS = ["head", "exterior", "interior", "handle", "charm"]
TIERS = ["basic", "uncommon", "rare", "mythic", "primordial", "unique"]
def key_green(im: Image.Image) -> Image.Image:
    """Drop the magenta backdrop used by the contact render."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r > 180 and b > 180 and g < 80:
                px[x, y] = (r, g, b, 0)
            elif r > 140 and b > 140 and g < 100 and r > g + 40 and b > g + 40:
                px[x, y] = (r, g, b, 0)
    return im


def content_box(im: Image.Image, y0=0.18, y1=0.86) -> tuple[int, int, int, int]:
    rgba = im.convert("RGBA")
    w, h = rgba.size
    top, bot = int(h * y0), int(h * y1)
    px = rgba.load()
    minx, miny, maxx, maxy = w, h, 0, 0
    found = False
    for y in range(top, bot):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 20:
                continue
            # Skip the parchment and the green spill. Keep wood, metal, gems.
            lum = (r + g + b) / 3
            sat = max(r, g, b) - min(r, g, b)
            if lum < 150 or sat > 40:
                found = True
                minx, miny = min(minx, x), min(miny, y)
                maxx, maxy = max(maxx, x), max(maxy, y)
    if not found:
        return (0, top, w, bot)
    return (minx, miny, maxx + 1, maxy + 1)


def _runs(im: Image.Image, y0: float, y1: float, dark: bool = False) -> list[tuple[int, int, int, int]]:
    """Vertical bands of weapon pixels, each as (x0, y0, x1, y1)."""
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    if dark:
        top, bot = int(h * 0.30), int(h * 0.80)
        x_margin = 48
        gap_lim = 8
    else:
        top, bot = int(h * y0), int(h * y1)
        x_margin = 0
        gap_lim = 12
    counts = [0] * w
    for x in range(x_margin, w - x_margin):
        for y in range(top, bot, 2):
            r, g, b, a = px[x, y]
            if a < 16 or (r > 180 and b > 180 and g < 90):
                continue
            if dark and (r + g + b) / 3.0 >= 105:
                continue
            if not dark or (r + g + b) / 3.0 < 105:
                counts[x] += 1
    hit = [n > (4 if dark else 0) for n in counts]
    bands = []
    start = None
    gap = 0
    for x, on in enumerate(hit + [False]):
        if on:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap > gap_lim:
                bands.append((start, x - gap))
                start = None
                gap = 0
    if start is not None:
        bands.append((start, w - x_margin))
    bands = [(a, b) for a, b in bands if b - a > 40]
    out = []
    for x0, x1 in bands:
        ys = []
        y_lo = top if dark else 0
        y_hi = bot if dark else h
        for y in range(y_lo, y_hi):
            for x in range(x0, x1, 3):
                r, g, b, a = px[x, y]
                if a < 16 or (r > 180 and b > 180 and g < 90):
                    continue
                if dark and (r + g + b) / 3.0 >= 105:
                    continue
                ys.append(y)
                break
        if ys:
            out.append((x0, min(ys), x1, max(ys) + 1))
    return out


def fit(render: Image.Image, sheet: Image.Image) -> Image.Image:
    """Drop each rendered weapon onto the matching column of the sheet."""
    keyed = key_green(render)
    sheet_bands = _runs(sheet.convert("RGBA"), 0.22, 0.84, dark=True)
    render_bands = _runs(keyed, 0.0, 1.0, dark=False)
    canvas = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    if len(sheet_bands) >= 7 and len(render_bands) >= 7:
        sheet_bands = sorted(sheet_bands, key=lambda b: b[2] - b[0], reverse=True)[:7]
        render_bands = sorted(render_bands, key=lambda b: b[2] - b[0], reverse=True)[:7]
        sheet_bands = sorted(sheet_bands)
        render_bands = sorted(render_bands)
        for sb, rb in zip(sheet_bands, render_bands):
            crop = keyed.crop(rb)
            sw, sh = sb[2] - sb[0], max(1, sb[3] - sb[1])
            scale = sh / max(1, crop.height)
            sized = crop.resize((max(1, int(crop.width * scale)), sh), Image.Resampling.LANCZOS)
            ox = sb[0] + (sw - sized.width) // 2
            canvas.paste(sized, (ox, sb[1]), sized)
        return canvas
    sb = content_box(sheet.convert("RGBA"), 0.20, 0.84)
    rb = content_box(keyed, 0.0, 1.0)
    sw, sh = sb[2] - sb[0], sb[3] - sb[1]
    rw, rh = max(1, rb[2] - rb[0]), max(1, rb[3] - rb[1])
    scale = min(sw / rw, sh / rh)
    crop = keyed.crop(rb)
    sized = crop.resize((max(1, int(rw * scale)), max(1, int(rh * scale))), Image.Resampling.LANCZOS)
    ox = sb[0] + (sw - sized.width) // 2
    oy = sb[1] + (sh - sized.height) // 2
    canvas.paste(sized, (ox, oy), sized)
    return canvas


def overlay(sheet: Image.Image, placed: Image.Image) -> Image.Image:
    base = sheet.convert("RGBA")
    ghost = placed.copy()
    alpha = ghost.getchannel("A").point(lambda a: int(a * 0.55))
    ghost.putalpha(alpha)
    return Image.alpha_composite(base, ghost).convert("RGB")


def contact(sheet: Image.Image, render: Image.Image, placed_overlay: Image.Image, title: str) -> Image.Image:
    w, h = sheet.size
    thumb_h = 360
    def frame(im: Image.Image) -> Image.Image:
        im = im.convert("RGB")
        s = thumb_h / im.height
        return im.resize((max(1, int(im.width * s)), thumb_h), Image.Resampling.LANCZOS)

    a, b, c = frame(sheet), frame(key_green(render).convert("RGB")), frame(placed_overlay)
    pad = 12
    canvas = Image.new("RGB", (a.width + b.width + c.width + pad * 4, thumb_h + 36), (28, 24, 20))
    canvas.paste(a, (pad, 28))
    canvas.paste(b, (pad * 2 + a.width, 28))
    canvas.paste(c, (pad * 3 + a.width + b.width, 28))
    draw = ImageDraw.Draw(canvas)
    draw.text((pad, 6), title + "    sheet | render | overlay", fill=(235, 220, 190))
    return canvas


def main() -> None:
    render_dir = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    sheets_out = out / "overlays"
    contacts = out / "contacts"
    sheets_out.mkdir(exist_ok=True)
    contacts.mkdir(exist_ok=True)
    for part in PARTS:
        for tier in TIERS:
            render = Image.open(render_dir / f"{part}_{tier}.png")
            for form in ("staff", "wand"):
                sheet = Image.open(SHEETS / f"{form}_{part}_{tier}.jpg")
                placed = fit(render, sheet)
                ov = overlay(sheet, placed)
                ov.save(sheets_out / f"{form}_{part}_{tier}.png")
                contact(sheet, render, ov, f"{form} {part} {tier}").save(contacts / f"{form}_{part}_{tier}.png")
            print(part, tier)
    # One board of the six assembled staffs, arcane, for the before/after set.
    rows = []
    for tier in TIERS:
        p = render_dir / f"assembled_staff_{tier}.png"
        if p.is_file():
            im = key_green(Image.open(p)).convert("RGB")
            im.thumbnail((640, 360))
            rows.append(im)
    if rows:
        board = Image.new("RGB", (rows[0].width * 3, rows[0].height * 2), (20, 18, 16))
        for i, im in enumerate(rows):
            board.paste(im, ((i % 3) * rows[0].width, (i // 3) * rows[0].height))
        board.save(out / "assembled_staffs.png")


if __name__ == "__main__":
    main()
