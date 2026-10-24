class_name Breath
extends RefCounted
## Breath: the sprint/dash pool (BUILD_PLAN step 4, port of the archived C++ game::Breath,
## old step 15; numbers are PLAN §30.8, a kept decision).
## Reinterprets Magewar/Cogito's StaminaAttribute (30 max, 3/s run drain, 2/s regen after
## 2 s, 5 per jump) with our own numbers: 100 max, -20/s while sprinting, +30/s once 1 s has
## passed since the last drain or spend. Like Magewar, regen pauses while draining and
## restarts its delay afterwards. Equipment (Belt/Shoes stamina_bonus, step 19) and
## level-ups (+5, step 27) raise the max through set_max_bonus() (no free refill; a
## level-up calls refill() itself, as Magewar's _level_up does).
## Deliberate deviation: Magewar re-allows sprint as soon as stamina > 0, which stutters
## (drain to 0, regen a sliver, sprint a frame, ...). Here an emptied pool stays
## `exhausted` until it regains `resume_at` (20 = 1 s of sprint); resume_at 0 = Magewar.
## Not taken from Magewar: the jump cost and slope-dependent drain (Breath stays a
## sprint/dash resource).

const EPS := 1e-9  # snaps float drift (300 x 20/60 drains to exactly 0)

var base_max := 100.0  ## PLAN §30.8 base Breath
var drain_per_sec := 20.0  ## while sprinting
var regen_per_sec := 30.0
var regen_delay := 1.0  ## seconds since the last drain/spend before regen starts
var resume_at := 20.0  ## after running dry, sprint needs this much back

var value := 100.0
var max_bonus := 0.0
var exhausted := false  ## true from running dry until value >= resume_at
var seconds_since_use := 1.0


static func from_tuning(t: PlayerTuning) -> Breath:
	var b := Breath.new()
	b.base_max = t.breath_max
	b.drain_per_sec = t.breath_drain_per_sec
	b.regen_per_sec = t.breath_regen_per_sec
	b.regen_delay = t.breath_regen_delay
	b.resume_at = t.breath_resume_at
	b.value = b.base_max
	b.seconds_since_use = b.regen_delay
	return b


func max_value() -> float:
	return base_max + max_bonus


func fraction() -> float:
	var m := max_value()
	return value / m if m > 0.0 else 0.0


func empty() -> bool:
	return value <= 0.0


func can_sprint() -> bool:
	return not exhausted and value > 0.0


func regenerating() -> bool:
	return seconds_since_use >= regen_delay and value < max_value()


## One fixed tick. `draining`: the player sprints this tick (costs drain_per_sec x dt,
## floored at 0). Otherwise the time since the last use grows and regen runs once it
## passes regen_delay; only the part of the tick past the delay counts, so timings are
## exact to the sub-tick at any tick rate.
func tick(draining: bool, dt: float) -> void:
	if draining:
		value = maxf(0.0, value - drain_per_sec * dt)
		if value < EPS:
			value = 0.0
			exhausted = true
		seconds_since_use = 0.0
		return
	var before := seconds_since_use
	seconds_since_use += dt
	var delay := regen_delay - 1e-7  # 60 x (1/60 s) counts as 1 s despite rounding
	var regen_time := clampf(seconds_since_use - maxf(before, delay), 0.0, dt)
	if regen_time > 0.0:
		value = minf(max_value(), value + regen_per_sec * regen_time)
		if max_value() - value < EPS:
			value = max_value()
	if exhausted and value >= minf(resume_at, max_value()) - EPS:
		exhausted = false


## Instant cost (step 5 dash: 25). Refused (no change, delay untouched) if value < amount;
## otherwise restarts the regen delay.
func spend(amount: float) -> bool:
	if value < amount - EPS:
		return false
	value = maxf(0.0, value - amount)
	if value < EPS:
		value = 0.0
		exhausted = true
	seconds_since_use = 0.0
	return true


## Equipment / level bonus to the max. The value is clamped to the new max; raising the
## max does not refill.
func set_max_bonus(bonus: float) -> void:
	max_bonus = bonus
	value = minf(value, max_value())


func refill() -> void:
	value = max_value()
	exhausted = false
