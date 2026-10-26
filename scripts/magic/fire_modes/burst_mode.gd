class_name BurstMode
extends FireMode
## Coltara Halo (step 139, BRANDS_PLAN §3): select fire. R toggles burst <-> semi (Q40, no
## shield). Burst: one press casts `burst_count` bolts `burst_gap` s apart for one mana charge
## x`burst_mana`, then the cooldown x`burst_cooldown_mult`; follow-ups need no press (Caster
## take_due) and each gets the flat gear bonus (Q36: per bolt) and heals allies per hit.
## Semi: a plain press. Accuracy ramp: each bolt within `ramp_window` of the last adds
## `ramp_per_cast` accuracy points (cap `ramp_max`), and the brand has no bloom (negative
## bloom). Wands (Q46): burst 2 and a smaller ramp (wand_scale).

var burst := true  ## false = semi
var queued := 0  ## follow-up bolts still to come in this burst
var gap_left := 0.0
var due := 0
var ramp := 0.0  ## accuracy points
var since_bolt := 99.0


func id() -> StringName:
	return &"burst"


func count() -> int:
	return maxi(1, roundi(param("burst_count", 1.0)))


func cost_mult() -> float:
	return param("burst_mana", 1.0) if burst else 1.0


func cooldown_mult() -> float:
	return raw("burst_cooldown_mult", 1.0) * (count() / 3.0) if burst else 1.0


func accuracy_bonus() -> float:
	return ramp


func bloom_mult() -> float:
	return 0.0


func modify(_s: SpellBolts.Spawn) -> void:
	ramp = ramp if since_bolt <= raw("ramp_window", 0.6) else 0.0
	ramp = minf(param("ramp_max", 0.0), ramp + param("ramp_per_cast", 0.0))
	since_bolt = 0.0


func after_cast() -> void:
	if burst and count() > 1:
		queued = count() - 1
		gap_left = raw("burst_gap", 0.07)
		emit(&"burst", count())


func tick(dt: float, _held: bool, _pressed: bool, in_hand: bool) -> void:
	since_bolt += dt
	if since_bolt > raw("ramp_window", 0.6):
		ramp = 0.0
	if not in_hand:
		queued = 0
		due = 0
		return
	if queued > 0:
		gap_left -= dt
		if gap_left <= 1e-9:
			queued -= 1
			due += 1
			gap_left += raw("burst_gap", 0.07)


func take_due() -> int:
	var n := due
	due = 0
	return n


func pending() -> bool:
	return due > 0 or (queued > 0 and gap_left - 1.0 / 60.0 <= 1e-9)


func reload(_out: Array) -> bool:
	burst = not burst
	queued = 0
	emit(&"mode_toggled", 1.0 if burst else 0.0)
	return true


func meter() -> float:
	var mx := param("ramp_max", 0.0)
	return ramp / mx if mx > 0.0 else 0.0


func meter_kind() -> StringName:
	return &"burst"


func meter_text() -> String:
	return "BURST" if burst else "SEMI"
