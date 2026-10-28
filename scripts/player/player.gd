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
##  * Loadout + viewmodel (step 10, scripts/player/loadout.gd + viewmodel.gd): a staff slot
##    and a wand slot, each with its own Caster (own cooldown, kept while holstered);
##    `caster` is the slot in hand. slot_1 / slot_2 (Magewar quickslot_1/2) draw the staff /
##    wand, the mouse wheel (quickslot_prev/next_wieldable) cycles; a draw takes 0.4 s
##    (24 ticks) in which presses don't cast (no mana check, cue, spread draw or bloom).
##    Both slots spend the one mana pool and share focus + spread. The Viewmodel (child of
##    the Head: bobs with it) shows the slot in hand at Magewar's pose, slid to x = 0 by
##    focus.amount(), raised during a draw, kicked by CameraFeel recoil; casts add recoil
##    and screen shake (zero under reduced motion). The bolt ray stays at the eye; only the
##    tracer starts at the viewmodel's cast point.
##  * Equipment (step 19, scripts/player/equipment.gd + scripts/loot/equipment_item.gd):
##    equip_item()/unequip_item() then apply_bonuses() recomputes the worn totals:
##    Health/Mana max (+ level_*_bonus, step 27), Mana regen, Breath max (stamina; no
##    refill), speed_multiplier (product), damage_target.resist per affinity (uncapped;
##    resolve_hit caps 60 %) and every caster's flat damage_bonus (spell damage).
##    use_potion() drinks the quick-slot potion (Health +30 / Mana +25), refused when full.
## In game _physics_process feeds PlayerInput.from_input(); tests call tick() directly.

const RESPEC_BASE := 25  ## step 59 gold
const RESPEC_MAX := 200
const GROUP := &"players"  # step 27: XpRewarder finds players here
const CHARACTER_LAYER := 2  # physics layer "character" (bit 2)
const HINT_NOT_ENOUGH_MANA := "Not enough mana!"  # Magewar wieldable_staff.gd

## Short on-screen message (Magewar player_interaction_component.send_hint); step 29 HUD.
signal hint(text: String)
signal hurt(player: Player, result: Damage.Result)  ## step 13: a hit that landed (after resolve)
signal died(player: Player)
signal respawned(player: Player)
signal downed_changed(player: Player, is_down: bool)  ## step 80 (co-op last stand)

@export var tuning: PlayerTuning

var yaw := 0.0
var pitch := 0.0
var eye_height := 1.5
var crouched := false
var jumps := 0
var steps_climbed := 0
var direction := Vector3.ZERO  # smoothed move direction (Magewar `direction`)
var speed := 4.0  # Magewar `current_speed`
var interact_held := false  ## 0.3.1 P2: Interact held this tick
var input_enabled := true  # false in tests: no Input polling in _physics_process
var ui_open := false  # step 30: a menu screen is up: no actions, no mouse look
# Step 32 settings (Settings.apply_to): look + hold/toggle modes.
var invert_y := false
var aim_sensitivity := 1.0  ## on top of focus.look_scale(); Magewar-like raw = 1/0.6784
var focus_toggle := false  ## action_secondary press latches focus
var crouch_toggle := false  ## crouch press latches "held" (Cogito TOGGLE_CROUCH)
var _focus_latch := false
var _crouch_latch := false
var breath: Breath  # sprint/dash pool (step 4)
var sprinting := false
var slide_left := 0.0  # seconds left on the slide (Magewar SlidingTimer)
var slide_dir := Vector3.ZERO
var slides := 0
var slide_jumps := 0
var speed_multiplier := 1.0  # set_speed_multiplier(): Shoes hook
var slow_factor := 1.0  # step 55: apply_slow()
var slow_left := 0.0
var dash: Dash  # step 5
var feel: CameraFeel  # step 5: bob / landing dip / step smoothing
var landings := 0
var last_landing_speed := 0.0  # m/s downward at the last touch-down
var last_step_rise := 0.0  # m, the last climbed step
var loadout := Loadout.new()  # step 10: staff + wand slots, each with its Caster
## step 7: the Caster of the slot in hand (wieldable + cooldown).
var caster: Caster:
	get:
		return loadout.caster()
var viewmodel: Viewmodel  # step 10 (built in _ready under the Head)
var bolts: SpellBolts  # where casts go (main.gd sets it; null = no bolts spawned)
var mana: Mana  # step 8: casting pool (caster.mana_spender)
var not_enough_mana_cues := 0
var focus: Focus  # step 9: ADS FOV tween
var spread: Spread  # step 9: accuracy cone + bloom (seeded)
var last_hint := ""
var health: Health  # step 13: shield first, then health
var damage_target := Damage.Target.new(ElementTable.Element.ARCANE)  ## bolts + enemy melee resolve on it
var spawn_feet := Vector3.ZERO  # the last spawn() point: respawns go back there
var spawn_yaw := 0.0
var respawn_left := 0.0  # s until the respawn while dead
## Step 80 (co-op): > 0 = falling leaves you downed for this many s (last stand) before
## you bleed out and the normal respawn countdown starts; a teammate can revive you.
var last_stand := 0.0
var downed := false
var downed_left := 0.0
var revives := 0
var bleed_outs := 0
var protection_left := 0.0  # step 14: s of spawn protection left after a respawn
var deaths := 0
var respawns := 0
var hits_taken := 0
var hits_ignored := 0  # i-frames / dead
var equipment := Equipment.new()  # step 19: worn items + potion quick-slot
var consecrations := Consecrations.new()  # step 36: worn Consecration effects
var archetype := Archetype.DEFAULT  ## step 73: nerd / gal / buff / loli
var character_name := "Ember"  ## step 73 customization
var character_color := Archetype.default_color(Archetype.DEFAULT)
var level_health_bonus := 0.0  # step 27 (level-ups) fills these; apply_bonuses() adds them
var level_mana_bonus := 0.0
var level_breath_bonus := 0.0
var potions_used := 0
var inventory := Inventory.new()  # step 23: backpack (30 slots) + Arcane Dust
var progression := Progression.new()  # step 27: XP + level
var skills := Skills.new()  # step 71: skill ranks (tree data in data/skills/)
var skill_procs := SkillProcs.new()  # step 72: kill procs + capstone frenzy
var quest_items := PackedStringArray()  # step 57: quest items (Joe's Trash), saved
var pickups := PickupCollector.new()  # step 23: walk-over auto-collect + Interact pickup

var _wheel := 0  # queued mouse-wheel cycles (+ next / - prev)
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
	skills.tree = SkillTree.default_tree()
	if tuning == null:
		tuning = PlayerTuning.new()
	breath = Breath.from_tuning(tuning)
	dash = Dash.from_tuning(tuning)
	feel = CameraFeel.from_tuning(tuning)
	set_mana(Mana.from_tuning(tuning))
	focus = Focus.from_tuning(tuning)
	spread = Spread.from_tuning(tuning)
	_set_health(Health.from_tuning(tuning))
	for c in loadout.casters:
		c.out_of_mana.connect(_on_out_of_mana)


func _ready() -> void:
	add_to_group(GROUP)
	if tuning == null:
		tuning = PlayerTuning.new()
	collision_layer = 1 << (CHARACTER_LAYER - 1)
	collision_mask = 1 | (1 << 2)  # world + enemy (step 11: dummies block the player)
	floor_max_angle = deg_to_rad(tuning.max_slope_deg)
	floor_snap_length = tuning.floor_snap
	floor_stop_on_slope = true
	floor_block_on_wall = true
	_collider = $CollisionShape3D
	_shape = CapsuleShape3D.new()  # own shape per player (resized for crouch)
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
	_set_health(Health.from_tuning(tuning))
	camera.fov = focus.fov
	apply_bonuses()  # the pools were rebuilt from tuning: put worn bonuses back
	loadout.swap_seconds = tuning.swap_seconds
	viewmodel = Viewmodel.new()
	viewmodel.fov = tuning.viewmodel_fov
	head.add_child(viewmodel)
	if input_enabled and DisplayServer.get_name() != "headless":
		viewmodel.enable_render(camera)
	eye_height = tuning.standing_eye
	head.position = Vector3(0.0, eye_height, 0.0)
	set_look(rotation.y, 0.0)
	if input_enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Step 40: when valid, returns this tick's PlayerInput instead of the keyboard/mouse.
var bot_input: Callable


## Uses `m` as the mana pool and plugs it into every slot's caster (one shared pool).
func set_mana(m: Mana) -> void:
	mana = m
	for c in loadout.casters:
		c.mana_spender = mana.spend
		c.mana_drain = mana.drain_fraction  # t69u: Pyrowning crystal reloads


## Puts a staff/wand into its slot (Loadout.equip); with empty hands it is drawn at once.
func equip(w: WieldableInstance) -> int:
	var slot := loadout.equip(w)
	if viewmodel != null:
		viewmodel.show_wieldable(caster.wieldable)
	return slot


func _on_out_of_mana(_cost: float) -> void:
	not_enough_mana_cues += 1
	last_hint = HINT_NOT_ENOUGH_MANA
	hint.emit(HINT_NOT_ENOUGH_MANA)


## Step 86: Alt+Tab / focus loss releases the mouse on every OS; a click recaptures it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or ui_open:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(mm.relative.x, mm.relative.y)
	elif event.is_action_pressed(&"quickslot_next_wieldable"):
		_wheel += 1  # wheel clicks press + release in one frame: queue them for the tick
	elif event.is_action_pressed(&"quickslot_prev_wieldable"):
		_wheel -= 1
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
	if input_enabled and ui_open:
		_wheel = 0
		tick(PlayerInput.hold(), delta)  # physics keeps running; no actions while a menu is up
	elif input_enabled and bot_input.is_valid():
		tick(bot_input.call() as PlayerInput, delta)  # step 40: the playtest bot drives
	elif input_enabled:
		var stick := Gamepad.look_vector()  # step 77: right-stick look
		if stick != Vector2.ZERO:
			add_look_degrees(stick * Gamepad.LOOK_DEG_PER_SEC * delta)
		var input := PlayerInput.from_input()
		if _wheel > 0:
			input.pressed[&"quickslot_next_wieldable"] = true
		elif _wheel < 0:
			input.pressed[&"quickslot_prev_wieldable"] = true
		_wheel = 0
		tick(input, delta)


## Places the feet at `feet`, facing `yaw_rad` (pitch 0), at rest; respawns return here.
func spawn(feet: Vector3, yaw_rad: float) -> void:
	spawn_feet = feet
	spawn_yaw = yaw_rad
	global_position = feet
	velocity = Vector3.ZERO
	direction = Vector3.ZERO
	set_look(yaw_rad, 0.0)


## Relative mouse motion in counts (dx right, dy down); scaled down while focused (step 9).
func add_look(dx_counts: float, dy_counts: float) -> void:
	var r := deg_to_rad(tuning.look_deg_per_count) * focus.look_scale() * aim_sensitivity
	set_look(yaw - dx_counts * r, pitch - dy_counts * r * (-1.0 if invert_y else 1.0))


## Stick look in degrees (step 77): same focus scale / sensitivity / invert as the mouse.
func add_look_degrees(d: Vector2) -> void:
	add_look(d.x / tuning.look_deg_per_count, d.y / tuning.look_deg_per_count)


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
	var a := Caster.Aim.make(eye_position(), look_direction(), ex)
	a.source = self
	return a


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


## Dash i-frames or spawn protection (step 14: respawn_protection after a respawn): enemy
## hits are ignored while this is true (Gnawer marks the bite dodged).
func invulnerable() -> bool:
	return dash.invulnerable() or protection_left > 0.0


func alive() -> bool:
	return not health.dead


func _set_health(h: Health) -> void:
	health = h
	health.died.connect(_on_died)


## Enemy melee (Gnawer bite / Heap slam) and any other non-bolt hit: ignored during dash
## i-frames or while dead (null); else resolved on damage_target (Arcane, resists capped
## at 60 %, no crit) and taken shield first. No damage numbers on the player.
func take_enemy_hit(damage: float, element: ElementTable.Element) -> Damage.Result:
	if invulnerable() or not alive():
		hits_ignored += 1
		return null
	var r := Damage.resolve_melee(damage, element, damage_target)
	_take(r)
	return r


## Gnawer.attacked / Heap slams (main.gd connects them): dodged attacks do nothing.
func on_enemy_attack(_from: Gnawer, bite: Gnawer.Bite) -> void:
	if bite.dodged:
		hits_ignored += 1
		return
	take_enemy_hit(bite.damage, bite.element)


## A bolt (SpellBolts already resolved it on damage_target): same i-frame/dead rules.
func take_hit(h: SpellBolts.Hit) -> void:
	if h.result == null:
		return
	if invulnerable() or not alive():
		hits_ignored += 1
		return
	_take(h.result)


func _take(r: Damage.Result) -> void:
	hits_taken += 1
	health.take(r.amount)
	hurt.emit(self, r)
	GameEvents.bus().announce_player_damaged(self, r)  # step 14: EventBus.player_damaged


func _on_died() -> void:
	deaths += 1
	respawn_left = tuning.respawn_delay
	slide_left = 0.0
	sprinting = false
	velocity = Vector3.ZERO
	direction = Vector3.ZERO
	if last_stand > 0.0:
		downed = true
		downed_left = last_stand
		downed_changed.emit(self, true)
	died.emit(self)


## Back at the last spawn point, full health/shield, mana and Breath refilled (equipment
## and level bonuses kept), focus and slide dropped. (Jolt: ray queries see the moved
## body only after the next physics step.)
func respawn() -> void:
	health.refill()
	mana.refill()
	breath.refill()
	respawn_left = 0.0
	slide_left = 0.0
	sprinting = false
	_set_crouched(false)
	spawn(spawn_feet, spawn_yaw)
	respawns += 1
	protection_left = tuning.respawn_protection
	respawned.emit(self)


## Step 80: back up where you fell with `fraction` of max health (no shield), briefly
## protected. False unless downed.
func revive(fraction := 0.3) -> bool:
	if not downed:
		return false
	downed = false
	downed_left = 0.0
	health.refill()
	health.value = maxf(1.0, health.max_value() * clampf(fraction, 0.01, 1.0))
	health.shield = 0.0
	respawn_left = 0.0
	protection_left = tuning.respawn_protection
	revives += 1
	downed_changed.emit(self, false)
	respawned.emit(self)
	return true


## Step 80: the last stand ran out; the normal respawn countdown starts.
func bleed_out() -> void:
	if not downed:
		return
	downed = false
	downed_left = 0.0
	bleed_outs += 1
	respawn_left = tuning.respawn_delay
	downed_changed.emit(self, false)


## Step 32: toggle modes turn a press into a latched "held" for focus / crouch.
func _apply_toggles(input: PlayerInput) -> void:
	for pair in [[focus_toggle, &"action_secondary", "_focus_latch"], [crouch_toggle, &"crouch", "_crouch_latch"]]:
		if not pair[0]:
			continue
		var a: StringName = pair[1]
		if input.was_pressed(a):
			set(pair[2], not get(pair[2]))
		if get(pair[2]):
			input.held[a] = true
		else:
			input.held.erase(a)


## Sets the hip FOV (focus target at rest + the camera now when not focused).
func set_hip_fov(deg: float) -> void:
	focus.hip_fov = deg
	if not focus.focused:
		focus.fov = deg
		focus.prev_fov = deg
		focus.target_fov = deg
		if is_node_ready():
			camera.fov = deg


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


## Wears `item` (EquipmentItem) and reapplies the bonuses; returns what it replaced.
func equip_item(item: EquipmentItem) -> EquipmentItem:
	var old := equipment.equip(item)
	apply_bonuses()
	return old


func unequip_item(slot: int) -> EquipmentItem:
	var old := equipment.unequip(slot)
	apply_bonuses()
	return old


## Step 24: equips a backpack item (staff/wand into its loadout slot, gear into its
## equipment slot); whatever it replaces goes back into the backpack in its place.
## Parts can't be equipped (they go to the Assembly Station). False = refused.
func equip_from_inventory(item: Resource) -> bool:
	if item == null or not inventory.has(item):
		return false
	var old: Resource = null
	if item is WieldableInstance:
		old = loadout.wieldable(Loadout.slot_for(item))
		inventory.remove(item)
		equip(item)
	elif item is EquipmentItem:
		inventory.remove(item)
		old = equip_item(item)
	else:
		return false
	if old != null:
		inventory.add(old)
	return true


## Step 24: moves the staff/wand in loadout `slot` to the backpack; false when empty/full.
func unequip_wieldable_to_inventory(slot: int) -> bool:
	var w := loadout.wieldable(slot)
	if w == null or inventory.is_full():
		if w != null:
			show_hint(PickupCollector.HINT_FULL)
		return false
	loadout.unequip(slot)
	if viewmodel != null:
		viewmodel.show_wieldable(caster.wieldable)
	return inventory.add(w)


## Step 24: moves the worn piece in equipment `slot` to the backpack; false when empty/full.
## t74u: see ItemTrash (quest items refused, worn gear must be unequipped first).
func trash_item(item: Variant, count: int = 1) -> String:
	return ItemTrash.trash(self, item, count)


func unequip_item_to_inventory(slot: int) -> bool:
	var it := equipment.item(slot)
	if it == null or inventory.is_full():
		if it != null:
			show_hint(PickupCollector.HINT_FULL)
		return false
	unequip_item(slot)
	return inventory.add(it)


## Pushes the worn totals (+ level parts) into the pools, speed, resists and casters.
## Max raises add the difference (Health/Mana; Breath doesn't refill), removals clamp.
func apply_bonuses() -> void:
	var sk := skills.totals()  # step 71: skill ranks stack on top of gear + levels
	var arch := Archetype.perks(archetype)  # step 73: the archetype perk stacks the same way
	for k in arch:
		sk[k] = float(sk.get(k, 0.0)) + float(arch[k])
	if health != null:
		health.set_max_bonus(equipment.health_bonus() + level_health_bonus + float(sk.get("max_health", 0.0)))
	if mana != null:
		mana.set_max_bonus(equipment.mana_bonus() + level_mana_bonus + float(sk.get("max_mana", 0.0)))
		mana.set_regen_bonus(equipment.mana_regen_bonus() + float(sk.get("mana_regen", 0.0)))
	if breath != null:
		breath.set_max_bonus(equipment.stamina_bonus() + level_breath_bonus + float(sk.get("max_breath", 0.0)))
	set_speed_multiplier(equipment.speed_multiplier() * (1.0 + float(sk.get("speed_pct", 0.0)) / 100.0))
	var res := equipment.resistances()
	for e in ElementTable.COUNT:
		damage_target.resist[e] = res[e] + float(sk.get("resist_all", 0.0)) / 100.0  # capped in Damage
	var dmg := equipment.spell_damage_bonus() + float(sk.get("spell_damage", 0.0))
	for c in loadout.casters:
		c.damage_bonus = dmg
		c.skills = skills  # step 145: element-tree mods
		c.owner_node = self
	consecrations.apply(self)
	skill_procs.bind(self)


## Step 73: archetype + customization (name, colour); re-applies the bonuses.
func set_character(arch: String, p_name: String, color: Variant = null) -> void:
	archetype = Archetype.valid(arch)
	character_name = Archetype.clean_name(p_name)
	character_color = color if color is Color else Archetype.default_color(archetype)
	apply_bonuses()


## Step 71: one skill rank (see Skills.why_not); re-applies the bonuses.
func spend_skill(sid: String) -> bool:
	if not skills.spend(sid, progression.level):
		return false
	apply_bonuses()
	return true


## Step 144: one rank in element tree `el` (see Skills.el_why_not); re-applies the bonuses.
func spend_element_skill(el: String, sid: String) -> bool:
	if not skills.el_spend(el, sid, progression.level):
		return false
	apply_bonuses()
	return true


## Step 59: respec price in gold: 25 x (respecs so far + 1), at most 200; free with nothing spent.
func respec_price() -> int:
	if skills.spent() <= 0:
		return 0
	return mini(RESPEC_MAX, RESPEC_BASE * (skills.respecs + 1))


## Step 71: refund every skill point (main.gd only offers it at the Old Oak); step 59: costs
## respec_price() gold, -1 when the player can't pay.
func respec_skills() -> int:
	if not inventory.spend_gold(respec_price()):
		return -1
	var n := skills.respec()
	apply_bonuses()
	return n


## Drinks the quick-slot potion; a refusal (pool full / dead / empty slot) costs nothing
## and hints "<attribute> is already maxed." like Cogito.
func use_potion() -> bool:
	var p := equipment.potion
	if equipment.use_potion(self):
		potions_used += 1
		if not p.hint.is_empty():
			hint.emit(p.hint)
			last_hint = p.hint
		return true
	if p != null:
		hint.emit(p.maxed_hint())
		last_hint = p.maxed_hint()
	return false


## Equipment speed hook (Magewar EquipmentItem.speed_modifier, Shoes x1.15): scales the
## walk/sprint/crouch targets, not the slide.
## Step 27: kill XP; every level gained applies Magewar's +5 mana / +5 Breath and refills.
func add_xp(amount: int) -> int:
	var gained := progression.add_xp(amount)
	if gained > 0:
		level_mana_bonus += Progression.MANA_PER_LEVEL * gained
		level_breath_bonus += Progression.BREATH_PER_LEVEL * gained
		level_health_bonus += Progression.HEALTH_PER_LEVEL * gained
		apply_bonuses()
		mana.refill()
		breath.refill()
		if Progression.HEALTH_PER_LEVEL > 0.0:
			health.refill()
	return gained


## Shows a short HUD hint (Magewar/Cogito hint pop-up) and remembers it.
func show_hint(text: String) -> void:
	last_hint = text
	hint.emit(text)


func set_speed_multiplier(m: float) -> void:
	speed_multiplier = m


## Step 55: a slow (Mire Ooze puddle) for `time` s; the strongest active slow wins.
func apply_slow(factor: float, time: float) -> void:
	if slow_left <= 0.0 or factor < slow_factor:
		slow_factor = clampf(factor, 0.05, 1.0)
	slow_left = maxf(slow_left, time)


func current_slow() -> float:
	return slow_factor if slow_left > 0.0 else 1.0


## One fixed tick (dt must be the physics step: move_and_slide uses the physics delta).
func tick(input: PlayerInput, dt: float) -> void:
	interact_held = input.down(&"interact")  # 0.3.1 P2: hold-to-use (Labyrinth stairs)
	_apply_toggles(input)
	slow_left = maxf(0.0, slow_left - dt)
	# Dead (step 13): no input, no movement; respawn after respawn_delay.
	if not alive():
		if downed:
			downed_left -= dt
			if downed_left <= 1e-7:
				bleed_out()
			return
		respawn_left -= dt
		if respawn_left <= 1e-7:
			respawn()
		return
	health.tick(dt)
	consecrations.tick(self)
	skill_procs.tick(self, dt)
	protection_left = maxf(0.0, protection_left - dt)
	if protection_left < 1e-6:  # 1 - 60 x 1/60 leaves float dust: exactly 60 ticks
		protection_left = 0.0
	# Still rising from a jump: never let a stale floor contact cancel the jump.
	if _rising and velocity.y <= 0.0:
		_rising = false
	var grounded := is_on_floor() and not _rising
	# Touch-down: the tick that landed still moved with its airborne velocity (impact speed).
	var landed := grounded and _airborne
	if landed:
		landings += 1
		last_landing_speed = maxf(0.0, -_air_vy)
	if grounded:  # landed
		_crouched_jump = false
		_jumped_from_slide = false
		dash.land()

	var wish := forward_for(yaw) * input.move_forward() + right_for(yaw) * input.move_right()
	var moving := wish.length_squared() > 1e-12
	if moving:
		wish = wish.normalized()  # diagonals are not faster

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
	sprinting = input.down(&"sprint") and not crouched and moving and breath.can_sprint() and (grounded or sprinting)
	breath.tick(sprinting, dt)

	# Horizontal: smoothed direction x eased speed (Magewar's lerps).
	if sliding():
		direction = slide_dir
		speed = (slide_left / tuning.slide_duration + 0.5) * tuning.slide_speed
	else:
		if not _jumped_from_slide:  # a slide jump keeps its speed until landing
			var base := tuning.crouch_speed if crouched else (tuning.sprint_speed if sprinting else tuning.walk_speed)
			speed = lerpf(speed, base * speed_multiplier * current_slow(), minf(1.0, dt * tuning.lerp_speed))
		if grounded:
			direction = direction.lerp(wish, minf(1.0, dt * tuning.lerp_speed))
		elif moving:
			direction = direction.lerp(wish, minf(1.0, dt * tuning.air_lerp_speed))
		if direction.length() < 1e-3:
			direction = Vector3.ZERO

	var v := direction * speed
	v.y = 0.0 if grounded else velocity.y - tuning.gravity * dt
	if grounded and input.was_pressed(&"jump"):
		if sliding():  # slide jump: jump x SLIDE_JUMP_MOD, stand up in the air
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
	if sliding():  # SlidingTimer counts down
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

	# Loadout (step 10): slot_1 staff / slot_2 wand / wheel cycle start a 0.4 s draw;
	# holstered slots keep cooling down.
	var started := false
	if input.was_pressed(&"slot_1"):
		started = loadout.select(Loadout.Slot.STAFF)
	elif input.was_pressed(&"slot_2"):
		started = loadout.select(Loadout.Slot.WAND)
	elif input.was_pressed(&"quickslot_next_wieldable"):
		started = loadout.cycle(1)
	elif input.was_pressed(&"quickslot_prev_wieldable"):
		started = loadout.cycle(-1)
	loadout.tick(dt, started)
	if input.was_pressed(&"use_potion"):  # step 24 (H since step 136): the quick-slot potion
		use_potion()
	# Pickups (step 23): walk-over auto-collect, then Interact on the looked-at item.
	pickups.tick(self, input.was_pressed(&"interact"), dt)
	# Mana regen (step 8) before the cast, so a pool back at the cost casts this tick.
	mana.tick(dt)
	# Focus (step 9): action_secondary held with a wieldable; costs no mana. A swap while
	# focused retargets to the drawn slot's type FOV.
	focus.tick(input.down(&"action_secondary"), caster.wieldable, dt)
	camera.fov = focus.fov
	# Casting (step 7): semi-auto on the press, from where the eye is after this tick.
	# Spread (step 9): bloom decays, a press that wants to cast is spread inside the cone;
	# bloom grows only on a real cast (not on a cooldown/mana refusal).
	spread.tick(dt)
	var fire_pressed := input.was_pressed(&"action_primary")
	var fire_held := input.down(&"action_primary")
	var w := caster.wieldable
	if loadout.swapping():  # drawing: no cast attempt at all (Cogito is_changing_wieldables)
		loadout.tick_swap(fire_pressed, dt)
	else:
		var a := aim()
		if w != null and caster.wants_aim(fire_pressed, fire_held):
			a = spread.apply(a, minf(100.0, w.accuracy() + caster.accuracy_bonus()), spread_stance())
		if viewmodel != null and w != null and viewmodel.is_inside_tree():
			viewmodel.update_pose(w, focus.amount(), loadout.draw_progress(), feel.recoil_offset())
			a.with_visual_origin(viewmodel.cast_point_position())
		if input.was_pressed(&"reload") and w != null:  # step 136: R = the brand's vent action
			caster.reload(a, bolts)
		if caster.tick(fire_pressed, fire_held, dt, a, bolts):
			spread.on_cast(caster.bloom_mult())
			var is_wand := w.type() == WieldableDef.Type.WAND
			feel.add_recoil(tuning.recoil_wand if is_wand else tuning.recoil_staff)
			feel.add_shake(tuning.shake_wand if is_wand else tuning.shake_staff)
	if viewmodel != null:
		viewmodel.update_pose(caster.wieldable, focus.amount(), loadout.draw_progress(), feel.recoil_offset())
		viewmodel.update_brand(caster.fire_mode())


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
	var lo := tuning.crouching_height - tuning.radius  # bottom of the extra part (sphere centre)
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
		return false  # a walkable slope: move_and_slide handles it
	var t := global_transform
	var up := Vector3(0.0, tuning.step_height + 0.02, 0.0)
	var c := KinematicCollision3D.new()
	if test_move(t, up, c):
		up = c.get_travel()
	t.origin += up
	var fwd := motion.normalized() * maxf(motion.length(), col.get_travel().length() + tuning.radius + 0.05)
	if test_move(t, fwd, c):
		return false  # still blocked when raised: a wall, not a step
	t.origin += fwd
	if not test_move(t, Vector3(0.0, -(up.y + 0.05), 0.0), c):
		return false  # nothing below: an edge, not a step
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
