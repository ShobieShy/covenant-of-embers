class_name CompareCard
extends RefCounted
## Item card data (BUILD_PLAN step 23, drawn in steps 30-31; PLAN §4 compare cards with
## green/red stat deltas): title, rarity name + colour, kind, and stat rows. When the
## player already has something in the same slot (staff/wand slot or equipment slot), each
## row carries `delta` = new - current and `better` (true/false; lower is better for the
## cooldown). Plain data so tests and UI share it.

var title := ""
var rarity_id := ""
var rarity_name := ""
var color := Color.WHITE
var kind := ""                     ## "staff" / "wand" / "part" / "hat" ...
var rows: Array[Dictionary] = []   ## {stat, label, value, delta, better, compared}
var compared_to := ""              ## the current item's title, "" when nothing to compare

static func for_item(item: Resource, player: Player = null) -> CompareCard:
	var c := CompareCard.new()
	var rt := RarityTable.load_default()
	var current: Resource = null
	if item is WieldableInstance:
		var w := item as WieldableInstance
		c.title = w.display_name()
		c.rarity_id = w.rarity_id()
		c.kind = "wand" if w.type() == WieldableDef.Type.WAND else "staff"
		if player != null:
			current = player.loadout.wieldable(Loadout.slot_for(w))
		var cw := current as WieldableInstance
		c._row("damage", "Damage", w.damage(), cw.damage() if cw else NAN, true)
		c._row("cooldown", "Cast time (s)", w.cooldown(), cw.cooldown() if cw else NAN, false)
		c._row("accuracy", "Accuracy", w.accuracy(), cw.accuracy() if cw else NAN, true)
		c._row("mana_cost", "Mana cost", w.mana_cost(), cw.mana_cost() if cw else NAN, false)
		c._row("gem_slots", "Gem slots", w.gem_slots(), cw.gem_slots() if cw else NAN, true)
	elif item is WieldablePart:
		var p := item as WieldablePart
		c.title = p.display_name
		c.rarity_id = p.rarity
		c.kind = "part"
		c._row("damage_bonus", "Damage", p.damage_bonus, NAN, true)
		c._row("fire_rate_modifier", "Cast time x", p.fire_rate_modifier, NAN, false)
		c._row("accuracy_bonus", "Accuracy", p.accuracy_bonus, NAN, true)
		c._row("handling_bonus", "Handling", p.handling_bonus, NAN, true)
		c._row("gem_slots", "Gem slots", p.gem_slots, NAN, true)
	elif item is EquipmentItem:
		var e := item as EquipmentItem
		c.title = e.display_name
		c.rarity_id = e.rarity
		c.kind = e.slot_name().to_lower()
		if player != null:
			current = player.equipment.item(e.slot)
		var ce := current as EquipmentItem
		for s in [["health_bonus", "Health", true], ["mana_bonus", "Mana", true],
				["stamina_bonus", "Breath", true], ["speed_modifier", "Speed x", true],
				["spell_damage_bonus", "Spell damage", true], ["elemental_resistance", "Resistance", true],
				["mana_regen_bonus", "Mana regen/s", true]]:
			c._row(s[0], s[1], float(e.get(s[0])), float(ce.get(s[0])) if ce else NAN, s[2])
	if current != null and current != item:
		c.compared_to = current.call("display_name") if current is WieldableInstance else String(current.get("display_name"))
	c.rarity_name = rt.display_name(c.rarity_id)
	c.color = rt.color(c.rarity_id)
	return c

func _row(stat: String, label: String, value: float, cur: float, higher_better: bool) -> void:
	var r := {"stat": stat, "label": label, "value": value, "compared": not is_nan(cur), "delta": 0.0, "better": false}
	if not is_nan(cur):
		r["delta"] = value - cur
		r["better"] = (value > cur) if higher_better else (value < cur)
	rows.append(r)

func row(stat: String) -> Dictionary:
	for r in rows:
		if r["stat"] == stat:
			return r
	return {}
