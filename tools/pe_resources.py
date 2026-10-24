#!/usr/bin/env python3
"""Dumps a Windows PE's icon + version resources (BUILD_PLAN step 84), stdlib only.

Usage: pe_resources.py EXE [--expect-version X.Y.Z.W] [--expect-product NAME]
Prints the resource types found, icon count, the fixed file/product version and the
StringFileInfo strings; exits 1 when an icon group or version resource is missing or an
expectation does not match. --self-test builds a tiny synthetic PE and checks the parser.
"""
from __future__ import annotations

import struct
import sys

RT_ICON, RT_GROUP_ICON, RT_VERSION = 3, 14, 16


def _sections(b: bytes):
    pe = struct.unpack_from("<I", b, 0x3C)[0]
    if b[pe : pe + 4] != b"PE\0\0":
        raise ValueError("not a PE file")
    nsec = struct.unpack_from("<H", b, pe + 6)[0]
    opt_size = struct.unpack_from("<H", b, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", b, opt)[0]
    dd = opt + (96 if magic == 0x10B else 112)
    rsrc_rva, rsrc_size = struct.unpack_from("<II", b, dd + 2 * 8)
    secs = []
    so = opt + opt_size
    for i in range(nsec):
        vsize, va, rsize, raw = struct.unpack_from("<IIII", b, so + i * 40 + 8)
        secs.append((va, max(vsize, rsize), raw))
    return rsrc_rva, rsrc_size, secs


def _rva_to_off(rva, secs):
    for va, size, raw in secs:
        if va <= rva < va + size:
            return rva - va + raw
    raise ValueError("rva %x outside sections" % rva)


def _walk(b, base, off, depth, path, out):
    n_named, n_id = struct.unpack_from("<HH", b, off + 12)
    for i in range(n_named + n_id):
        name, target = struct.unpack_from("<II", b, off + 16 + i * 8)
        key = path + [name & 0x7FFFFFFF if name & 0x80000000 == 0 else ("name", name)]
        if target & 0x80000000:
            _walk(b, base, base + (target & 0x7FFFFFFF), depth + 1, key, out)
        else:
            rva, size = struct.unpack_from("<II", b, base + target)
            out.append((key, rva, size))


def resources(b: bytes):
    rva, _size, secs = _sections(b)
    if rva == 0:
        return []
    base = _rva_to_off(rva, secs)
    out = []
    _walk(b, base, base, 0, [], out)
    return [(k, b[_rva_to_off(r, secs) : _rva_to_off(r, secs) + s]) for k, r, s in out]


def parse_version(data: bytes) -> dict:
    info = {}
    i = data.find(struct.pack("<I", 0xFEEF04BD))
    if i >= 0:
        fms, fls, pms, pls = struct.unpack_from("<IIII", data, i + 8)
        info["FileVersion#"] = "%d.%d.%d.%d" % (fms >> 16, fms & 0xFFFF, fls >> 16, fls & 0xFFFF)
        info["ProductVersion#"] = "%d.%d.%d.%d" % (pms >> 16, pms & 0xFFFF, pls >> 16, pls & 0xFFFF)
    text = data.decode("utf-16-le", errors="ignore")
    for key in ("CompanyName", "FileDescription", "FileVersion", "ProductName", "ProductVersion", "LegalCopyright"):
        j = text.find(key + "\0")
        if j >= 0:
            rest = text[j + len(key) + 1 :].lstrip("\0")
            info[key] = rest.split("\0", 1)[0]
    return info


def dump(b: bytes) -> dict:
    res = resources(b)
    types = sorted({k[0] for k, _ in res if isinstance(k[0], int)})
    icons = [d for k, d in res if k[0] == RT_ICON]
    groups = [d for k, d in res if k[0] == RT_GROUP_ICON]
    vers = [d for k, d in res if k[0] == RT_VERSION]
    return {"types": types, "icons": len(icons), "icon_groups": len(groups), "version": parse_version(vers[0]) if vers else {}}


def _synthetic() -> bytes:
    # DOS stub -> PE header -> 1 section (.rsrc at RVA 0x1000, raw 0x200) holding one RT_VERSION leaf.
    ver = struct.pack("<I", 0xFEEF04BD) + struct.pack("<I", 0x10000) + struct.pack("<IIII", 0x10002, 0x30001, 0x10002, 0x30001)
    ver += "ProductName\0Test Game\0".encode("utf-16-le")
    def d(entries):  # entries: (id, target)
        return struct.pack("<IIHHHH", 0, 0, 0, 0, 0, len(entries)) + b"".join(struct.pack("<II", i, t) for i, t in entries)
    root = d([(RT_VERSION, 0x80000000 | 0x18)])  # 16 + 8 = 0x18
    lvl2 = d([(1, 0x80000000 | 0x30)])
    lvl3 = d([(0x409, 0x48)])
    leaf = struct.pack("<IIII", 0x1000 + 0x58, len(ver), 0, 0)
    rsrc = root + lvl2 + lvl3 + leaf + ver
    pe_off = 0x40
    hdr = bytearray(0x200)
    hdr[0:2] = b"MZ"
    struct.pack_into("<I", hdr, 0x3C, pe_off)
    hdr[pe_off : pe_off + 4] = b"PE\0\0"
    struct.pack_into("<HH", hdr, pe_off + 4, 0x8664, 1)
    struct.pack_into("<H", hdr, pe_off + 20, 240)
    opt = pe_off + 24
    struct.pack_into("<H", hdr, opt, 0x20B)
    struct.pack_into("<II", hdr, opt + 112 + 16, 0x1000, len(rsrc))
    so = opt + 240
    hdr[so : so + 8] = b".rsrc\0\0\0"
    struct.pack_into("<IIII", hdr, so + 8, len(rsrc), 0x1000, len(rsrc), 0x200)
    return bytes(hdr) + rsrc


def main(argv) -> int:
    if argv[1:] == ["--self-test"]:
        r = dump(_synthetic())
        ok = r["types"] == [RT_VERSION] and r["version"].get("FileVersion#") == "1.2.3.1" and r["version"].get("ProductName") == "Test Game"
        print("pe_resources self-test:", "OK" if ok else "FAIL %s" % r)
        return 0 if ok else 1
    if len(argv) < 2:
        print(__doc__)
        return 2
    r = dump(open(argv[1], "rb").read())
    print("[pe] types %s, %d icon image(s) in %d group(s)" % (r["types"], r["icons"], r["icon_groups"]))
    for k, v in r["version"].items():
        print("[pe]   %s = %s" % (k, v))
    bad = []
    if r["icon_groups"] == 0 or r["icons"] == 0:
        bad.append("no icon")
    if not r["version"]:
        bad.append("no version resource")
    args = argv[2:]
    for flag, key in (("--expect-version", "FileVersion#"), ("--expect-product", "ProductName")):
        if flag in args:
            want = args[args.index(flag) + 1]
            if r["version"].get(key) != want:
                bad.append("%s %r != %r" % (key, r["version"].get(key), want))
    if bad:
        print("[pe] FAIL: " + ", ".join(bad))
        return 1
    print("[pe] OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
