#!/usr/bin/env python3
"""Original staff cast and impact placeholders (CC0).

The batch_09 cast_*.ogg synth is broadband hiss (spectral flatness around 0.5-0.8).
These are a few sine partials with an envelope: a tone, not noise. Ember Art replaces
the files under assets/original/ember_art/sfx/staff/ when real audio is recorded.

License: CC0 1.0, original synthesis for Covenant of Embers. No Kenney or other
samples are mixed in.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/original/ember_art/sfx/staff"
SR = 44100
# Geometric mean / arithmetic mean of the magnitude spectrum. White noise is ~1,
# a handful of sines is well under 0.2.
FLAT_MAX = 0.2

# name -> (duration, decay, partials as (hz, amp) or ("sweep", f0, f1, amp))
CASTS = {
    "arcane": (0.48, 5.0, [(523.25, 1.0), (784.0, 0.55), (1046.5, 0.28)]),
    "fire": (0.42, 7.0, [("sweep", 320.0, 140.0, 1.0), (210.0, 0.7), (430.0, 0.35)]),
    "water": (0.5, 4.5, [("sweep", 660.0, 330.0, 1.0), (495.0, 0.4)]),
    "earth": (0.4, 10.0, [(92.5, 1.0), (138.0, 0.55), (185.0, 0.22)]),
    "air": (0.4, 6.0, [("sweep", 880.0, 1480.0, 1.0), (1760.0, 0.25)]),
    "light": (0.46, 5.5, [(659.25, 1.0), (1318.5, 0.45), (1975.5, 0.18)]),
    "dark": (0.55, 3.2, [(110.0, 1.0), (164.8, 0.6), (220.0, 0.3)]),
}
IMPACTS = {
    "arcane": (0.18, 16.0, [(784.0, 1.0), (1568.0, 0.4)]),
    "fire": (0.16, 18.0, [(220.0, 1.0), (330.0, 0.6), (440.0, 0.25)]),
    "water": (0.18, 14.0, [(523.25, 1.0), (784.0, 0.35)]),
    "earth": (0.2, 14.0, [(73.4, 1.0), (110.0, 0.45)]),
    "air": (0.14, 20.0, [(1174.0, 1.0), (1760.0, 0.3)]),
    "light": (0.16, 18.0, [(1046.5, 1.0), (2093.0, 0.4)]),
    "dark": (0.2, 12.0, [(98.0, 1.0), (146.8, 0.5)]),
}


def _render(dur: float, decay: float, partials: list) -> np.ndarray:
    n = int(SR * dur)
    t = np.arange(n, dtype=np.float64) / SR
    y = np.zeros(n, dtype=np.float64)
    for p in partials:
        if p[0] == "sweep":
            _, f0, f1, amp = p
            phase = 2.0 * np.pi * (f0 * t + (f1 - f0) * t * t / (2.0 * dur))
            y += amp * np.sin(phase)
        else:
            freq, amp = p
            y += amp * np.sin(2.0 * np.pi * freq * t)
    attack = np.minimum(t / 0.006, 1.0)
    y *= attack * np.exp(-decay * t)
    peak = np.max(np.abs(y))
    if peak > 0.0:
        y *= 0.89 / peak
    return y.astype(np.float32)


def _flatness(y: np.ndarray) -> float:
    w = y * np.hanning(len(y))
    spec = np.abs(np.fft.rfft(w)) + 1e-12
    return float(np.exp(np.mean(np.log(spec))) / np.mean(spec))


def _write(path: Path, y: np.ndarray) -> None:
    subprocess.run(
        [
            "ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1",
            "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "5", str(path),
        ],
        input=y.tobytes(),
        check=True,
    )


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    bad = 0
    for kind, table in (("cast", CASTS), ("impact", IMPACTS)):
        for name, (dur, decay, partials) in table.items():
            y = _render(dur, decay, partials)
            flat = _flatness(y)
            path = OUT / f"{kind}_{name}.ogg"
            if flat > FLAT_MAX:
                print(f"[staff_sfx] {path.name} flatness {flat:.3f} > {FLAT_MAX}", file=sys.stderr)
                bad += 1
            _write(path, y)
            print(f"[staff_sfx] {path.name} {dur:.2f}s flat={flat:.3f}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
