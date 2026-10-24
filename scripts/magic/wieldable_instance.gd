class_name WieldableInstance
extends Resource
## A base staff/wand + the parts attached to it (BUILD_PLAN step 7). Final stats are
## Magewar's StaffWieldableItem getters, followed directly:
##   damage()   = get_final_damage: base x rarity multiplier + sum of every part's
##                damage_bonus (Damage.wieldable_damage, step 6)
##   cooldown() = get_final_fire_rate: base x Exterior x Charm fire_rate_modifier, >= 0.1 s
##   accuracy() = get_final_accuracy: 50 + Head + Handle + Charm accuracy_bonus, 0..100
##   element()  = get_element: the Head's element when it has one, else the base's
## The part list is free-form until step 17 adds the assembly rules (counts per type).

## Rarity: the base's `base_rarity` looked up in the Rarity resource (RarityTable, step 15;
## replaced step 7's temporary basic/uncommon lookup). Step 17 averages the parts instead.
const BASE_ACCURACY := 50.0

@export var def: WieldableDef
@export var parts: Array[WieldablePart] = []

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
	return def.base_rarity

func rarity() -> Rarity:
	return Rarity.of(rarity_id())

func rarity_color() -> Color:
	return RarityTable.load_default().color(rarity_id())

func type() -> WieldableDef.Type:
	return def.type

func display_name() -> String:
	return def.display_name

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
