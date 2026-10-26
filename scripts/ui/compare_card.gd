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
var kind := ""  ## "staff" / "wand" / "part" / "hat" ...
var rows: Array[Dictionary] = []  ## {stat, label, value, delta, better, compared}
var compared_to := ""  ## the current item's title, "" when nothing to compare
var gems: Array[Dictionary] = []  ## step 45: socketed gems {element, name, color}
var consecration := ""  ## step 45: consecration id ("" = none)
var consecration_text := ""
var current_consecration := ""  ## the compared item's consecration ("" = none / nothing compared)
var brand: Brand  ## step 140: the maker (Head element), null = unbranded
var is_wand := false


static func for_item(item: Resource, player: Player = null) -> CompareCard:
	var c := CompareCard.new()
	var rt := RarityTable.load_default()
	var current: Resource = null
	if item is WieldableInstance:
		var w := item as WieldableInstance
		c.title = w.display_name()
		c.rarity_id = w.rarity_id()
		c.kind = "wand" if w.type() == WieldableDef.Type.WAND else "staff"
		c.brand = w.brand()
		c.is_wand = w.is_wand()
		if player != null:
			current = player.loadout.wieldable(Loadout.slot_for(w))
		var cw := current as WieldableInstance
		c._row("damage", "Damage", w.damage(), cw.damage() if cw else NAN, true)
		c._row("cooldown", "Cast time (s)", w.cooldown(), cw.cooldown() if cw else NAN, false)
		c._row("accuracy", "Accuracy", w.accuracy(), cw.accuracy() if cw else NAN, true)
		c._row("mana_cost", "Mana cost", w.mana_cost(), cw.mana_cost() if cw else NAN, false)
		c._row("gem_slots", "Gem slots", w.gem_slots(), cw.gem_slots() if cw else NAN, true)
		if w.dark_chance_bonus() > 0.0 or (cw and cw.dark_chance_bonus() > 0.0):
			c._row(
				"dark_bonus",
				"Dark conversion %",
				w.dark_chance_bonus() * 100.0,
				cw.dark_chance_bonus() * 100.0 if cw else NAN,
				true
			)
		for part in w.parts:
			if part != null:
				c._add_gems(part.gems)
	elif item is WieldablePart:
		var p := item as WieldablePart
		c.title = p.display_name
		c.rarity_id = p.rarity
		c.kind = "part"
		c.brand = p.brand()
		c._row("damage_bonus", "Damage", p.damage_bonus, NAN, true)
		c._row("fire_rate_modifier", "Cast time x", p.fire_rate_modifier, NAN, false)
		c._row("accuracy_bonus", "Accuracy", p.accuracy_bonus, NAN, true)
		c._row("handling_bonus", "Handling", p.handling_bonus, NAN, true)
		c._row("gem_slots", "Gem slots", p.gem_slots, NAN, true)
		if p.dark_chance_bonus() > 0.0:
			c._row("dark_bonus", "Dark conversion %", p.dark_chance_bonus() * 100.0, NAN, true)
		c._add_gems(p.gems)
	elif item is EquipmentItem:
		var e := item as EquipmentItem
		c.title = e.display_name
		c.rarity_id = e.rarity
		c.kind = e.slot_name().to_lower()
		if player != null:
			current = player.equipment.item(e.slot)
		var ce := current as EquipmentItem
		for s in [
			["health_bonus", "Health", true],
			["mana_bonus", "Mana", true],
			["stamina_bonus", "Breath", true],
			["speed_modifier", "Speed x", true],
			["spell_damage_bonus", "Spell damage", true],
			["elemental_resistance", "Resistance", true],
			["mana_regen_bonus", "Mana regen/s", true]
		]:
			c._row(s[0], s[1], float(e.get(s[0])), float(ce.get(s[0])) if ce else NAN, s[2])
		c.consecration = e.consecration
		c.consecration_text = Consecrations.describe(e.consecration)
		if ce != null and ce != e:
			c.current_consecration = ce.consecration
	if current != null and current != item:
		c.compared_to = (
			current.call("display_name") if current is WieldableInstance else String(current.get("display_name"))
		)
	c.rarity_name = rt.display_name(c.rarity_id)
	c.color = rt.color(c.rarity_id)
	return c


func _add_gems(list: Array) -> void:
	var et := ElementTable.load_default()
	for g in list:
		if g is ElementGem:
			var el: ElementTable.Element = (g as ElementGem).element
			gems.append({"element": el, "name": et.display_name(el), "color": et.color(el)})


## Step 45: the gem + consecration lines as BBCode (shared by the inventory and station cards).
## Gems in their element colour; the consecration in gold with a "replaces"/"loses" delta line.
func extra_lines() -> String:
	var s := brand_line()
	if not gems.is_empty():
		var names := PackedStringArray()
		for g in gems:
			names.append("[color=#%s]%s[/color]" % [(g.color as Color).to_html(false), g.name])
		s += "Gems: %s (+%d damage)\n" % [", ".join(names), int(ElementGem.GEM_DAMAGE * gems.size())]
	if not consecration.is_empty():
		s += "[color=#e0b040]Consecrated: %s[/color] - %s\n" % [consecration.capitalize(), consecration_text]
		if not current_consecration.is_empty() and current_consecration != consecration:
			s += "[color=#e05050](replaces %s)[/color]\n" % current_consecration.capitalize()
	elif not current_consecration.is_empty():
		s += "[color=#e05050](loses %s)[/color]\n" % current_consecration.capitalize()
	return s


## Step 140: "[logo] Pyrowning Arms - Heat: hold to fire, ..." in the brand colour, plus the
## tagline in grey on Rare+ wieldables and "(wand: lighter)" on wands; "" when unbranded.
func brand_line() -> String:
	if brand == null:
		return ""
	var s := ""
	if not brand.logo_path.is_empty() and ResourceLoader.exists(brand.logo_path):
		s += "[img=16x16]%s[/img] " % brand.logo_path
	s += "[color=#%s][b]%s[/b][/color] - %s" % [brand.color.to_html(false), brand.display_name, brand.mode_line]
	if is_wand:
		s += " [i](wand: lighter)[/i]"
	s += "\n"
	if not brand.tagline.is_empty() and kind != "part" and Rarity.parse(rarity_id) >= Rarity.Tier.RARE:
		s += "[color=#a0a0a0][i]%s[/i][/color]\n" % brand.tagline
	return s


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
