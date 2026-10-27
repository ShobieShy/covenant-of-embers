class_name WorldFog
extends RefCounted
## OW7: fog of war over the open world - 32 m cells, one bit each, revealed within
## RADIUS of each player. Saved as base64 under progress.fog (absent in old saves: all fog).

const CELL := 32.0
const RADIUS := 48.0
const INFO := "res://world/map.json"

var origin := Vector2.ZERO
var size := Vector2.ZERO
var cols := 0
var rows := 0
var bits := PackedByteArray()


func _init(o := Vector2.INF, s := Vector2.ZERO) -> void:
	if o == Vector2.INF:
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(INFO))
		if v is Dictionary:
			o = Vector2(v["origin"][0], v["origin"][1])
			s = Vector2(v["size"][0], v["size"][1])
		else:
			o = Vector2.ZERO
	origin = o
	size = s
	cols = ceili(s.x / CELL)
	rows = ceili(s.y / CELL)
	bits.resize((cols * rows + 7) / 8)
	bits.fill(0)


func _index(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return -1
	return c.y * cols + c.x


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - origin.x) / CELL), floori((z - origin.y) / CELL))


func is_revealed(x: float, z: float) -> bool:
	var i := _index(cell_of(x, z))
	return i >= 0 and (bits[i >> 3] >> (i & 7)) & 1 == 1


## Reveals every cell whose centre is within RADIUS of (x, z); returns how many were new.
func reveal(x: float, z: float) -> int:
	var c := cell_of(x, z)
	var r := ceili(RADIUS / CELL)
	var n := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := c + Vector2i(dx, dy)
			var centre := origin + (Vector2(k) + Vector2(0.5, 0.5)) * CELL
			var i := _index(k)
			if i < 0 or centre.distance_to(Vector2(x, z)) > RADIUS:
				continue
			if (bits[i >> 3] >> (i & 7)) & 1 == 0:
				bits[i >> 3] |= 1 << (i & 7)
				n += 1
	return n


func revealed_count() -> int:
	var n := 0
	for b in bits:
		while b:
			n += b & 1
			b >>= 1
	return n


## Co-op: the host's save also keeps what partners revealed.
func merge(other: WorldFog) -> void:
	if other.bits.size() != bits.size():
		return
	for i in bits.size():
		bits[i] |= other.bits[i]


func to_save() -> String:
	return Marshalls.raw_to_base64(bits)


func from_save(s: String) -> void:
	if s.is_empty():
		return
	var b := Marshalls.base64_to_raw(s)
	if b.size() == bits.size():  # a world resize drops old fog rather than misplacing it
		bits = b
