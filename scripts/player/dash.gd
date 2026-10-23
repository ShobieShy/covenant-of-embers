class_name Dash
extends RefCounted
## Dash (BUILD_PLAN step 5, port of the archived C++ game::Dash, old step 16; numbers are
## PLAN §30.8, a kept decision): 6 m in 0.15 s, 2 charges, 25 Breath, 0.1 s i-frames,
## usable once in the air.
## Magewar has no dash (cogito_player / magewar_player only sprint, slide and bunny-hop),
## so this is our own verb on top of the reinterpreted controller:
##  * try_start(): refused (nothing spent) while a dash is running, with no charge left,
##    in the air once the air dash is used, with a zero direction, or when
##    Breath.spend(25) refuses (value < 25; an exhausted pool is < 20). spend() restarts
##    Breath's 1 s regen delay.
##  * advance(dt), once per tick: returns the fraction of this tick the dash covers (1 on
##    full ticks, the remainder on the last one, 0 when idle), so the distance is exactly
##    speed() x duration at any tick rate. Player blends the horizontal velocity:
##    dash x fraction + normal x (1 - fraction); move_and_slide still collides, so walls
##    stop it.
##  * Charges recharge one at a time, 1.5 s each, the clock starting when the first one
##    is spent (2 back-to-back dashes = 50 Breath, so Breath stays the real limiter).
##  * The air dash is used by a dash started off the ground and given back on landing
##    (land()); a ground dash carrying off a ledge doesn't use it.
##  * set_bonus_charges(): hook for a 3rd charge (PLAN §30.8 Sandals; gear/Consecration).
##  * invulnerable(): i-frames cover every tick starting within 0.1 s of the dash start
##    (6 at 60 Hz); step 13's damage check reads it.

const EPS := 1e-6   # 9 x (1/60 s) must end a 0.15 s dash exactly

var distance := 6.0
var duration := 0.15
var base_charges := 2
var breath_cost := 25.0
var invulnerability := 0.1
var recharge_seconds := 1.5
var air_dashes := 1

var charges := 2
var bonus_charges := 0
var dashes := 0
var direction := Vector3.ZERO
var _recharge := 0.0     # seconds into the current charge's recharge
var _time_left := 0.0
var _invuln_left := 0.0
var _invuln_tick := false
var _air_used := 0

static func from_tuning(t: PlayerTuning) -> Dash:
	var d := Dash.new()
	d.distance = t.dash_distance
	d.duration = t.dash_duration
	d.base_charges = t.dash_charges
	d.breath_cost = t.dash_breath_cost
	d.invulnerability = t.dash_invulnerability
	d.recharge_seconds = t.dash_recharge
	d.air_dashes = t.dash_air_dashes
	d.charges = d.base_charges
	return d

func max_charges() -> int:
	return base_charges + bonus_charges

func active() -> bool:
	return _time_left > 0.0

func invulnerable() -> bool:
	return _invuln_tick

func speed() -> float:
	return distance / duration

func air_dash_available() -> bool:
	return _air_used < air_dashes

## Progress of the charge currently recharging, [0, 1) (0 when full).
func recharge_progress() -> float:
	return _recharge / recharge_seconds

## `dir`: horizontal direction (flattened and normalised here).
func try_start(dir: Vector3, grounded: bool, breath: Breath) -> bool:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if active() or charges <= 0 or flat.length() < 1e-6:
		return false
	if not grounded and not air_dash_available():
		return false
	if not breath.spend(breath_cost):
		return false   # short (or exhausted): refused, no cost
	direction = flat.normalized()
	_time_left = duration
	_invuln_left = invulnerability
	_invuln_tick = _invuln_left > 0.0
	if charges == max_charges():
		_recharge = 0.0   # the first spent charge starts the clock
	charges -= 1
	if not grounded:
		_air_used += 1
	dashes += 1
	return true

## One fixed tick (call every tick, dashing or not). Returns the covered fraction [0, 1].
func advance(dt: float) -> float:
	var covered := 0.0
	if _time_left > 0.0:
		var c := minf(_time_left, dt)
		_time_left -= c
		if _time_left < EPS:
			_time_left = 0.0
		covered = minf(1.0, c / dt)
	_invuln_tick = _invuln_left > 0.0
	if _invuln_left > 0.0:
		_invuln_left -= dt
		if _invuln_left < EPS:
			_invuln_left = 0.0
	if charges < max_charges():
		_recharge += dt
		while charges < max_charges() and _recharge >= recharge_seconds - EPS:
			charges += 1
			_recharge = maxf(0.0, _recharge - recharge_seconds)
		if charges >= max_charges():
			_recharge = 0.0
	return covered

## Touched the ground: the air dash is back.
func land() -> void:
	_air_used = 0

func set_bonus_charges(n: int) -> void:
	bonus_charges = maxi(0, n)
	charges = mini(charges, max_charges())
	if charges >= max_charges():
		_recharge = 0.0
