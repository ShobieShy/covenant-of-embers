class_name Elites
extends RefCounted
## Elite affixes (BUILD_PLAN step 58; PLAN §7 / §31): Burning, Warded, Swift, Splitting,
## rolled more often on higher Vigil tiers. `apply()` returns an elite copy of an EnemyDef
## (the shipped def is never touched):
##   * every elite: health x ELITE_HEALTH, xp x ELITE_XP (PLAN eliteMult), name prefix,
##     colour tinted towards the affix colour;
##   * burning:   Fire affinity, attack damage x 1.3, +50 % Fire resist;
##   * warded:    health x 1.5 more, +25 % resist to every element (still capped at 60 %);
##   * swift:     walk/sprint x 1.4, attack cooldown x 0.75;
##   * splitting: a Gnawer-brain ("rusher") elite gets the Ooze brain ("splitter"):
##     it splits into 2 halves on death. Others get no split (only Gnawer brains can).
## Chance per spawn: BASE_CHANCE + PER_TIER x tier (Vigil 0 = 5 %, Vigil 10 = 45 %), affix
## picked evenly. The numbers are plan design (Magewar has no elites).

const AFFIXES: PackedStringArray = ["burning", "warded", "swift", "splitting"]
const BASE_CHANCE := 0.05
const PER_TIER := 0.04
const ELITE_HEALTH := 1.5
const ELITE_XP := 2
const COLORS := {
	"burning": Color(1.0, 0.35, 0.1),
	"warded": Color(0.6, 0.7, 1.0),
	"swift": Color(0.9, 0.95, 0.3),
	"splitting": Color(0.4, 0.8, 0.3),
}


static func chance(tier: int) -> float:
	if tier < 0:  # step 95: tier -1 turns elites off (deterministic tests)
		return 0.0
	return clampf(BASE_CHANCE + PER_TIER * maxi(0, tier), 0.0, 1.0)


## "" (not elite) or one of AFFIXES.
static func roll(rng: RandomNumberGenerator, tier: int) -> String:
	if rng.randf() >= chance(tier):
		return ""
	return AFFIXES[rng.randi_range(0, AFFIXES.size() - 1)]


static func apply(d: EnemyDef, affix: String) -> EnemyDef:
	if not AFFIXES.has(affix):
		return d
	var e := d.duplicate(true) as EnemyDef
	e.max_health = d.max_health * ELITE_HEALTH
	e.xp_reward = d.xp_reward * ELITE_XP
	e.display_name = "%s %s" % [affix.capitalize(), d.display_name]
	e.color = d.color.lerp(COLORS[affix], 0.5)
	var ai := e.ai.duplicate(true)
	match affix:
		"burning":
			e.affinity = ElementTable.Element.FIRE
			e.resist["fire"] = minf(1.0, float(e.resist.get("fire", 0.0)) + 0.5)
			if ai.has("attack_damage"):
				ai["attack_damage"] = float(ai["attack_damage"]) * 1.3
		"warded":
			e.max_health *= 1.5
			for id in ElementTable.IDS:
				e.resist[id] = minf(1.0, float(e.resist.get(id, 0.0)) + 0.25)
		"swift":
			for k in ["walk_speed", "sprint_speed"]:
				if ai.has(k):
					ai[k] = float(ai[k]) * 1.4
			if ai.has("attack_cooldown"):
				ai["attack_cooldown"] = float(ai["attack_cooldown"]) * 0.75
		"splitting":
			if String(ai.get("kind", "")) == "rusher":
				ai["kind"] = "splitter"
	e.ai = ai
	e.set_meta(&"elite", affix)
	return e


static func affix_of(d: EnemyDef) -> String:
	return String(d.get_meta(&"elite", "")) if d else ""
