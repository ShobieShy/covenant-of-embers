class_name HeatMode
extends FireMode
## Pyrowning Arms (step 137, BRANDS_PLAN §3): no mana per cast; each cast adds heat. Heat
## decays after `vent_delay` without a cast; at 100 % the staff overheats and is locked
## for `overheat_seconds` (Q4: lockout only, no self-burn; Q3: no mana at all). R vents:
## dumps the heat over `vent_seconds` (no casting meanwhile). Holding repeats.
## Wands (Q46): the cooldown cut and heat per cast scale toward neutral by wand_scale.

var heat := 0.0  ## 0..1
var overheated := false
var venting := false
var lock_left := 0.0
var since_cast := 99.0


func id() -> StringName:
	return &"heat"


func wants_cast(pressed: bool, held: bool, _released: bool) -> bool:
	return pressed or held


func is_locked() -> bool:
	return overheated or venting


func cost_mult() -> float:
	return 0.0


func cooldown_mult() -> float:
	return param("cooldown_mult", 1.0)


func damage_mult() -> float:
	return param("damage_mult", 1.0)


func after_cast() -> void:
	since_cast = 0.0
	heat = minf(1.0, heat + param("heat_per_cast", 0.0))
	emit(&"heat", heat)
	if heat >= 1.0 - 1e-9:
		overheated = true
		lock_left = raw("overheat_seconds", 2.0)
		emit(&"overheated", 1.0)


func tick(dt: float, _held: bool, _pressed: bool, _in_hand: bool) -> void:
	since_cast += dt
	var before := heat
	if overheated:
		lock_left -= dt
		heat = maxf(0.0, lock_left / maxf(raw("overheat_seconds", 2.0), 1e-6))
		if lock_left <= 0.0:
			overheated = false
			heat = 0.0
			emit(&"vented", 0.0)
	elif venting:
		heat = maxf(0.0, heat - dt / maxf(raw("vent_seconds", 1.0), 1e-6))
		if heat <= 0.0:
			venting = false
			emit(&"vented", 0.0)
	elif since_cast >= raw("vent_delay", 0.4):
		heat = maxf(0.0, heat - raw("heat_decay", 0.6) * dt)
	if heat != before and not overheated:
		emit(&"heat", heat)


func reload(_out: Array) -> bool:
	if overheated or venting or heat <= 0.0:
		return false
	venting = true
	emit(&"vent", heat)
	return true


func meter() -> float:
	return heat


func meter_kind() -> StringName:
	return &"heat"


func meter_text() -> String:
	return "OVERHEAT" if overheated else ("VENT" if venting else "")


func fx_bits() -> int:
	return (1 if heat >= 0.6 else 0) | (2 if overheated or venting else 0)
