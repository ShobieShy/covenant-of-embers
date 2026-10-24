class_name Stash
extends RefCounted
## The Old Oak stash (BUILD_PLAN step 66; Bible Home Tree). One stash shared by every save
## slot / character: it lives in its own file (PATH), not in a slot save. Items move
## between the player's backpack and the stash; they are kept as ItemCodes (like saves).

const PATH := "user://stash.json"
const CAPACITY := 60

static var shared_path := PATH  ## tests point this elsewhere

var items: Array[Resource] = []
var path := PATH


static func load_shared(p := "") -> Stash:
	if p.is_empty():
		p = shared_path
	var s := Stash.new()
	s.path = p
	if FileAccess.file_exists(p):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			s.from_codes((d as Dictionary).get("items", []))
	return s


func save() -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"items": to_codes()}))
	return OK


func is_full() -> bool:
	return items.size() >= CAPACITY


## Backpack -> stash; false when the stash is full or the item isn't in the backpack.
func store(p: Player, item: Resource) -> bool:
	if is_full() or not p.inventory.has(item) or not p.inventory.remove(item):
		return false
	items.append(item)
	return true


## Stash -> backpack; false when the backpack is full or the item isn't stashed.
func take(p: Player, item: Resource) -> bool:
	if not items.has(item) or p.inventory.is_full() or not p.inventory.add(item):
		return false
	items.erase(item)
	return true


func to_codes() -> Array:
	var out: Array = []
	for it in items:
		var c := ItemCodes.encode(it)
		if not c.is_empty():
			out.append(c)
	return out


func from_codes(codes: Array) -> void:
	items.clear()
	for c in codes:
		var m := ItemCodes.decode(String(c))
		if m.ok() and items.size() < CAPACITY:
			items.append(m.item)
