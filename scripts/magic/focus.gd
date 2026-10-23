class_name Focus
extends RefCounted
## Focus = aim down sights (BUILD_PLAN step 9, port of the archived C++ game/magic/accuracy.*
## Focus, old step 19). Follows Magewar's wieldable_staff.gd action_secondary (weapon
## system, followed directly): holding action_secondary tweens the camera FOV from wherever
## it is to the wieldable's ads_fov (55 deg) over 0.2 s, linear (Godot tween_property
## default); releasing tweens it back to 75 deg over 0.2 s. Staffs *and* wands use 55 deg:
## Magewar's wieldable_wand.tscn runs wieldable_staff.gd without an ads_fov override. The
## values stay per type so they can diverge later. Focusing costs nothing (no mana).
## Here the tween advances per physics tick (64-bit elapsed time, so 12 ticks at 60 Hz land
## exactly on 55 deg) and render frames interpolate between the last two ticks (fov_at).
## Any change of target (press, release, unequip, swap to a wieldable with another FOV)
## starts a new 0.2 s tween from the current FOV. Empty hands: no focus.
## Not from Magewar (plan choices): mouse look scaled by tan(fov/2) / tan(hip/2)
## (look_scale(): 0.6784 at 55 deg) so a mouse count moves the image under the crosshair
## by the same screen fraction at any FOV; the viewmodel keeps a fixed 75 deg (step 10).

var hip_fov := 75.0       ## Camera3D fov; Magewar tweens back to 75
var staff_fov := 55.0     ## wieldable_staff.gd ads_fov
var wand_fov := 55.0      ## wieldable_wand.tscn: same script, no override
var tween_seconds := 0.2  ## both directions

var focused := false      ## aiming with a wieldable in hand
var fov := 75.0           ## after the last tick
var prev_fov := 75.0
var target_fov := 75.0
var _from := 75.0
var _elapsed := 0.0
var _ads_fov := 55.0      ## focused FOV of the last wieldable (for amount())

static func from_tuning(t: PlayerTuning) -> Focus:
	var f := Focus.new()
	f.hip_fov = t.hip_fov
	f.staff_fov = t.focus_staff_fov
	f.wand_fov = t.focus_wand_fov
	f.tween_seconds = t.focus_tween_seconds
	f.reset()
	return f

## Back to the hip FOV at once (spawn).
func reset() -> void:
	focused = false
	fov = hip_fov
	prev_fov = hip_fov
	target_fov = hip_fov
	_from = hip_fov
	_elapsed = 0.0
	_ads_fov = staff_fov

func fov_for(type: WieldableDef.Type) -> float:
	return wand_fov if type == WieldableDef.Type.WAND else staff_fov

## One physics tick. aim_held = action_secondary held; w = the wieldable in hand (null =
## empty hands).
func tick(aim_held: bool, w: WieldableInstance, dt: float) -> void:
	prev_fov = fov
	focused = aim_held and w != null
	if w != null:
		_ads_fov = fov_for(w.type())
	var target := _ads_fov if focused else hip_fov
	if target != target_fov:   # new tween from where the FOV is now (Godot tween_property)
		_from = fov
		target_fov = target
		_elapsed = 0.0
	if fov == target_fov:
		return
	_elapsed += dt
	var k := _elapsed / tween_seconds if tween_seconds > 0.0 else 1.0
	fov = target_fov if k >= 1.0 - 1e-9 else _from + (target_fov - _from) * k

## Render FOV between the last two ticks (alpha = physics interpolation fraction).
func fov_at(alpha: float) -> float:
	return lerpf(prev_fov, fov, alpha)

## 0 at the hip FOV .. 1 at the focused FOV, from the current tween position.
func amount() -> float:
	var span := hip_fov - _ads_fov
	if absf(span) < 1e-9:
		return 1.0 if focused else 0.0
	return clampf((hip_fov - fov) / span, 0.0, 1.0)

## Mouse look multiplier at the current FOV.
func look_scale() -> float:
	return look_scale_for_fov(fov, hip_fov)

static func look_scale_for_fov(fov_deg: float, hip_deg: float = 75.0) -> float:
	return tan(deg_to_rad(fov_deg) * 0.5) / tan(deg_to_rad(hip_deg) * 0.5)
