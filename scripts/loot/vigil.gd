class_name Vigil
extends RefCounted
## Vigils (BUILD_PLAN step 28; PLAN §31.4): endgame tiers 1..10 (0 = off) with seeded Omens.
## Difficulty and reward are separate curves; the rarity shift goes through WeightModel on a
## COPY of the RarityTable (rarities.tres is never edited) and then the normal
## RarityTable.roll(rng, luck) - so Magewar's luck rule still stacks on top.
## All numbers are placeholders for playtesting (our design, not Magewar's).
##   enemy health x(1 + 0.25 t), enemy damage x(1 + 0.15 t), XP x(1 + 0.10 t)
##   rarity weight: Basic x 1/(1 + 0.05 t), Uncommon x1, Rare+ x(1 + 0.10 t (tier_index - 1))
##   omens: t 1-3 one Easy, 4-6 + one Medium, 7-9 + one Hard, 10 + a second Hard.

const MAX_TIER := 10
const HEALTH_PER_TIER := 0.25
const DAMAGE_PER_TIER := 0.15
const XP_PER_TIER := 0.10
const BASIC_DROP_PER_TIER := 0.05
const RARE_SHIFT_PER_TIER := 0.10

## Omen pools. "rarity" = extra rare+ weight multiplier; others are hooks for later steps.
const OMENS := {
	"easy":
	[
		{"id": "ember_rain", "name": "Ember Rain", "enemy_damage": 1.10},
		{"id": "restless", "name": "Restless Dead", "enemy_health": 1.10},
		{"id": "gilded_ashes", "name": "Gilded Ashes", "rarity": 1.20},
	],
	"medium":
	[
		{"id": "shades_twice", "name": "Shades rise twice", "enemy_health": 1.20},
		{"id": "hungry_dark", "name": "Hungry Dark", "enemy_damage": 1.20, "rarity": 1.10},
	],
	"hard":
	[
		{"id": "ward_regen", "name": "Wards regenerate faster", "enemy_health": 1.30},
		{"id": "blood_moon", "name": "Blood Moon", "enemy_damage": 1.30, "rarity": 1.25},
		{"id": "iron_vow", "name": "Iron Vow", "enemy_health": 1.40},
	],
}

var tier := 0
var session_seed := 0  ## per session, stored in the save (step 33) to share a run
var rerolls := 0
var omens: Array[Dictionary] = []


static func create(t: int, session_seed: int) -> Vigil:
	var v := Vigil.new()
	v.tier = clampi(t, 0, MAX_TIER)
	v.session_seed = session_seed
	v._draw_omens()
	return v


static func pools_for(t: int) -> PackedStringArray:
	var out := PackedStringArray()
	if t >= 1:
		out.append("easy")
	if t >= 4:
		out.append("medium")
	if t >= 7:
		out.append("hard")
	if t >= 10:
		out.append("hard")
	return out


## Re-roll at the Memorial Stones: a new deterministic draw from the same seed.
func reroll() -> void:
	rerolls += 1
	_draw_omens()


func _draw_omens() -> void:
	omens.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([session_seed, tier, rerolls])
	for pool in pools_for(tier):
		var opts: Array = OMENS[pool].filter(func(o: Dictionary) -> bool: return not omens.has(o))
		omens.append(opts[rng.randi_range(0, opts.size() - 1)])


func _omen_product(key: String) -> float:
	var m := 1.0
	for o in omens:
		m *= float(o.get(key, 1.0))
	return m


func enemy_health_mult() -> float:
	return (1.0 + HEALTH_PER_TIER * tier) * _omen_product("enemy_health")


func enemy_damage_mult() -> float:
	return (1.0 + DAMAGE_PER_TIER * tier) * _omen_product("enemy_damage")


func xp_mult() -> float:
	return 1.0 + XP_PER_TIER * tier


## The WeightModel modifiers for one rarity tier (context {"vigil": tier}).
func rarity_mods(rarity_tier: int) -> Array:
	if rarity_tier == Rarity.Tier.BASIC:
		return [{"mul": 1.0 / (1.0 + BASIC_DROP_PER_TIER * tier)}]
	if rarity_tier == Rarity.Tier.UNCOMMON:
		return []
	return [{"attr": "vigil", "per": RARE_SHIFT_PER_TIER * (rarity_tier - 1)}, {"mul": _omen_product("rarity")}]


## A copy of `base` (default: the shipped table) with Vigil-shifted drop weights.
func table_for(base: RarityTable = null) -> RarityTable:
	var src := base if base != null else RarityTable.load_default()
	var t := RarityTable.new()
	t.luck_common_step = src.luck_common_step
	t.luck_rare_step = src.luck_rare_step
	t.luck_common_floor = src.luck_common_floor
	var ctx := {"vigil": tier}
	for r in src.rarities:
		var c := r.duplicate() as Rarity
		c.drop_weight = WeightModel.weight(r.drop_weight, rarity_mods(Rarity.parse(r.id)), ctx)
		t.rarities.append(c)
	t.rebuild()
	return t


func describe() -> String:
	return "Vigil %d: %s" % [tier, ", ".join(omens.map(func(o: Dictionary) -> String: return o["name"]))]
