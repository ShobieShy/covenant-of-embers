class_name PostClear
extends RefCounted
## 0.8.8: Covenant Escalation after Forgemaw. The class stays Vigil. Tier 0 is the
## story run. The saved field is optional and defaults to 0.

const MAX_TIER := 10

static var forgemaw_clear := false
static var tier := 0
static var seed := 1


static func note_clear() -> void:
	forgemaw_clear = true


static func set_tier(t: int) -> int:
	if not forgemaw_clear:
		tier = 0
		return 0
	tier = clampi(t, 0, MAX_TIER)
	return tier


static func vigil() -> Vigil:
	return Vigil.create(tier, seed)


static func scale_health(base: float) -> float:
	if tier <= 0:
		return base
	return base * vigil().enemy_health_mult()


static func scale_damage(amount: float) -> float:
	if tier <= 0:
		return amount
	return amount * vigil().enemy_damage_mult()


static func to_dict() -> Dictionary:
	return {"forgemaw_clear": forgemaw_clear, "vigil_tier": tier, "vigil_seed": seed}


static func from_dict(d: Dictionary) -> void:
	forgemaw_clear = bool(d.get("forgemaw_clear", false))
	seed = int(d.get("vigil_seed", 1))
	tier = clampi(int(d.get("vigil_tier", 0)), 0, MAX_TIER) if forgemaw_clear else 0
