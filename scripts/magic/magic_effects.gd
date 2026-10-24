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
## Dark (step 52, Bible: Dark "corrupts"): a Dark hit that leaves a non-boss enemy at <= 25%
## health has a 40% chance to turn it into an ally for 30 s (Enemy.corrupt): it hunts other
## enemies (Gnawer._ally_retarget), its bites hurt them, and it then crumbles.

const LIGHT_HEAL_MIN := 8.0
const LIGHT_HEAL_FRACTION := 0.35

const DARK_THRESHOLD := 0.25
const DARK_CHANCE := 0.4
const DARK_SECONDS := 30.0

static var light_heals := 0
static var corruptions := 0
static var dark_roll := Callable()  ## tests: func() -> float in [0, 1)
static var summons_made := 0


static func on_hit(h: SpellBolts.Hit) -> void:
	if h == null or h.result == null or h.result.amount <= 0.0:
		return
	if not (h.collider is Enemy):
		return
	match h.element:
		ElementTable.Element.LIGHT:
			light(h)
		ElementTable.Element.DARK:
			dark(h)


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


static func is_ally(e: Enemy) -> bool:
	return e != null and e.is_ally()


## Dark: the hit left a non-boss brute at <= DARK_THRESHOLD of its health; DARK_CHANCE to
## corrupt it into an ally for DARK_SECONDS. `dark_roll` (tests) returns the 0..1 roll.
static func dark(h: SpellBolts.Hit) -> bool:
	var e := h.collider as Enemy
	if e == null or not e.alive() or e.is_boss() or not (e is Gnawer) or e.is_ally():
		return false
	if e.health > DARK_THRESHOLD * e.max_health():
		return false
	var roll := float(dark_roll.call()) if dark_roll.is_valid() else randf()
	if roll >= DARK_CHANCE:
		return false
	if e.corrupt(DARK_SECONDS):
		corruptions += 1
		return true
	return false
