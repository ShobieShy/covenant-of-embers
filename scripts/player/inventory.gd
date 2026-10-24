class_name Inventory
extends RefCounted
## The backpack (BUILD_PLAN steps 23-24; PLAN §30.3: 30-slot grid): staffs/wands
## (WieldableInstance), loose parts (WieldablePart) and equipment (EquipmentItem), one item
## per slot, plus the Arcane Dust counter (step 26 salvage currency, not a slot item).
## Magewar uses Cogito's grid inventory; this is a plain model the screens (step 30) draw.

signal changed()

const CAPACITY := 30

var capacity := CAPACITY
var items: Array[Resource] = []    ## dense, slot order = list order
var dust := 0                      ## Arcane Dust

static func accepts(item: Resource) -> bool:
	return item is WieldableInstance or item is WieldablePart or item is EquipmentItem

func size() -> int:
	return items.size()

func free_slots() -> int:
	return maxi(0, capacity - items.size())

func is_full() -> bool:
	return items.size() >= capacity

func has(item: Resource) -> bool:
	return items.has(item)

## Adds `item`; false when full, null, already inside or not a backpack item.
func add(item: Resource) -> bool:
	if item == null or not accepts(item) or is_full() or items.has(item):
		return false
	items.append(item)
	changed.emit()
	return true

func remove(item: Resource) -> bool:
	var i := items.find(item)
	if i < 0:
		return false
	items.remove_at(i)
	changed.emit()
	return true

func at(i: int) -> Resource:
	return items[i] if i >= 0 and i < items.size() else null

func add_dust(n: int) -> void:
	if n > 0:
		dust += n
		changed.emit()

func spend_dust(n: int) -> bool:
	if n < 0 or dust < n:
		return false
	dust -= n
	changed.emit()
	return true

func of_type(script: Script) -> Array[Resource]:
	var out: Array[Resource] = []
	for it in items:
		if it.get_script() == script or is_instance_of(it, script):
			out.append(it)
	return out
