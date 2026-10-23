#!/usr/bin/env python3
"""Level TOML -> Godot .tscn generator (BUILD_PLAN step 2).

The TOML in data/levels/ stays the source of truth; the .tscn is generated from it
and checked into git so the editor and the game can load it directly.

  tools/toml_to_scene.py                       regenerate every known level
  tools/toml_to_scene.py --check               fail (exit 1) if a .tscn is stale
  tools/toml_to_scene.py IN.toml OUT.tscn      one level
  tools/toml_to_scene.py --self-test           validation self-test

Mapping (same rules as the archived C++ loader, archive/cpp-engine/game/world/level.cpp):
  * every [[box]] -> StaticBody3D named after `name`, transform = translate(center) *
    Basis.from_euler(rotation_deg, YXZ); children Mesh (BoxMesh of `size`) and Shape
    (BoxShape3D of `size`; size lives in the shape, not a node scale, so Jolt gets
    unscaled shapes). Metadata: kind, toml_index.
  * TOML colours are linear RGB (the C++ renderer wrote them to an sRGB swapchain);
    Godot Color properties are sRGB-encoded, so they are written as linear_to_srgb(c).
  * [environment] -> WorldEnvironment: clear colour = sky_color, ambient = ambient_color,
    exponential depth fog of fog_density toward sky_color (sky itself unfogged).
  * [sun] -> DirectionalLight3D whose +Z basis axis is to_light (light shines along -Z).
  * [player_start] -> Marker3D PlayerStart (feet) at position, yaw_deg about +Y
    (0 = facing north, -Z), with an Eye Marker3D 1.5 m up (Magewar body 0.8 + neck 0.7).
  * [[enemy]] -> Marker3D under EnemySpawns with metadata enemy (used from step 11).
  * Navigation (step 12) -> NavigationRegion3D with scripts/world/level_navigation.gd, a
    sibling of Boxes (Boxes keeps its node path): at load it bakes a NavigationMesh from
    the StaticBody3D colliders under ../Boxes, which the Gnawer paths on.
Python stdlib only (tomllib, Python >= 3.11).
"""
from __future__ import annotations

import math
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS = {  # source TOML -> generated scene
    "data/levels/midden_greybox.toml": "scenes/levels/midden.tscn",
}
KINDS = ("ground", "wall", "ramp", "crate", "heap", "platform")
EYE_HEIGHT = 1.5
NAV_SCRIPT = "res://scripts/world/level_navigation.gd"


class LevelError(Exception):
    pass


def _vec(v, what: str, n: int = 3) -> list[float]:
    if not isinstance(v, list) or len(v) != n or not all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v):
        raise LevelError(f"{what} must be an array of {n} numbers")
    return [float(x) for x in v]


def _color(v, what: str) -> list[float]:
    c = _vec(v, what)
    if any(x < 0.0 or x > 1.0 for x in c):
        raise LevelError(f"{what} components must be in [0, 1]")
    return c


def _only(t: dict, keys: set[str], where: str) -> None:
    for k in t:
        if k not in keys:
            raise LevelError(f"{where}: unknown key '{k}'")


def _need(t: dict, key: str, where: str):
    if key not in t:
        raise LevelError(f"{where}: missing key '{key}'")
    return t[key]


def rot_yxz(deg: list[float]) -> list[list[float]]:
    """Basis.from_euler(rad(deg), EULER_ORDER_YXZ) = Ry * Rx * Rz, row-major."""
    x, y, z = (math.radians(d) for d in deg)
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    return _mul(_mul(ry, rx), rz)


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def _apply(m, p):
    return [sum(m[i][k] * p[k] for k in range(3)) for i in range(3)]


def surface_distance(box: dict, p: list[float]) -> float:
    """Signed distance from p to the box (negative inside)."""
    m = rot_yxz(box["rotation_deg"])
    d = [p[i] - box["center"][i] for i in range(3)]
    local = [sum(m[k][i] * d[k] for k in range(3)) for i in range(3)]  # R^T * d
    q = [abs(local[i]) - box["size"][i] * 0.5 for i in range(3)]
    outside = math.sqrt(sum(max(x, 0.0) ** 2 for x in q))
    return outside + min(max(q[0], q[1], q[2]), 0.0)


def on_surface(boxes: list[dict], p: list[float], eps: float = 0.05) -> bool:
    return any(abs(surface_distance(b, p)) <= eps for b in boxes)


def parse_level(text: str) -> dict:
    try:
        d = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        raise LevelError(f"TOML: {e}") from e
    _only(d, {"level", "environment", "sun", "player_start", "box", "enemy"}, "top level")
    for sec in ("level", "environment", "sun", "player_start"):
        if sec not in d:
            raise LevelError(f"missing [{sec}]")
    lv = d["level"]
    _only(lv, {"id", "name"}, "[level]")
    env = d["environment"]
    _only(env, {"sky_color", "ambient_color", "fog_density"}, "[environment]")
    fog = float(env.get("fog_density", 0.0))
    if not 0.0 <= fog <= 1.0:
        raise LevelError("fog_density must be in [0, 1]")
    sun = d["sun"]
    _only(sun, {"to_light", "color"}, "[sun]")
    tl = _vec(_need(sun, "to_light", "[sun]"), "sun to_light")
    ln = math.sqrt(sum(x * x for x in tl))
    if ln < 1e-4:
        raise LevelError("sun to_light must not be zero")
    ps = d["player_start"]
    _only(ps, {"position", "yaw_deg"}, "[player_start]")
    out = {
        "id": str(_need(lv, "id", "[level]")),
        "name": str(_need(lv, "name", "[level]")),
        "sky_color": _color(_need(env, "sky_color", "[environment]"), "sky_color"),
        "ambient_color": _color(_need(env, "ambient_color", "[environment]"), "ambient_color"),
        "fog_density": fog,
        "to_light": [x / ln for x in tl],
        "sun_color": _color(_need(sun, "color", "[sun]"), "sun color"),
        "start_position": _vec(_need(ps, "position", "[player_start]"), "player_start position"),
        "start_yaw_deg": float(ps.get("yaw_deg", 0.0)),
        "boxes": [],
        "enemies": [],
    }
    names: set[str] = set()
    for i, b in enumerate(d.get("box", [])):
        w = f"box {i + 1}"
        _only(b, {"name", "kind", "center", "size", "rotation_deg", "color"}, w)
        name = str(_need(b, "name", w))
        w = f"box '{name}'"
        if name in names:
            raise LevelError(f"duplicate box name '{name}'")
        names.add(name)
        kind = str(_need(b, "kind", w))
        if kind not in KINDS:
            raise LevelError(f"{w}: unknown kind '{kind}'")
        size = _vec(_need(b, "size", w), f"{w} size")
        if min(size) <= 0.0:
            raise LevelError(f"{w}: size must be > 0")
        out["boxes"].append({
            "name": name, "kind": kind, "size": size,
            "center": _vec(_need(b, "center", w), f"{w} center"),
            "rotation_deg": _vec(b.get("rotation_deg", [0, 0, 0]), f"{w} rotation_deg"),
            "color": _color(_need(b, "color", w), f"{w} color"),
        })
    if not out["boxes"]:
        raise LevelError("need at least one [[box]]")
    if not on_surface(out["boxes"], out["start_position"]):
        raise LevelError("player_start position (feet) must lie on a box surface (within 5 cm)")
    for i, e in enumerate(d.get("enemy", [])):
        w = f"enemy {i + 1}"
        _only(e, {"enemy", "position", "yaw_deg"}, w)
        pos = _vec(_need(e, "position", w), f"{w} position")
        if not on_surface(out["boxes"], pos):
            raise LevelError(f"{w} position (feet) must lie on a box surface (within 5 cm)")
        out["enemies"].append({"enemy": str(_need(e, "enemy", w)), "position": pos,
                               "yaw_deg": float(e.get("yaw_deg", 0.0))})
    return out


# ---------------------------------------------------------------- .tscn writer
def _f(x: float) -> str:
    s = f"{x:.6f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def _srgb(c: float) -> float:
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1.0 / 2.4) - 0.055


def _color_str(c: list[float]) -> str:
    return "Color(%s, 1)" % ", ".join(_f(_srgb(x)) for x in c)


def _v3(v) -> str:
    return "Vector3(%s)" % ", ".join(_f(x) for x in v)


def _xf(basis, origin) -> str:
    vals = [basis[i][j] for i in range(3) for j in range(3)] + list(origin)
    return "Transform3D(%s)" % ", ".join(_f(x) for x in vals)


def sun_basis(z: list[float]) -> list[list[float]]:
    up = [0.0, 1.0, 0.0] if abs(z[1]) < 0.999 else [0.0, 0.0, 1.0]
    x = [up[1] * z[2] - up[2] * z[1], up[2] * z[0] - up[0] * z[2], up[0] * z[1] - up[1] * z[0]]
    n = math.sqrt(sum(a * a for a in x))
    x = [a / n for a in x]
    y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
    return [[x[i], y[i], z[i]] for i in range(3)]  # columns x, y, z


def to_tscn(lv: dict, source: str) -> str:
    subs: list[str] = []
    ids: dict[tuple, str] = {}

    def sub(kind: str, key, body: str) -> str:
        k = (kind, key)
        if k not in ids:
            ids[k] = f"{kind}_{len([1 for kk in ids if kk[0] == kind]) + 1}"
            subs.append(f'[sub_resource type="{kind}" id="{ids[k]}"]\n{body}\n')
        return ids[k]

    env = sub("Environment", 0, "\n".join([
        "background_mode = 1",
        f"background_color = {_color_str(lv['sky_color'])}",
        "ambient_light_source = 2",
        f"ambient_light_color = {_color_str(lv['ambient_color'])}",
        "tonemap_mode = 0",
        f"fog_enabled = {'true' if lv['fog_density'] > 0 else 'false'}",
        "fog_mode = 0",
        f"fog_light_color = {_color_str(lv['sky_color'])}",
        f"fog_density = {_f(lv['fog_density'])}",
        "fog_sky_affect = 0.0",
    ]))
    nodes: list[str] = []
    nodes.append(f'[node name="Midden" type="Node3D"]\nmetadata/level_id = "{lv["id"]}"\n'
                 f'metadata/level_name = "{lv["name"]}"\nmetadata/source = "res://{source}"\n')
    nodes.append(f'[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("{env}")\n')
    nodes.append(f'[node name="Sun" type="DirectionalLight3D" parent="."]\n'
                 f'transform = {_xf(sun_basis(lv["to_light"]), [0, 10, 0])}\n'
                 f'light_color = {_color_str(lv["sun_color"])}\nshadow_enabled = true\n')
    nodes.append('[node name="Boxes" type="Node3D" parent="."]\n')
    for i, b in enumerate(lv["boxes"]):
        sk = tuple(b["size"])
        mesh = sub("BoxMesh", sk, f"size = {_v3(b['size'])}")
        shape = sub("BoxShape3D", sk, f"size = {_v3(b['size'])}")
        mat = sub("StandardMaterial3D", tuple(b["color"]), f"albedo_color = {_color_str(b['color'])}")
        nodes.append(f'[node name="{b["name"]}" type="StaticBody3D" parent="Boxes"]\n'
                     f'transform = {_xf(rot_yxz(b["rotation_deg"]), b["center"])}\n'
                     f'metadata/kind = "{b["kind"]}"\nmetadata/toml_index = {i}\n')
        nodes.append(f'[node name="Mesh" type="MeshInstance3D" parent="Boxes/{b["name"]}"]\n'
                     f'mesh = SubResource("{mesh}")\nsurface_material_override/0 = SubResource("{mat}")\n')
        nodes.append(f'[node name="Shape" type="CollisionShape3D" parent="Boxes/{b["name"]}"]\n'
                     f'shape = SubResource("{shape}")\n')
    nodes.append('[node name="Navigation" type="NavigationRegion3D" parent="."]\n'
                 'script = ExtResource("1_nav")\nsource = NodePath("../Boxes")\n')
    nodes.append(f'[node name="PlayerStart" type="Marker3D" parent="."]\n'
                 f'transform = {_xf(rot_yxz([0, lv["start_yaw_deg"], 0]), lv["start_position"])}\n'
                 f'metadata/yaw_deg = {_f(lv["start_yaw_deg"])}\n')
    nodes.append(f'[node name="Eye" type="Marker3D" parent="PlayerStart"]\n'
                 f'transform = {_xf(rot_yxz([0, 0, 0]), [0, EYE_HEIGHT, 0])}\n')
    nodes.append('[node name="EnemySpawns" type="Node3D" parent="."]\n')
    for i, e in enumerate(lv["enemies"]):
        nodes.append(f'[node name="{e["enemy"]}_{i + 1}" type="Marker3D" parent="EnemySpawns"]\n'
                     f'transform = {_xf(rot_yxz([0, e["yaw_deg"], 0]), e["position"])}\n'
                     f'metadata/enemy = "{e["enemy"]}"\n')
    head = (f"; GENERATED by tools/toml_to_scene.py from {source}. Do not edit; edit the TOML and\n"
            f"; rerun the tool (tools/run_tests.sh fails while this file is stale).\n"
            f"[gd_scene format=3]\n")
    ext = f'[ext_resource type="Script" path="{NAV_SCRIPT}" id="1_nav"]\n'
    return head + "\n" + ext + "\n" + "\n".join(subs) + "\n" + "\n".join(nodes)


def generate(src: Path, rel_src: str) -> str:
    try:
        lv = parse_level(src.read_text(encoding="utf-8"))
    except LevelError as e:
        raise LevelError(f"{rel_src}: {e}") from e
    return to_tscn(lv, rel_src)


def self_test() -> int:
    good = (Path(ROOT / "data/levels/midden_greybox.toml")).read_text(encoding="utf-8")
    lv = parse_level(good)
    assert len(lv["boxes"]) == 17, len(lv["boxes"])
    scene = to_tscn(lv, "data/levels/midden_greybox.toml")
    assert '[node name="Navigation" type="NavigationRegion3D" parent="."]' in scene
    assert scene.index('name="Navigation"') > scene.index('parent="Boxes"')  # after the boxes it bakes
    assert NAV_SCRIPT in scene
    m = rot_yxz([90, 90, 0])
    assert all(abs(a - b) < 1e-9 for a, b in zip(_apply(m, [0, 0, 1]), [0, -1, 0]))  # Y*X*Z, like the C++ test
    hdr = ('[level]\nid = "t"\nname = "t"\n[environment]\nsky_color = [0.1, 0.1, 0.1]\nambient_color = [0.2, 0.2, 0.2]\n'
           '[sun]\nto_light = [0, 2, 0]\ncolor = [1, 1, 1]\n[player_start]\nposition = [0, 1, 0]\nyaw_deg = 0\n')
    box = '[[box]]\nname = "a"\nkind = "crate"\ncenter = [0, 0.5, 0]\nsize = [1, 1, 1]\ncolor = [1, 0, 0]\n'
    assert parse_level(hdr + box)["to_light"] == [0.0, 1.0, 0.0]
    bad = {
        box.replace("crate", "barrel"): "unknown kind 'barrel'",
        box.replace("size = [1, 1, 1]", "size = [1, 0, 1]"): "size must be > 0",
        box.replace("color", "colour"): "unknown key 'colour'",
        box.replace("[0, 0.5, 0]", "[0, 0.5]"): "must be an array of 3 numbers",
        box.replace("[1, 0, 0]", "[1, 2, 0]"): "[0, 1]",
        box.replace("[0, 0.5, 0]", "[5, 0.5, 0]"): "must lie on a box surface",
        box + box: "duplicate box name 'a'",
        "": "need at least one [[box]]",
    }
    for body, msg in bad.items():
        try:
            parse_level(hdr + body)
        except LevelError as e:
            assert msg in str(e), (msg, str(e))
        else:
            raise AssertionError(f"expected error: {msg}")
    print("[toml_to_scene] self-test OK")
    return 0


def main(argv: list[str]) -> int:
    if argv[:1] == ["--self-test"]:
        return self_test()
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    pairs = list(LEVELS.items()) if not args else [(args[0], args[1])]
    stale = 0
    for src, dst in pairs:
        try:
            text = generate(ROOT / src, src)
        except LevelError as e:
            print(f"[toml_to_scene] ERROR {e}", file=sys.stderr)
            return 1
        out = ROOT / dst
        if check:
            if not out.is_file() or out.read_text(encoding="utf-8") != text:
                print(f"[toml_to_scene] STALE {dst}: rerun tools/toml_to_scene.py", file=sys.stderr)
                stale += 1
            else:
                print(f"[toml_to_scene] {dst} up to date with {src}")
        else:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(text, encoding="utf-8")
            print(f"[toml_to_scene] wrote {dst} from {src}")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
