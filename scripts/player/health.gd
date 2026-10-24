class_name Health
extends RefCounted
## Player health + shield (BUILD_PLAN step 13; PLAN §7 "a shield that regenerates after a
## delay before health"). The archived C++ engine never built this (its step 24 ended the
## port), so the numbers are plan design.
##
## Magewar reference (Cogito HealthAttribute on the player, read-only): value_max 100 is
## kept; Magewar starts the player at 80 (value_start 80) and has no regen and no shield.
## Reinterpreted: the player starts full; a shield pool sits in front of health:
##   * take(amount): the shield absorbs first, the rest comes off health (clamped at 0);
##     any damage (even fully absorbed) restarts the shield's regen delay;
##   * the shield regenerates shield_regen_per_sec once shield_regen_delay has passed
##     since the last damage; only the part of the tick past the delay counts (exact to
##     the sub-tick, like Breath/Mana); health never regenerates (potions, step 19);
##   * health 0 = dead (`died` once); take() on a dead pool does nothing; refill()
##     (respawn) brings both back to full and clears the death.
##   * equipment (Magewar EquipmentItem.health_bonus, Clothes/Belt, step 19) and level-ups
##     (step 27): set_max_bonus() like Mana (raising adds the difference, lowering clamps);
##     Health Potion (+30, Magewar consumable, step 19): heal().

signal damaged(shield_lost: float, health_lost: float)
signal died

const EPS := 1e-9

var base_max := 100.0              ## Cogito HealthAttribute value_max
var shield_max := 50.0
var shield_regen_per_sec := 25.0
var shield_regen_delay := 3.0      ## s since the last damage

var value := 100.0
var shield := 50.0
var max_bonus := 0.0
var seconds_since_damage := 3.0
var dead := false
var hits := 0
var shield_absorbed := 0.0         ## totals (tests, HUD)
var health_lost := 0.0

static func from_tuning(t: PlayerTuning) -> Health:
	var h := Health.new()
	h.base_max = t.health_max
	h.shield_max = t.shield_max
	h.shield_regen_per_sec = t.shield_regen_per_sec
	h.shield_regen_delay = t.shield_regen_delay
	h.refill()
	return h

func max_value() -> float:
	return base_max + max_bonus

func fraction() -> float:
	var m := max_value()
	return value / m if m > 0.0 else 0.0

func shield_fraction() -> float:
	return shield / shield_max if shield_max > 0.0 else 0.0

func regenerating() -> bool:
	return not dead and seconds_since_damage >= shield_regen_delay - 1e-7 and shield < shield_max

## Takes `amount` (already resolved: Damage.resolve_hit) shield first, then health.
## Returns the health lost.
func take(amount: float) -> float:
	if dead or amount <= 0.0:
		return 0.0
	hits += 1
	seconds_since_damage = 0.0
	var from_shield := minf(shield, amount)
	shield -= from_shield
	if shield < EPS:
		shield = 0.0
	var rest := amount - from_shield
	var from_health := minf(value, rest)
	value -= from_health
	if value < EPS:
		value = 0.0
	shield_absorbed += from_shield
	health_lost += from_health
	damaged.emit(from_shield, from_health)
	if value <= 0.0:
		dead = true
		died.emit()
	return from_health

## One fixed tick: the shield regenerates for the part of the tick past the delay.
func tick(dt: float) -> void:
	if dead:
		return
	var before := seconds_since_damage
	seconds_since_damage += dt
	var delay := shield_regen_delay - 1e-7   # 180 x (1/60 s) counts as 3 s despite rounding
	var regen_time := clampf(seconds_since_damage - maxf(before, delay), 0.0, dt)
	if regen_time > 0.0 and shield < shield_max:
		shield = minf(shield_max, shield + shield_regen_per_sec * regen_time)
		if shield_max - shield < EPS:
			shield = shield_max

## Health Potion (step 19). Nothing while dead.
func heal(amount: float) -> void:
	if not dead and amount > 0.0:
		value = minf(max_value(), value + amount)

## Equipment / level bonus total (Mana.set_max_bonus rules).
func set_max_bonus(total: float) -> void:
	var before := max_value()
	max_bonus = total
	var after := max_value()
	if after > before and not dead:
		value += after - before
	value = minf(value, after)

## Respawn: full health and shield, alive again (bonuses kept).
func refill() -> void:
	value = max_value()
	shield = shield_max
	dead = false
	seconds_since_damage = shield_regen_delay
