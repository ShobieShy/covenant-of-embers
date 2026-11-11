class_name NamedUniques
extends RefCounted
## 0.8.5 named uniques (issue #38). Handmade parts under resources/uniques, not the
## Magewar part folder, so the 16 imported parts stay untouched. Item codes keep
## version 1 for those parts and use index-table version 2 only when a named unique
## is in the code. SaveGame.VERSION stays 1.
## The pearlescent colour is the unique beam / compare-card tint. The Magewar unique
## tier gold stays on the rarity table for rolled uniques.

const COLOR := Color(0.91, 0.32, 0.72)
const BOSS_CHANCE := 0.22  ## dedicated unique from a boss, every kill
const RARE_CHANCE := 0.45  ## the named rare's own unique
const SIDE_SALT := 0x0A1505

## id -> source (boss id or rare id), effect, amount, display name, flavor.
## Names and flavor are proposals for ShobieShy.
const DEFS := {
	"unique_void_charm":
	{
		"source": "",
		"effect": "",
		"amount": 0.0,
		"name": "Unique Void Charm",
		"flavor": "A one-of-a-kind charm whispering of the Demon Lord's lair.",
	},
	"cinder_of_the_heap":
	{
		"source": "the_filth",
		"effect": "leech",
		"amount": 6.0,
		"name": "Cinder of the Heap",
		"flavor": "It still remembers the fire that was buried here.",
	},
	"rotglass_lens":
	{
		"source": "the_filth",
		"effect": "low_hp",
		"amount": 8.0,
		"name": "Rotglass Lens",
		"flavor": "The Filth looked through it. So do you.",
	},
	"matriarchs_mandible":
	{
		"source": "blightmaw_matriarch",
		"effect": "mana",
		"amount": 12.0,
		"name": "Matriarch's Mandible",
		"flavor": "A tooth that never stopped chewing the dark.",
	},
	"crownspore_charm":
	{
		"source": "blightmaw_matriarch",
		"effect": "next",
		"amount": 14.0,
		"name": "Crownspore Charm",
		"flavor": "The crown dies. The spore does not.",
	},
	"forgemaws_tooth":
	{
		"source": "forgemaw",
		"effect": "flat",
		"amount": 6.0,
		"name": "Forgemaw's Tooth",
		"flavor": "The forge bit down and left this behind.",
	},
	"slagheart":
	{
		"source": "forgemaw",
		"effect": "focus",
		"amount": 8.0,
		"name": "Slagheart",
		"flavor": "Hold your aim. The slag holds its heat.",
	},
	"gnawers_vow":
	{
		"source": "pit_warden",
		"effect": "leech",
		"amount": 4.0,
		"name": "Gnawer's Vow",
		"flavor": "The pit keeps what it kills, and so does this.",
	},
	"last_coal":
	{
		"source": "old_heap",
		"effect": "flat",
		"amount": 4.0,
		"name": "Last Coal",
		"flavor": "One coal left in a heap that should have gone cold.",
	},
	"sump_lantern":
	{
		"source": "pale_husk",
		"effect": "mana",
		"amount": 8.0,
		"name": "Sump Lantern",
		"flavor": "It still burns under the water.",
	},
	"canopy_antler":
	{
		"source": "crown_treant",
		"effect": "next",
		"amount": 10.0,
		"name": "Canopy Antler",
		"flavor": "Broken from a crown that walks.",
	},
	"brand_iron":
	{
		"source": "walking_brand",
		"effect": "flat",
		"amount": 5.0,
		"name": "Brand-Iron",
		"flavor": "The mark was hotter than the troll.",
	},
	"cinderspine":
	{
		"source": "unfinished_construct",
		"effect": "focus",
		"amount": 6.0,
		"name": "Cinderspine",
		"flavor": "The forge never finished it. The heat did.",
	},
}

static var _next := {}
static var _bound := false


static func is_named(part_id: String) -> bool:
	return DEFS.has(part_id)


static func flavor(part_id: String) -> String:
	return String(DEFS.get(part_id, {}).get("flavor", ""))


static func effect_line(part_id: String) -> String:
	var d: Dictionary = DEFS.get(part_id, {})
	if d.is_empty():
		return ""
	var n := int(d["amount"])
	match String(d["effect"]):
		"leech":
			return "Kills restore %d health" % n
		"mana":
			return "Kills restore %d mana" % n
		"low_hp":
			return "Below half health, spells deal +%d damage" % n
		"next":
			return "After a kill, your next spell deals +%d damage" % n
		"flat":
			return "Spells deal +%d damage" % n
		"focus":
			return "While focused, spells deal +%d damage" % n
		_:
			return ""


static func color_for(item: Resource, fallback: Color) -> Color:
	if item is WieldablePart and is_named((item as WieldablePart).id):
		return COLOR
	return fallback


static func ids_for(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in DEFS:
		if String(DEFS[id]["source"]) == source and source != "":
			out.append(id)
	return out


## Side stream from the kill rng's state, so the kill's own draws stay in order.
static func roll_drop(source: String, state: int) -> String:
	var ids := ids_for(source)
	if ids.is_empty():
		return ""
	var chance := RARE_CHANCE if not source in ["the_filth", "blightmaw_matriarch", "forgemaw"] else BOSS_CHANCE
	var side := RandomNumberGenerator.new()
	side.seed = state ^ SIDE_SALT
	if side.randf() >= chance:
		return ""
	return ids[side.randi_range(0, ids.size() - 1)]


static func make_drop(part_id: String) -> LootDrop:
	var part := WieldablePart.load_part(part_id)
	if part == null:
		return null
	var d := LootDrop.new()
	d.kind = LootDrop.Kind.PART
	d.item = part.duplicate()
	d.rarity_id = "unique"
	d.rolled_rarity_id = "unique"
	d.element = part.element
	return d


static func tick(p: Player) -> void:
	if not _bound:
		_bound = true
		GameEvents.bus().enemy_killed.connect(_on_killed)
	var bonus := 0.0
	var low := p.health != null and p.health.max_value() > 0.0 and p.health.value < p.health.max_value() * 0.5
	var focused := p.focus != null and p.focus.focused
	for id in _equipped(p):
		var d: Dictionary = DEFS[id]
		var amt := float(d["amount"])
		match String(d["effect"]):
			"flat":
				bonus += amt
			"low_hp":
				if low:
					bonus += amt
			"focus":
				if focused:
					bonus += amt
	var extra := float(_next.get(p.get_instance_id(), 0.0))
	_next.erase(p.get_instance_id())
	for c in p.loadout.casters:
		c.conditional_bonus += bonus
		if extra > 0.0:
			c.next_cast_bonus += extra


static func _equipped(p: Player) -> PackedStringArray:
	var out := PackedStringArray()
	var w: WieldableInstance = p.caster.wieldable if p.caster != null else null
	if w == null:
		return out
	for part in w.parts:
		if part != null and DEFS.has(part.id) and String(DEFS[part.id]["effect"]) != "":
			out.append(part.id)
	return out


static func _on_killed(enemy: Enemy, _element: ElementTable.Element) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	for n in enemy.get_tree().get_nodes_in_group(Player.GROUP):
		if not (n is Player) or not (n as Player).alive():
			continue
		var p := n as Player
		for id in _equipped(p):
			var d: Dictionary = DEFS[id]
			var amt := float(d["amount"])
			match String(d["effect"]):
				"leech":
					if p.health != null:
						p.health.heal(amt)
				"mana":
					if p.mana != null:
						p.mana.restore(amt)
				"next":
					var key := p.get_instance_id()
					_next[key] = float(_next.get(key, 0.0)) + amt
