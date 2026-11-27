#!/usr/bin/env python3
"""Fail when an exported Linux build would draw a missing texture.

Textures named by an exported scene, a material, or a runtime load() must
be in the PCK (the imported .ctex, not merely the source file). Terrain
layer ids written into a level scene must also survive in the packed
scene: Godot 4.7 drops PackedStringArray overrides, and the zone then
asks for the script default, whose PNGs the export filter removes.

  tools/check_export_textures.py --self-test
  tools/check_export_textures.py build/linux/covenant_of_embers.x86_64
"""
from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEX = re.compile(r"res://(assets/[^\s\"']+\.(?:png|jpg|jpeg|webp))")
LAYER_LINE = re.compile(
    r"^layers = (?:Array\[String\]\(\[|PackedStringArray\()([^\]]*)",
    re.M,
)
QUOTED_RES = re.compile(r"""["'](res://assets/[^"']+)["']""")
MAPS = ("color.jpg", "normal.jpg", "roughness.jpg", "metalness.jpg", "emission.jpg")


def _strings(blob: bytes) -> set[str]:
    out: set[str] = set()
    cur = bytearray()
    for b in blob:
        if 32 <= b < 127:
            cur.append(b)
        else:
            if len(cur) >= 2:
                out.add(cur.decode())
            cur = bytearray()
    if len(cur) >= 2:
        out.add(cur.decode())
    return out


def read_pck(binary: Path) -> dict[str, bytes]:
    data = binary.read_bytes()
    header = None
    start = 0
    while True:
        i = data.find(b"GDPC", start)
        if i < 0 or i + 24 > len(data):
            break
        version, major, minor, _patch = struct.unpack_from("<4I", data, i + 4)
        if version == 4 and major == 4 and minor >= 4:
            header = i
            break
        start = i + 1
    if header is None:
        raise SystemExit(f"[export-textures] no Godot 4 PCK in {binary}")
    pos = header + 4
    version, _maj, _minor, _patch, _flags = struct.unpack_from("<5I", data, pos)
    pos += 20
    file_base = struct.unpack_from("<Q", data, pos)[0]
    pos += 8
    dir_offset = struct.unpack_from("<Q", data, pos)[0]
    pos = header + dir_offset
    count = struct.unpack_from("<I", data, pos)[0]
    pos += 4
    base = header + file_base
    files: dict[str, bytes] = {}
    for _i in range(count):
        sl = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        name = data[pos : pos + sl].split(b"\0", 1)[0].decode()
        pos += sl
        ofs, size = struct.unpack_from("<QQ", data, pos)
        pos += 16
        pos += 16  # md5
        pos += 4  # flags
        files[name] = data[base + ofs : base + ofs + size]
    return files


def layer_ids(text: str) -> list[str]:
    ids: list[str] = []
    for raw in LAYER_LINE.findall(text):
        ids.extend(re.findall(r'"([^"]+)"', raw))
    return ids


def layer_files(layer: str) -> list[str]:
    ember = [
        f"assets/original/ember_art/terrain/{layer}_albedo_height.png",
        f"assets/original/ember_art/terrain/{layer}_normal_roughness.png",
    ]
    if all((ROOT / p).is_file() for p in ember):
        return ember
    ambient = [
        f"assets/ambientcg/{layer}/terrain_alb_ht.png",
        f"assets/ambientcg/{layer}/terrain_nrm_rgh.png",
    ]
    if (ROOT / ambient[0]).is_file():
        return ambient
    return []


def referenced_textures() -> set[str]:
    needed: set[str] = set()
    texts: list[tuple[Path, str]] = []
    for folder in ("scenes", "resources", "scripts"):
        base = ROOT / folder
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if path.suffix not in {".tscn", ".tres", ".gd"}:
                continue
            texts.append((path, path.read_text(encoding="utf-8", errors="replace")))
    for _path, text in texts:
        for rel in TEX.findall(text):
            needed.add(rel)
        for layer in layer_ids(text):
            needed.update(layer_files(layer))
        for quoted in QUOTED_RES.findall(text):
            rel = quoted.removeprefix("res://")
            if "%s" in rel:
                continue
            if rel.endswith((".png", ".jpg", ".jpeg", ".webp")):
                needed.add(rel)
            elif rel.endswith("/"):
                for name in MAPS:
                    cand = rel + name
                    if (ROOT / cand).is_file():
                        needed.add(cand)
    return needed


def imported_ctex(rel: str) -> list[str]:
    imp = ROOT / f"{rel}.import"
    if not imp.is_file():
        return []
    text = imp.read_text(encoding="utf-8", errors="replace")
    found = re.findall(r"res://(\.godot/imported/[^\s\"']+\.ctex)", text)
    # Preserve order, drop duplicates (.import lists the same path twice).
    out: list[str] = []
    for item in found:
        if item not in out:
            out.append(item)
    return out


def scene_layer_errors(files: dict[str, bytes]) -> list[str]:
    errors: list[str] = []
    for path in sorted((ROOT / "scenes").rglob("*.tscn")):
        ids = layer_ids(path.read_text(encoding="utf-8", errors="replace"))
        if not ids:
            continue
        stem = path.stem
        packed = [name for name in files if name.endswith(f"-{stem}.scn") or name.endswith(f"/{stem}.scn")]
        if not packed:
            errors.append(f"{path.relative_to(ROOT)}: exported scene is not in the PCK")
            continue
        tokens: set[str] = set()
        for name in packed:
            tokens |= _strings(files[name])
        for layer in ids:
            if layer not in tokens:
                errors.append(
                    f"{path.relative_to(ROOT)}: layer {layer!r} did not survive export "
                    "(PackedStringArray overrides are dropped; use Array[String])"
                )
    return errors


def check(binary: Path) -> list[str]:
    if not binary.is_file():
        return [f"{binary}: missing export binary"]
    files = read_pck(binary)
    errors = scene_layer_errors(files)
    for rel in sorted(referenced_textures()):
        src = ROOT / rel
        if not src.is_file():
            errors.append(f"{rel}: referenced texture is not on disk")
            continue
        payloads = imported_ctex(rel)
        if not payloads:
            errors.append(f"{rel}: no .import, so the exporter cannot pack it")
            continue
        for payload in payloads:
            if payload not in files:
                errors.append(f"{rel}: imported file missing from the PCK ({payload})")
    return errors


def self_test() -> int:
    sample = 'layers = Array[String](["grass", "rock", "path_cobble"])\n'
    sample += 'layers = PackedStringArray("dirt")\n'
    assert layer_ids(sample) == ["grass", "rock", "path_cobble", "dirt"], layer_ids(sample)
    assert "grass" in _strings(b"xx\x00grass\x00rock-large.glb\x00")
    assert "rock" not in _strings(b"rock-large.glb\x00")
    print("export textures: self-test OK")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 1:
        print("usage: check_export_textures.py [--self-test] <linux-binary>", file=sys.stderr)
        return 2
    errors = check(Path(argv[0]))
    if errors:
        print(f"[export-textures] {len(errors)} missing", file=sys.stderr)
        for err in errors:
            print(f"[export-textures] {err}", file=sys.stderr)
        return 1
    print("[export-textures] every referenced texture is in the PCK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
