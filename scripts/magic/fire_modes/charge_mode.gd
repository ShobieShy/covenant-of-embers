class_name ChargeMode
extends FireMode
## Sigil Sauer (step 138, BRANDS_PLAN §3): holding the trigger charges 0..1 over
## charge_time() (step 143); releasing casts. Damage x lerp(min_mult, max_mult, charge), mana x
## lerp(mana_min, mana_max, charge). A charge >= chain_threshold chains to `chain_targets`
## enemies within `chain_range` for `chain_fraction` of the damage (Q42: Water chains only on
## a full charge). A tap (press and release in one tick) is a weak quick shot. A release
## during the cooldown spends the charge with no cast. R does nothing. Holstering drops it.
## Wands (Q46): the multipliers and jump count scale toward neutral by wand_scale.

var charge := 0.0  ## 0..1 while held
var shot := 0.0  ## the charge the next release casts with


func id() -> StringName:
	return &"charge"


func wants_cast(pressed: bool, held: bool, released: bool) -> bool:
	return released or (pressed and not held)


func cost_mult() -> float:
	return lerpf(param("mana_min", 1.0), param("mana_max", 1.0), shot)


func damage_mult() -> float:
	return lerpf(param("min_mult", 1.0), param("max_mult", 1.0), shot)


## Step 143: seconds to full charge = `charge_cooldowns` x the wieldable cooldown (wands
## scale it toward 1 like the multipliers), min 0.12 s; else the flat `charge_seconds`.
func charge_time() -> float:
	if brand != null and brand.params.has("charge_cooldowns"):
		return maxf(0.12, param("charge_cooldowns", 1.0) * base_cooldown() * skill_mult("charge_pct", 0.3))
	return maxf(raw("charge_seconds", 1.0) * skill_mult("charge_pct", 0.3), 1e-6)


func full() -> bool:
	return shot >= raw("chain_threshold", 0.95)


func modify(s: SpellBolts.Spawn) -> void:
	if full():
		s.chain_targets = maxi(1, roundi(param("chain_targets", 0.0) + skill_add("chain_jumps")))
		s.chain_range = raw("chain_range", 6.0) + skill_add("chain_range")
		s.chain_fraction = raw("chain_fraction", 0.5)


func after_cast() -> void:
	emit(&"charge_released", shot)
	shot = 0.0


func tick(dt: float, held: bool, _pressed: bool, in_hand: bool) -> void:
	if held and in_hand:
		charge = minf(1.0, charge + dt / charge_time())
		shot = charge
		emit(&"charge", charge)
	elif charge > 0.0:
		shot = charge if in_hand else 0.0
		charge = 0.0
		emit(&"charge", 0.0)


func meter() -> float:
	return charge if charge > 0.0 else -1.0


func meter_kind() -> StringName:
	return &"charge"


func meter_text() -> String:
	return "FULL" if charge >= raw("chain_threshold", 0.95) else ""


func fx_bits() -> int:
	return 4 if charge > 0.0 else 0
