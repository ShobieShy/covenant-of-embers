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


## Step 150 (co-op §7): the status keys a client sends with its "hit" ("sm"); the host clamps each.
const NET_KEYS := {
	"status_seconds": 10.0,
	"status_pct": 100.0,
	"status_damage_pct": 300.0,
	"mark_seconds": 20.0,
	"vs_mark_status_pct": 300.0,
}


## The non-zero NET_KEYS of `mods` (what the host needs to apply this hit's statuses).
static func net_status(mods: Dictionary) -> Dictionary:
	var out := {}
	for k in NET_KEYS:
		var v := value(mods, k)
		if v != 0.0:
			out[k] = v
	return out


## Host side: only known keys, each clamped to [0, NET_KEYS[key]].
static func sanitize_net(d: Variant) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		return out
	for k in d:
		if NET_KEYS.has(String(k)):
			out[String(k)] = clampf(float(d[k]), 0.0, float(NET_KEYS[String(k)]))
	return out
