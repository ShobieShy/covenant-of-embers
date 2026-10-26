class_name Mana
extends RefCounted
## Mana: the only casting resource (BUILD_PLAN step 8, port of the archived C++ game::Mana,
## old step 18; numbers are PLAN §30.1, a kept decision). No ammo, no reloads.
##
## Follows Magewar's ManaAttribute (scripts/player/mana_attribute.gd + the player scenes'
## ManaAttribute node) directly:
##   * value_max 100, value_start 100;
##   * spend(cost) = spend_mana: refused (nothing changes, the regen delay is NOT
##     restarted) when value < cost (exactly enough is fine); otherwise subtracts and
##     restarts the delay;
##   * regen (mana_regen_speed 3 + equipment regen bonus)/s once regen_delay 1.5 s has
##     passed since the last successful spend; never above the max; auto_regenerate off =
##     no regen;
##   * equipment (magewar_player.gd _apply/_remove_equipment_bonuses, step 19):
##     set_max_bonus() raising the max adds the difference to the current value too
##     (clamped), lowering it clamps; set_regen_bonus() adds to the rate (Novice Grimoire
##     +5 max / +0.5 regen);
##   * level-up (_level_up, step 27): max +5 and refill();
##   * Mana Potion (Magewar consumable, +25, step 19/23): restore().
## Reinterpretation (like Breath): Magewar counts the delay per rendered frame in _process
## and regenerates the whole frame in which the timer runs out; here it runs per fixed
## physics tick and only the part of the tick past the delay regenerates, so timings are
## exact to the sub-tick at 30/60/144 Hz.

signal refused(cost: float)  ## a spend() was refused (not enough mana)

const EPS := 1e-9  # snaps float drift (100 x 3/60 s regains exactly 5)

var base_max := 100.0  ## ManaAttribute value_max (player scene)
var regen_per_sec := 3.0  ## mana_regen_speed
var regen_delay := 1.5  ## seconds since the last successful spend before regen
var auto_regenerate := true  ## auto_regenerate

var value := 100.0
var max_bonus := 0.0  ## equipment + levels (steps 19/27): total
var regen_bonus := 0.0  ## equipment (Magewar equipment_regen_bonus): total
var seconds_since_spend := 1.5
var spends := 0
var refusals := 0


static func from_tuning(t: PlayerTuning) -> Mana:
	var m := Mana.new()
	m.base_max = t.mana_max
	m.regen_per_sec = t.mana_regen_per_sec
	m.regen_delay = t.mana_regen_delay
	m.auto_regenerate = t.mana_auto_regenerate
	m.value = m.base_max
	m.seconds_since_spend = m.regen_delay
	return m


func max_value() -> float:
	return base_max + max_bonus


func fraction() -> float:
	var m := max_value()
	return value / m if m > 0.0 else 0.0


## Mana/s while regenerating: base + equipment bonus, never negative.
func regen_rate() -> float:
	return maxf(0.0, regen_per_sec + regen_bonus)


## Magewar has_mana.
func has(amount: float) -> bool:
	return value >= amount - EPS


func regenerating() -> bool:
	return auto_regenerate and seconds_since_spend >= regen_delay - 1e-7 and value < max_value()


## One fixed tick: the time since the last spend grows; once it passes regen_delay only
## the part of this tick past the delay regenerates.
func tick(dt: float) -> void:
	var before := seconds_since_spend
	seconds_since_spend += dt
	if not auto_regenerate:
		return
	var delay := regen_delay - 1e-7  # 90 x (1/60 s) counts as 1.5 s despite rounding
	var regen_time := clampf(seconds_since_spend - maxf(before, delay), 0.0, dt)
	if regen_time > 0.0 and value < max_value():
		value = minf(max_value(), value + regen_rate() * regen_time)
		if max_value() - value < EPS:
			value = max_value()


## Magewar spend_mana; plugged into Caster.mana_spender. false = refused: no change, the
## delay keeps running (a refusal must not hold regen back), `refused` is emitted.
func spend(amount: float) -> bool:
	if value < amount - EPS:
		refusals += 1
		refused.emit(amount)
		return false
	value = maxf(0.0, value - amount)
	if value < EPS:
		value = 0.0
	seconds_since_spend = 0.0
	spends += 1
	return true


## t69u: a Pyrowning crystal reload takes `fraction` of MAX mana, or whatever is left; it
## never refuses (the reload always finishes). Returns the amount taken.
func drain_fraction(fraction: float) -> float:
	var amount := minf(value, maxf(0.0, fraction) * max_value())
	if amount <= 0.0:
		return 0.0
	value = maxf(0.0, value - amount)
	if value < EPS:
		value = 0.0
	seconds_since_spend = 0.0
	return amount


## Equipment/level hook: total max bonus. Raising it adds the difference to the current
## value too (Magewar equip); lowering it clamps (Magewar unequip). No full refill.
func set_max_bonus(bonus: float) -> void:
	var delta := bonus - max_bonus
	max_bonus = bonus
	if delta > 0.0:
		value += delta
	value = clampf(value, 0.0, max_value())


## Equipment hook: total regen bonus (mana/s).
func set_regen_bonus(bonus: float) -> void:
	regen_bonus = bonus


## Level-up (Magewar _level_up refills).
func refill() -> void:
	value = max_value()


## Mana Potion / pickups: +amount up to the max; doesn't touch the regen delay.
func restore(amount: float) -> void:
	value = clampf(value + maxf(0.0, amount), 0.0, max_value())
