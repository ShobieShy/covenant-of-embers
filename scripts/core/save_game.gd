class_name SaveGame
extends RefCounted
## Versioned JSON save (BUILD_PLAN step 38) in user://save.json.
## Items are Ember Mark strings (ItemCodes.encode; codes carry their own version): the
## backpack, staff + wand, the 5 equipment slots and the potion stack. Saved values:
## level/XP, Arcane Dust, current health/shield/mana/Breath (a save while dead stores the
## respawn state: full), skill ranks (step 71), and a free-form `progress` dictionary (level id, Breach cleared...).
## Load: pieces are worn first (equipment.slots, then one apply_bonuses() with the level
## bonuses rebuilt from the level), then the saved values are clamped in. Bonuses are never
## saved. A code that fails to decode is dropped with a warning; a save of another version
## is rejected with an error (never a crash).

const VERSION := 1
const PATH := "user://save.json"
const SLOTS := 3  # step 49: slot 1 keeps the old save.json path, so existing saves stay slot 1


static func slot_path(slot: int) -> String:
	slot = clampi(slot, 1, SLOTS)
	return PATH if slot == 1 else "user://save_%d.json" % slot


static func capture(p: Player, progress := {}) -> Dictionary:
	var dead := not p.alive()
	var eq: Array = []
	for i in EquipmentItem.SLOT_COUNT:
		var it := p.equipment.item(i)
		eq.append(ItemCodes.encode(it) if it else "")
	var inv: Array = []
	for it in p.inventory.items:
		var c := ItemCodes.encode(it)
		if not c.is_empty():
			inv.append(c)
	var staff := p.loadout.wieldable(Loadout.Slot.STAFF)
	var wand := p.loadout.wieldable(Loadout.Slot.WAND)
	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"player":
		{
			"level": p.progression.level,
			"xp": p.progression.xp,
			"xp_to_next": p.progression.xp_to_next,
			"total_xp": p.progression.total_xp,
			"dust": p.inventory.dust,
			"gold": p.inventory.gold,  # step 59
			"health": p.health.max_value() if dead else p.health.value,
			"shield": p.health.shield_max if dead else p.health.shield,
			"mana": p.mana.max_value() if dead else p.mana.value,
			"breath": p.breath.max_value() if dead else p.breath.value,
			"quest_items": Array(p.quest_items),  # step 57
			"archetype": p.archetype,  # step 73 (+ customization; travels with the character)
			"name": p.character_name,
			"color": p.character_color.to_html(false),
			"skills": p.skills.to_dict(),  # step 71 (older saves: no key = no ranks)
		},
		"items":
		{
			"staff": ItemCodes.encode(staff) if staff else "",
			"wand": ItemCodes.encode(wand) if wand else "",
			"equipment": eq,
			"potion":
			(
				ItemCodes.encode(p.equipment.potion, p.equipment.potion_count)
				if p.equipment.potion and p.equipment.potion_count > 0
				else ""
			),
			"inventory": inv,
		},
		"progress": progress.duplicate(true),
	}


static func write(data: Dictionary, path := PATH) -> Error:
	return UserDir.write_atomic(path, Compat.canonical(data))  # step 83 atomic, step 90 canonical bytes


## {"data": Dictionary} or {"error": String}.
static func read(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "no save at %s" % path}
	var txt := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if parser.parse(txt) != OK or not (parser.data is Dictionary):
		return {"error": "save is not a JSON object"}
	var j: Dictionary = parser.data
	var v := int(j.get("version", -1))
	if v != VERSION:
		return {"error": "unsupported save version %d (this build reads %d)" % [v, VERSION]}
	return {"data": j}


static func _decode(code: String, want: Script, warnings: PackedStringArray, what: String) -> EmberMark:
	if code.is_empty():
		return null
	var m := ItemCodes.decode(code)
	if not m.ok() or (want and m.item.get_script() != want and not is_instance_of(m.item, want)):
		var msg := "%s: dropped bad item code (%s)" % [what, m.error if not m.ok() else "wrong kind"]
		push_warning(msg)
		warnings.append(msg)
		return null
	return m


## Applies `data` (from read()) to `p`; returns the warnings (dropped codes).
static func apply(p: Player, data: Dictionary) -> PackedStringArray:
	var warn := PackedStringArray()
	var pl: Dictionary = data.get("player", {})
	var it: Dictionary = data.get("items", {})
	var pr := p.progression
	pr.level = maxi(1, int(pl.get("level", 1)))
	pr.xp = maxi(0, int(pl.get("xp", 0)))
	pr.xp_to_next = maxi(1, int(pl.get("xp_to_next", pr.xp_to_next)))
	pr.total_xp = maxi(0, int(pl.get("total_xp", 0)))
	p.level_health_bonus = Progression.HEALTH_PER_LEVEL * (pr.level - 1)
	p.level_mana_bonus = Progression.MANA_PER_LEVEL * (pr.level - 1)
	p.level_breath_bonus = Progression.BREATH_PER_LEVEL * (pr.level - 1)
	p.inventory.items.clear()
	p.inventory.dust = maxi(0, int(pl.get("dust", 0)))
	p.inventory.gold = maxi(0, int(pl.get("gold", Inventory.STARTING_GOLD)))
	var arch := Archetype.valid(String(pl.get("archetype", Archetype.DEFAULT)))
	var col := String(pl.get("color", ""))
	p.archetype = arch
	p.character_name = Archetype.clean_name(String(pl.get("name", "")))
	p.character_color = (
		Color.from_string(col, Archetype.default_color(arch)) if not col.is_empty() else Archetype.default_color(arch)
	)
	for c in it.get("inventory", []):
		var m := _decode(String(c), null, warn, "inventory")
		if m:
			p.inventory.add(m.item)
	for s in ["staff", "wand"]:
		var m := _decode(String(it.get(s, "")), WieldableInstance, warn, s)
		if m:
			p.loadout.equip(m.item as WieldableInstance)
	var eq: Array = it.get("equipment", [])
	for i in EquipmentItem.SLOT_COUNT:
		p.equipment.slots[i] = null
	for c in eq:
		var m := _decode(String(c), EquipmentItem, warn, "equipment")
		if m:
			p.equipment.slots[(m.item as EquipmentItem).slot] = m.item
	p.equipment.potion = null
	p.equipment.potion_count = 0
	var pm := _decode(String(it.get("potion", "")), ConsumableItem, warn, "potion")
	if pm:
		p.equipment.add_potions(pm.item as ConsumableItem, pm.count)
	p.quest_items = PackedStringArray(pl.get("quest_items", []))
	warn.append_array(p.skills.from_dict(pl.get("skills", {}), pr.level))
	p.apply_bonuses()
	p.health.value = clampf(float(pl.get("health", p.health.max_value())), 0.0, p.health.max_value())
	p.health.shield = clampf(float(pl.get("shield", p.health.shield_max)), 0.0, p.health.shield_max)
	p.mana.value = clampf(float(pl.get("mana", p.mana.max_value())), 0.0, p.mana.max_value())
	p.breath.value = clampf(float(pl.get("breath", p.breath.max_value())), 0.0, p.breath.max_value())
	if p.health.value <= 0.0:
		p.health.value = p.health.max_value()
	return warn
