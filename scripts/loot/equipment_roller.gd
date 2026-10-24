class_name EquipmentRoller
extends RefCounted
## Seeded equipment rolls and names (BUILD_PLAN step 19; PLAN §30.3). Follows Magewar's
## MagewarLootGenerator.generate_equipment_with_rng directly (weapon/loot = Magewar design):
##  - the Magewar template for the slot (apprentice_hat, basic_robes, leather_belt,
##    traveler_shoes, novice_grimoire; resources/equipment) keeps every stat the slot
##    doesn't roll (a rolled Shoes keeps the template's health 5, an Arcane Clothes the
##    template's 5 % resistance);
##  - ROLLS in Magewar's draw order, `rng.randf_range(lo, hi) × rarity multiplier`
##    (Shoes speed = 1 + that, so ×1.02–1.10 at Basic, more at higher tiers);
##  - Clothes resistance only for an elemental (non-Arcane) piece, any rarity (Magewar;
##    PLAN §30.3's "Rare+" was corrected). Reinterpreted: the resist draw is always made
##    and dropped for Arcane, so the element can be rolled after the stats and
##    regenerate() gives the same numbers;
##  - names "<Tattered|Sturdy|Enchanted|Arcane|Primordial|Legendary> [<Element>]
##    <Hat|Robes|Belt|Boots|Grimoire>" (Magewar _generate_equip_name), description =
##    EquipmentItem.full_description();
##  - seeding like PartRoller: roll() draws exactly one seed from the caller's rng and
##    from_seed() rolls on a private generator (stored in roll_seed; Ember Marks, step 20).

const S := EquipmentItem.Slot

## Magewar EQUIP_TEMPLATE_PATHS (resources/equipment ids).
const TEMPLATE_IDS := {
	S.HAT: "apprentice_hat",
	S.CLOTHES: "basic_robes",
	S.BELT: "leather_belt",
	S.SHOES: "traveler_shoes",
	S.GRIMOIRE: "novice_grimoire",
}

## Per slot: [stat, lo, hi, offset] in Magewar's draw order; value = offset + roll × mult.
const ROLLS := {
	S.HAT: [["mana_bonus", 5.0, 15.0, 0.0], ["spell_damage_bonus", 0.5, 3.0, 0.0], ["mana_regen_bonus", 0.2, 1.0, 0.0]],
	S.CLOTHES:
	[["health_bonus", 5.0, 20.0, 0.0], ["mana_bonus", 3.0, 10.0, 0.0], ["elemental_resistance", 0.05, 0.15, 0.0]],
	S.BELT: [["health_bonus", 3.0, 8.0, 0.0], ["stamina_bonus", 5.0, 15.0, 0.0]],
	S.SHOES: [["speed_modifier", 0.02, 0.10, 1.0], ["stamina_bonus", 3.0, 10.0, 0.0]],
	S.GRIMOIRE:
	[["spell_damage_bonus", 2.0, 8.0, 0.0], ["mana_bonus", 10.0, 25.0, 0.0], ["mana_regen_bonus", 0.5, 2.0, 0.0]],
}

## Magewar _generate_equip_name, by rarity tier / slot.
const PREFIXES: PackedStringArray = ["Tattered", "Sturdy", "Enchanted", "Arcane", "Primordial", "Legendary"]
const BASE_NAMES: PackedStringArray = ["Hat", "Robes", "Belt", "Boots", "Grimoire"]


## Rolls one piece: draws exactly one seed from `rng`, then from_seed(). element < 0 = roll it.
static func roll(rng: RandomNumberGenerator, slot: int, rarity_id: String, element: int = -1) -> EquipmentItem:
	return from_seed(rng.randi(), slot, rarity_id, element)


## The piece for (seed, slot, rarity, element): same inputs, same piece on every machine.
## Null for an unknown slot/rarity or a missing template.
static func from_seed(seed: int, slot: int, rarity_id: String, element: int = -1) -> EquipmentItem:
	if Rarity.parse(rarity_id) < 0 or not TEMPLATE_IDS.has(slot):
		return null
	var template := EquipmentItem.load_item(TEMPLATE_IDS[slot])
	if template == null:
		return null
	var item := template.duplicate() as EquipmentItem
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mult := RarityTable.load_default().multiplier(rarity_id)
	var rolled := {}
	for r in ROLLS[slot]:
		rolled[r[0]] = float(r[3]) + rng.randf_range(r[1], r[2]) * mult
	item.element_affinity = (
		(element if element >= 0 and element < ElementTable.COUNT else PartRoller.roll_element(rng))
		as ElementTable.Element
	)
	for stat in rolled:
		if stat == "elemental_resistance" and item.element_affinity == ElementTable.Element.ARCANE:
			continue  # Magewar: only elemental robes roll a resistance
		item.set(stat, rolled[stat])
	item.slot = slot as EquipmentItem.Slot
	item.rarity = rarity_id
	item.roll_seed = seed
	item.display_name = name_for(slot, rarity_id, item.element_affinity)
	item.id = (
		"%s_%s_%s_%08x"
		% [
			rarity_id,
			ElementTable.id_of(item.element_affinity),
			EquipmentItem.SLOT_NAMES[slot].to_lower(),
			seed & 0xFFFFFFFF
		]
	)
	item.description = item.full_description()
	return item


## Rebuilds a rolled piece from what it stores; null for a template (roll_seed < 0).
static func regenerate(item: EquipmentItem) -> EquipmentItem:
	if item == null or item.roll_seed < 0:
		return null
	return from_seed(item.roll_seed, item.slot, item.rarity, item.element_affinity)


## Final range of `stat` for a slot/rarity (offset included); Vector2.ZERO when not rolled.
static func stat_range(slot: int, rarity_id: String, stat: String) -> Vector2:
	var m := RarityTable.load_default().multiplier(rarity_id)
	for r in ROLLS.get(slot, []):
		if r[0] == stat:
			return Vector2(r[3] + r[1] * m, r[3] + r[2] * m)
	return Vector2.ZERO


static func rolled_stats(slot: int) -> PackedStringArray:
	var out := PackedStringArray()
	for r in ROLLS.get(slot, []):
		out.append(r[0])
	return out


static func name_for(slot: int, rarity_id: String, element: ElementTable.Element) -> String:
	var t := clampi(Rarity.parse(rarity_id), 0, PREFIXES.size() - 1)
	var base: String = BASE_NAMES[slot] if slot >= 0 and slot < BASE_NAMES.size() else "Item"
	if element != ElementTable.Element.ARCANE:
		return "%s %s %s" % [PREFIXES[t], ElementTable.load_default().display_name(element), base]
	return "%s %s" % [PREFIXES[t], base]
