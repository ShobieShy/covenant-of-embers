class_name EquipmentItem
extends Resource
## One piece of worn equipment (BUILD_PLAN step 19; PLAN §30.3), Magewar EquipmentItem
## (weapon/loot system = Magewar design): a Hat / Clothes / Belt / Shoes / Grimoire with a
## rarity, an element affinity and flat bonuses. Player.apply_bonuses() (via Equipment)
## turns the worn totals into:
##   health_bonus -> Health max (Health.set_max_bonus: raise adds the difference, removal clamps)
##   mana_bonus -> Mana max (same rules), mana_regen_bonus -> Mana regen (+/s)
##   stamina_bonus -> Breath max (no refill; Magewar never applied it - flagged fix)
##   speed_modifier -> product of the worn ones scales walk/sprint/crouch
##   spell_damage_bonus -> flat + on every cast's damage (Magewar only displays it - flagged)
##   elemental_resistance -> summed per element_affinity into damage_target.resist,
##     uncapped; Damage.resolve_hit caps it at 60 % (Magewar get_elemental_resistance: 90 %).
## Templates: resources/equipment (imported from Magewar by tools/import_magewar_parts.py);
## rolled pieces come from EquipmentRoller (roll_seed >= 0).

enum Slot { HAT, CLOTHES, BELT, SHOES, GRIMOIRE }

const DIR := "res://resources/equipment"
const SLOT_COUNT := 5
const SLOT_NAMES: PackedStringArray = ["Hat", "Clothes", "Belt", "Shoes", "Grimoire"]   ## Magewar get_slot_name
const STATS: PackedStringArray = ["health_bonus", "mana_bonus", "stamina_bonus", "speed_modifier",
	"spell_damage_bonus", "elemental_resistance", "mana_regen_bonus"]

@export var id := ""                          ## lower_snake_case (= the Magewar file stem)
@export var display_name := ""                ## Magewar `name`
@export_multiline var description := ""
@export var slot: Slot = Slot.HAT             ## Magewar equip_slot
@export var rarity := "basic"                 ## Rarity.IDS
@export var element_affinity: ElementTable.Element = ElementTable.Element.ARCANE   ## ARCANE = Magewar NONE
@export var health_bonus := 0.0
@export var mana_bonus := 0.0
@export var stamina_bonus := 0.0              ## Breath max
@export var speed_modifier := 1.0             ## multiplier (Shoes 1.15)
@export var spell_damage_bonus := 0.0         ## flat, added to each cast
@export_range(0.0, 1.0) var elemental_resistance := 0.0   ## vs element_affinity damage
@export var mana_regen_bonus := 0.0           ## mana/s
@export var consecration := ""                ## step 36: Consecrations.DEFS id ("" = none)
@export var roll_seed := -1                   ## EquipmentRoller seed; -1 = template / hand-made

## resources/equipment/<id>.tres (null when missing). Shared resource: duplicate() before editing.
static func load_item(item_id: String) -> EquipmentItem:
	var path := "%s/%s.tres" % [DIR, item_id]
	return load(path) as EquipmentItem if ResourceLoader.exists(path) else null

## Every template id under resources/equipment, sorted.
static func list_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tres"):
			ids.append(f.get_basename())
	ids.sort()
	return ids

func slot_name() -> String:
	return SLOT_NAMES[slot] if slot >= 0 and slot < SLOT_COUNT else "Unknown"

func rarity_color() -> Color:
	return RarityTable.load_default().color(rarity)

## Problems with this item (empty = valid).
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if id.is_empty():
		errs.append("no id")
	if display_name.is_empty():
		errs.append("%s: no display_name" % id)
	if slot < 0 or slot >= SLOT_COUNT:
		errs.append("%s: slot %d out of range" % [id, slot])
	if Rarity.parse(rarity) < 0:
		errs.append("%s: unknown rarity '%s'" % [id, rarity])
	if element_affinity < 0 or element_affinity >= ElementTable.COUNT:
		errs.append("%s: element %d out of range" % [id, element_affinity])
	if speed_modifier <= 0.0:
		errs.append("%s: speed_modifier %f must be > 0" % [id, speed_modifier])
	if elemental_resistance < 0.0 or elemental_resistance > 1.0:
		errs.append("%s: elemental_resistance %f outside 0..1" % [id, elemental_resistance])
	return errs

## Magewar get_full_description layout ("[Rare] Clothes", affinity, the non-default stats),
## numbers without trailing zeros.
func full_description() -> String:
	var lines := PackedStringArray(["[%s] %s" % [RarityTable.load_default().display_name(rarity), slot_name()]])
	if element_affinity != ElementTable.Element.ARCANE:
		lines.append("Affinity: " + ElementTable.load_default().display_name(element_affinity))
	if health_bonus != 0.0:
		lines.append("Health: +" + num(health_bonus))
	if mana_bonus != 0.0:
		lines.append("Mana: +" + num(mana_bonus))
	if stamina_bonus != 0.0:
		lines.append("Stamina: +" + num(stamina_bonus))
	if speed_modifier != 1.0:
		lines.append("Speed: x" + num(speed_modifier))
	if spell_damage_bonus != 0.0:
		lines.append("Spell Damage: +" + num(spell_damage_bonus))
	if elemental_resistance > 0.0:
		lines.append("Resistance: %s%%" % num(elemental_resistance * 100.0))
	if mana_regen_bonus != 0.0:
		lines.append("Mana Regen: +" + num(mana_regen_bonus))
	return "\n".join(lines)

static func num(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else String.num(v, 2)
