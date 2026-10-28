#!/usr/bin/env python3
"""Labyrinth step L1: seeded floor generator for a room kit (docs/LABYRINTH_PLAN.md section 6).

  tools/labyrinth_gen.py --self-test        checks the rules on many seeds
  tools/labyrinth_gen.py --check            golden file matches (tests/fixtures/labyrinth)
  tools/labyrinth_gen.py --write-golden     rewrites the golden file
  tools/labyrinth_gen.py SAVE_SEED FLOOR [REMIX]   prints one floor

scripts/labyrinth/floor_gen.gd is the same algorithm in GDScript; the unit test compares it
with the golden file line by line, so any change here must be made there too.
"""
import sys, tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "data/labyrinth/warrens.toml"
GOLDEN = ROOT / "tests/fixtures/labyrinth/warrens_golden.txt"
M = 0xFFFFFFFF
DIRS = [(0, -1), (1, 0), (0, 1), (-1, 0)]  # N E S W


def floor_seed(save_seed, kit_id, floor, remix=0):
    h = 0x811C9DC5
    for b in ("%d:%s:%d:%d" % (save_seed, kit_id, floor, remix)).encode():
        h = ((h ^ b) * 0x01000193) & M
    return h or 1


class Rng:
    def __init__(self, seed):
        self.x = seed & M or 1

    def next(self):
        x = self.x
        x ^= (x << 13) & M
        x ^= x >> 17
        x ^= (x << 5) & M
        self.x = x
        return x

    def below(self, n):
        return self.next() % n


def _free(cells, c):
    return [d for d in range(4) if (c[0] + DIRS[d][0], c[1] + DIRS[d][1]) not in cells]


def generate(kit, seed):
    f = kit["floor"]
    rng = Rng(seed)
    n = f["main_min"] + rng.below(f["main_max"] - f["main_min"] + 1)
    for _attempt in range(64):
        cells = {(0, 0): 0}
        path = [(0, 0)]
        while len(path) < n:
            free = _free(cells, path[-1])
            if not free:
                break
            d = free[rng.below(len(free))]
            c = (path[-1][0] + DIRS[d][0], path[-1][1] + DIRS[d][1])
            cells[c] = len(path)
            path.append(c)
        if len(path) == n:
            break
    else:
        raise RuntimeError("no path for seed %d" % seed)
    kinds = ["normal"] * n
    kinds[0], kinds[n - 1], kinds[n // 2] = "start", "exit", "elite"
    rooms = [[k, c] for k, c in zip(kinds, path)]
    edges = [[i, i + 1, 0] for i in range(n - 1)]
    branches = [("rest", f["rest"]), ("secret", f["secrets_min"] + rng.below(f["secrets_max"] - f["secrets_min"] + 1))]
    for kind, count in branches:
        for _ in range(count):
            start = rng.below(n - 2) + 1  # never off the start or the exit
            for k in range(n - 2):
                host = 1 + (start - 1 + k) % (n - 2)
                free = _free(cells, path[host])
                if free:
                    d = free[rng.below(len(free))]
                    c = (path[host][0] + DIRS[d][0], path[host][1] + DIRS[d][1])
                    cells[c] = len(rooms)
                    edges.append([host, len(rooms), 1 if kind == "secret" else 0])
                    rooms.append([kind, c])
                    break
    out = []
    for kind, c in rooms:
        pool = [r["id"] for r in kit["room"] if r["kind"] == kind]
        out.append({"kind": kind, "room": pool[rng.below(len(pool))], "cell": c, "rot": rng.below(4)})
    return {"seed": seed, "rooms": out, "edges": edges, "stair_row": stair_row(path)}


def stair_row(path):
    """Exit room's stair hole row: 0 = north row, 1 = the southmost full row.

    The exit is the path's last room and its only doorway faces path[-2]; a north doorway
    would open straight onto a north-row hole, so the hole moves south. No RNG is used, so
    room layouts are unchanged."""
    d = (path[-2][0] - path[-1][0], path[-2][1] - path[-1][1])
    return 1 if DIRS.index(d) == 0 else 0


def signature(fl):
    r = "|".join("%s:%s:%d,%d:%d" % (x["kind"], x["room"], x["cell"][0], x["cell"][1], x["rot"]) for x in fl["rooms"])
    e = " ".join("%d-%d%s" % (a, b, "s" if s else "") for a, b, s in fl["edges"])
    return "%d %s %s stair=%d" % (fl["seed"], r, e, fl["stair_row"])


GOLDEN_CASES = [(s, fl, rm) for s in (1, 42, 1337, 20261028, 4294967295) for fl in (1, 2, 3, 4) for rm in (0, 1)]


def golden(kit):
    return "".join("%d %d %d %s\n" % (s, fl, rm, signature(generate(kit, floor_seed(s, kit["kit"]["id"], fl, rm)))) for s, fl, rm in GOLDEN_CASES)


def validate(kit, fl):
    f = kit["floor"]
    rooms, edges = fl["rooms"], fl["edges"]
    kinds = [r["kind"] for r in rooms]
    assert kinds.count("start") == 1 and kinds.count("exit") == 1 and kinds.count("elite") == 1, kinds
    assert kinds.count("rest") == f["rest"], kinds
    assert f["secrets_min"] <= kinds.count("secret") <= f["secrets_max"], kinds
    cells = [tuple(r["cell"]) for r in rooms]
    assert len(set(cells)) == len(cells), "overlap"
    adj = {i: set() for i in range(len(rooms))}
    for a, b, s in edges:
        assert abs(cells[a][0] - cells[b][0]) + abs(cells[a][1] - cells[b][1]) == 1, "edge not adjacent"
        assert (s == 1) == (rooms[b]["kind"] == "secret")
        adj[a].add(b); adj[b].add(a)
    seen, todo = {0}, [0]
    while todo:
        for j in adj[todo.pop()] - seen:
            seen.add(j); todo.append(j)
    assert len(seen) == len(rooms), "disconnected"
    assert len(edges) == len(rooms) - 1, "not a tree"
    ex = kinds.index("exit")
    sides = [DIRS.index((cells[b][0] - cells[a][0], cells[b][1] - cells[a][1])) for a, b, _ in edges if a == ex] + [
        DIRS.index((cells[a][0] - cells[b][0], cells[a][1] - cells[b][1])) for a, b, _ in edges if b == ex]
    assert sides and not (fl["stair_row"] == 0 and 0 in sides), "doorway opens onto the stair well"
    assert not (fl["stair_row"] == 1 and 2 in sides), "doorway opens onto the stair well"


def load_kit(path=KIT):
    return tomllib.loads(Path(path).read_text())


def main(argv):
    kit = load_kit()
    if "--self-test" in argv:
        for s in range(2000):
            for floor in kit["kit"]["floors"]:
                validate(kit, generate(kit, floor_seed(s, kit["kit"]["id"], floor)))
        a = generate(kit, floor_seed(7, "warrens", 1))
        assert signature(a) == signature(generate(kit, floor_seed(7, "warrens", 1))), "not deterministic"
        assert signature(a) != signature(generate(kit, floor_seed(7, "warrens", 1, 1))), "remix did not change"
        print("[labyrinth_gen] self-test OK (8000 floors)")
    elif "--check" in argv:
        if not GOLDEN.exists() or GOLDEN.read_text() != golden(kit):
            print("[labyrinth_gen] %s is stale: run tools/labyrinth_gen.py --write-golden" % GOLDEN.relative_to(ROOT))
            return 1
        print("[labyrinth_gen] golden OK")
    elif "--write-golden" in argv:
        GOLDEN.write_text(golden(kit))
        print("[labyrinth_gen] wrote", GOLDEN.relative_to(ROOT))
    else:
        s, fl = int(argv[0]), int(argv[1])
        print(signature(generate(kit, floor_seed(s, kit["kit"]["id"], fl, int(argv[2]) if len(argv) > 2 else 0))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
