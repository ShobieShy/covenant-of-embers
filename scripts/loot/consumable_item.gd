class_name ConsumableItem
extends Resource
## A potion (BUILD_PLAN step 19), Cogito ConsumableItemPD as Magewar uses it: Health Potion
## +30 health, Mana Potion +25 mana, stacks of 5, a hint on use. Like Cogito's
## increase_attribute, use() refuses (returns false, nothing consumed) when the pool is
## already full - hint "<attribute> is already maxed." - or the player is dead.
## Templates: resources/consumables (imported by tools/import_magewar_parts.py).

const DIR := "res://resources/consumables"
const ATTRIBUTES: PackedStringArray = ["health", "mana"]

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var attribute := "health"     ## "health" -> Health.heal, "mana" -> Mana.restore
@export var amount := 0.0
@export var stack_size := 5
@export var hint := ""                ## Magewar hint_text_on_use

static func load_item(item_id: String) -> ConsumableItem:
	var path := "%s/%s.tres" % [DIR, item_id]
	return load(path) as ConsumableItem if ResourceLoader.exists(path) else null

static func list_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tres"):
			ids.append(f.get_basename())
	ids.sort()
	return ids

func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if id.is_empty() or display_name.is_empty():
		errs.append("%s: no id/display_name" % id)
	if not attribute in ATTRIBUTES:
		errs.append("%s: attribute '%s' is not health/mana" % [id, attribute])
	if amount <= 0.0:
		errs.append("%s: amount %f must be > 0" % [id, amount])
	if stack_size < 1:
		errs.append("%s: stack_size %d < 1" % [id, stack_size])
	return errs

## Applies to a player (anything with `health: Health` and `mana: Mana`). True = used.
func use(target: Object) -> bool:
	if target == null:
		return false
	match attribute:
		"health":
			var h: Health = target.get("health")
			if h == null or h.dead or h.value >= h.max_value():
				return false
			h.heal(amount)
			return true
		"mana":
			var m: Mana = target.get("mana")
			if m == null or m.value >= m.max_value():
				return false
			m.restore(amount)
			return true
	return false

## The refusal hint (Cogito: "health is already maxed.").
func maxed_hint() -> String:
	return "%s is already maxed." % attribute
