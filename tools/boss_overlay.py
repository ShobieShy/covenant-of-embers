#!/usr/bin/env python3
"""Put a boss front render beside its concept crop, and again as a 50% overlay.

    python3 tools/boss_overlay.py /opt/cursor/artifacts/bosses/after /opt/cursor/artifacts/bosses/overlay
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SHEETS = ROOT / "docs" / "concepts" / "creatures"
CROPS = json.loads((ROOT / "tools" / "boss_crops.json").read_text())


def crop_sheet(boss_id: str) -> Image.Image:
    spec = CROPS[boss_id]
    im = Image.open(SHEETS / spec["file"]).convert("RGB")
    w, h = im.size
    x0, y0, x1, y1 = spec["crop"]
    return im.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))


def key_magenta(im: Image.Image) -> Image.Image:
    arr = np.asarray(im.convert("RGBA")).astype(np.float32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mag = (r > 180) & (b > 180) & (g < 80)
    arr[mag, 3] = 0
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def content_box(im: Image.Image) -> tuple[int, int, int, int]:
    alpha = np.asarray(im.split()[-1])
    ys, xs = np.where(alpha > 16)
    if len(xs) == 0:
        return (0, 0, im.size[0], im.size[1])
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def fit_height(render: Image.Image, height: int) -> Image.Image:
    x0, y0, x1, y1 = content_box(render)
    cut = render.crop((x0, y0, x1, y1))
    scale = height / max(cut.size[1], 1)
    return cut.resize((max(1, int(cut.size[0] * scale)), height), Image.Resampling.LANCZOS)


def side_by_side(sheet: Image.Image, render: Image.Image) -> Image.Image:
    h = 720
    a = sheet.resize((int(sheet.size[0] * h / sheet.size[1]), h), Image.Resampling.LANCZOS)
    b = fit_height(render, h)
    canvas = Image.new("RGB", (a.size[0] + b.size[0] + 24, h), (90, 40, 90))
    canvas.paste(a, (0, 0))
    canvas.paste(b, (a.size[0] + 24, 0), b)
    return canvas


def overlay(sheet: Image.Image, render: Image.Image) -> Image.Image:
    base = sheet.convert("RGBA")
    fitted = fit_height(render, base.size[1])
    # Centre the render on the sheet. Both are the same silhouette height.
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    x = (base.size[0] - fitted.size[0]) // 2
    layer.paste(fitted, (x, 0), fitted)
    return Image.blend(base, layer, 0.5).convert("RGB")


def main() -> None:
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    tag = sys.argv[3] if len(sys.argv) > 3 else src.name
    for boss_id in CROPS:
        front = src / f"{boss_id}_p1_plate.png"
        if not front.is_file():
            print("missing", front)
            continue
        sheet = crop_sheet(boss_id)
        render = key_magenta(Image.open(front))
        side_by_side(sheet, render).save(dst / f"{tag}_{boss_id}_side_by_side.png")
        overlay(sheet, render).save(dst / f"{tag}_{boss_id}_overlay.png")
        print(tag, boss_id)
    print("wrote", dst)


if __name__ == "__main__":
    main()
