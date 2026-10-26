class_name ExplosiveMode
extends FireMode
## Moss & Berg (step 138, BRANDS_PLAN §3): semi-auto boulders. Slower (cooldown x
## cooldown_mult), harder (damage x damage_mult), heavier (speed x speed_mult, straight: Q39),
## dearer (mana x mana_mult); the impact bursts for blast_fraction of the damage on every
## other enemy within blast_radius, falling off to blast_falloff at the edge
## (MagicEffects.blast; Earth still staggers; no self-damage). Wands (Q46) scale toward neutral.


func id() -> StringName:
	return &"explosive"


func cost_mult() -> float:
	return param("mana_mult", 1.0)


func cooldown_mult() -> float:
	return param("cooldown_mult", 1.0)


func damage_mult() -> float:
	return param("damage_mult", 1.0)


func modify(s: SpellBolts.Spawn) -> void:
	s.speed *= param("speed_mult", 1.0) * skill_mult("speed_pct")
	s.blast_radius = param("blast_radius", 0.0) * skill_mult("splash_pct")
	s.blast_falloff = raw("blast_falloff", 0.5)
	s.blast_fraction = raw("blast_fraction", 0.5) * skill_mult("splash_damage_pct")
