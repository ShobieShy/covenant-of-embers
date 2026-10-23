class_name Player
extends CharacterBody3D
## First-person controller (BUILD_PLAN steps 3-5, port of the archived C++ PlayerController,
## old steps 14-15), reinterpreting Magewar's cogito_player:
##  * Origin = feet. Capsule r 0.3, 1.7 m standing / 0.7 m crouched; eye (Head) 1.5 / 0.6 m,
##    eased at LERP 10/s.
##  * Per physics tick (tick()): wish direction = move axes turned by the current yaw,
##    smoothed at LERP 10/s on the ground and AIR 6/s in the air (only while a move key is
##    held); speed eases to walk 4 / crouch 3 m/s at 10/s. Vertical: 0 on the ground,
##    gravity 9.8 otherwise; jump on the press edge (ground only) 4.5 / 3.0 m/s crouched.
##  * Crouch is held; starts on the ground only; a crouch-jump stays crouched until landing;
##    standing up waits until the tall capsule fits (Magewar CrouchRayCast).
##  * Steps up to 0.35 m are climbed (probe up / forward / down, like Cogito's step_check),
##    floor_max_angle 45 deg, floor snap 0.5 m.
##  * Mouse look: 0.25 deg/count, mouse right = turn right, pitch clamped to +-89 deg.
##  * Sprint (held, step 4): 7 m/s; starts on the ground with a move key held, not while
##    crouched or with Breath exhausted, carries on in the air while held, eases like walk;
##    drains Breath 20/s (Breath: scripts/player/breath.gd).
##  * Slide (Magewar): Crouch on the ground while sprinting (previous tick) + a move key
##    slides 1.5 s along the entry wish direction (look doesn't steer it) at
##    (time_left / 1.5 + 0.5) x 5 m/s = 7.5 -> 2.5 m/s; ends on timeout, on releasing
##    Crouch or Sprint, or on leaving the ground; no re-trigger while held. Jump during a
##    slide = slide jump 4.5 x 1.3 m/s, stands up in the air, keeps its speed until landing.
##    Slides don't drain Breath.
##  * speed_multiplier (Magewar Shoes speed_modifier, step 19) scales walk/sprint/crouch,
##    not the slide.
##  * Dash (step 5, scripts/player/dash.gd; our own verb, Magewar has none): press edge,
##    along the wish direction or the view's forward with no move key; 6 m in 0.15 s
##    (40 m/s blended into the horizontal velocity for the covered part of each tick),
##    25 Breath, 2 charges, one air dash per airborne stretch, 0.1 s i-frames
##    (invulnerable()). A dash ends an active slide (crouch rules unchanged: Crouch held
##    on the ground keeps the crouch) and no slide starts while dashing.
##  * Camera feel (step 5, scripts/player/camera_feel.gd): Head = eased eye height + the
##    feel offset (Cogito wiggle head bob, landing dip, step smoothing at Cogito's
##    step_height_camera_lerp 2.5 after a climbed step);
##    set_reduced_motion() turns bob and dip off. eye_position() stays the plain eye
##    (casts aim from it), camera_position() is where the camera is.
##  * Casting (step 7, scripts/magic/caster.gd): after the move, an action_primary press
##    casts the equipped wieldable (caster.wieldable) into `bolts` (SpellBolts) from
##    aim(): the plain eye along yaw/pitch, excluding this body.
##  * Mana (step 8, scripts/player/mana.gd): ticked right before the cast; the caster
##    spends from it (caster.mana_spender = mana.spend). A press refused for mana emits
##    `hint("Not enough mana!")` (Magewar send_hint; the HUD shows it in step 29) and counts
##    `not_enough_mana_cues`.
##  * Focus + spread (step 9, scripts/magic/focus.gd + spread.gd): action_secondary held with
##    a wieldable tweens the camera FOV 75 -> 55 deg in 0.2 s (Magewar ADS; no mana) and
##    scales mouse look by tan(fov/2)/tan(37.5 deg). Each tick the bloom decays, then a
##    press that wants to cast gets aim() perturbed inside the spread cone (accuracy x
##    stance x bloom, spread_stance()); only a cast that happened (Caster.tick true) adds
##    bloom. `spread_seed` makes the shots reproducible.
## In game _physics_process feeds PlayerInput.from_input(); tests call tick() directly.

const CHARACTER_LAYER := 2   # physics layer "character" (bit 2)
const HINT_NOT_ENOUGH_MANA := "Not enough mana!"   # Magewar wieldable_staff.gd

## Short on-screen message (Magewar player_interaction_component.send_hint); step 29 HUD.
signal hint(text: String)

@export var tuning: PlayerTuning

var yaw := 0.0
var pitch := 0.0
var eye_height := 1.5
var crouched := false
var jumps := 0
var steps_climbed := 0
var direction := Vector3.ZERO   # smoothed move direction (Magewar `direction`)
var speed := 4.0                # Magewar `current_speed`
var input_enabled := true       # false in tests: no Input polling in _physics_process
var breath: Breath              # sprint/dash pool (step 4)
var sprinting := false
var slide_left := 0.0           # seconds left on the slide (Magewar SlidingTimer)
var slide_dir := Vector3.ZERO
var slides := 0
var slide_jumps := 0
var speed_multiplier := 1.0     # set_speed_multiplier(): Shoes hook
var dash: Dash                  # step 5
var feel: CameraFeel            # step 5: bob / landing dip / step smoothing
var landings := 0
var last_landing_speed := 0.0   # m/s downward at the last touch-down
var last_step_rise := 0.0       # m, the last climbed step
var caster := Caster.new()      # step 7: equipped staff/wand + cooldown
var bolts: SpellBolts           # where casts go (main.gd sets it; null = no bolts spawned)
var mana: Mana                  # step 8: casting pool (caster.mana_spender)
var not_enough_mana_cues := 0
var focus: Focus                # step 9: ADS FOV tween
var spread: Spread              # step 9: accuracy cone + bloom (seeded)
var last_hint := ""

var _crouched_jump := false
var _jumped_from_slide := false
var _rising := false
var _airborne := false
var _air_vy := 0.0
var _shape: CapsuleShape3D
var _collider: CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

func _init() -> void:
	if tuning == null:
		tuning = PlayerTuning.new()
	breath = Breath.from_tuning(tuning)
	dash = Dash.from_tuning(tuning)
	feel = CameraFeel.from_tuning(tuning)
	set_mana(Mana.from_tuning(tuning))
	focus = Focus.from_tuning(tuning)
	spread = Spread.from_tuning(tuning)
	caster.out_of_mana.connect(_on_out_of_mana)

func _ready() -> void:
	if tuning == null:
		tuning = PlayerTuning.new()
	collision_layer = 1 << (CHARACTER_LAYER - 1)
	collision_mask = 1
	floor_max_angle = deg_to_rad(tuning.max_slope_deg)
	floor_snap_length = tuning.floor_snap
	floor_stop_on_slope = true
	floor_block_on_wall = true
	_collider = $CollisionShape3D
	_shape = CapsuleShape3D.new()   # own shape per player (resized for crouch)
	_shape.radius = tuning.radius
	_collider.shape = _shape
	_set_capsule(tuning.standing_height)
	speed = tuning.walk_speed
	breath = Breath.from_tuning(tuning)
	dash = Dash.from_tuning(tuning)
	feel = CameraFeel.from_tuning(tuning)
	set_mana(Mana.from_tuning(tuning))
	focus = Focus.from_tuning(tuning)
	spread = Spread.from_tuning(tuning)
	camera.fov = focus.fov
	eye_height = tuning.standing_eye
	head.position = Vector3(0.0, eye_height, 0.0)
	set_look(rotation.y, 0.0)
	if input_enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Uses `m` as the mana pool and plugs it into the caster.
func set_mana(m: Mana) -> void:
	mana = m
	caster.mana_spender = mana.spend

func _on_out_of_mana(_cost: float) -> void:
	not_enough_mana_cues += 1
	last_hint = HINT_NOT_ENOUGH_MANA
	hint.emit(HINT_NOT_ENOUGH_MANA)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(mm.relative.x, mm.relative.y)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Render frames: the camera FOV between the last two ticks of the focus tween.
func _process(_delta: float) -> void:
	camera.fov = focus.fov_at(Engine.get_physics_interpolation_fraction())

## Reseeds the spread RNG (tests, replays).
func set_spread_seed(s: int) -> void:
	spread.rng.seed = s

func _physics_process(delta: float) -> void:
	if input_enabled:
		tick(PlayerInput.from_input(), delta)

## Places the feet at `feet`, facing `yaw_rad` (pitch 0), at rest.
func spawn(feet: Vector3, yaw_rad: float) -> void:
	global_position = feet
	velocity = Vector3.ZERO
	direction = Vector3.ZERO
	set_look(yaw_rad, 0.0)

## Relative mouse motion in counts (dx right, dy down); scaled down while focused (step 9).
func add_look(dx_counts: float, dy_counts: float) -> void:
	var r := deg_to_rad(tuning.look_deg_per_count) * focus.look_scale()
	set_look(yaw - dx_counts * r, pitch - dy_counts * r)

func set_look(yaw_rad: float, pitch_rad: float) -> void:
	yaw = wrapf(yaw_rad, -PI, PI)
	var mp := deg_to_rad(tuning.max_pitch_deg)
	pitch = clampf(pitch_rad, -mp, mp)
	rotation = Vector3(0.0, yaw, 0.0)
	if is_node_ready():
		head.rotation = Vector3(pitch, 0.0, 0.0)

static func forward_for(yaw_rad: float) -> Vector3:
	return Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad))

static func right_for(yaw_rad: float) -> Vector3:
	return Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))

func feet() -> Vector3:
	return global_position

## The plain eye (no camera feel): casts and AI line of sight use this.
func eye_position() -> Vector3:
	return global_position + Vector3(0.0, eye_height, 0.0)

## Where the camera actually is (eye + bob/dip/step offset).
func camera_position() -> Vector3:
	return head.global_position

## Camera feel offset of the Head from the plain eye (x right, y up).
func camera_offset() -> Vector2:
	return feel.offset()

## Look direction (yaw, pitch): Head basis forward.
func look_direction() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD

## Cast aim: the plain eye (not the bobbed camera) along the look, skipping this body.
func aim() -> Caster.Aim:
	var ex: Array[RID] = [get_rid()]
	return Caster.Aim.make(eye_position(), look_direction(), ex)

## Spread stance right now (after this tick's move): focus amount, crouched (also while
## sliding), moving on the ground above 0.5 m/s, airborne.
func spread_stance() -> Spread.Stance:
	var air := not on_ground()
	return Spread.Stance.make(focus.amount(), crouched, not air and horizontal_speed() > spread.moving_speed, air)

## Accuracy of the wieldable in hand (Magewar get_final_accuracy; 0 with empty hands).
func accuracy() -> float:
	return caster.wieldable.accuracy() if caster.wieldable != null else 0.0

func dashing() -> bool:
	return dash.active()

## Dash i-frames (step 13's damage check reads this after the tick).
func invulnerable() -> bool:
	return dash.invulnerable()

## Accessibility: no head bob, no landing dip (step smoothing stays).
func set_reduced_motion(on: bool) -> void:
	feel.set_reduced_motion(on)
	head.position = Vector3(0.0, eye_height + feel.offset().y, 0.0)

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

func on_ground() -> bool:
	return is_on_floor() and not _rising

func capsule_height() -> float:
	return _shape.height

func sliding() -> bool:
	return slide_left > 0.0

## Equipment speed hook (Magewar EquipmentItem.speed_modifier, Shoes x1.15): scales the
## walk/sprint/crouch targets, not the slide.
func set_speed_multiplier(m: float) -> void:
	speed_multiplier = m

## One fixed tick (dt must be the physics step: move_and_slide uses the physics delta).
func tick(input: PlayerInput, dt: float) -> void:
	# Still rising from a jump: never let a stale floor contact cancel the jump.
	if _rising and velocity.y <= 0.0:
		_rising = false
	var grounded := is_on_floor() and not _rising
	# Touch-down: the tick that landed still moved with its airborne velocity (impact speed).
	var landed := grounded and _airborne
	if landed:
		landings += 1
		last_landing_speed = maxf(0.0, -_air_vy)
	if grounded:   # landed
		_crouched_jump = false
		_jumped_from_slide = false
		dash.land()

	var wish := forward_for(yaw) * input.move_forward() + right_for(yaw) * input.move_right()
	var moving := wish.length_squared() > 1e-12
	if moving:
		wish = wish.normalized()   # diagonals are not faster

	# Slide (Magewar): Crouch on the ground while sprinting (last tick) with a move key
	# starts it along the current wish direction; leaving the ground or letting go of
	# Crouch or Sprint stops it (the timeout counts down after the move).
	var crouch_held := input.down(&"crouch")
	if sliding() and (not grounded or not crouch_held or not input.down(&"sprint")):
		slide_left = 0.0
	# Dash (press edge): along the wish direction, or the view's forward with no move key.
	# Ends an active slide; refusals (no charge, air dash used, Breath < 25) cost nothing.
	if input.was_pressed(&"dash") and dash.try_start(wish if moving else forward_for(yaw), grounded, breath):
		slide_left = 0.0
	if not sliding() and not dash.active() and grounded and crouch_held and sprinting and moving:
		slide_left = tuning.slide_duration
		slide_dir = wish
		slides += 1

	# Crouch (held): starts on the ground only; a crouch-jump stays crouched in the air;
	# standing up needs head room.
	var want_crouch := _crouched_jump or (grounded and crouch_held)
	if want_crouch:
		_set_crouched(true)
	elif crouched and _can_stand():
		_set_crouched(false)

	# Sprint (held): starts on the ground, carries on in the air while held; never while
	# crouched or exhausted; needs a move key (standing still with Sprint doesn't drain).
	sprinting = input.down(&"sprint") and not crouched and moving and breath.can_sprint() \
		and (grounded or sprinting)
	breath.tick(sprinting, dt)

	# Horizontal: smoothed direction x eased speed (Magewar's lerps).
	if sliding():
		direction = slide_dir
		speed = (slide_left / tuning.slide_duration + 0.5) * tuning.slide_speed
	else:
		if not _jumped_from_slide:   # a slide jump keeps its speed until landing
			var base := tuning.crouch_speed if crouched else (tuning.sprint_speed if sprinting else tuning.walk_speed)
			speed = lerpf(speed, base * speed_multiplier, minf(1.0, dt * tuning.lerp_speed))
		if grounded:
			direction = direction.lerp(wish, minf(1.0, dt * tuning.lerp_speed))
		elif moving:
			direction = direction.lerp(wish, minf(1.0, dt * tuning.air_lerp_speed))
		if direction.length() < 1e-3:
			direction = Vector3.ZERO

	var v := direction * speed
	v.y = 0.0 if grounded else velocity.y - tuning.gravity * dt
	if grounded and input.was_pressed(&"jump"):
		if sliding():   # slide jump: jump x SLIDE_JUMP_MOD, stand up in the air
			v.y = tuning.jump_velocity * tuning.slide_jump_mod
			_jumped_from_slide = true
			_crouched_jump = false
			slide_left = 0.0
			slide_jumps += 1
		else:
			v.y = tuning.crouch_jump_velocity if crouched else tuning.jump_velocity
			_crouched_jump = crouched
		_rising = true
		jumps += 1
	# Dash: replaces the horizontal velocity for the part of this tick it covers.
	var dash_cover := dash.advance(dt)
	if dash_cover > 0.0:
		var d := dash.direction * dash.speed()
		v.x = d.x * dash_cover + v.x * (1.0 - dash_cover)
		v.z = d.z * dash_cover + v.z * (1.0 - dash_cover)
	velocity = v
	# A climbed step already moved the body this tick (up, over the edge, onto the top);
	# the camera stays and eases up after it. (Stepping down needs no smoothing: the
	# capsule's round bottom rolls off the edge and falls, <= 0.04 m/tick off 0.35 m.)
	if grounded and v.y <= 0.0 and _try_step_up(Vector3(v.x, 0.0, v.z) * dt):
		feel.add_step(last_step_rise)
	else:
		move_and_slide()
	if sliding():   # SlidingTimer counts down
		slide_left = maxf(0.0, slide_left - dt)
		if slide_left < 1e-9:
			slide_left = 0.0

	# Eye height eases toward the stance's.
	var target := tuning.crouching_eye if crouched else tuning.standing_eye
	eye_height = lerpf(eye_height, target, minf(1.0, dt * tuning.lerp_speed))
	if absf(eye_height - target) < 1e-4:
		eye_height = target

	# Landing detection for the next tick + camera feel (bob / dip / step).
	_airborne = not grounded
	if _airborne:
		_air_vy = v.y
	var gait := CameraFeel.Gait.CROUCH if crouched else (CameraFeel.Gait.SPRINT if sprinting else CameraFeel.Gait.WALK)
	feel.tick(grounded and moving and not sliding() and dash_cover <= 0.0, gait, landed, last_landing_speed, dt)
	var o := feel.offset()
	head.position = Vector3(o.x, eye_height + o.y, 0.0)

	# Mana regen (step 8) before the cast, so a pool back at the cost casts this tick.
	mana.tick(dt)
	# Focus (step 9): action_secondary held with a wieldable; costs no mana.
	focus.tick(input.down(&"action_secondary"), caster.wieldable, dt)
	camera.fov = focus.fov
	# Casting (step 7): semi-auto on the press, from where the eye is after this tick.
	# Spread (step 9): bloom decays, a press that wants to cast is spread inside the cone;
	# bloom grows only on a real cast (not on a cooldown/mana refusal).
	spread.tick(dt)
	var fire_pressed := input.was_pressed(&"action_primary")
	var fire_held := input.down(&"action_primary")
	var a := aim()
	if caster.wieldable != null and (fire_pressed or (caster.hold_to_repeat and fire_held)):
		a = spread.apply(a, caster.wieldable.accuracy(), spread_stance())
	if caster.tick(fire_pressed, fire_held, dt, a, bolts):
		spread.on_cast()

func _set_capsule(h: float) -> void:
	_shape.height = h
	_collider.position = Vector3(0.0, h * 0.5, 0.0)

func _set_crouched(on: bool) -> void:
	if on == crouched:
		return
	crouched = on
	_set_capsule(tuning.crouching_height if on else tuning.standing_height)

## The part of the standing capsule above the crouched one (slightly thinner so touching
## walls don't count) must be free.
func _can_stand() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = tuning.radius - 0.01
	var lo := tuning.crouching_height - tuning.radius   # bottom of the extra part (sphere centre)
	probe.height = tuning.standing_height - lo
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, lo + probe.height * 0.5, 0.0))
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Step climbing (reinterprets Cogito's step_check): if this tick's horizontal motion hits
## a wall, probe up by step_height (+2 cm), forward until the capsule's bottom sphere is
## past the edge (contact travel + radius + 5 cm), then down; a walkable top at most
## step_height above the feet places the body on it (true = moved this tick).
## The lift goes to last_step_rise; tick() hands it to the camera feel (step 5).
func _try_step_up(motion: Vector3) -> bool:
	if motion.length_squared() < 1e-10:
		return false
	var col := KinematicCollision3D.new()
	if not test_move(global_transform, motion, col):
		return false
	var min_floor_y := cos(floor_max_angle) - 1e-4
	if col.get_normal().y >= min_floor_y:
		return false   # a walkable slope: move_and_slide handles it
	var t := global_transform
	var up := Vector3(0.0, tuning.step_height + 0.02, 0.0)
	var c := KinematicCollision3D.new()
	if test_move(t, up, c):
		up = c.get_travel()
	t.origin += up
	var fwd := motion.normalized() * maxf(motion.length(), col.get_travel().length() + tuning.radius + 0.05)
	if test_move(t, fwd, c):
		return false   # still blocked when raised: a wall, not a step
	t.origin += fwd
	if not test_move(t, Vector3(0.0, -(up.y + 0.05), 0.0), c):
		return false   # nothing below: an edge, not a step
	if c.get_normal().y < min_floor_y:
		return false
	t.origin += c.get_travel()
	var rise := t.origin.y - global_position.y
	if rise <= 0.01 or rise > tuning.step_height + 0.005:
		return false
	global_transform = t
	last_step_rise = rise
	steps_climbed += 1
	return true
