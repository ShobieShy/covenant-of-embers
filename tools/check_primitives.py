#!/usr/bin/env python3
"""Art gate (0.11.3). Scan shipped scenes for PrimitiveMesh and CSG geometry.

Collision shapes and debug nodes are allowed. A scene listed in
tools/art_gate_remade.txt fails the build when it still has a primitive.
Every other scene is printed and does not fail. --self-test checks both paths
on fixture text, including a BoxMesh that must fail when the scene is remade.

  tools/check_primitives.py
  tools/check_primitives.py --self-test
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REMADE = ROOT / "tools" / "art_gate_remade.txt"
PRIMS = {
    "BoxMesh",
    "SphereMesh",
    "CapsuleMesh",
    "CylinderMesh",
    "PrismMesh",
    "PlaneMesh",
    "QuadMesh",
    "TorusMesh",
}
NODE_RE = re.compile(r'^\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]*)")?')
SUB_RE = re.compile(r'^\[sub_resource type="([^"]+)" id="([^"]+)"\]')
MESH_RE = re.compile(r'^mesh = SubResource\("([^"]+)"\)')


def remade_paths() -> set[str]:
    out: set[str] = set()
    if not REMADE.is_file():
        return out
    for line in REMADE.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        line = line.removeprefix("res://")
        out.add(line)
    return out


def _allowed(path: str) -> bool:
    for part in path.split("/"):
        low = part.lower()
        if "collision" in low or "debug" in low:
            return True
    return False


def scan_text(text: str) -> list[str]:
    """Primitive hits as 'path type'. Collision and debug nodes are omitted."""
    subs: dict[str, str] = {}
    hits: list[str] = []
    current = ""
    current_type = ""
    for line in text.splitlines():
        sub = SUB_RE.match(line)
        if sub:
            subs[sub.group(2)] = sub.group(1)
            current = ""
            continue
        node = NODE_RE.match(line)
        if node:
            name, typ, parent = node.group(1), node.group(2), node.group(3)
            if parent in (None, ".", ""):
                current = name
            else:
                current = f"{parent}/{name}"
            current_type = typ
            if typ.startswith("CSG") and not _allowed(current):
                hits.append(f"{current} {typ}")
            continue
        mesh = MESH_RE.match(line.strip())
        if mesh and current_type == "MeshInstance3D" and not _allowed(current):
            kind = subs.get(mesh.group(1), "")
            if kind in PRIMS:
                hits.append(f"{current} {kind}")
    return hits


def scan_tree() -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    """(enforced, reported) maps of scene path -> hits."""
    enforced_set = remade_paths()
    enforced: dict[str, list[str]] = {}
    reported: dict[str, list[str]] = {}
    for path in sorted((ROOT / "scenes").rglob("*.tscn")):
        rel = path.relative_to(ROOT).as_posix()
        hits = scan_text(path.read_text(encoding="utf-8", errors="replace"))
        if not hits:
            continue
        if rel in enforced_set:
            enforced[rel] = hits
        else:
            reported[rel] = hits
    missing = enforced_set - {p.relative_to(ROOT).as_posix() for p in (ROOT / "scenes").rglob("*.tscn")}
    for rel in sorted(missing):
        enforced[rel] = ["MISSING scene"]
    return enforced, reported


def self_test() -> int:
    bad = """
[sub_resource type="BoxMesh" id="BoxMesh_a"]
[sub_resource type="BoxShape3D" id="BoxShape_a"]
[node name="floor" type="StaticBody3D" parent="Boxes"]
[node name="Mesh" type="MeshInstance3D" parent="Boxes/floor"]
mesh = SubResource("BoxMesh_a")
[node name="Shape" type="CollisionShape3D" parent="Boxes/floor"]
shape = SubResource("BoxShape_a")
[node name="Marker" type="MeshInstance3D" parent="Debug"]
mesh = SubResource("BoxMesh_a")
[node name="Wall" type="CSGBox3D" parent="."]
[node name="DebugBlock" type="CSGBox3D" parent="Debug"]
"""
    hits = scan_text(bad)
    want = {"Boxes/floor/Mesh BoxMesh", "Wall CSGBox3D"}
    got = set(hits)
    if got != want:
        print(f"[primitives] self-test saw {sorted(got)}", file=sys.stderr)
        return 1
    clean = """
[sub_resource type="BoxShape3D" id="BoxShape_a"]
[node name="Shape" type="CollisionShape3D" parent="Boxes/floor"]
shape = SubResource("BoxShape_a")
"""
    if scan_text(clean):
        print("[primitives] self-test flagged a collision shape", file=sys.stderr)
        return 1
    print("[primitives] self-test ok")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    enforced, reported = scan_tree()
    for rel in sorted(reported):
        print(f"[primitives] REPORT {rel} {len(reported[rel])}")
    if not enforced:
        print(f"[primitives] enforced 0, reported {len(reported)}")
        return 0
    for rel in sorted(enforced):
        print(f"[primitives] FAIL {rel} {len(enforced[rel])}", file=sys.stderr)
        for hit in enforced[rel][:8]:
            print(f"  {hit}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
