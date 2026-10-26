class_name Caster
extends RefCounted
## Casting (BUILD_PLAN step 7, port of the archived C++ game/magic/casting.*, old step 17):
## the equipped staff/wand turns an action_primary press into a spell bolt, gated by its
## cooldown (WieldableInstance.cooldown(), >= 0.1 s).
##
## Magewar wieldable_staff.gd (followed: weapon system): a cast happens on the press
## (semi-auto: holding does not repeat, Magewar returns on release and never re-fires while
## held); a press while the cooldown runs is ignored; a cast sets cooldown = final fire
## rate. Here the cooldown counts down per physics tick *before* the press is checked, so at
## 60 Hz the Swift Wind Wand (0.18 s) casts at most every 11 ticks (0.183 s) and the
## Apprentice Fire Staff (0.4 s) every 24 ticks. hold_to_repeat (off; an options toggle
## later) re-casts while held. Mana (step 8): mana_spender(cost) -> bool is asked after the
## cooldown check; false = no cast and no cooldown (Magewar spends before setting the timer);
## a refused *press* counts `mana_refused` and emits `out_of_mana` (Magewar's
## "Not enough mana!" hint + cast-fail sound hook, wired by Player).
## The bolt starts at the plain eye (Player.eye_position(), not the bobbed camera) along
## the look, excluding the caster's body (Player.aim()).
## Step 136 (Brands B2): the input rules live on a FireMode picked from the wieldable's brand
## (fire_mode()); unbranded = FireMode's semi behaviour, identical to the above. Brand
## multipliers apply to the wieldable's damage before the flat gear bonuses (BRANDS_PLAN §4),
## Light's 0.9x after both. reload() is the R vent action (brand-specific).


## Where a cast starts.
class Aim:
	extends RefCounted
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD
	var exclude: Array[RID] = []
	var has_visual_origin := false  ## step 10: tracer starts at the viewmodel cast point
	var visual_origin := Vector3.ZERO
	var source: Object  ## step 50: who cast (the Player; Light/Dark effects need him)

	## Same aim with the tracer drawn from `p` (the ray itself stays at `origin`).
	func with_visual_origin(p: Vector3) -> Aim:
		has_visual_origin = true
		visual_origin = p
		return self

	static func make(p_origin: Vector3, p_direction: Vector3, p_exclude: Array[RID] = []) -> Aim:
		var a := Aim.new()
		a.origin = p_origin
		a.direction = p_direction
		a.exclude = p_exclude
		return a


signal out_of_mana(cost: float)  ## a press refused by mana_spender (step 8 cue)
## Step 136: brand mode events for HUD/VFX/SFX: heat, overheated, vented, charge,
## charge_released, spin, mode_toggled, orb_thrown, burst (value = the new level / count).
signal brand_event(kind: StringName, value: float)

var wieldable: WieldableInstance
var hold_to_repeat := false
var mana_spender := Callable()  ## step 8: func(cost: float) -> bool
## t69u: func(fraction_of_max: float) -> float taken; never refuses (Pyrowning crystal reload).
var mana_drain := Callable()
var cooldown_left := 0.0  ## seconds (GDScript floats are 64-bit: no drift at 60 Hz)
var casts := 0
var blocked := 0  ## presses refused by the cooldown or mana
var mana_refused := 0
var damage_bonus := 0.0  ## step 19: worn spell_damage_bonus, added flat to each cast
var conditional_bonus := 0.0  ## step 36: Consecration bonus while its condition holds (flat, each cast)
var next_cast_bonus := 0.0  ## step 36: Consecration one-shot bonus, spent by the next cast
var mode: FireMode  ## step 136: rebuilt when the wieldable's brand or type changes
var _was_held := false


func _init(w: WieldableInstance = null) -> void:
	wieldable = w


## Counts the cooldown down without casting (a holstered slot, or the slot being drawn
## during a swap: step 10's per-slot cooldown keeps running).
func cool(dt: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - dt)
	_was_held = false
	var m := fire_mode()
	if m != null:
		m.tick(dt, false, false, false)


## Swaps the wieldable (null = empty hands); the running cooldown is kept.
func equip(w: WieldableInstance) -> void:
	wieldable = w
	fire_mode()


## The FireMode for the current wieldable (null with empty hands); a new brand/type gets
## a fresh mode, the same one keeps its state (heat keeps cooling while holstered).
func fire_mode() -> FireMode:
	if wieldable == null:
		return null
	var b := wieldable.brand()
	if mode == null or mode.brand != b or mode.is_wand != wieldable.is_wand():
		mode = FireMode.for_wieldable(wieldable)
		mode.attach(self)
	return mode


## Whether this tick's input asks for a cast (Player applies spread only then).
func wants_aim(pressed: bool, held: bool) -> bool:
	var m := fire_mode()
	return m != null and (m.wants_cast(pressed, held, _was_held and not held) or m.pending())


## Extra accuracy points from the brand (Coltara ramp, Hexler).
func accuracy_bonus() -> float:
	var m := fire_mode()
	return m.accuracy_bonus() if m != null else 0.0


func bloom_mult() -> float:
	var m := fire_mode()
	return m.bloom_mult() if m != null else 1.0


## The R action (vent / toggle / orb). True when the brand did something.
func reload(aim: Aim, bolts: SpellBolts) -> bool:
	var m := fire_mode()
	if m == null:
		return false
	var extra: Array = []
	var did := m.reload(extra)
	for s in extra:
		_fill_aim(s, aim)
		if bolts != null and aim != null:
			bolts.spawn(s)
	return did


## One physics tick. Returns true when a bolt was cast (spawned into `bolts` if given).
func tick(pressed: bool, held: bool, dt: float, aim: Aim, bolts: SpellBolts) -> bool:
	cooldown_left = maxf(0.0, cooldown_left - dt)
	var released := _was_held and not held
	_was_held = held
	var m := fire_mode()
	if m == null:
		return false
	m.tick(dt, held, pressed, true)
	var fired := false
	for i in m.take_due():  # burst follow-ups: no press, no extra mana or cooldown
		_cast(m, aim, bolts)
		fired = true
	if not m.wants_cast(pressed, held, released):
		return fired
	var edge := pressed or released
	if m.is_locked() or cooldown_left > 1e-9:
		if edge:
			blocked += 1
		return fired
	var cost := wieldable.mana_cost() * m.cost_mult()
	if m.cost_mult() > 0.0 and mana_spender.is_valid() and not bool(mana_spender.call(cost)):
		if edge:
			blocked += 1
			mana_refused += 1
			out_of_mana.emit(cost)
		return fired
	var cd := wieldable.cooldown()
	var cm := m.cooldown_mult()
	cooldown_left = cd if cm == 1.0 else maxf(WieldableDef.MIN_COOLDOWN, cd * cm)
	_cast(m, aim, bolts)
	m.after_cast()
	if m.auto_reload():
		reload(aim, bolts)
	return true


func _cast(m: FireMode, aim: Aim, bolts: SpellBolts) -> void:
	if bolts != null and aim != null:
		var s := SpellBolts.Spawn.new()
		s.speed = wieldable.projectile_speed()
		s.range_m = wieldable.range_m()
		s.element = wieldable.element()
		var base := wieldable.damage()
		var dm := m.damage_mult()
		s.damage = (base if dm == 1.0 else base * dm) + damage_bonus + conditional_bonus + next_cast_bonus
		next_cast_bonus = 0.0
		if s.element == ElementTable.Element.LIGHT:
			s.damage *= MagicEffects.LIGHT_DAMAGE_SCALE  # step 108
		s.dark_bonus = wieldable.dark_chance_bonus()
		m.modify(s)
		_fill_aim(s, aim)
		bolts.spawn(s)
	casts += 1


func _fill_aim(s: SpellBolts.Spawn, aim: Aim) -> void:
	if aim == null:
		return
	s.origin = aim.origin
	s.direction = aim.direction
	s.exclude = aim.exclude
	s.has_visual_origin = aim.has_visual_origin
	s.visual_origin = aim.visual_origin
	s.source = aim.source
