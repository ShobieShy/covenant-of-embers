class_name Spread
extends RefCounted
## Accuracy -> spread cone + bloom (BUILD_PLAN step 9, port of the archived C++
## game/magic/accuracy.* Spread, old step 19).
## Accuracy is Magewar's get_final_accuracy (WieldableInstance.accuracy(): 50 + Head +
## Handle + Charm, clamped 0..100). Magewar only shows it in the stats summary (its bolts fly
## straight at the crosshair point); turning it into a cone is our design (PLAN §30.1):
##   half-angle = (max_spread_deg + bloom) x (1 - accuracy/100) x stance
##   stance = lerp(1, focus 0.35, focus amount) x (airborne 1.8 | crouch 0.8 x moving 1.3)
## The focus amount follows the FOV tween (Focus.amount()), so a quick tap of focus doesn't
## give full focus accuracy. "Moving" = on the ground above 0.5 m/s; sliding counts as
## crouched (Player.crouched is set). Each *real* cast (Caster.tick returned true; never a
## cooldown or mana refusal) adds bloom_per_cast_deg, capped at bloom_max_deg, decaying
## linearly so a full bloom is gone bloom_recovery_seconds after the last cast (30 ticks at
## 60 Hz). 100 % accuracy is a perfect line whatever the stance or bloom (the aim is
## returned untouched). Directions are uniform over the cone's spherical cap from a seeded
## RandomNumberGenerator (PCG32): same seed => same shots. Two numbers per apply().


## Body state for the multiplier.
class Stance:
	extends RefCounted
	var focus := 0.0  ## Focus.amount()
	var crouched := false
	var moving := false
	var airborne := false

	static func make(
		p_focus: float = 0.0, p_crouched: bool = false, p_moving: bool = false, p_airborne: bool = false
	) -> Stance:
		var s := Stance.new()
		s.focus = p_focus
		s.crouched = p_crouched
		s.moving = p_moving
		s.airborne = p_airborne
		return s


const DEFAULT_SEED := 0x434F45  ## "COE"

var max_spread_deg := 4.0  ## half-angle at 0 % accuracy, hip, still
var focus_mul := 0.35  ## fully focused
var crouch_mul := 0.8  ## crouched on the ground (also sliding)
var moving_mul := 1.3  ## on the ground above moving_speed
var airborne_mul := 1.8  ## not on the ground (replaces crouch/moving)
var moving_speed := 0.5  ## m/s horizontal
var bloom_per_cast_deg := 1.0  ## added to max_spread_deg per cast (so x (1 - acc/100) too)
var bloom_max_deg := 4.0  ## cap: spamming at most doubles the cone
var bloom_recovery_seconds := 0.5  ## a full bloom decays to 0 in this time (linear)

var bloom := 0.0  ## degrees
var last_cone_deg := 0.0  ## the cone used by the last apply()
var rng := RandomNumberGenerator.new()


func _init(p_seed: int = DEFAULT_SEED) -> void:
	rng.seed = p_seed


static func from_tuning(t: PlayerTuning, p_seed: int = DEFAULT_SEED) -> Spread:
	var s := Spread.new(p_seed)
	s.max_spread_deg = t.spread_max_deg
	s.focus_mul = t.spread_focus_mul
	s.crouch_mul = t.spread_crouch_mul
	s.moving_mul = t.spread_moving_mul
	s.airborne_mul = t.spread_airborne_mul
	s.moving_speed = t.spread_moving_speed
	s.bloom_per_cast_deg = t.bloom_per_cast_deg
	s.bloom_max_deg = t.bloom_max_deg
	s.bloom_recovery_seconds = t.bloom_recovery_seconds
	return s


func stance_multiplier(s: Stance) -> float:
	var focus := 1.0 + (focus_mul - 1.0) * clampf(s.focus, 0.0, 1.0)
	var body := 1.0
	if s.airborne:
		body = airborne_mul
	else:
		if s.crouched:
			body *= crouch_mul
		if s.moving:
			body *= moving_mul
	return focus * body


## Cone half-angle in degrees for an accuracy (clamped 0..100), stance multiplier and bloom.
func cone_for(accuracy: float, stance_mul: float, bloom_deg: float) -> float:
	var miss := 1.0 - clampf(accuracy, 0.0, 100.0) / 100.0
	return (max_spread_deg + bloom_deg) * miss * stance_mul


## The cone right now (current bloom).
func cone_deg(accuracy: float, s: Stance) -> float:
	return cone_for(accuracy, stance_multiplier(s), bloom)


## A direction inside the cone around unit `dir`; u1, u2 in [0, 1) pick it uniformly over
## the spherical cap (u1 -> polar angle, u2 -> azimuth). Half-angle 0 returns dir as is.
static func cone_direction(dir: Vector3, half_angle_rad: float, u1: float, u2: float) -> Vector3:
	if half_angle_rad <= 0.0:
		return dir
	var cos_max := cos(half_angle_rad)
	var cos_t := 1.0 - u1 * (1.0 - cos_max)
	var sin_t := sqrt(maxf(0.0, 1.0 - cos_t * cos_t))
	var phi := TAU * u2
	var helper := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var right := dir.cross(helper).normalized()
	var up := right.cross(dir)
	return (dir * cos_t + (right * cos(phi) + up * sin(phi)) * sin_t).normalized()


## Per physics tick, before casting: bloom decays.
func tick(dt: float) -> void:
	if bloom <= 0.0:
		return
	var rate := bloom_max_deg / bloom_recovery_seconds if bloom_recovery_seconds > 0.0 else 1e30
	bloom -= rate * dt
	if bloom < 1e-6:
		bloom = 0.0


## The aim with its direction spread for this accuracy/stance (+ the current bloom).
func apply(aim: Caster.Aim, accuracy: float, s: Stance) -> Caster.Aim:
	last_cone_deg = cone_deg(accuracy, s)
	var u1 := rng.randf()
	var u2 := rng.randf()
	if last_cone_deg <= 0.0:
		return aim
	var a := Caster.Aim.make(aim.origin, cone_direction(aim.direction, deg_to_rad(last_cone_deg), u1, u2), aim.exclude)
	a.source = aim.source
	return a


## After a real cast (Caster.tick returned true): bloom grows.
func on_cast() -> void:
	bloom = minf(bloom_max_deg, bloom + bloom_per_cast_deg)
