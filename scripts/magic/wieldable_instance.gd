class_name WieldableInstance
extends Resource
## A base staff/wand + the parts attached to it (BUILD_PLAN step 7). Final stats are
## Magewar's StaffWieldableItem getters, followed directly:
##   damage()   = get_final_damage: base x rarity multiplier + sum of every part's
##                damage_bonus (Damage.wieldable_damage, step 6)
##   cooldown() = get_final_fire_rate: base x Exterior x Charm fire_rate_modifier, >= 0.1 s
##   accuracy() = get_final_accuracy: 50 + Head + Handle + Charm accuracy_bonus, 0..100
##   element()  = get_element: the Head's element when it has one, else the base's
##   handling() = sum of every part's handling_bonus (step 17: shortens the draw; Magewar
##                declares the stat but never reads it)
##   gem_slots()= the Head's sockets (a wand caps them at 1, Bible)
## Legal builds come from Assembly.assemble() (step 17: staff 4-5 parts, wand 2-3; sets
## `assembled`); the getters themselves accept any part list (tests, Magewar getters).

## Rarity (RarityTable, step 15): a bare base uses its `base_rarity`; an assembled one uses
## floor(mean of its parts' tiers) (Magewar _calculate_assembled_rarity overwrites
## base_rarity on assembly; ours is computed from the current parts so it can't go stale).
const BASE_ACCURACY := 50.0

@export var def: WieldableDef
@export var parts: Array[WieldablePart] = []
@export var assembled := false   ## built by Assembly.assemble(): rarity from the parts

static func of(p_def: WieldableDef) -> WieldableInstance:
	var w := WieldableInstance.new()
	w.def = p_def
	return w

## Loads resources/wieldables/<id>.tres as a fresh instance (no parts).
static func load_base(id: String) -> WieldableInstance:
	var d := load("res://resources/wieldables/%s.tres" % id) as WieldableDef
	return of(d) if d != null else null

## Magewar ItemRarity.get_multiplier (x1.0 for an unknown id).
static func rarity_multiplier(rarity_id: String) -> float:
	return RarityTable.load_default().multiplier(rarity_id)

func rarity_id() -> String:
	return Assembly.rarity_for(parts) if assembled else def.base_rarity

func rarity() -> Rarity:
	return Rarity.of(rarity_id())

func rarity_color() -> Color:
	return RarityTable.load_default().color(rarity_id())

func type() -> WieldableDef.Type:
	return def.type

## The base's name; an assembled one is Magewar's "<Rarity> <Element> Staff|Wand".
func display_name() -> String:
	return Assembly.name_for(def.type, rarity_id(), element()) if assembled else def.display_name

## The attached part of `part_type` (first one), or null.
func part(part_type: WieldablePart.PartType) -> WieldablePart:
	for p in parts:
		if p != null and p.part_type == part_type:
			return p
	return null

func handling() -> float:
	var h := 0.0
	for p in parts:
		h += p.handling_bonus
	return h

## Swap-in time for a `base_seconds` draw (Loadout.swap_seconds), shortened by handling().
func draw_seconds(base_seconds: float) -> float:
	return Assembly.draw_seconds(base_seconds, handling())

func gem_slots() -> int:
	var head := part(WieldablePart.PartType.HEAD)
	if head == null:
		return 0
	return mini(head.gem_slots, Assembly.WAND_GEM_SLOTS) if def.type == WieldableDef.Type.WAND else head.gem_slots

func damage() -> float:
	var bonuses := PackedFloat64Array()
	for p in parts:
		bonuses.append(p.damage_bonus)
	var r := rarity()
	return Damage.wieldable_damage(def.damage, r.multiplier if r != null else 1.0, bonuses)

func cooldown() -> float:
	var rate := def.cooldown
	for p in parts:
		if p.part_type in WieldablePart.FIRE_RATE_TYPES:
			rate *= p.fire_rate_modifier
	return maxf(WieldableDef.MIN_COOLDOWN, rate)

func accuracy() -> float:
	var acc := BASE_ACCURACY
	for p in parts:
		if p.part_type in WieldablePart.ACCURACY_TYPES:
			acc += p.accuracy_bonus
	return clampf(acc, 0.0, 100.0)

func element() -> ElementTable.Element:
	for p in parts:
		if p.part_type == WieldablePart.PartType.HEAD and p.element != ElementTable.Element.ARCANE:
			return p.element
	return def.element

func mana_cost() -> float:
	return def.mana_cost

func projectile_speed() -> float:
	return def.projectile_speed

func range_m() -> float:
	return def.range_m
