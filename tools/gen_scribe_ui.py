#!/usr/bin/env python3
"""Project-made Auto-Scribe UI art (CC0). Parchment, brass, serif, skill medallions.

Palette sampled from docs/maps/eldoria-hub-map.jpg and levels/town.jpg:
paper (196, 168, 122), stained edge (122, 90, 50), brass (168, 124, 62),
ink (42, 26, 14). Run from the repo root. Writes assets/original/ui_scribe/.
"""

from __future__ import annotations

import math
import random
import shutil
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "original" / "ui_scribe"
MAPS = ROOT / "docs" / "maps"

INK = (42, 26, 14, 255)
INK_RGB = (42, 26, 14)
PAPER = (196, 168, 122, 255)
PAPER_LIT = (214, 190, 154, 255)
PAPER_DIM = (168, 138, 96, 255)
BRASS = (176, 132, 64, 255)
BRASS_LIT = (214, 176, 104, 255)
BRASS_DIM = (120, 84, 40, 255)
BRASS_DARK = (78, 52, 24, 255)
STAIN = (122, 90, 50, 255)

# Element colours from data/magic/elements.toml, outlined so pale ones still read.
ELEMENTS = {
    "arcane": (179, 179, 179),
    "fire": (255, 77, 26),
    "water": (26, 102, 255),
    "earth": (160, 112, 40),
    "air": (170, 214, 230),
    "light": (255, 230, 150),
    "dark": (110, 40, 170),
    "ember": (232, 120, 36),
}


def paper(w: int, h: int, seed: int, light: tuple[int, int, int] = (206, 178, 132)) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (w, h), (*light, 255))
    px = img.load()
    for y in range(h):
        for x in range(w):
            n = rng.randint(-14, 14)
            fiber = 8 if (x * 3 + y * 7 + seed) % 17 == 0 else 0
            nx = abs(x / max(1, w - 1) - 0.5) * 2
            ny = abs(y / max(1, h - 1) - 0.5) * 2
            edge = max(nx, ny) ** 2
            stain = int(48 * edge)
            r = max(0, min(255, light[0] + n - stain - fiber))
            g = max(0, min(255, light[1] + n - int(stain * 1.05) - fiber))
            b = max(0, min(255, light[2] + int(n * 0.7) - int(stain * 1.2) - fiber))
            px[x, y] = (r, g, b, 255)
    return img.filter(ImageFilter.SMOOTH)


def band(draw: ImageDraw.ImageDraw, w: int, h: int, inset: int, thick: int, color: tuple) -> None:
    draw.rectangle((inset, inset, w - 1 - inset, inset + thick), fill=color)
    draw.rectangle((inset, h - 1 - inset - thick, w - 1 - inset, h - 1 - inset), fill=color)
    draw.rectangle((inset, inset, inset + thick, h - 1 - inset), fill=color)
    draw.rectangle((w - 1 - inset - thick, inset, w - 1 - inset, h - 1 - inset), fill=color)


def knot(draw: ImageDraw.ImageDraw, x: int, y: int, s: int, flipx: int, flipy: int) -> None:
    """A small acanthus corner, kept inside the 9-slice corner."""
    pts = []
    for i, (px, py) in enumerate(
        [(0.15, 0.72), (0.28, 0.28), (0.55, 0.12), (0.78, 0.34), (0.62, 0.55), (0.82, 0.82), (0.4, 0.7)]
    ):
        pts.append((x + flipx * px * s, y + flipy * py * s))
    draw.polygon(pts, fill=BRASS_LIT)
    draw.line(pts + [pts[0]], fill=BRASS_DARK, width=2)
    draw.ellipse((x + flipx * 0.34 * s - 3, y + flipy * 0.4 * s - 3, x + flipx * 0.34 * s + 4, y + flipy * 0.4 * s + 4), fill=BRASS_DARK)


def frame(w: int, h: int, seed: int, lit: tuple[int, int, int], center_alpha: int = 255) -> Image.Image:
    img = paper(w, h, seed, lit)
    if center_alpha < 255:
        # Bar frames leave the middle clear so the coloured fill shows through.
        px = img.load()
        m = 18
        for y in range(m, h - m):
            for x in range(m, w - m):
                px[x, y] = (0, 0, 0, 0)
    d = ImageDraw.Draw(img)
    band(d, w, h, 4, 3, BRASS_DARK)
    band(d, w, h, 8, 8, BRASS)
    band(d, w, h, 16, 2, BRASS_LIT)
    band(d, w, h, 19, 2, BRASS_DARK)
    knot(d, 8, 8, 40, 1, 1)
    knot(d, w - 8, 8, 40, -1, 1)
    knot(d, 8, h - 8, 40, 1, -1)
    knot(d, w - 8, h - 8, 40, -1, -1)
    return img


def buttons() -> None:
    # Slimmer than the panel: a 26 px corner so a 22 px label sits in the clear centre.
    specs = {
        "button.png": (206, 178, 132),
        "button_hover.png": (224, 200, 158),
        "button_pressed.png": (176, 146, 104),
        "button_disabled.png": (168, 156, 136),
    }
    for name, col in specs.items():
        img = paper(160, 80, hash(name) & 0xFFFF, col)
        d = ImageDraw.Draw(img)
        band(d, 160, 80, 2, 2, BRASS_DARK)
        band(d, 160, 80, 5, 6, BRASS)
        band(d, 160, 80, 12, 2, BRASS_LIT)
        for ox, oy, fx, fy in ((4, 4, 1, 1), (156, 4, -1, 1), (4, 76, 1, -1), (156, 76, -1, -1)):
            pts = [
                (ox + fx * 2, oy + fy * 18),
                (ox + fx * 8, oy + fy * 6),
                (ox + fx * 20, oy + fy * 4),
                (ox + fx * 16, oy + fy * 14),
                (ox + fx * 22, oy + fy * 22),
                (ox + fx * 8, oy + fy * 18),
            ]
            d.polygon(pts, fill=BRASS_LIT)
            d.line(pts + [pts[0]], fill=BRASS_DARK, width=1)
        img.save(OUT / name)


def panels() -> None:
    frame(192, 192, 15, (206, 178, 132)).save(OUT / "panel.png")
    inn = paper(160, 160, 21, (176, 146, 108))
    d = ImageDraw.Draw(inn)
    band(d, 160, 160, 3, 2, BRASS_DIM)
    inn.save(OUT / "inlay.png")
    slot = frame(128, 128, 33, (188, 158, 114))
    slot.save(OUT / "slot.png")
    slot_on = frame(128, 128, 34, (214, 186, 140))
    slot_on.save(OUT / "slot_selected.png")
    bar = frame(160, 64, 40, (150, 116, 64), center_alpha=0)
    bar.save(OUT / "bar_frame.png")
    focus = Image.new("RGBA", (128, 80), (0, 0, 0, 0))
    d = ImageDraw.Draw(focus)
    band(d, 128, 80, 4, 4, BRASS_LIT)
    focus.save(OUT / "focus.png")


def medallion(kind: str, color: tuple[int, int, int]) -> Image.Image:
    s = 128
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((4, 4, s - 5, s - 5), fill=BRASS_DARK)
    d.ellipse((10, 10, s - 11, s - 11), fill=BRASS)
    d.ellipse((18, 18, s - 19, s - 19), fill=BRASS_LIT)
    d.ellipse((24, 24, s - 25, s - 25), fill=(214, 190, 154, 255))
    ink = INK_RGB
    c = (s // 2, s // 2)
    if kind == "fire" or kind == "ember":
        d.polygon([(64, 30), (84, 70), (74, 68), (90, 100), (64, 86), (38, 100), (54, 68), (44, 70)], fill=color, outline=ink)
        d.polygon([(64, 52), (74, 78), (64, 72), (54, 78)], fill=(255, 214, 120, 255))
    elif kind == "water":
        d.polygon([(64, 28), (90, 78), (64, 102), (38, 78)], fill=color, outline=ink)
        d.ellipse((48, 58, 80, 100), fill=color, outline=ink)
    elif kind == "earth":
        d.polygon([(64, 32), (100, 96), (28, 96)], fill=color, outline=ink)
        d.polygon([(64, 52), (82, 90), (46, 90)], fill=(214, 176, 90, 255))
    elif kind == "air":
        for i, y in enumerate((46, 64, 82)):
            d.arc((30, y - 8, 98, y + 14), 200, 340, fill=color, width=5)
            d.line((88, y, 100, y - 4), fill=ink, width=3)
    elif kind == "light":
        d.ellipse((46, 46, 82, 82), fill=color, outline=ink)
        for a in range(0, 360, 45):
            rad = math.radians(a)
            d.line((64 + math.cos(rad) * 22, 64 + math.sin(rad) * 22, 64 + math.cos(rad) * 36, 64 + math.sin(rad) * 36), fill=color, width=4)
    elif kind == "dark":
        d.ellipse((36, 32, 92, 96), fill=color, outline=ink)
        d.ellipse((52, 28, 104, 90), fill=(214, 190, 154, 255))
    else:  # arcane
        d.regular_polygon((64, 64, 30), 6, rotation=30, fill=color, outline=ink)
        d.regular_polygon((64, 64, 14), 6, rotation=0, outline=ink)
    return img.resize((64, 64), Image.Resampling.LANCZOS)


def icons() -> None:
    folder = OUT / "icons"
    folder.mkdir(parents=True, exist_ok=True)
    for name, col in ELEMENTS.items():
        medallion(name, col).save(folder / f"{name}.png")


def cursor() -> None:
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    arrow = [(1, 1), (1, 26), (7, 20), (12, 30), (16, 28), (11, 18), (20, 18)]
    d.polygon(arrow, fill=BRASS_LIT)
    inner = [(3, 4), (3, 20), (7, 16), (11, 24), (13, 23), (9, 15), (16, 15)]
    d.polygon(inner, fill=INK)
    img.save(OUT / "cursor.png")


def copy_maps() -> None:
    folder = OUT / "maps"
    folder.mkdir(parents=True, exist_ok=True)
    pairs = {
        "town.jpg": MAPS / "levels" / "town.jpg",
        "association.jpg": MAPS / "levels" / "association.jpg",
        "oak.jpg": MAPS / "levels" / "bobs_lab.jpg",
        "landfill.jpg": MAPS / "levels" / "landfill.jpg",
        "breach.jpg": MAPS / "levels" / "breach.jpg",
        "warrens.jpg": MAPS / "levels" / "act1_goblin_warrens.jpg",
        "blightcoil.jpg": MAPS / "levels" / "act2_blightcoil.jpg",
        "slagworks.jpg": MAPS / "levels" / "act3_slagworks.jpg",
        "sunken.jpg": MAPS / "levels" / "act4_sunken_ruins.jpg",
        "spire.jpg": MAPS / "levels" / "inverted_spire.jpg",
        "elyria.jpg": MAPS / "elyria-world-map.jpg",
    }
    for name, src in pairs.items():
        shutil.copyfile(src, folder / name)


# --- serif -----------------------------------------------------------------

UPM = 1000
SW = 96
SB = 26
SO = 54
CAP = 680
XHgt = 460
ASC = 710
DESC = -200


def clockwise_rect(pen: TTGlyphPen, x: float, y: float, w: float, h: float) -> None:
    if w <= 0 or h <= 0:
        return
    pen.moveTo((x, y))
    pen.lineTo((x, y + h))
    pen.lineTo((x + w, y + h))
    pen.lineTo((x + w, y))
    pen.closePath()


def _area(pts: list[tuple[float, float]]) -> float:
    acc = 0.0
    for i, (x1, y1) in enumerate(pts):
        x2, y2 = pts[(i + 1) % len(pts)]
        acc += x1 * y2 - x2 * y1
    return acc


def poly(pen: TTGlyphPen, pts: list[tuple[float, float]]) -> None:
    # Clockwise fill. Reversing a backwards diagonal keeps overlaps solid.
    if _area(pts) < 0:
        pts = list(reversed(pts))
    pen.moveTo(pts[0])
    for p in pts[1:]:
        pen.lineTo(p)
    pen.closePath()


def stem(pen: TTGlyphPen, x: float, y0: float, y1: float, serifs: str = "both", w: float = SW) -> None:
    lo, hi = (y0, y1) if y1 >= y0 else (y1, y0)
    clockwise_rect(pen, x, lo, w, hi - lo)
    if serifs in ("both", "bottom"):
        clockwise_rect(pen, x - SO, lo, w + 2 * SO, SB)
    if serifs in ("top", "both"):
        clockwise_rect(pen, x - SO, hi - SB, w + 2 * SO, SB)


def bar(pen: TTGlyphPen, x: float, y: float, w: float, h: float = SW) -> None:
    clockwise_rect(pen, x, y, w, h)


def diag(pen: TTGlyphPen, x0: float, y0: float, x1: float, y1: float, width: float = SW) -> None:
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy) or 1
    px, py = -dy / length * width / 2, dx / length * width / 2
    poly(pen, [(x0 - px, y0 - py), (x1 - px, y1 - py), (x1 + px, y1 + py), (x0 + px, y0 + py)])


def oval(pen: TTGlyphPen, cx: float, cy: float, rx: float, ry: float, reverse: bool = False) -> None:
    n = 8
    pts = []
    ctrls = []
    scale = 1 / math.cos(math.pi / n)
    for i in range(n):
        a = 2 * math.pi * i / n
        pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
        b = 2 * math.pi * (i + 0.5) / n
        ctrls.append((cx + rx * scale * math.cos(b), cy + ry * scale * math.sin(b)))
    seq = list(range(n))
    if reverse:
        seq.reverse()
    pen.moveTo(pts[seq[0]])
    for k in range(n):
        i = seq[k]
        j = seq[(k + 1) % n]
        ctrl = ctrls[j if reverse else i]
        # The off-curve sits on the bisector between the two on-curve points.
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * ((i + 1) % n) / n
        if reverse:
            a0, a1 = a1, a0
        mid = a0 + ((a1 - a0 + math.pi) % (2 * math.pi) - math.pi) / 2
        # Recompute a stable control from the actual neighbour pair.
        i0 = seq[k]
        i1 = seq[(k + 1) % n]
        ang0 = 2 * math.pi * i0 / n
        ang1 = 2 * math.pi * i1 / n
        delta = (ang1 - ang0 + math.pi) % (2 * math.pi) - math.pi
        mid = ang0 + delta / 2
        ctrl = (cx + rx * scale * math.cos(mid), cy + ry * scale * math.sin(mid))
        pen.qCurveTo(ctrl, pts[i1])
    pen.closePath()


def ring(pen: TTGlyphPen, cx: float, cy: float, rx: float, ry: float, thick: float) -> None:
    oval(pen, cx, cy, rx, ry, False)
    oval(pen, cx, cy, max(8, rx - thick), max(8, ry - thick), True)


def arc_band(
    pen: TTGlyphPen, cx: float, cy: float, rx: float, ry: float, thick: float, a0: float, a1: float, steps: int = 18
) -> None:
    """One filled band. No counter contour, so a bar drawn across it stays visible."""
    outer: list[tuple[float, float]] = []
    inner: list[tuple[float, float]] = []
    for i in range(steps + 1):
        t = a0 + (a1 - a0) * i / steps
        outer.append((cx + rx * math.cos(t), cy + ry * math.sin(t)))
        inner.append((cx + (rx - thick) * math.cos(t), cy + (ry - thick) * math.sin(t)))
    poly(pen, outer + list(reversed(inner)))


class Pen:
    def __init__(self) -> None:
        self.p = TTGlyphPen(None)

    def g(self) -> object:
        return self.p.glyph()


def build_font(path: Path) -> None:
    glyphs: dict = {}
    metrics: dict = {}
    cmap: dict = {}

    def add(cp: int | None, name: str, advance: int, draw) -> None:
        pen = TTGlyphPen(None)
        draw(pen)
        glyphs[name] = pen.glyph()
        metrics[name] = (advance, 30)
        if cp is not None:
            cmap[cp] = name

    def empty(pen: TTGlyphPen) -> None:
        clockwise_rect(pen, 80, 0, SW, CAP)

    add(None, ".notdef", 560, empty)
    add(32, "space", 300, lambda pen: None)
    add(ord("-"), "hyphen", 420, lambda pen: bar(pen, 60, 280, 280, 48))
    add(ord("–"), "endash", 520, lambda pen: bar(pen, 40, 280, 420, 48))
    add(ord("—"), "emdash", 760, lambda pen: bar(pen, 40, 280, 660, 48))
    add(ord("."), "period", 280, lambda pen: clockwise_rect(pen, 70, 0, 90, 90))
    add(ord(","), "comma", 280, lambda pen: poly(pen, [(70, 80), (160, 80), (140, 0), (90, -140), (50, -80)]))
    add(ord(":"), "colon", 300, lambda pen: (clockwise_rect(pen, 90, 0, 80, 80), clockwise_rect(pen, 90, 360, 80, 80)))
    add(ord(";"), "semicolon", 300, lambda pen: (clockwise_rect(pen, 90, 360, 80, 80), poly(pen, [(90, 80), (170, 80), (140, 0), (80, -140)])))
    add(ord("!"), "exclam", 320, lambda pen: (stem(pen, 100, 200, CAP, "top", 80), clockwise_rect(pen, 100, 0, 80, 90)))
    add(ord("?"), "question", 560, lambda pen: (ring(pen, 280, 480, 180, 180, 70), clockwise_rect(pen, 240, 180, 70, 120), clockwise_rect(pen, 230, 0, 80, 80)))
    add(ord("'"), "quote", 240, lambda pen: poly(pen, [(70, CAP), (150, CAP), (120, CAP - 180)]))
    add(ord('"'), "quotedbl", 420, lambda pen: (poly(pen, [(60, CAP), (130, CAP), (100, CAP - 180)]), poly(pen, [(180, CAP), (250, CAP), (220, CAP - 180)])))
    add(ord("("), "parenleft", 380, lambda pen: arc_band(pen, 280, 340, 160, 340, 64, math.radians(110), math.radians(250)))
    add(ord(")"), "parenright", 380, lambda pen: arc_band(pen, 80, 340, 160, 340, 64, math.radians(-70), math.radians(70)))
    add(ord("/"), "slash", 420, lambda pen: diag(pen, 40, -40, 340, CAP + 20, 70))
    add(ord("+"), "plus", 560, lambda pen: (bar(pen, 60, 280, 420, 70), bar(pen, 230, 120, 70, 400)))
    add(ord("%"), "percent", 720, lambda pen: (ring(pen, 160, 520, 90, 90, 40), ring(pen, 520, 160, 90, 90, 40), diag(pen, 140, 40, 560, 640, 60)))
    add(ord("&"), "ampersand", 680, lambda pen: (ring(pen, 300, 480, 180, 160, 70), ring(pen, 260, 180, 160, 140, 60)))
    add(ord("*"), "asterisk", 480, lambda pen: (diag(pen, 80, 200, 360, 520, 50), diag(pen, 360, 200, 80, 520, 50), bar(pen, 70, 330, 320, 50)))
    add(ord("#"), "numbersign", 640, lambda pen: (stem(pen, 160, 40, 640, "none", 60), stem(pen, 360, 40, 640, "none", 60), bar(pen, 60, 420, 500, 56), bar(pen, 60, 200, 500, 56)))
    add(ord("@"), "at", 780, lambda pen: ring(pen, 390, 340, 280, 280, 60))
    add(ord("_"), "underscore", 560, lambda pen: bar(pen, 40, -20, 460, 40))
    add(ord("="), "equal", 560, lambda pen: (bar(pen, 60, 220, 420, 56), bar(pen, 60, 380, 420, 56)))
    # U+2122 is left to the font fallback. A hand-drawn mark read as noise.
    add(0x25C6, "diamond", 560, lambda pen: poly(pen, [(280, 680), (500, 340), (280, 0), (60, 340)]))
    add(0x25C7, "diamondopen", 560, lambda pen: ring(pen, 280, 340, 200, 300, 50))

    def digit(shapes) -> object:
        return shapes

    # Digits. Open forms, heavy stems.
    add(ord("0"), "zero", 620, lambda pen: ring(pen, 300, 360, 220, 340, SW))
    add(ord("1"), "one", 460, lambda pen: (stem(pen, 180, 0, CAP, "bottom", SW), diag(pen, 40, 520, 180, CAP, 70)))
    add(ord("2"), "two", 620, lambda pen: (bar(pen, 50, 0, 480, 70), diag(pen, 80, 70, 500, 360, 80), arc_band(pen, 300, 520, 210, 160, 70, math.radians(20), math.radians(200))))
    add(ord("3"), "three", 620, lambda pen: (arc_band(pen, 260, 500, 200, 160, 70, math.radians(-70), math.radians(200)), arc_band(pen, 260, 180, 210, 170, 70, math.radians(-120), math.radians(140)), bar(pen, 160, 310, 220, 56)))
    add(ord("4"), "four", 640, lambda pen: (stem(pen, 380, 0, CAP, "bottom"), diag(pen, 40, 280, 360, CAP, 80), bar(pen, 40, 240, 540, 70)))
    add(ord("5"), "five", 620, lambda pen: (bar(pen, 70, CAP - 70, 440, 64), stem(pen, 70, 340, CAP, "none", 76), arc_band(pen, 280, 180, 210, 180, 72, math.radians(-110), math.radians(160)), bar(pen, 180, 300, 240, 56)))
    add(ord("6"), "six", 620, lambda pen: (ring(pen, 300, 210, 200, 190, 80), arc_band(pen, 300, 480, 190, 180, 72, math.radians(40), math.radians(200))))
    add(ord("7"), "seven", 600, lambda pen: (bar(pen, 40, CAP - 70, 500, 70), diag(pen, 460, CAP - 40, 140, 0, SW)))
    add(ord("8"), "eight", 620, lambda pen: (ring(pen, 300, 510, 180, 150, 64), ring(pen, 300, 190, 200, 170, 70)))
    add(ord("9"), "nine", 620, lambda pen: (ring(pen, 300, 470, 190, 180, 76), arc_band(pen, 300, 200, 180, 190, 70, math.radians(220), math.radians(380))))

    # Capitals.
    add(ord("A"), "A", 680, lambda pen: (diag(pen, 40, 0, 300, CAP, SW), diag(pen, 560, 0, 300, CAP, SW), bar(pen, 120, 240, 360, 70), clockwise_rect(pen, 20, 0, 150, SB), clockwise_rect(pen, 430, 0, 150, SB)))
    add(ord("B"), "B", 660, lambda pen: (stem(pen, 40, 0, CAP), bar(pen, 40, CAP - SW, 280, SW), bar(pen, 40, 300, 260, 70), bar(pen, 40, 0, 300, SB + 8), ring(pen, 300, 500, 180, 150, 70), ring(pen, 310, 170, 190, 150, 70)))
    add(ord("C"), "C", 680, lambda pen: arc_band(pen, 360, 340, 260, 320, SW, math.radians(40), math.radians(320)))
    add(ord("D"), "D", 700, lambda pen: (stem(pen, 40, 0, CAP), ring(pen, 280, 340, 280, 330, SW)))
    add(ord("E"), "E", 620, lambda pen: (stem(pen, 40, 0, CAP), bar(pen, 40, CAP - SW, 420, SW), bar(pen, 40, 300, 340, 70), bar(pen, 40, 0, 420, SB + 10)))
    add(ord("F"), "F", 580, lambda pen: (stem(pen, 40, 0, CAP, "bottom"), bar(pen, 40, CAP - SW, 420, SW), bar(pen, 40, 300, 320, 70)))
    add(ord("G"), "G", 720, lambda pen: (arc_band(pen, 360, 340, 260, 320, SW, math.radians(40), math.radians(320)), bar(pen, 340, 300, 200, 64), stem(pen, 480, 80, 340, "bottom", 72)))
    add(ord("H"), "H", 700, lambda pen: (stem(pen, 40, 0, CAP), stem(pen, 480, 0, CAP), bar(pen, 40, 300, 536, 70)))
    add(ord("I"), "I", 400, lambda pen: stem(pen, 140, 0, CAP))
    add(ord("J"), "J", 560, lambda pen: (stem(pen, 300, 160, CAP, "top"), ring(pen, 220, 160, 180, 150, 70)))
    add(ord("K"), "K", 680, lambda pen: (stem(pen, 40, 0, CAP), diag(pen, 140, 340, 540, CAP, SW), diag(pen, 180, 300, 560, 0, SW)))
    add(ord("L"), "L", 560, lambda pen: (stem(pen, 40, 0, CAP, "top"), bar(pen, 40, 0, 420, SB + 12)))
    add(ord("M"), "M", 820, lambda pen: (stem(pen, 30, 0, CAP, "bottom"), stem(pen, 640, 0, CAP, "bottom"), diag(pen, 80, CAP, 370, 180, SW), diag(pen, 660, CAP, 370, 180, SW)))
    add(ord("N"), "N", 720, lambda pen: (stem(pen, 40, 0, CAP), stem(pen, 500, 0, CAP), diag(pen, 100, CAP, 540, 40, SW)))
    add(ord("O"), "O", 720, lambda pen: ring(pen, 350, 340, 270, 330, SW))
    add(ord("P"), "P", 620, lambda pen: (stem(pen, 40, 0, CAP, "bottom"), ring(pen, 280, 500, 200, 170, 70)))
    add(ord("Q"), "Q", 740, lambda pen: (ring(pen, 340, 360, 260, 320, SW), diag(pen, 380, 200, 620, -20, 70)))
    add(ord("R"), "R", 680, lambda pen: (stem(pen, 40, 0, CAP), ring(pen, 280, 500, 200, 160, 70), diag(pen, 240, 340, 560, 0, SW)))
    add(
        ord("S"),
        "S",
        620,
        lambda pen: (
            arc_band(pen, 300, 500, 210, 160, 72, math.radians(20), math.radians(200)),
            arc_band(pen, 300, 180, 220, 170, 72, math.radians(200), math.radians(380)),
        ),
    )
    add(ord("T"), "T", 620, lambda pen: (bar(pen, 40, CAP - SW, 500, SW), stem(pen, 250, 0, CAP, "bottom")))
    add(ord("U"), "U", 700, lambda pen: (stem(pen, 40, 180, CAP, "top"), stem(pen, 480, 180, CAP, "top"), ring(pen, 310, 200, 250, 180, SW)))
    add(ord("V"), "V", 680, lambda pen: (diag(pen, 40, CAP, 300, 0, SW), diag(pen, 560, CAP, 300, 0, SW)))
    add(ord("W"), "W", 900, lambda pen: (diag(pen, 20, CAP, 200, 0, 80), diag(pen, 380, CAP, 200, 0, 80), diag(pen, 380, CAP, 620, 0, 80), diag(pen, 820, CAP, 620, 0, 80)))
    add(ord("X"), "X", 680, lambda pen: (diag(pen, 40, 0, 560, CAP, SW), diag(pen, 560, 0, 40, CAP, SW)))
    add(ord("Y"), "Y", 660, lambda pen: (diag(pen, 40, CAP, 300, 340, SW), diag(pen, 560, CAP, 300, 340, SW), stem(pen, 250, 0, 360, "bottom")))
    add(ord("Z"), "Z", 620, lambda pen: (bar(pen, 40, CAP - 70, 500, 70), bar(pen, 40, 0, 500, SB + 10), diag(pen, 480, CAP - 40, 80, 40, SW)))

    # Lowercase.
    add(ord("a"), "a", 560, lambda pen: (arc_band(pen, 230, 220, 170, 170, 68, math.radians(30), math.radians(330)), stem(pen, 340, 0, 400, "bottom", 76)))
    add(ord("b"), "b", 580, lambda pen: (stem(pen, 40, 0, ASC), ring(pen, 300, 220, 190, 190, 70)))
    add(ord("c"), "c", 500, lambda pen: arc_band(pen, 270, 230, 180, 180, 68, math.radians(45), math.radians(315)))
    add(ord("d"), "d", 580, lambda pen: (stem(pen, 400, 0, ASC), ring(pen, 260, 220, 190, 190, 70)))
    add(ord("e"), "e", 540, lambda pen: (arc_band(pen, 260, 230, 180, 175, 64, math.radians(20), math.radians(340)), bar(pen, 90, 210, 300, 52)))
    add(ord("f"), "f", 400, lambda pen: (stem(pen, 140, 0, ASC, "bottom", 70), bar(pen, 60, 460, 240, 56), ring(pen, 220, 620, 120, 100, 50)))
    add(ord("g"), "g", 560, lambda pen: (arc_band(pen, 230, 250, 165, 160, 64, math.radians(20), math.radians(340)), stem(pen, 330, DESC + 20, 420, "none", 72), arc_band(pen, 230, DESC + 70, 160, 100, 58, math.radians(200), math.radians(360))))
    add(ord("h"), "h", 580, lambda pen: (stem(pen, 40, 0, ASC), stem(pen, 380, 0, 280, "bottom", 80), ring(pen, 260, 300, 180, 140, 60)))
    add(ord("i"), "i", 280, lambda pen: (stem(pen, 70, 0, XHgt, "both", 70), clockwise_rect(pen, 70, XHgt + 60, 70, 70)))
    add(ord("j"), "j", 340, lambda pen: (stem(pen, 140, 40, XHgt, "top", 70), ring(pen, 80, 40, 100, 90, 50), clockwise_rect(pen, 140, XHgt + 60, 70, 70)))
    add(ord("k"), "k", 560, lambda pen: (stem(pen, 40, 0, ASC), diag(pen, 120, 220, 440, XHgt, 70), diag(pen, 160, 200, 460, 0, 70)))
    add(ord("l"), "l", 280, lambda pen: stem(pen, 70, 0, ASC))
    add(ord("m"), "m", 840, lambda pen: (stem(pen, 30, 0, XHgt, "bottom", 70), stem(pen, 300, 0, 300, "bottom", 70), stem(pen, 560, 0, 300, "bottom", 70), ring(pen, 200, 320, 150, 120, 50), ring(pen, 460, 320, 150, 120, 50)))
    add(ord("n"), "n", 580, lambda pen: (stem(pen, 40, 0, XHgt, "bottom"), stem(pen, 380, 0, 280, "bottom", 80), ring(pen, 260, 320, 180, 130, 56)))
    add(ord("o"), "o", 560, lambda pen: ring(pen, 270, 230, 200, 200, SW))
    add(ord("p"), "p", 580, lambda pen: (stem(pen, 40, DESC, XHgt), ring(pen, 300, 230, 190, 180, 70)))
    add(ord("q"), "q", 580, lambda pen: (stem(pen, 400, DESC, XHgt), ring(pen, 250, 230, 190, 180, 70)))
    add(ord("r"), "r", 400, lambda pen: (stem(pen, 40, 0, XHgt, "bottom", 80), ring(pen, 180, 340, 140, 100, 50)))
    add(
        ord("s"),
        "s",
        480,
        lambda pen: (
            arc_band(pen, 230, 340, 150, 110, 56, math.radians(15), math.radians(200)),
            arc_band(pen, 230, 130, 160, 120, 56, math.radians(195), math.radians(370)),
        ),
    )
    add(ord("t"), "t", 400, lambda pen: (stem(pen, 140, 0, ASC, "bottom", 70), bar(pen, 40, 460, 280, 56)))
    add(ord("u"), "u", 580, lambda pen: (stem(pen, 40, 180, XHgt, "top", 80), stem(pen, 380, 0, XHgt, "both"), ring(pen, 250, 180, 180, 120, 56)))
    add(ord("v"), "v", 520, lambda pen: (diag(pen, 30, XHgt, 240, 0, 70), diag(pen, 450, XHgt, 240, 0, 70)))
    add(ord("w"), "w", 760, lambda pen: (diag(pen, 20, XHgt, 160, 0, 64), diag(pen, 320, XHgt, 160, 0, 64), diag(pen, 320, XHgt, 520, 0, 64), diag(pen, 680, XHgt, 520, 0, 64)))
    add(ord("x"), "x", 520, lambda pen: (diag(pen, 30, 0, 450, XHgt, 70), diag(pen, 450, 0, 30, XHgt, 70)))
    add(ord("y"), "y", 540, lambda pen: (diag(pen, 20, XHgt, 240, 80, 70), diag(pen, 460, XHgt, 80, DESC, 70)))
    add(ord("z"), "z", 480, lambda pen: (bar(pen, 40, XHgt - 56, 380, 52), bar(pen, 40, 0, 380, SB), diag(pen, 380, XHgt - 30, 60, 30, 64)))

    order = [".notdef"] + [n for n in glyphs if n != ".notdef"]
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=860, descent=240)
    fb.setupNameTable(
        {
            "familyName": "Scribe Serif",
            "styleName": "Regular",
            "uniqueFontIdentifier": "Scribe Serif Regular",
            "fullName": "Scribe Serif Regular",
            "psName": "ScribeSerif-Regular",
            "version": "Version 1.000",
        }
    )
    fb.setupOS2(sTypoAscender=860, sTypoDescender=-240, usWinAscent=860, usWinDescent=240, sxHeight=XHgt, sCapHeight=CAP)
    fb.setupPost()
    fb.save(str(path))


def specimen(font_path: Path) -> None:
    font = ImageFont.truetype(str(font_path), 48)
    small = ImageFont.truetype(str(font_path), 22)
    img = paper(1400, 520, 3, (214, 190, 154))
    d = ImageDraw.Draw(img)
    lines = [
        (font, "Auto-Scribe  Inventory  Unmark junk"),
        (font, "The quick brown fox jumps. 0123456789"),
        (small, "Trash   Favorite   Sell all junk   Level 12   480 Gold"),
        (small, "Health  Shield  Mana  Breath   Skill ready"),
        (font, "ELDORIA  ◆ ™  —  Settings"),
    ]
    y = 30
    for fnt, text in lines:
        d.text((36, y), text, font=fnt, fill=INK_RGB)
        y += 90 if fnt is font else 50
    img.save("/tmp/scribe_specimen.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "icons").mkdir(exist_ok=True)
    (OUT / "maps").mkdir(exist_ok=True)
    panels()
    buttons()
    icons()
    cursor()
    copy_maps()
    # The UI face is Libre Baskerville (OFL), not a generated serif.
    print("wrote", OUT)


if __name__ == "__main__":
    main()
