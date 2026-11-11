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
##  * Crouch is held. On the ground it starts there; a crouch-jump stays crouched until
##    landing; standing up waits until the tall capsule fits (Magewar CrouchRayCast).
##    Crouching in the air (not a slide-jump) tucks the capsule up by the height
##    difference so the feet clear a higher ledge. Letting go drops the feet again
##    only when the standing capsule fits; a landing keeps the tucked feet and then
##    uses the same headroom check before standing.
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
##    wand, slot_3 / slot_4 draw the two extra carry slots, and the mouse wheel
##    (quickslot_prev/next_wieldable) cycles filled slots; a draw takes 0.4 s
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
var sprint_toggle := false  ## sprint press latches "held"
var _focus_latch := false
var _crouch_latch := false
var _sprint_latch := false
var breath: Breath  # sprint/dash pool (step 4)
var sprinting := false
var slide_left := 0.0  # seconds left on the slide (Magewar SlidingTimer)
var slide_dir := Vector3.ZERO
var slides := 0
var slide_jumps := 0
var speed_multiplier := 1.0  # set_speed_multiplier(): Shoes hook
var slow_factor := 1.0  # step 55: apply_slow()
var poison_left := 0.0  ## s of lingering spore fog still to come off health
var poison_dps := 0.0  ## fraction of max health per second; not the Breath pool
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
var _seen_dashes := 0  ## P5: dash.dashes at the last tick (FOV kick)
var _death_tint: DeathTint  ## P5: game only (headless has no renderer)
var respawn_left := 0.0  # s until the respawn while dead
## Step 80 (co-op): > 0 = the downed window (co-op sets this to CoopWorld.LAST_STAND).
## 0 = the solo Second Wind window (SECOND_WIND_S). Either way a kill gets you up, and
## in co-op a teammate can still revive you. The window ending starts the respawn countdown.
const SECOND_WIND_S := 8.0
const SECOND_WIND_HEALTH := 0.3
const CRAWL_SPEED := 1.6
var last_stand := 0.0
var downed := false
var downed_left := 0.0
var revives := 0
var second_wind_revives := 0
var bleed_outs := 0
var _second_wind_bound := false
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
var _air_tuck := false  ## crouched in the air: feet were lifted by _tuck_rise
var _tuck_rise := 0.0
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
	_bind_second_wind()  # before consecrations, so a downed kill revives first
	apply_bonuses()  # the pools were rebuilt from tuning: put worn bonuses back
	loadout.swap_seconds = tuning.swap_seconds
	viewmodel = Viewmodel.new()
	viewmodel.fov = tuning.viewmodel_fov
	head.add_child(viewmodel)
	if input_enabled and DisplayServer.get_name() != "headless":
		viewmodel.enable_render(camera)
		_death_tint = DeathTint.new()  # P5 (L5): desaturate while dead
		add_child(_death_tint)
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


## Puts a staff/wand into its typed slot (Loadout.equip); with empty hands it is drawn at once.
func equip(w: WieldableInstance) -> int:
	return equip_in(loadout.slot_for(w), w)


## Puts `w` in `slot` (a carry slot, or a typed one). Updates the viewmodel.
func equip_in(slot: int, w: WieldableInstance) -> int:
	var got := loadout.equip_slot(slot, w)
	if viewmodel != null:
		viewmodel.show_wieldable(caster.wieldable)
	return got


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
	camera.fov = focus.fov_at(Engine.get_physics_interpolation_fraction()) + feel.fov_kick
	if _death_tint:
		_death_tint.sync(feel.death())


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
func on_enemy_attack(from: Variant, bite: Gnawer.Bite) -> void:
	if bite.dodged:
		hits_ignored += 1
		return
	var dmg := bite.damage
	if LevelScale.player_level > 0:
		var dl := bite.dl
		if from is Enemy:
			dl = (from as Enemy).combat_dl(LevelScale.player_level)
		dmg *= LevelScale.mult("dmg", dl)
	take_enemy_hit(dmg, bite.element)
	if alive() and from is Enemy and (from as Enemy).def != null and (from as Enemy).def.id == "spore_beast":
		poison_dps = 0.02
		poison_left = maxf(poison_left, 2.0)


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
	PlayerState._on_died(self)


func respawn() -> void:
	PlayerState.respawn(self)


func revive(fraction := 0.3) -> bool:
	return PlayerState.revive(self, fraction)


func bleed_out() -> void:
	PlayerState.bleed_out(self)


func _apply_toggles(input: PlayerInput) -> void:
	for pair in [
		[focus_toggle, &"action_secondary", "_focus_latch"],
		[crouch_toggle, &"crouch", "_crouch_latch"],
		[sprint_toggle, &"sprint", "_sprint_latch"]
	]:
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
	return PlayerState.equip_from_inventory(self, item)


func unequip_wieldable_to_inventory(slot: int) -> bool:
	return PlayerState.unequip_wieldable_to_inventory(self, slot)


func trash_item(item: Variant, count: int = 1) -> String:
	return PlayerState.trash_item(self, item, count)


func unequip_item_to_inventory(slot: int) -> bool:
	return PlayerState.unequip_item_to_inventory(self, slot)


func apply_bonuses() -> void:
	PlayerState.apply_bonuses(self)


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


## Act II: mire, fog and falls come off health. Breath and the shield are not spent.
func hurt_health(amount: float) -> void:
	if not alive() or downed or amount <= 0.0:
		return
	health.take_health(amount)


func clear_blight_status() -> void:
	poison_left = 0.0
	poison_dps = 0.0
	slow_left = 0.0
	slow_factor = 1.0


## Lingering fog. A full second at poison_dps removes that fraction of max health.
func tick_poison(dt: float) -> void:
	if not alive() or downed or poison_left <= 0.0 or poison_dps <= 0.0:
		if poison_left <= 0.0:
			poison_dps = 0.0
		return
	var step := minf(dt, poison_left)
	poison_left -= step
	hurt_health(health.max_value() * poison_dps * step)
	if poison_left <= 1e-6:
		poison_left = 0.0
		poison_dps = 0.0


func current_slow() -> float:
	return slow_factor if slow_left > 0.0 else 1.0


## One fixed tick (dt must be the physics step: move_and_slide uses the physics delta).
func tick(input: PlayerInput, dt: float) -> void:
	interact_held = input.down(&"interact")  # 0.3.1 P2: hold-to-use (Labyrinth stairs)
	_apply_toggles(input)
	slow_left = maxf(0.0, slow_left - dt)
	tick_poison(dt)
	# Dead (step 13): Second Wind first (crawl and cast; a kill revives). When that
	# window ends, bleed_out() starts the respawn countdown. No input while that runs.
	if not alive():
		if downed:
			downed_left -= dt
			if downed_left <= 1e-7:
				bleed_out()
				return
			_tick_crawl(input)
			_tick_combat(input, dt, false)
			return
		respawn_left -= dt
		feel.tick_death(true, dt)  # P5 (L5): the eye sinks while dead
		head.position = Vector3(0.0, eye_height + feel.offset().y, 0.0)
		if respawn_left <= 1e-7:
			respawn()
		return
	health.tick(dt)
	consecrations.tick(self)
	skill_procs.tick(self, dt)
	NamedUniques.tick(self)
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
		# A tuck lands on the raised feet. Do not drop them back through the ledge.
		if _air_tuck:
			_air_tuck = false
			_tuck_rise = 0.0
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

	# Crouch (held): starts on the ground; a crouch-jump stays crouched in the air.
	# An air tuck stays crouched until it is released into open space or we land.
	# Standing up on the ground needs head room.
	var want_crouch := _crouched_jump or _air_tuck or (grounded and crouch_held)
	if want_crouch:
		_set_crouched(true)
	elif crouched and _can_stand():
		_set_crouched(false)
	if (
		not grounded
		and not _jumped_from_slide
		and not _crouched_jump
		and crouch_held
		and not _air_tuck
		and not crouched
	):
		_begin_air_tuck()
	elif not grounded and _air_tuck and not crouch_held and not _crouched_jump:
		_try_release_tuck()

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
	if grounded:
		var floor_n := get_floor_normal()
		# A flat wish climbs the Midden's 20 deg ramps and stops on a steeper one.
		# Past about 25 deg, carry the wish up the floor (the Blightcoil root-bridges).
		if floor_n.y < 0.91 and floor_n.y > 0.05:
			var along := Vector3(v.x, 0.0, v.z).slide(floor_n)
			v = along if along.dot(Vector3(direction.x, 0.0, direction.z)) > 0.0 else Vector3(v.x, 0.0, v.z)
		else:
			v.y = 0.0
	else:
		v.y = velocity.y - tuning.gravity * dt
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
	if dash.dashes > _seen_dashes:  # P5 (M5): the dash FOV kick
		feel.add_fov_kick()
	_seen_dashes = dash.dashes
	feel.tick(grounded and moving and not sliding() and dash_cover <= 0.0, gait, landed, last_landing_speed, dt)
	feel.tick_death(false, dt)  # P5 (L5): the respawn rise
	var o := feel.offset()
	head.position = Vector3(o.x, eye_height + o.y, 0.0)

	_tick_combat(input, dt, true)


## Second Wind: a slow crawl. No jump, sprint, slide, or dash.
func _tick_crawl(input: PlayerInput) -> void:
	PlayerState._tick_crawl(self, input)


func _bind_second_wind() -> void:
	PlayerState._bind_second_wind(self)


func _on_second_wind_kill(_enemy: Enemy, _element: ElementTable.Element) -> void:
	PlayerState._on_second_wind_kill(self, _enemy, _element)


func _tick_combat(input: PlayerInput, dt: float, allow_potion: bool) -> void:
	PlayerState._tick_combat(self, input, dt, allow_potion)


func _set_capsule(h: float) -> void:
	_shape.height = h
	_collider.position = Vector3(0.0, h * 0.5, 0.0)


func _set_crouched(on: bool) -> void:
	if on == crouched:
		return
	crouched = on
	_set_capsule(tuning.crouching_height if on else tuning.standing_height)


func air_tucked() -> bool:
	return _air_tuck


## Source-style crouch jump: shrink from the bottom. The crouched capsule moves up
## so its top stays where the standing head was and the feet rise by the difference
## (1.0 m with the shipped tuning). A low ceiling stops the rise early.
func _begin_air_tuck() -> void:
	PlayerState._begin_air_tuck(self)


func _try_release_tuck() -> void:
	PlayerState._try_release_tuck(self)


func _stand_fits(feet: Vector3) -> bool:
	return PlayerState._stand_fits(self, feet)


func _can_stand() -> bool:
	return PlayerState._can_stand(self)


func _try_step_up(motion: Vector3) -> bool:
	return PlayerState._try_step_up(self, motion)
