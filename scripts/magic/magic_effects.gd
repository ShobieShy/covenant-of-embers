class_name MagicEffects
extends RefCounted
## Per-element on-hit effects (BUILD_PLAN steps 50-53), run by SpellBolts after a bolt's
## take_hit (so the enemy's health already shows the hit). Pure statics so tests drive them
## with a hand-made SpellBolts.Hit.
##
## Light (steps 50/51, Magewar Bible: Light "heals and summons"): a Light hit that dealt
## damage to an enemy heals its caster for max(LIGHT_HEAL_MIN, LIGHT_HEAL_FRACTION x damage)
## (green number via EventBus.player_healed) and, if the caster has none, calls one
## LightSummon that fights beside him for LightSummon.LIFETIME (30 s).

const LIGHT_HEAL_MIN := 8.0
const LIGHT_HEAL_FRACTION := 0.35

static var light_heals := 0
static var summons_made := 0


static func on_hit(h: SpellBolts.Hit) -> void:
	if h == null or h.result == null or h.result.amount <= 0.0:
		return
	if not (h.collider is Enemy):
		return
	match h.element:
		ElementTable.Element.LIGHT:
			light(h)


static func light_heal_amount(dmg: float) -> float:
	return maxf(LIGHT_HEAL_MIN, LIGHT_HEAL_FRACTION * dmg)


static func light(h: SpellBolts.Hit) -> void:
	var p := h.source as Player
	if p == null or not is_instance_valid(p) or not p.alive() or p.health == null:
		return
	var before := p.health.value
	p.health.heal(light_heal_amount(h.result.amount))
	var gained := p.health.value - before
	light_heals += 1
	if gained > 0.0:
		GameEvents.bus().player_healed.emit(p, gained)
	summon_light(p)


## One live summon per caster; returns the new one or null (already has one / no world).
static func summon_light(p: Player) -> LightSummon:
	if LightSummon.of(p) != null:
		return null
	var parent := p.get_parent()
	if parent == null:
		return null
	var s := LightSummon.new()
	s.owner_player = p
	parent.add_child(s)
	s.global_position = p.global_position + LightSummon.OFFSET
	summons_made += 1
	return s


## Step 52 sets this up (Dark corruption); until then nothing is an ally.
static func is_ally(_e: Enemy) -> bool:
	return false
