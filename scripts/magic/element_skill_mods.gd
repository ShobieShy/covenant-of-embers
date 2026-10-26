class_name ElementSkillMods
extends RefCounted
## Phase V step 145 (docs/ELEMENT_TREES_PLAN.md section 3): the element-tree effects that apply
## to one element, as a plain dictionary (stat -> summed value) read by Caster, MagicEffects and
## FireMode. Pure lookups; constants are never written. An element skill counts only when the
## bolt (or the active wieldable's brand meter) is that element.

const SLOW_FLOOR := 0.45
const BURN_FRACTION_MAX := 0.6
const COST_MIN := 0.5  ## cost and cooldown multipliers never drop below this


## The summed effects of `skills`' tree for element `element` ({} without skills).
static func of(skills: Skills, element: int) -> Dictionary:
	if skills == null or element < 0 or element >= ElementTable.COUNT:
		return {}
	return skills.el_totals(ElementTable.id_of(element))


static func value(mods: Dictionary, key: String) -> float:
	return float(mods.get(key, 0.0))


## 1 + mods[key] / 100 (a percentage key as a multiplier), never below `floor_v`.
static func mult(mods: Dictionary, key: String, floor_v := 0.0) -> float:
	return maxf(floor_v, 1.0 + value(mods, key) / 100.0)


## The bolt's mods (spawn.mods), {} for a plain bolt.
static func of_hit(h: SpellBolts.Hit) -> Dictionary:
	return h.spawn.mods if h != null and h.spawn != null else {}
