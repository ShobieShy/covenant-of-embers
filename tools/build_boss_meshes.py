#!/usr/bin/env python3
"""Rebuild the boss glbs as volumetric sculpts.

The sheets are reference only. This does not extrude or displace the paintings.
Requires Blender 4.2 on PATH, or BLENDER=/path/to/blender.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = Path(__file__).resolve().parent / "sculpt_bosses.py"


def main() -> None:
    blender = os.environ.get("BLENDER") or shutil.which("blender")
    if not blender:
        sys.exit("blender not found; set BLENDER to the Blender 4.2 binary")
    cmd = [blender, "-b", "-P", str(SCRIPT), "--", *sys.argv[1:]]
    raise SystemExit(subprocess.call(cmd))


if __name__ == "__main__":
    main()
