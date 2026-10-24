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


## Where a cast starts.
class Aim:
	extends RefCounted
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD
	var exclude: Array[RID] = []
	var has_visual_origin := false  ## step 10: tracer starts at the viewmodel cast point
	var visual_origin := Vector3.ZERO

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

var wieldable: WieldableInstance
var hold_to_repeat := false
var mana_spender := Callable()  ## step 8: func(cost: float) -> bool
var cooldown_left := 0.0  ## seconds (GDScript floats are 64-bit: no drift at 60 Hz)
var casts := 0
var blocked := 0  ## presses refused by the cooldown or mana
var mana_refused := 0
var damage_bonus := 0.0  ## step 19: worn spell_damage_bonus, added flat to each cast
var conditional_bonus := 0.0  ## step 36: Consecration bonus while its condition holds (flat, each cast)
var next_cast_bonus := 0.0  ## step 36: Consecration one-shot bonus, spent by the next cast


func _init(w: WieldableInstance = null) -> void:
	wieldable = w


## Counts the cooldown down without casting (a holstered slot, or the slot being drawn
## during a swap: step 10's per-slot cooldown keeps running).
func cool(dt: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - dt)


## Swaps the wieldable (null = empty hands); the running cooldown is kept.
func equip(w: WieldableInstance) -> void:
	wieldable = w


## One physics tick. Returns true when a bolt was cast (spawned into `bolts` if given).
func tick(pressed: bool, held: bool, dt: float, aim: Aim, bolts: SpellBolts) -> bool:
	cooldown_left = maxf(0.0, cooldown_left - dt)
	var want := pressed or (hold_to_repeat and held)
	if not want or wieldable == null:
		return false
	if cooldown_left > 1e-9:
		if pressed:
			blocked += 1
		return false
	if mana_spender.is_valid() and not bool(mana_spender.call(wieldable.mana_cost())):
		if pressed:
			blocked += 1
			mana_refused += 1
			out_of_mana.emit(wieldable.mana_cost())
		return false
	cooldown_left = wieldable.cooldown()
	if bolts != null and aim != null:
		var s := SpellBolts.Spawn.new()
		s.origin = aim.origin
		s.direction = aim.direction
		s.speed = wieldable.projectile_speed()
		s.range_m = wieldable.range_m()
		s.element = wieldable.element()
		s.damage = wieldable.damage() + damage_bonus + conditional_bonus + next_cast_bonus
		next_cast_bonus = 0.0
		s.exclude = aim.exclude
		s.has_visual_origin = aim.has_visual_origin
		s.visual_origin = aim.visual_origin
		bolts.spawn(s)
	casts += 1
	return true
