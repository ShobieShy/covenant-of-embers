#!/usr/bin/env python3
"""Asset license lint (BUILD_PLAN step 5, PLAN §25).

Fails (exit 1) when anything under assets/ is not covered by ASSETS.toml,
or when an ASSETS.toml entry is incomplete.

What counts as a "top-level folder" (an *asset unit*):
  * every directory directly under assets/ is a unit, unless it is a
    *vendor grouping folder*: a folder that is not itself listed in
    ASSETS.toml and holds only sub-folders (e.g. assets/kenney/). A grouping
    folder is expanded and each of its children becomes a unit instead, so
    assets/kenney/<pack> is the unit for Kenney packs. Expansion recurses.
  * a unit is covered if its path, or one of its ancestors, is an
    ASSETS.toml `path`.
  * loose files (in assets/ or in a grouping folder) are never covered by a
    grouping folder, so they fail unless an entry covers them.
  Dotfiles (.gitattributes, .gitkeep, .DS_Store) are ignored.

Each [[asset]] entry must have non-empty string `name`, `path`, `license`
and `source`; `path` must start with assets/, exist, and be unique. Every
entry's `name` must also appear in CREDITS.md, so the manifest and the
human-facing credits never drift apart.

Python stdlib only (tomllib, Python >= 3.11), so CI needs no pip install.
Usage: check_assets.py [--root DIR] | --self-test
"""
from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path, PurePosixPath

if sys.version_info < (3, 11):
    sys.exit("check_assets.py needs Python >= 3.11 (tomllib)")
import tomllib

REQUIRED = ("name", "path", "license", "source")


def _visible(p: Path) -> bool:
    return not p.name.startswith(".")


def _covered(rel: PurePosixPath, listed: set[PurePosixPath]) -> bool:
    return any(rel == lp or lp in rel.parents for lp in listed)


def check(root: Path) -> list[str]:
    errors: list[str] = []
    manifest = root / "ASSETS.toml"
    assets = root / "assets"
    if not manifest.is_file():
        return [f"{manifest}: missing"]
    try:
        data = tomllib.loads(manifest.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as e:
        return [f"ASSETS.toml: parse error: {e}"]
    entries = data.get("asset", [])
    if not isinstance(entries, list):
        return ["ASSETS.toml: `asset` must be an array of tables ([[asset]])"]

    credits_path = root / "CREDITS.md"
    credits = credits_path.read_text(encoding="utf-8") if credits_path.is_file() else ""
    if not credits:
        errors.append("CREDITS.md: missing or empty")

    listed: set[PurePosixPath] = set()
    for i, e in enumerate(entries):
        label = f"ASSETS.toml asset #{i + 1}"
        if not isinstance(e, dict):
            errors.append(f"{label}: not a table")
            continue
        if isinstance(e.get("name"), str) and e["name"].strip():
            label += f" ({e['name']})"
        for key in REQUIRED:
            v = e.get(key)
            if not isinstance(v, str) or not v.strip():
                errors.append(f"{label}: missing or empty `{key}`")
        path = e.get("path")
        if not isinstance(path, str) or not path.strip():
            continue
        rel = PurePosixPath(path.strip().rstrip("/"))
        if rel.is_absolute() or ".." in rel.parts or rel.parts[:1] != ("assets",) or len(rel.parts) < 2:
            errors.append(f"{label}: path `{path}` must be a relative path inside assets/")
            continue
        if not (root / rel).exists():
            errors.append(f"{label}: path `{path}` does not exist")
        if rel in listed:
            errors.append(f"{label}: duplicate path `{path}`")
        listed.add(rel)
        name = e.get("name")
        if credits and isinstance(name, str) and name.strip() and name.strip() not in credits:
            errors.append(f"{label}: name not found in CREDITS.md")

    if not assets.is_dir():
        return errors  # nothing to cover yet

    def walk(d: Path) -> None:
        for child in sorted(filter(_visible, d.iterdir())):
            rel = PurePosixPath(child.relative_to(root).as_posix())
            if _covered(rel, listed):
                continue
            if child.is_dir():
                kids = list(filter(_visible, child.iterdir()))
                if kids and all(k.is_dir() for k in kids):
                    walk(child)  # vendor grouping folder, e.g. assets/kenney/
                else:
                    errors.append(f"{rel}/: asset folder not listed in ASSETS.toml")
            else:
                errors.append(f"{rel}: file not covered by any ASSETS.toml entry")

    walk(assets)
    return errors


def self_test() -> int:
    good_entry = (
        '[[asset]]\nname = "Pack A"\npath = "assets/vendor/pack-a"\n'
        'license = "CC0-1.0"\nsource = "https://example.org/a"\n'
    )

    def make(tmp: Path, manifest: str, dirs=(), files=(), credits="Pack A\n") -> Path:
        (tmp / "ASSETS.toml").write_text(manifest, encoding="utf-8")
        (tmp / "CREDITS.md").write_text(credits, encoding="utf-8")
        for d in ("assets/vendor/pack-a", *dirs):
            (tmp / d).mkdir(parents=True, exist_ok=True)
        (tmp / "assets/vendor/pack-a/model.glb").write_bytes(b"x")
        for f in files:
            (tmp / f).parent.mkdir(parents=True, exist_ok=True)
            (tmp / f).write_bytes(b"x")
        return tmp

    cases = [  # (description, expect_ok, manifest, dirs, files, credits)
        ("baseline passes", True, good_entry, (), (), "Pack A\n"),
        ("dotfiles ignored", True, good_entry, (), ("assets/.gitattributes",), "Pack A\n"),
        ("untracked top-level dir", False, good_entry, ("assets/stray",), (), "Pack A\n"),
        ("untracked pack in group", False, good_entry, ("assets/vendor/pack-b",), (), "Pack A\n"),
        ("loose file in group", False, good_entry, (), ("assets/vendor/readme.txt",), "Pack A\n"),
        ("loose file in assets/", False, good_entry, (), ("assets/x.png",), "Pack A\n"),
        ("missing license", False, good_entry.replace('license = "CC0-1.0"\n', ""), (), (), "Pack A\n"),
        ("empty source", False, good_entry.replace('"https://example.org/a"', '""'), (), (), "Pack A\n"),
        ("path outside assets", False, good_entry.replace("assets/vendor/pack-a", "../x"), (), (), "Pack A\n"),
        ("path missing on disk", False, good_entry + good_entry.replace("pack-a", "pack-z"), (), (), "Pack A\n"),
        ("duplicate path", False, good_entry * 2, (), (), "Pack A\n"),
        ("not in CREDITS.md", False, good_entry, (), (), "Someone else\n"),
        ("bad TOML", False, "[[asset]\n", (), (), "Pack A\n"),
    ]
    failed = 0
    for desc, expect_ok, manifest, dirs, files, credits in cases:
        with tempfile.TemporaryDirectory() as t:
            errs = check(make(Path(t), manifest, dirs, files, credits))
        ok = not errs
        status = "ok" if ok == expect_ok else "FAIL"
        if ok != expect_ok:
            failed += 1
        print(f"[{status}] {desc}: {'pass' if ok else 'fail'} ({len(errs)} error(s))")
    print(f"self-test: {len(cases) - failed}/{len(cases)} cases behaved as expected")
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                    help="repository root (default: parent of tools/)")
    ap.add_argument("--self-test", action="store_true", help="run built-in fixture tests")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    errors = check(args.root.resolve())
    for e in errors:
        print(f"error: {e}", file=sys.stderr)
    if errors:
        print(f"asset license lint: FAILED ({len(errors)} problem(s))", file=sys.stderr)
        return 1
    print("asset license lint: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
