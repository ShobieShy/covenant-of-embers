class_name LevelScale
extends RefCounted
## 0.3.2 per-player enemy level scaling (docs/PLAN_0.3.2.md). Pure numbers.
## An enemy keeps its authored level as L0. Each peer's effective level is
## player level + tier offset, clamped 1..50. Solo never goes under the zone floor.
## `mult(curve, dL)` is 1 at dL 0. Growth is then capped (hp x60, damage x25,
## xp x40, gold x20 at a 49-level span).

const MAX_LEVEL := 50
const ELITE_OFFSET := 1
const BOSS_OFFSET := 2
const RES_PER_LEVEL := 0.005

const CURVES := {
	"hp": {"growth": 1.09, "cap": 60.0},
	"dmg": {"growth": 1.07, "cap": 25.0},
	"xp": {"growth": 1.5, "cap": 40.0},  # Magewar Progression.GROWTH
	"gold": {"growth": 1.06, "cap": 20.0},
	"thr": {"growth": 1.09, "cap": 60.0},  # same shape as hp
	"res": {"add": 0.005, "cap": 0.6},
}

## stat -> {"scale": curve} or {"fixed": reason}. Coverage test keeps this exact.
const TABLE := {
	"id": {"fixed": "identity"},
	"display_name": {"fixed": "identity"},
	"affinity": {"fixed": "element"},
	"max_health": {"scale": "hp"},
	"level": {"fixed": "L0"},
	"xp_reward": {"scale": "xp"},
	"gold_drop": {"scale": "gold"},
	"size": {"fixed": "visual"},
	"color": {"fixed": "visual"},
	"resist": {"scale": "res"},
	"has_weak_point": {"fixed": "geometry"},
	"weak_point_offset": {"fixed": "geometry"},
	"weak_point_size": {"fixed": "geometry"},
	"ai": {"fixed": "per key"},
	"kind": {"fixed": "brain"},
	"detect_range": {"fixed": "ai geometry"},
	"aggro_range": {"fixed": "ai geometry"},
	"walk_speed": {"fixed": "movement"},
	"sprint_speed": {"fixed": "movement"},
	"attack_range": {"fixed": "ai geometry"},
	"attack_damage": {"scale": "dmg"},
	"attack_cooldown": {"fixed": "timing"},
	"knockback_strength": {"fixed": "player impulse"},
	"knockback_time": {"fixed": "player impulse"},
	"knockback_threshold": {"scale": "thr"},
	"turn_rate_deg": {"fixed": "movement"},
	"attack_windup": {"fixed": "timing"},
	"projectile_speed": {"fixed": "dodgeability"},
	"min_range": {"fixed": "ai geometry"},
	"flee_below": {"fixed": "fraction"},
	"BASE_CHANCE": {"fixed": "spawn odds"},
	"PER_TIER": {"fixed": "spawn odds"},
	"ELITE_HEALTH": {"fixed": "multiplies scaled hp"},
	"ELITE_XP": {"fixed": "multiplies scaled xp"},
	"THROW_MIN": {"fixed": "geometry"},
	"THROW_MAX": {"fixed": "geometry"},
	"THROW_COOLDOWN": {"fixed": "timing"},
	"THROW_DAMAGE": {"scale": "dmg"},
	"THROW_FALLBACK": {"fixed": "timing"},
	"ROCK_SPEED": {"fixed": "dodgeability"},
	"ROCK_HIT": {"fixed": "geometry"},
	"ROCK_LIFE": {"fixed": "timing"},
	"ROAR_S": {"fixed": "timing"},
	"PHASE_2_AT": {"fixed": "fraction"},
	"PHASE_3_AT": {"fixed": "fraction"},
	"BLOB_RANGE": {"fixed": "geometry"},
	"BLOB_SPEED": {"fixed": "dodgeability"},
	"BLOB_HIT": {"fixed": "geometry"},
	"BLOB_LIFE": {"fixed": "timing"},
	"REGEN_DELAY": {"fixed": "timing"},
	"REGEN_PER_S": {"scale": "hp"},
	"CORE_GROW": {"fixed": "geometry"},
	"ENRAGE_SPEED": {"fixed": "tempo"},
	"ENRAGE_TEMPO": {"fixed": "tempo"},
	"SPLIT_COUNT": {"fixed": "count"},
	"SPLIT_SCALE": {"fixed": "fraction of scaled max"},
	"PUDDLE_RADIUS": {"fixed": "geometry"},
	"PUDDLE_TIME": {"fixed": "status on the player"},
	"PUDDLE_SLOW": {"fixed": "status on the player"},
	"EMBER_HIT": {"fixed": "geometry"},
	"EMBER_LIFE": {"fixed": "timing"},
	"ATTACK_SLACK": {"fixed": "ai geometry"},
	"HUNT_TIME": {"fixed": "timing"},
	"BITE_HEIGHT": {"fixed": "geometry"},
	"ALLY_SEEK": {"fixed": "ai geometry"},
	"PLAYER_RADIUS": {"fixed": "geometry"},
	"GRAVITY": {"fixed": "movement"},
	"STEP_UP": {"fixed": "movement"},
	"NAV_SNAP": {"fixed": "ai geometry"},
	"SEPARATION_GAP": {"fixed": "ai geometry"},
	"SEPARATION_WEIGHT": {"fixed": "ai geometry"},
	"SEPARATION_AHEAD": {"fixed": "ai geometry"},
	"SEPARATION_FORWARD": {"fixed": "ai geometry"},
	"SLIDE_OFF_SPEED": {"fixed": "movement"},
	"ENEMY_LAYER": {"fixed": "physics"},
	"FLASH_TIME": {"fixed": "status received"},
	"FLINCH_S": {"fixed": "timing"},
	"FLINCH_PUNCH": {"fixed": "visual"},
	"FLINCH_LEAN": {"fixed": "visual"},
	"CRIT_PUNCH": {"fixed": "visual"},
	"CRIT_LEAN": {"fixed": "visual"},
	"CRIT_STUN_S": {"fixed": "timing"},
	"WEAK_POINT_BRIGHTEN": {"fixed": "visual"},
	"BURN_TICK": {"fixed": "status received"},
	"FX_BURN": {"fixed": "status bit"},
	"FX_SLOW": {"fixed": "status bit"},
	"FX_STAGGER": {"fixed": "status bit"},
	"FALL_LIMIT": {"fixed": "geometry"},
}

## 0 = tests and tools, no scaling. The running game sets this from the local player.
static var player_level := 0
static var solo := true

## Act I floors 1..King map to +0..+2 (five floors).
const LABYRINTH_OFFSETS: Array[int] = [0, 0, 1, 1, 2]


static func bind(level: int, is_solo: bool) -> void:
	player_level = maxi(0, level)
	solo = is_solo


static func clamp_level(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL)


static func labyrinth_offset(floor_no: int) -> int:
	if floor_no < 1:
		return 0
	var i := clampi(floor_no - 1, 0, LABYRINTH_OFFSETS.size() - 1)
	return LABYRINTH_OFFSETS[i]


## Effective combat level. `viewer` <= 0 leaves scaling off (returns 0).
## Solo uses max(player + offset, zone floor). Co-op is pure player + offset.
static func effective(viewer: int, offset: int, zone_floor: int, is_solo: bool) -> int:
	if viewer <= 0:
		return 0
	if is_solo:
		return clamp_level(maxi(viewer + offset, zone_floor))
	return clamp_level(viewer + offset)


static func mult(curve: String, d_l: int) -> float:
	var c: Dictionary = CURVES[curve]
	if c.has("add"):
		return 1.0
	var raw := pow(float(c["growth"]), d_l)
	var cap := float(c["cap"])
	if d_l >= 0:
		return minf(cap, raw)
	return maxf(1.0 / cap, raw)


## Spell damage term: same growth as enemy health, anchored at level 1.
static func player_dmg_mult(level: int) -> float:
	if level <= 1:
		return 1.0
	return mult("hp", level - 1)


static func resist_of(base: float, d_l: int) -> float:
	return clampf(base + RES_PER_LEVEL * float(d_l), 0.0, Damage.RESIST_CAP)


## Authored gold, or 3 per effective level. The multiplier is capped at x20.
static func gold_amount(def: EnemyDef, eff_level: int) -> int:
	if def == null:
		return 0
	var lv := clamp_level(eff_level if eff_level > 0 else def.level)
	if def.gold_drop >= 0:
		return maxi(0, int(round(float(def.gold_drop) * mult("gold", lv - def.level))))
	var base := 3 * def.level
	var scaled := 3 * lv
	if base <= 0:
		return scaled
	return mini(scaled, base * int(CURVES["gold"]["cap"]))


static func normalise(amount: float, d_l: int) -> float:
	var m := mult("hp", d_l)
	if m <= 0.0:
		return amount
	return amount / m
