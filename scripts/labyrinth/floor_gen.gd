class_name FloorGen
extends RefCounted
## Labyrinth step L1: seeded floor generator (docs/LABYRINTH_PLAN.md section 6). The same
## algorithm as tools/labyrinth_gen.py, which writes tests/fixtures/labyrinth/*_golden.txt;
## test_floor_gen.gd checks both agree. Change one, change both, then --write-golden.
## A floor is a tree of rooms on a slot grid: a start -> exit main path with the elite
## room halfway, then the rest room and 1-2 secret rooms as side branches.

const M := 0xFFFFFFFF
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var _x := 1


static func load_kit(path: String = "res://data/labyrinth/warrens.toml") -> Dictionary:
	return LevelToml.load_file(path)


## The per-save, per-floor seed; `remix` > 0 re-rolls a cleared floor for farming.
static func floor_seed(save_seed: int, kit_id: String, floor_no: int, remix: int = 0) -> int:
	var h := 0x811C9DC5
	for b in ("%d:%s:%d:%d" % [save_seed, kit_id, floor_no, remix]).to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & M
	return h if h != 0 else 1


func _next() -> int:
	var x := _x
	x ^= (x << 13) & M
	x ^= x >> 17
	x ^= (x << 5) & M
	_x = x
	return x


func _below(n: int) -> int:
	return _next() % n


static func _free(cells: Dictionary, c: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for d in 4:
		if not cells.has(c + DIRS[d]):
			out.append(d)
	return out


## {seed, rooms: [{kind, room, cell: Vector2i, rot}], edges: [[a, b, secret 0/1]]}
static func generate(kit: Dictionary, seed_value: int) -> Dictionary:
	var g := FloorGen.new()
	g._x = seed_value & M if seed_value & M != 0 else 1
	var f: Dictionary = kit["floor"]
	var lo := int(f["main_min"])
	var n := lo + g._below(int(f["main_max"]) - lo + 1)
	var cells := {}
	var path: Array[Vector2i] = []
	var ok := false
	for _attempt in 64:
		cells = {Vector2i.ZERO: 0}
		path = [Vector2i.ZERO]
		while path.size() < n:
			var free := _free(cells, path[-1])
			if free.is_empty():
				break
			var c: Vector2i = path[-1] + DIRS[free[g._below(free.size())]]
			cells[c] = path.size()
			path.append(c)
		if path.size() == n:
			ok = true
			break
	if not ok:
		return {"error": "no path for seed %d" % seed_value}
	var kinds: Array[String] = []
	kinds.resize(n)
	kinds.fill("normal")
	kinds[0] = "start"
	kinds[n - 1] = "exit"
	kinds[n / 2] = "elite"
	var rooms: Array = []
	for i in n:
		rooms.append([kinds[i], path[i]])
	var edges: Array = []
	for i in n - 1:
		edges.append([i, i + 1, 0])
	var smin := int(f["secrets_min"])
	var branches := [
		["rest", int(f["rest"])], ["secret", smin + g._below(int(f["secrets_max"]) - smin + 1)]
	]
	for br: Array in branches:
		for _i in int(br[1]):
			var start := g._below(n - 2) + 1
			for k in n - 2:
				var host := 1 + (start - 1 + k) % (n - 2)
				var free := _free(cells, path[host])
				if not free.is_empty():
					var c: Vector2i = path[host] + DIRS[free[g._below(free.size())]]
					cells[c] = rooms.size()
					edges.append([host, rooms.size(), 1 if br[0] == "secret" else 0])
					rooms.append([br[0], c])
					break
	var out: Array = []
	for r: Array in rooms:
		var pool: Array[String] = []
		for kr: Dictionary in kit["room"]:
			if kr["kind"] == r[0]:
				pool.append(String(kr["id"]))
		var room := pool[g._below(pool.size())]
		out.append({"kind": r[0], "room": room, "cell": r[1], "rot": g._below(4)})
	return {"seed": seed_value, "rooms": out, "edges": edges, "stair_row": stair_row(path)}


## Exit room's stair hole row (0 north, 1 the southmost full row), as tools/labyrinth_gen.py.
## The exit's only doorway faces path[-2]; a north doorway would open onto a north-row hole.
## Uses no RNG, so room layouts are unchanged.
static func stair_row(path: Array[Vector2i]) -> int:
	return 1 if DIRS.find(path[-2] - path[-1]) == 0 else 0


## Same text as tools/labyrinth_gen.py signature(), for the golden comparison.
static func signature(fl: Dictionary) -> String:
	var rs: PackedStringArray = []
	for r: Dictionary in fl["rooms"]:
		rs.append("%s:%s:%d,%d:%d" % [r["kind"], r["room"], r["cell"].x, r["cell"].y, r["rot"]])
	var es: PackedStringArray = []
	for e: Array in fl["edges"]:
		es.append("%d-%d%s" % [e[0], e[1], "s" if e[2] else ""])
	return "%d %s %s stair=%d" % [fl["seed"], "|".join(rs), " ".join(es), fl["stair_row"]]


## Open sides (0 N, 1 E, 2 S, 3 W) of room `i`; the floor builder walls the others off.
static func doors(fl: Dictionary, i: int) -> Array[int]:
	var out: Array[int] = []
	for e: Array in fl["edges"]:
		var other := -1
		if e[0] == i:
			other = e[1]
		elif e[1] == i:
			other = e[0]
		if other >= 0:
			out.append(DIRS.find(fl["rooms"][other]["cell"] - fl["rooms"][i]["cell"]))
	out.sort()
	return out
