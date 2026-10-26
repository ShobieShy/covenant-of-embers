class_name WieldablePart
extends Resource
## A staff/wand part (BUILD_PLAN steps 7 + 15; Magewar StaffPartItem, followed directly).
## Data: resources/parts/<id>.tres, imported from Magewar's 16 part resources
## (assets/magewar copies) by tools/import_magewar_parts.py (--check in run_tests.sh).
## Which stats count is decided by Magewar's StaffWieldableItem getters (WieldableInstance):
## damage_bonus on every part, fire_rate_modifier on Exterior + Charm, accuracy_bonus on
## Head + Handle + Charm, gem_slots on the Head. Magewar's own data sets some stats on
## other part types; ignored_stats() lists them (step 30's compare card greys them out).
## Rolled parts: PartRoller (step 16). Assembly rules (step 17) and the station (step 25) come later.

enum PartType { HEAD, EXTERIOR, INTERIOR, HANDLE, CHARM }  ## Magewar order

const DIR := "res://resources/parts"
const PART_TYPE_NAMES: PackedStringArray = ["Head", "Exterior", "Interior", "Handle", "Charm"]  ## Magewar get_part_type_name
const FIRE_RATE_TYPES: Array[PartType] = [PartType.EXTERIOR, PartType.CHARM]  ## Magewar get_final_fire_rate
const ACCURACY_TYPES: Array[PartType] = [PartType.HEAD, PartType.HANDLE, PartType.CHARM]  ## Magewar get_final_accuracy
const MAX_GEM_SLOTS := 3

@export var id := ""  ## lower_snake_case (= the Magewar file stem)
@export var display_name := ""  ## Magewar `name`
@export_multiline var description := ""  ## Magewar `description`
@export var part_type: PartType = PartType.HEAD
@export var rarity := "basic"  ## Rarity.IDS (look up with rarity_def())
@export var element: ElementTable.Element = ElementTable.Element.ARCANE  ## ARCANE = Magewar NONE = no override

## Step 108: a Dark part adds this (by rarity) to the 1% Dark conversion chance per hit.
const DARK_BONUS := {
	"basic": 0.0025, "uncommon": 0.005, "rare": 0.01, "mythic": 0.015, "primordial": 0.025, "unique": 0.03
}
@export var damage_bonus := 0.0  ## flat, every part type counts (Magewar)
@export var fire_rate_modifier := 1.0  ## Exterior and Charm multiply the cooldown
@export var accuracy_bonus := 0.0  ## Head, Handle and Charm count
@export var handling_bonus := 0.0  ## swap speed (step 17)
@export_range(0, 3) var gem_slots := 1  ## Head only: 1 (+1 Rare+, +1 Primordial+); Magewar's default 1
@export var gems: Array[ElementGem] = []  ## step 26: socketed gems (Head only, <= gem_slots)
@export var roll_seed := -1  ## PartRoller seed (step 16); -1 = hand-made part


static func make(
	p_type: PartType,
	p_damage_bonus := 0.0,
	p_fire_rate := 1.0,
	p_accuracy := 0.0,
	p_element: ElementTable.Element = ElementTable.Element.ARCANE
) -> WieldablePart:
	var p := WieldablePart.new()
	p.part_type = p_type
	p.damage_bonus = p_damage_bonus
	p.fire_rate_modifier = p_fire_rate
	p.accuracy_bonus = p_accuracy
	p.element = p_element
	p.gem_slots = PartRoller.gem_slots_for(p_type, p.rarity)  # non-Heads 0 (step 16 fix)
	return p


## resources/parts/<id>.tres (null when missing). Shared resource: duplicate() before editing.
static func load_part(part_id: String) -> WieldablePart:
	var path := "%s/%s.tres" % [DIR, part_id]
	return load(path) as WieldablePart if ResourceLoader.exists(path) else null


## Every part id under resources/parts, sorted.
static func list_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tres"):
			ids.append(f.get_basename())
	ids.sort()
	return ids


func rarity_def() -> Rarity:
	return Rarity.of(rarity)


func rarity_color() -> Color:
	return RarityTable.load_default().color(rarity)


func part_type_name() -> String:
	return PART_TYPE_NAMES[part_type] if part_type >= 0 and part_type < PART_TYPE_NAMES.size() else "Unknown"


## Stats set on this part that Magewar's final-stat getters never read for its type.
func ignored_stats() -> PackedStringArray:
	var out := PackedStringArray()
	if fire_rate_modifier != 1.0 and not part_type in FIRE_RATE_TYPES:
		out.append("fire_rate_modifier")
	if accuracy_bonus != 0.0 and not part_type in ACCURACY_TYPES:
		out.append("accuracy_bonus")
	if gem_slots > 0 and part_type != PartType.HEAD:
		out.append("gem_slots")
	return out


## Magewar get_full_description layout ("[Rare] Head", element, the non-default stats),
## numbers without trailing zeros. Stats the getters ignore are left out.
func full_description() -> String:
	var ignored := ignored_stats()
	var lines := PackedStringArray(["[%s] %s" % [RarityTable.load_default().display_name(rarity), part_type_name()]])
	if element != ElementTable.Element.ARCANE:
		lines.append("Element: " + ElementTable.load_default().display_name(element))
	if damage_bonus != 0.0:
		lines.append("Damage: " + _signed(damage_bonus))
	if fire_rate_modifier != 1.0 and not ignored.has("fire_rate_modifier"):
		lines.append("Fire Rate: x" + _num(fire_rate_modifier))
	if accuracy_bonus != 0.0 and not ignored.has("accuracy_bonus"):
		lines.append("Accuracy: " + _signed(accuracy_bonus))
	if handling_bonus != 0.0:
		lines.append("Handling: " + _signed(handling_bonus))
	if gem_slots > 0 and part_type == PartType.HEAD:
		lines.append("Gem Slots: %d" % gem_slots)
	if dark_chance_bonus() > 0.0:
		lines.append("Dark Conversion: +%s%%" % _num(dark_chance_bonus() * 100.0))
	return "\n".join(lines)


## Step 108: conversion chance this part adds (0 unless it is a Dark part).
func dark_chance_bonus() -> float:
	if element != ElementTable.Element.DARK:
		return 0.0
	return float(DARK_BONUS.get(rarity, 0.0))


static func _num(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else String.num(v, 2)


static func _signed(v: float) -> String:
	return ("+" if v >= 0.0 else "") + _num(v)


## Empty when usable; else one message per problem.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var w := "part '%s'" % id
	if RegEx.create_from_string("^[a-z0-9_]+$").search(id) == null:
		errs.append("%s: id must be lower_snake_case [a-z0-9_]" % w)
	if display_name.is_empty():
		errs.append("%s: name is empty" % w)
	if part_type < 0 or part_type >= PART_TYPE_NAMES.size():
		errs.append("%s: unknown part_type %d" % [w, part_type])
	if Rarity.parse(rarity) < 0:
		errs.append("%s: unknown rarity '%s' (expected %s)" % [w, rarity, ", ".join(Rarity.IDS)])
	if element < 0 or element >= ElementTable.COUNT:
		errs.append("%s: unknown element %d" % [w, element])
	if not (fire_rate_modifier > 0.0 and fire_rate_modifier <= 10.0):
		errs.append("%s fire_rate_modifier must be in (0, 10] (got %s)" % [w, fire_rate_modifier])
	for r in [["damage_bonus", damage_bonus], ["accuracy_bonus", accuracy_bonus], ["handling_bonus", handling_bonus]]:
		var v: float = r[1]
		if not (v >= -100.0 and v <= 100.0):
			errs.append("%s %s must be in [-100, 100] (got %s)" % [w, r[0], v])
	if gem_slots < 0 or gem_slots > MAX_GEM_SLOTS:
		errs.append("%s gem_slots must be in [0, %d] (got %d)" % [w, MAX_GEM_SLOTS, gem_slots])
	return errs


## Step 135: the brand for this part's own element (null for Arcane). Only the Head's brand
## counts on a wieldable (Q44); gems never change it (Q35).
func brand() -> Brand:
	return BrandTable.for_element(element)
