class_name PartRoller
extends RefCounted
## Seeded part stat rolls, gem slots and generated names (BUILD_PLAN step 16; PLAN §30.2).
## Follows Magewar's MagewarLootGenerator.generate_staff_part_with_rng directly (weapon/loot
## system = Magewar design):
##  - a Magewar template part per type (basic_fire_head, basic_exterior, basic_interior,
##    basic_handle, uncommon_earth_charm; ours in resources/parts) gives every stat the type
##    doesn't roll (e.g. a Charm keeps the template's handling 4);
##  - ROLLS: the stats each type rolls, in Magewar's draw order, `rng.randf_range(lo, hi)`,
##    × the rarity multiplier except fire-rate modifiers. Exterior fire rate ×0.7–1.3 below
##    Rare, ×0.5–1.0 at Rare+ (Magewar; PLAN's "×1.0 below Rare" was corrected to this);
##  - Head gem slots = 1 (+1 at Rare+, +1 at Primordial+), every other type 0;
##  - names: Magewar's _generate_*_name ladders (prefix / material / core / wrap / charm per
##    rarity tier, element names from ElementTable = Magewar ELEMENT_NAMES), description =
##    WieldablePart.full_description() (Magewar get_full_description);
##  - the element is the caller's (Magewar passes it in) or rolled from ELEMENT_WEIGHTS.
## Reinterpreted: every roll is seeded from the caller's RandomNumberGenerator (never the
## global one): roll() draws exactly one 32-bit seed from it and from_seed() rolls on a
## private generator, so every part stores `roll_seed` and regenerate() rebuilds it
## identically (PLAN §30.2 deterministic generation; Ember Marks in step 20). Magewar's
## roll_element ignores its own element_weights (uniform over 7); ours uses the weights.

const P := WieldablePart.PartType
const E := ElementTable.Element

## Magewar PART_TEMPLATE_PATHS (resources/parts ids).
const TEMPLATE_IDS := {
	P.HEAD: "basic_fire_head",
	P.EXTERIOR: "basic_exterior",
	P.INTERIOR: "basic_interior",
	P.HANDLE: "basic_handle",
	P.CHARM: "uncommon_earth_charm",
}

## Per type: [stat, lo, hi, scaled by the rarity multiplier], in Magewar's draw order.
const ROLLS := {
	P.HEAD: [["damage_bonus", 1.0, 5.0, true], ["accuracy_bonus", 0.0, 10.0, true]],
	P.EXTERIOR: [["fire_rate_modifier", 0.7, 1.3, false]],
	P.INTERIOR: [["damage_bonus", 2.0, 8.0, true]],
	P.HANDLE: [["accuracy_bonus", 5.0, 20.0, true], ["handling_bonus", 2.0, 10.0, true]],
	P.CHARM:
	[["damage_bonus", 0.0, 3.0, true], ["fire_rate_modifier", 0.85, 1.0, false], ["accuracy_bonus", 0.0, 8.0, true]],
}
## Magewar: Rare+ Exteriors roll ×0.5–1.0 ("faster at higher rarity").
const EXTERIOR_RARE_RATE := Vector2(0.5, 1.0)

## Magewar MagewarLootGenerator.element_weights (enum order Arcane..Dark).
const ELEMENT_WEIGHTS: PackedFloat64Array = [2.0, 1.0, 1.0, 1.0, 1.0, 0.5, 0.5]

## Magewar name ladders, indexed by rarity tier (Basic..Unique).
const HEAD_PREFIXES: PackedStringArray = ["Rough", "Polished", "Brilliant", "Ethereal", "Ancient", "Legendary"]
const EXTERIOR_MATERIALS: PackedStringArray = ["Oak", "Ash", "Ironwood", "Darkwood", "Starwood", "Worldtree"]
const INTERIOR_CORES: PackedStringArray = [
	"Mana Core", "Arcane Conduit", "Ley Channel", "Void Heart", "Prism Core", "Soul Engine"
]
const HANDLE_WRAPS: PackedStringArray = ["Leather", "Silk", "Chain", "Rune-etched", "Crystalweave", "Dragonhide"]
const CHARM_KINDS: PackedStringArray = ["Charm", "Talisman", "Sigil", "Ward", "Relic", "Artifact"]


## Rolls one part: draws exactly one seed from `rng`, then from_seed(). element < 0 = roll it.
static func roll(
	rng: RandomNumberGenerator, part_type: WieldablePart.PartType, rarity_id: String, element: int = -1
) -> WieldablePart:
	return from_seed(rng.randi(), part_type, rarity_id, element)


## The part for (seed, type, rarity, element): same inputs, same part, on every machine.
## Returns null for an unknown rarity or type, or a missing template.
static func from_seed(
	seed: int, part_type: WieldablePart.PartType, rarity_id: String, element: int = -1
) -> WieldablePart:
	var tier := Rarity.parse(rarity_id)
	if tier < 0 or not TEMPLATE_IDS.has(part_type):
		return null
	var template := WieldablePart.load_part(TEMPLATE_IDS[part_type])
	if template == null:
		return null
	var p := template.duplicate() as WieldablePart
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mult := RarityTable.load_default().multiplier(rarity_id)
	p.part_type = part_type
	p.rarity = rarity_id
	for r in ROLLS[part_type]:
		var range := stat_range(part_type, rarity_id, r[0])
		p.set(r[0], rng.randf_range(range.x, range.y))
	p.gem_slots = gem_slots_for(part_type, rarity_id)
	# Stats first (their draws don't depend on the element), so regenerate() can pass the
	# stored element and still get the same numbers.
	p.element = (
		(element if element >= 0 and element < ElementTable.COUNT else roll_element(rng)) as ElementTable.Element
	)
	p.roll_seed = seed
	p.display_name = name_for(part_type, rarity_id, p.element)
	p.id = (
		"%s_%s_%s_%08x"
		% [
			rarity_id,
			ElementTable.id_of(p.element),
			WieldablePart.PART_TYPE_NAMES[part_type].to_lower(),
			seed & 0xFFFFFFFF
		]
	)
	p.description = p.full_description()
	return p


## Rebuilds a rolled part from what it stores (roll_seed, type, rarity, element); null for a
## hand-made part (roll_seed < 0).
static func regenerate(part: WieldablePart) -> WieldablePart:
	if part == null or part.roll_seed < 0:
		return null
	return from_seed(part.roll_seed, part.part_type, part.rarity, part.element)


## Final (multiplied) roll range of `stat` for a type/rarity; Vector2.ZERO when the type
## doesn't roll it.
static func stat_range(part_type: WieldablePart.PartType, rarity_id: String, stat: String) -> Vector2:
	for r in ROLLS.get(part_type, []):
		if r[0] != stat:
			continue
		var lo: float = r[1]
		var hi: float = r[2]
		if part_type == P.EXTERIOR and Rarity.parse(rarity_id) >= Rarity.Tier.RARE:
			return EXTERIOR_RARE_RATE
		var m := RarityTable.load_default().multiplier(rarity_id) if r[3] else 1.0
		return Vector2(lo * m, hi * m)
	return Vector2.ZERO


## Stats a type rolls (Magewar order).
static func rolled_stats(part_type: WieldablePart.PartType) -> PackedStringArray:
	var out := PackedStringArray()
	for r in ROLLS.get(part_type, []):
		out.append(r[0])
	return out


## Magewar: Head 1 + (Rare+) + (Primordial+), max 3; every other part type 0.
static func gem_slots_for(part_type: WieldablePart.PartType, rarity_id: String) -> int:
	if part_type != P.HEAD:
		return 0
	var t := maxi(0, Rarity.parse(rarity_id))
	return 1 + (1 if t >= Rarity.Tier.RARE else 0) + (1 if t >= Rarity.Tier.PRIMORDIAL else 0)


## One weighted element draw (one rng.randf()); weights in ElementTable order.
static func roll_element(
	rng: RandomNumberGenerator, weights: PackedFloat64Array = ELEMENT_WEIGHTS
) -> ElementTable.Element:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, w)
	var pick := rng.randf() * total
	var cum := 0.0
	var last := E.ARCANE
	for i in mini(weights.size(), ElementTable.COUNT):
		if weights[i] <= 0.0:
			continue
		last = i as ElementTable.Element
		cum += weights[i]
		if pick < cum:
			return last
	return last


## Magewar _generate_<type>_name.
static func name_for(part_type: WieldablePart.PartType, rarity_id: String, element: ElementTable.Element) -> String:
	var t := clampi(Rarity.parse(rarity_id), 0, Rarity.COUNT - 1)
	var el := ElementTable.load_default().display_name(element)
	match part_type:
		P.HEAD:
			return "%s %s Crystal Head" % [HEAD_PREFIXES[t], el]
		P.EXTERIOR:
			return "%s Exterior" % EXTERIOR_MATERIALS[t]
		P.INTERIOR:
			return "%s %s" % [el, INTERIOR_CORES[t]]
		P.HANDLE:
			return "%s-Wrapped Handle" % HANDLE_WRAPS[t]
		P.CHARM:
			return "%s %s" % [el, CHARM_KINDS[t]]
	return "Unknown Part"
