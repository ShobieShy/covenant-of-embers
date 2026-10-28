class_name CameraFeel
extends RefCounted
## Camera feel (BUILD_PLAN step 5, port of the archived C++ game::CameraFeel, old step 16;
## PLAN "Feel"): head bob, landing dip and step smoothing as an eye offset that Player
## adds to the eased crouch eye height on its Head (x along the view's right, y up).
## Head bob reinterprets Magewar's cogito_player "wiggle" (read-only reference):
##  * a phase advances while grounded with a move key held and not sliding/dashing, at
##    12 rad/s walking, 16 sprinting, 8 crouched; target y = sin(phase) x I / 2,
##    x = sin(phase / 2) x I with I 0.03 / 0.05 / 0.08 m, eased toward the target (and
##    back to 0 when not bobbing) at LERP_SPEED 10/s.
##  * deliberate changes: Cogito's sway is sin(phase/2) + 0.5 (a constant 0.5 x I shift to
##    the right while walking); ours is centred. Cogito's HEADBOBBLE strength scales walk
##    and sprint only; our bob_scale scales all three (0 = off).
## Landing dip (Cogito plays a 0.3 s "landing" camera animation at <= -5 m/s and a head
## drop + roll at <= -7.5 m/s; we use one positional dip, no roll): landing at s >= 2 m/s
## (Cogito landing_threshold) drops the eye by 0.12 x clamp((s - 2) / (8 - 2), 0, 1) m
## (Cogito min/max landing velocity): ease-out down over 0.1 s, cosine back up by 0.3 s.
## Step smoothing (Cogito step_height_camera_lerp 2.5): when the body snaps up a step
## add_step(dy) keeps the camera where it was and the offset eases back to 0 at 2.5/s
## (Cogito also snaps down steps; our capsule rolls off and falls instead, which is
## already smooth). Not motion but smoothing, so it stays on under
## reduced motion.
## Recoil + screen shake (step 10): a cast kicks the viewmodel (recoil 0..1 -> back
## recoil_kick m toward the eye and up recoil_rise m, linear back to rest in recoil_seconds)
## and may add screen-shake trauma (0..1, decays shake_decay/s; camera offset = trauma^2 x
## shake_max m along two fixed-rate sines, deterministic per tick). Both are offsets only:
## aim (Player.aim(), the plain eye) never moves.
## Reduced motion (PLAN accessibility; persisted by step 32's settings): no bob, no dip, no
## recoil kick, no shake (add_recoil/add_shake are ignored and current values zeroed).

## 0.3.1 P5 (M5): a dash kicks the FOV out by DASH_FOV_KICK deg, easing back in
## FOV_KICK_SECONDS; none under reduced motion.
## 0.3.1 P5 (L5): dead, the eye sinks DEATH_DROP m over DEATH_FALL_SECONDS (death()
## 0 -> 1 also drives the screen desaturate); after the respawn it rises back in
## RISE_SECONDS. Under reduced motion the eye stays put (the desaturate still runs).

enum Gait { WALK, SPRINT, CROUCH }

const DASH_FOV_KICK := 6.0
const FOV_KICK_SECONDS := 0.25
const DEATH_DROP := 1.1
const DEATH_FALL_SECONDS := 1.2
const RISE_SECONDS := 0.4

var walk_intensity := 0.03
var walk_rate := 12.0
var sprint_intensity := 0.05
var sprint_rate := 16.0
var crouch_intensity := 0.08
var crouch_rate := 8.0
var lerp_speed := 10.0
var land_min_speed := 2.0
var land_max_speed := 8.0
var max_dip := 0.12
var dip_down_time := 0.1
var dip_total_time := 0.3
var step_lerp := 2.5

var reduced_motion := false
var bob_scale := 1.0  ## Cogito HEADBOBBLE (options slider in step 32)
var bob := Vector2.ZERO  ## x right, y up
var dip := 0.0  ## <= 0
var dip_depth := 0.0  ## depth of the current/last dip
var step := 0.0  ## step smoothing offset (y)
var landings := 0  ## dips started
var recoil := 0.0  ## 0..1 viewmodel kick (step 10)
var recoil_kick := 0.05
var recoil_rise := 0.012
var recoil_seconds := 0.15
var shake := 0.0  ## 0..1 trauma (step 10)
var shake_max := 0.03
var shake_decay := 2.0
var shake_offset := Vector2.ZERO  ## camera offset from the shake (x right, y up)
var recoils := 0
var _shake_time := 0.0
var fov_kick := 0.0  ## deg added to the camera FOV (P5)
var death_t := 0.0  ## 0 alive .. 1 fully fallen (P5)
var _phase := 0.0
var _dip_time := -1.0  ## seconds since the landing, < 0 = no dip running


static func from_tuning(t: PlayerTuning) -> CameraFeel:
	var f := CameraFeel.new()
	f.walk_intensity = t.bob_walk_intensity
	f.walk_rate = t.bob_walk_rate
	f.sprint_intensity = t.bob_sprint_intensity
	f.sprint_rate = t.bob_sprint_rate
	f.crouch_intensity = t.bob_crouch_intensity
	f.crouch_rate = t.bob_crouch_rate
	f.lerp_speed = t.lerp_speed
	f.land_min_speed = t.land_min_speed
	f.land_max_speed = t.land_max_speed
	f.max_dip = t.land_max_dip
	f.dip_down_time = t.land_dip_down_time
	f.dip_total_time = t.land_dip_total_time
	f.step_lerp = t.step_camera_lerp
	f.recoil_kick = t.recoil_kick
	f.recoil_rise = t.recoil_rise
	f.recoil_seconds = t.recoil_seconds
	f.shake_max = t.shake_max
	f.shake_decay = t.shake_decay
	return f


## Eye offset after the last tick: x along the view's right, y up (bob + shake + dip + step
## + the death fall).
func offset() -> Vector2:
	return bob + shake_offset + Vector2(0.0, dip + step + death_offset())


## P5: the dash FOV kick (ignored under reduced motion).
func add_fov_kick(deg := DASH_FOV_KICK) -> void:
	if reduced_motion or deg <= 0.0:
		return
	fov_kick = maxf(fov_kick, deg)


## P5: 0..1, eased; how far the death fall / desaturate has gone.
func death() -> float:
	return death_t * death_t * (3.0 - 2.0 * death_t)


func death_offset() -> float:
	return 0.0 if reduced_motion else -DEATH_DROP * death()


## P5: one tick of the death fall (dead) or the respawn rise (alive).
func tick_death(dead: bool, dt: float) -> void:
	if dead:
		death_t = minf(1.0, death_t + dt / DEATH_FALL_SECONDS)
	else:
		death_t = maxf(0.0, death_t - dt / RISE_SECONDS)


## Viewmodel recoil offset in view space (x right, y up, +z back toward the eye).
func recoil_offset() -> Vector3:
	return Vector3(0.0, recoil_rise * recoil, recoil_kick * recoil)


## A cast's kick (0..1, added, capped at 1); ignored under reduced motion.
func add_recoil(amount: float) -> void:
	if reduced_motion or amount <= 0.0:
		return
	recoil = minf(1.0, recoil + amount)
	recoils += 1


## Screen-shake trauma (0..1, added, capped at 1); ignored under reduced motion.
func add_shake(trauma: float) -> void:
	if reduced_motion or trauma <= 0.0:
		return
	shake = minf(1.0, shake + trauma)


func set_reduced_motion(on: bool) -> void:
	reduced_motion = on
	if on:  # snap: nothing may move the view
		bob = Vector2.ZERO
		dip = 0.0
		_dip_time = -1.0
		recoil = 0.0
		shake = 0.0
		shake_offset = Vector2.ZERO
		fov_kick = 0.0


func set_bob_scale(s: float) -> void:
	bob_scale = maxf(0.0, s)


## The body moved `dy` (up > 0) in one snap (a climbed step): the camera
## stays put and eases after it.
func add_step(dy: float) -> void:
	step -= dy


## One fixed tick. `bobbing`: grounded, move key held, not sliding or dashing.
## `landed`: touched down this tick at `landing_speed` m/s (downward, positive).
func tick(bobbing: bool, gait: Gait, landed: bool, landing_speed: float, dt: float) -> void:
	step = lerpf(step, 0.0, minf(1.0, dt * step_lerp))
	fov_kick = 0.0 if reduced_motion else move_toward(fov_kick, 0.0, dt * DASH_FOV_KICK / FOV_KICK_SECONDS)
	if absf(step) < 1e-4:
		step = 0.0
	if reduced_motion:
		bob = Vector2.ZERO
		dip = 0.0
		_dip_time = -1.0
		recoil = 0.0
		shake = 0.0
		shake_offset = Vector2.ZERO
		return
	recoil = move_toward(recoil, 0.0, dt / recoil_seconds) if recoil_seconds > 0.0 else 0.0
	if recoil < 1e-9:
		recoil = 0.0
	shake = move_toward(shake, 0.0, dt * shake_decay)
	_shake_time += dt
	var amp := shake * shake * shake_max
	shake_offset = Vector2(sin(_shake_time * 41.0), sin(_shake_time * 53.0 + 1.3)) * amp

	var target := Vector2.ZERO
	if bobbing and bob_scale > 0.0:
		var intensity := walk_intensity
		var rate := walk_rate
		if gait == Gait.SPRINT:
			intensity = sprint_intensity
			rate = sprint_rate
		elif gait == Gait.CROUCH:
			intensity = crouch_intensity
			rate = crouch_rate
		intensity *= bob_scale
		_phase = fmod(_phase + rate * dt, 4.0 * PI)  # sin(phase/2) has period 4 pi
		target = Vector2(sin(_phase * 0.5) * intensity, sin(_phase) * intensity * 0.5)
	bob = bob.lerp(target, minf(1.0, dt * lerp_speed))
	if not bobbing and bob.length() < 1e-5:
		bob = Vector2.ZERO

	if landed and landing_speed >= land_min_speed:
		var k := clampf((landing_speed - land_min_speed) / (land_max_speed - land_min_speed), 0.0, 1.0)
		if max_dip * k > 0.0:
			dip_depth = max_dip * k
			_dip_time = 0.0
			landings += 1
	dip = 0.0
	if _dip_time >= 0.0:
		_dip_time += dt
		if _dip_time >= dip_total_time:
			_dip_time = -1.0
		elif _dip_time < dip_down_time:
			dip = -dip_depth * sin(0.5 * PI * _dip_time / dip_down_time)
		else:
			dip = -dip_depth * 0.5 * (1.0 + cos(PI * (_dip_time - dip_down_time) / (dip_total_time - dip_down_time)))
