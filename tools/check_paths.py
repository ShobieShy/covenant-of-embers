#!/usr/bin/env python3
"""res:// path case lint (BUILD_PLAN step 83).

Windows' filesystem is case-insensitive, so a res:// path with the wrong case works in the
editor there but breaks the Linux export (and vice versa for exported .pck lookups). Every
literal res://... in .gd/.tscn/.tres/.toml/.cfg/project.godot must match a real file with
exactly that case. Usage: check_paths.py [--self-test]
"""
from __future__ import annotations
import re, sys, tempfile
from pathlib import Path

PAT = re.compile(r'res://([A-Za-z0-9_\-./ ]+?)(?=["\'\s)\]]|$)')
EXTS = {".gd", ".tscn", ".tres", ".toml", ".cfg", ".godot"}
SKIP = {".godot", "build", "playtest", ".git", "addons"}


def exact_exists(root: Path, rel: str) -> str | None:
    """None if rel exists with exact case, else an error string."""
    cur = root
    for part in [p for p in rel.split("/") if p]:
        if not cur.is_dir():
            return "missing"
        names = {c.name for c in cur.iterdir()}
        if part not in names:
            lower = {n.lower(): n for n in names}
            return f"case mismatch (on disk: {lower[part.lower()]})" if part.lower() in lower else "missing"
        cur = cur / part
    return None


def check(root: Path) -> list[str]:
    errs = []
    for f in root.rglob("*"):
        if not f.is_file() or (f.suffix not in EXTS and f.name != "project.godot"):
            continue
        if any(p in SKIP for p in f.relative_to(root).parts[:-1]):
            continue
        for n, line in enumerate(f.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
            for m in PAT.finditer(line):
                rel = m.group(1).rstrip("/")
                if not rel or "%" in rel or rel.endswith(".") or "*" in rel:
                    continue
                e = exact_exists(root, rel)
                if e == "case mismatch" or (e and e.startswith("case")):
                    errs.append(f"{f.relative_to(root)}:{n}: res://{rel}: {e}")
    return errs


def self_test() -> None:
    with tempfile.TemporaryDirectory() as d:
        r = Path(d)
        (r / "scenes").mkdir()
        (r / "scenes" / "A.tscn").write_text("")
        (r / "x.gd").write_text('load("res://scenes/a.tscn")\nload("res://scenes/A.tscn")\n')
        e = check(r)
        assert len(e) == 1 and "case mismatch" in e[0], e
    print("check_paths self-test: OK")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test(); sys.exit(0)
    errs = check(Path(__file__).resolve().parent.parent)
    for e in errs:
        print(e)
    print("res:// path case lint: " + ("OK" if not errs else f"{len(errs)} error(s)"))
    sys.exit(1 if errs else 0)
