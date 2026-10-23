class_name Damage
extends RefCounted
## Damage formula (BUILD_PLAN step 6, port of the archived C++ game/combat/damage.*, old
## step 20; PLAN §30.1/§30.4):
##
##   wieldable damage = base x rarity multiplier + sum of part damage_bonus
##   hit damage       = wieldable damage x effectiveness(spell element, target affinity)
##                      x (1 - resist[spell element], clamped to 0..0.6) x weak point 2
##
## The first line is Magewar's StaffWieldableItem.get_final_damage (weapon system follows
## Magewar directly): part bonuses are flat and added after the rarity scaling. The
## effectiveness is MagicElement.get_effectiveness on impact (Magewar spell_projectile.gd
## / enemy_base.take_elemental_damage). Resistance is per incoming element like Magewar's
## magewar_player.get_elemental_resistance, but capped at 60 % (kept decision; Magewar
## clamps to 90 %). Weak points (x2) are our addition: Magewar has no crits.
## Enemies (step 11) and the player (step 13) call resolve_hit() with their own Target.

const RESIST_CAP := 0.6            ## per element, kept decision (Magewar 0.9)
const WEAK_POINT_MULTIPLIER := 2.0 ## PLAN §30.1 crit on a weak-point hitbox

## What a hit lands on.
class Target:
	extends RefCounted
	var affinity: ElementTable.Element = ElementTable.Element.ARCANE  ## defender element
	var resist := PackedFloat64Array()   ## 0..1 per incoming Element, uncapped (summed from gear)
	var weak_point := false              ## the hit struck a weak-point hitbox

	func _init(p_affinity: ElementTable.Element = ElementTable.Element.ARCANE) -> void:
		affinity = p_affinity
		resist.resize(ElementTable.COUNT)
		resist.fill(0.0)

	func set_resist(e: ElementTable.Element, r: float) -> Target:
		resist[e] = r
		return self

## What one hit did.
class Result:
	extends RefCounted
	var amount := 0.0          ## final damage dealt
	var effectiveness := 1.0   ## 0.5 / 1.0 / 1.5 from the chart
	var resist := 0.0          ## applied (clamped) resistance
	var crit := 1.0            ## WEAK_POINT_MULTIPLIER on a weak point, else 1

	func strong() -> bool:     ## Magewar "Super Effective!"
		return effectiveness > 1.0

	func weak() -> bool:       ## Magewar "Not Very Effective..."
		return effectiveness < 1.0

## Magewar get_final_damage: base x rarity multiplier + the parts' flat damage bonuses.
static func wieldable_damage(base: float, rarity_multiplier: float,
		part_bonuses: PackedFloat64Array = PackedFloat64Array()) -> float:
	var sum := 0.0
	for b in part_bonuses:
		sum += b
	return base * rarity_multiplier + sum

static func clamp_resist(r: float) -> float:
	return clampf(r, 0.0, RESIST_CAP)

## One hit of `damage` (wieldable damage; negative counts as 0, never heals) of `element`.
static func resolve_hit(damage: float, element: ElementTable.Element, target: Target,
		table: ElementTable = null) -> Result:
	var t := table if table != null else ElementTable.load_default()
	var r := Result.new()
	r.effectiveness = t.effectiveness(element, target.affinity)
	r.resist = clamp_resist(target.resist[element] if element < target.resist.size() else 0.0)
	r.crit = WEAK_POINT_MULTIPLIER if target.weak_point else 1.0
	r.amount = maxf(0.0, damage) * r.effectiveness * (1.0 - r.resist) * r.crit
	return r
