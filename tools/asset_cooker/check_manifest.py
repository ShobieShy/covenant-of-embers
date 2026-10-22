#!/usr/bin/env python3
"""Verify an asset_cooker manifest against its sources (BUILD_PLAN step 6).

Checks that every .gltf/.glb/.png/.ogg under --source is listed, and that each
listed file exists in the cooked dir with the recorded size and FNV-1a 64 hash
identical to its source (the stub copies verbatim)."""
import argparse, json, pathlib, sys

KINDS = {".gltf", ".glb", ".png", ".ogg"}

def fnv1a64(b: bytes) -> str:
    h = 0xcbf29ce484222325
    for c in b:
        h = ((h ^ c) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--cooked", required=True)
    ap.add_argument("--source", required=True, help="dir that was cooked, relative to root")
    a = ap.parse_args()
    root, cooked = pathlib.Path(a.root), pathlib.Path(a.cooked)
    m = json.loads((cooked / "manifest.json").read_text())
    errs = []
    if m.get("format") != "coe-cooked-manifest" or m.get("version") != 1:
        errs.append("bad format/version")
    files = {f["source"]: f for f in m["files"]}
    if m.get("file_count") != len(m["files"]):
        errs.append("file_count mismatch")
    want = sorted(p.relative_to(root).as_posix() for p in (root / a.source).rglob("*")
                  if p.is_file() and p.suffix.lower() in KINDS
                  and not any(part.startswith(".") for part in p.relative_to(root).parts))
    for w in want:
        if w not in files:
            errs.append(f"not in manifest: {w}")
    for src, f in files.items():
        s, c = root / src, cooked / f["cooked"]
        if not c.is_file():
            errs.append(f"cooked file missing: {c}"); continue
        data = c.read_bytes()
        if data != s.read_bytes() or len(data) != f["bytes"] or fnv1a64(data) != f["hash"]:
            errs.append(f"content/size/hash mismatch: {src}")
        for d in f["deps"]:
            if d not in files:
                errs.append(f"{src}: dep {d} not cooked")
    for e in errs:
        print("FAIL", e)
    print(f"{len(want)} source files, {len(files)} manifest entries, {len(errs)} error(s)")
    return 1 if errs or not want else 0

if __name__ == "__main__":
    sys.exit(main())
