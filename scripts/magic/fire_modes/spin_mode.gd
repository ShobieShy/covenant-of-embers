class_name SpinMode
extends FireMode
## Windchester (step 137): full auto (holding always repeats). Spin rises 0..1 over
## `spin_seconds` while held and falls `spin_down`/s when released; cooldown x
## lerp(spin_start, spin_end, spin), still >= 0.1 s (Q45). Damage x damage_mult, bloom x
## bloom_mult; mana per cast as normal (mana is the ammo). Wands: the range scales.

var spin := 0.0


func id() -> StringName:
	return &"spin"


func wants_cast(pressed: bool, held: bool, _released: bool) -> bool:
	return pressed or held


func cooldown_mult() -> float:
	return lerpf(param("spin_start", 1.0), param("spin_end", 1.0), spin)


func damage_mult() -> float:
	return param("damage_mult", 1.0)


func bloom_mult() -> float:
	return param("bloom_mult", 1.0)


func tick(dt: float, held: bool, _pressed: bool, in_hand: bool) -> void:
	var before := spin
	if held and in_hand:
		spin = minf(1.0, spin + dt / maxf(raw("spin_seconds", 1.5) * skill_mult("spin_pct", 0.3), 1e-6))
	else:
		spin = maxf(0.0, spin - raw("spin_down", 1.5) * dt)
	if spin != before:
		emit(&"spin", spin)


func meter() -> float:
	return spin


func meter_kind() -> StringName:
	return &"spin"


func fx_bits() -> int:
	return 8 if spin >= 0.5 else 0
