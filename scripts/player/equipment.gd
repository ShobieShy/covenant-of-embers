class_name Equipment
extends RefCounted
## What a player wears (BUILD_PLAN step 19): one EquipmentItem per Hat / Clothes / Belt /
## Shoes / Grimoire slot plus a potion quick-slot (one ConsumableItem stack). Only holds
## items and sums them; Player.apply_bonuses() pushes the totals into Health / Mana /
## Breath / speed / damage_target / casters. Reinterpreted: Magewar adds and subtracts each
## item's stats on equip/unequip (+= / -=, speed *= and /=); we recompute the totals from
## the worn set every time, so removal is always exact.

signal changed(slot: int)   ## an equipment slot changed (-1 = the potion slot)

var slots: Array[EquipmentItem] = []
var potion: ConsumableItem
var potion_count := 0

func _init() -> void:
	slots.resize(EquipmentItem.SLOT_COUNT)

## Wears `item` in its slot; returns what was there (null). A null/invalid item does nothing.
func equip(item: EquipmentItem) -> EquipmentItem:
	if item == null or item.slot < 0 or item.slot >= EquipmentItem.SLOT_COUNT:
		return null
	var old := slots[item.slot]
	slots[item.slot] = item
	changed.emit(item.slot)
	return old

func unequip(slot: int) -> EquipmentItem:
	if slot < 0 or slot >= EquipmentItem.SLOT_COUNT or slots[slot] == null:
		return null
	var old := slots[slot]
	slots[slot] = null
	changed.emit(slot)
	return old

func item(slot: int) -> EquipmentItem:
	return slots[slot] if slot >= 0 and slot < EquipmentItem.SLOT_COUNT else null

func worn() -> Array[EquipmentItem]:
	var out: Array[EquipmentItem] = []
	for i in slots:
		if i != null:
			out.append(i)
	return out

func _sum(stat: String) -> float:
	var t := 0.0
	for i in worn():
		t += float(i.get(stat))
	return t

func health_bonus() -> float:
	return _sum("health_bonus")

func mana_bonus() -> float:
	return _sum("mana_bonus")

func stamina_bonus() -> float:
	return _sum("stamina_bonus")

func mana_regen_bonus() -> float:
	return _sum("mana_regen_bonus")

func spell_damage_bonus() -> float:
	return _sum("spell_damage_bonus")

## Product of the worn speed modifiers (Magewar multiplies them in).
func speed_multiplier() -> float:
	var m := 1.0
	for i in worn():
		m *= i.speed_modifier
	return m

## Per incoming element: the summed resistance of the worn pieces with that affinity,
## uncapped (Damage.resolve_hit caps at RESIST_CAP).
func resistances() -> PackedFloat64Array:
	var r := PackedFloat64Array()
	r.resize(ElementTable.COUNT)
	r.fill(0.0)
	for i in worn():
		r[i.element_affinity] += i.elemental_resistance
	return r

## Adds up to `count` potions to the quick-slot (one kind at a time, capped at its
## stack_size). Returns how many were taken.
func add_potions(p: ConsumableItem, count: int = 1) -> int:
	if p == null or count <= 0:
		return 0
	if potion != null and potion_count > 0 and potion.id != p.id:
		return 0
	potion = p
	var took := mini(count, p.stack_size - potion_count)
	potion_count += maxi(0, took)
	if took > 0:
		changed.emit(-1)
	return maxi(0, took)

## Uses one quick-slot potion on `target`; false (nothing spent) when empty or refused.
func use_potion(target: Object) -> bool:
	if potion == null or potion_count <= 0 or not potion.use(target):
		return false
	potion_count -= 1
	if potion_count == 0:
		potion = null
	changed.emit(-1)
	return true
