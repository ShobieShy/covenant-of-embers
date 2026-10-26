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
## Light rework (step 108): Light bolts deal LIGHT_DAMAGE_SCALE (0.9x) damage (Caster), and a
## Light bolt that hits an ALLY heals it instead of hurting it (intercept): another Player,
## a co-op RemotePlayer (its owner heals over the net, "heal"), or a corrupted ally enemy, for
## max(LIGHT_HEAL_MIN, LIGHT_ALLY_FRACTION x bolt damage). LightSummons have no health and
## are not healed. Player bolts never hurt allies (other elements pass harmlessly).
## Dark (step 52, reworked step 108, Bible: Dark "corrupts"): every Dark hit on a non-boss
## brute has DARK_BASE_CHANCE (1%) + the wieldable's Dark-part bonus (capped, see
## WieldablePart.DARK_BONUS) to turn it into an ally for 30 s (Enemy.corrupt): it hunts other
## enemies (Gnawer._ally_retarget), its bites hurt them, and it then crumbles. In co-op only
## the host rolls (clients send the bonus with their "hit").
## Status effects (step 53): Fire burns (30% of the hit again over 3 s, refreshed, not
## stacked), Water slows (x0.6 walk for 2.5 s), Earth staggers (0.4 s: no move, no attack),
## Air chains (50% of the bolt's damage to the nearest other enemy within 6 m, one jump,
## resolved against its own resist). Durations shrink by the hit's resist (already capped at
## 60% by Damage), so a fully resistant enemy still gets 40%.

const LIGHT_HEAL_MIN := 8.0
const LIGHT_HEAL_FRACTION := 0.35

const LIGHT_DAMAGE_SCALE := 0.9  ## step 108: Light is very slightly weaker than the rest
const LIGHT_ALLY_FRACTION := 0.5  ## step 108: ally heal = max(MIN, this x bolt damage)

const DARK_BASE_CHANCE := 0.01  ## step 108: per Dark hit
const DARK_MAX_CHANCE := 0.15  ## base + part bonuses never exceed this
const DARK_SECONDS := 30.0

const BURN_SECONDS := 3.0
const BURN_FRACTION := 0.3  ## of the hit's damage, dealt over BURN_SECONDS
const SLOW_SECONDS := 2.5
const SLOW_FACTOR := 0.6
const STAGGER_SECONDS := 0.4
const CHAIN_RANGE := 6.0
const CHAIN_FRACTION := 0.5

static var light_heals := 0
static var chains := 0
static var corruptions := 0
static var force_convert := false  ## step 115: the tutorial's next Dark roll always turns
static var dark_roll := Callable()  ## tests: func() -> float in [0, 1)
static var summons_made := 0
static var ally_heals := 0
static var blasts := 0  ## step 138: enemies struck by blasts (Moss & Berg, cursed orb)
static var crits := 0  ## step 139: brand crits (Hexler & Koch)
static var crit_roll := Callable()  ## tests: func() -> float in [0, 1)
## Step 142: blast hits on co-op puppets this frame, [Enemy, amount, element]; CoopWorld
## forwards them to the host like a client's "hit".
static var puppet_hits: Array = []


## Step 108: before take_hit. True when the bolt hit an ally: a Light bolt heals it, any
## other bolt does nothing; SpellBolts then skips take_hit and on_hit.
static func intercept(h: SpellBolts.Hit) -> bool:
	if h == null or not is_instance_valid(h.collider) or h.source == null:
		return false
	var light_bolt := h.element == ElementTable.Element.LIGHT
	var amt := ally_heal_amount(h.damage)
	var c: Object = h.collider
	if c is Enemy:
		var e := c as Enemy
		if not e.is_ally():
			return false
		if light_bolt:
			if e.hold_death and e.get_parent() is CoopWorld:  # a client puppet: tell the host
				(e.get_parent() as CoopWorld).send_puppet_heal(e, amt)
			heal_enemy(e, amt)
		return true
	if c is Player:
		if c == h.source:
			return false
		if light_bolt:
			heal_player(c as Player, amt)
			return true
		return false
	var rp := remote_of(c)
	if rp != null:
		if light_bolt:
			ally_heals += 1
			rp.light_healed.emit(amt)
		return true
	return false


static func remote_of(c: Object) -> RemotePlayer:
	if c is RemotePlayer:
		return c
	if c is Node and (c as Node).get_parent() is RemotePlayer:
		return (c as Node).get_parent()
	return null


static func ally_heal_amount(bolt_damage: float) -> float:
	return maxf(LIGHT_HEAL_MIN, LIGHT_ALLY_FRACTION * bolt_damage)


static func heal_player(p: Player, amt: float) -> float:
	if p == null or not is_instance_valid(p) or not p.alive() or p.health == null:
		return 0.0
	var before := p.health.value
	p.health.heal(amt)
	var gained := p.health.value - before
	ally_heals += 1
	if gained > 0.0:
		GameEvents.bus().player_healed.emit(p, gained)
	return gained


static func heal_enemy(e: Enemy, amt: float) -> float:
	if e == null or not is_instance_valid(e) or e.dead:
		return 0.0
	var before := e.health
	e.health = minf(e.max_health(), e.health + amt)
	ally_heals += 1
	return e.health - before


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
		ElementTable.Element.FIRE:
			burn(h)
		ElementTable.Element.WATER:
			slow(h)
		ElementTable.Element.EARTH:
			stagger(h)
		ElementTable.Element.AIR:
			chain(h)
	var md := ElementSkillMods.of_hit(h)
	mark(h.collider as Enemy, h.element, md)
	if h.element == ElementTable.Element.AIR and int(ElementSkillMods.value(md, "chain_jumps")) > 0:
		chain_n(h, int(ElementSkillMods.value(md, "chain_jumps")), _chain_range(md), _chain_fraction(md))
	if h.spawn != null and h.spawn.chain_targets > 0:  # step 138: Sigil Sauer full charge
		chain_n(h, h.spawn.chain_targets, h.spawn.chain_range, h.spawn.chain_fraction)
	Capstones.on_hit(h)  # step 148


## Step 145/147: weak-point and conditional bonuses on a bolt with element-skill mods:
## vs_status_pct (target has the element's status), mark_pct (target has the element's mark).
static func apply_skill_hit(h: SpellBolts.Hit, weak_point: bool, target: Object) -> void:
	var md := ElementSkillMods.of_hit(h)
	if md.is_empty():
		return
	if weak_point and md.has("weakpoint_pct"):
		h.result.amount *= ElementSkillMods.mult(md, "weakpoint_pct")
	h.result.amount *= conditional_mult(md, h.element, target as Enemy)


## Step 147: the conditional damage multiplier of `md` against `e` (1.0 without a match).
static func conditional_mult(md: Dictionary, element: int, e: Enemy) -> float:
	if e == null:
		return 1.0
	var k := 1.0
	if md.has("vs_status_pct") and e.has_status_of(element):
		k *= ElementSkillMods.mult(md, "vs_status_pct")
	if md.has("mark_pct") and e.has_mark_of(element):
		k *= ElementSkillMods.mult(md, "mark_pct")
	return k


## Step 147: apply the tree's mark (Water: Soaked, others: Hex) for mark_seconds.
static func mark(e: Enemy, element: int, md: Dictionary) -> void:
	var secs := ElementSkillMods.value(md, "mark_seconds")
	if e == null or secs <= 0.0 or not e.alive():
		return
	if element == ElementTable.Element.WATER:
		e.soaked_left = maxf(e.soaked_left, secs)
	else:
		e.hex_left = maxf(e.hex_left, secs)


## Step 147 (Tremor, Conductive): status strength x(1 + vs_mark_status_pct) on a Soaked enemy.
static func soaked_mult(md: Dictionary, e: Enemy) -> float:
	if e == null or e.soaked_left <= 0.0:
		return 1.0
	return ElementSkillMods.mult(md, "vs_mark_status_pct")


static func _chain_range(md: Dictionary) -> float:
	return CHAIN_RANGE + ElementSkillMods.value(md, "chain_range")


static func _chain_fraction(md: Dictionary) -> float:
	return CHAIN_FRACTION * ElementSkillMods.mult(md, "status_pct")


static func light_heal_amount(dmg: float) -> float:
	return maxf(LIGHT_HEAL_MIN, LIGHT_HEAL_FRACTION * dmg)


static func light(h: SpellBolts.Hit) -> void:
	var p := h.source as Player
	if p == null or not is_instance_valid(p) or not p.alive() or p.health == null:
		return
	var before := p.health.value
	p.health.heal(light_heal_amount(h.result.amount) * ElementSkillMods.mult(ElementSkillMods.of_hit(h), "heal_pct"))
	var gained := p.health.value - before
	light_heals += 1
	if gained > 0.0:
		GameEvents.bus().player_healed.emit(p, gained)
	var s := summon_light(p)
	if s != null:
		s.lifetime += ElementSkillMods.value(ElementSkillMods.of_hit(h), "status_seconds")


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


## Dark: chance = DARK_BASE_CHANCE + bonus (capped at DARK_MAX_CHANCE) to corrupt a
## non-boss brute into an ally for DARK_SECONDS. `dark_roll` (tests) returns the 0..1 roll.
## A co-op client's puppet never converts locally: the host rolls (CoopWorld "hit").
static func dark(h: SpellBolts.Hit) -> bool:
	var e := h.collider as Enemy
	if e == null or e.hold_death:
		return false
	return try_corrupt(e, h.dark_bonus, ElementSkillMods.value(ElementSkillMods.of_hit(h), "status_seconds"))


static func dark_chance(bonus: float) -> float:
	return clampf(DARK_BASE_CHANCE + maxf(0.0, bonus), 0.0, DARK_MAX_CHANCE)


static func try_corrupt(e: Enemy, bonus: float, extra_seconds := 0.0) -> bool:
	if e == null or not e.alive() or e.is_boss() or not (e is Gnawer) or e.is_ally():
		return false
	var roll := float(dark_roll.call()) if dark_roll.is_valid() else randf()
	if force_convert:
		force_convert = false
		roll = 0.0
	if roll >= dark_chance(bonus):
		return false
	if e.corrupt(DARK_SECONDS + extra_seconds):
		corruptions += 1
		return true
	return false


static func _scale(h: SpellBolts.Hit) -> float:
	return 1.0 - Damage.clamp_resist(h.result.resist)


static func burn(h: SpellBolts.Hit) -> void:
	var e := h.collider as Enemy
	if e == null or not e.alive():
		return
	var md := ElementSkillMods.of_hit(h)
	var secs := (BURN_SECONDS + ElementSkillMods.value(md, "status_seconds")) * _scale(h)
	if secs <= 0.0:
		return
	var frac := minf(
		ElementSkillMods.BURN_FRACTION_MAX, BURN_FRACTION + ElementSkillMods.value(md, "status_pct") / 100.0
	)
	frac *= ElementSkillMods.mult(md, "status_damage_pct")
	e.burn_dps = maxf(e.burn_dps if e.burn_left > 0.0 else 0.0, frac * h.result.amount / secs)
	e.burn_left = maxf(e.burn_left, secs)


static func slow(h: SpellBolts.Hit) -> void:
	var e := h.collider as Enemy
	if e == null or not e.alive():
		return
	var md := ElementSkillMods.of_hit(h)
	e.slow_factor = maxf(ElementSkillMods.SLOW_FLOOR, SLOW_FACTOR - ElementSkillMods.value(md, "status_pct") / 100.0)
	e.slow_left = maxf(e.slow_left, (SLOW_SECONDS + ElementSkillMods.value(md, "status_seconds")) * _scale(h))


static func stagger(h: SpellBolts.Hit) -> void:
	var e := h.collider as Enemy
	if e == null or not e.alive():
		return
	var md := ElementSkillMods.of_hit(h)
	var secs := (STAGGER_SECONDS + ElementSkillMods.value(md, "status_seconds")) * soaked_mult(md, e)
	e.stagger_left = maxf(e.stagger_left, secs * _scale(h))


## Returns the enemy the bolt jumped to (null = none in range).
static func chain(h: SpellBolts.Hit) -> Enemy:
	var src := h.collider as Enemy
	if src == null:
		return null
	var md := ElementSkillMods.of_hit(h)
	return chain_from(
		src, _chain_fraction(md) * soaked_mult(md, src) * h.damage, ElementTable.Element.AIR, _chain_range(md), []
	)


## Step 138 (Sigil Sauer): up to `n` jumps, each from the last enemy struck to the nearest
## new one within `range_m`, for `fraction` x the bolt's damage in the bolt's element.
static func chain_n(h: SpellBolts.Hit, n: int, range_m: float, fraction: float) -> int:
	var src := h.collider as Enemy
	var done := 0
	var seen: Array = [src]
	while src != null and done < n:
		src = chain_from(src, fraction * h.damage, h.element, range_m, seen)
		if src != null:
			seen.append(src)
			done += 1
	return done


## One jump from `src` to the nearest live hostile enemy within `range_m` not in `skip`.
static func chain_from(src: Enemy, dmg: float, element: ElementTable.Element, range_m: float, skip: Array) -> Enemy:
	if src == null or not src.is_inside_tree():
		return null
	var best: Enemy = null
	var best_d := range_m
	for n in src.get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or e == src or not e.alive() or e.is_ally() or skip.has(e):
			continue
		var d := e.global_position.distance_to(src.global_position)
		if d <= best_d:
			best_d = d
			best = e
	if best == null or best.damage_target == null:
		return null
	var wp := best.damage_target.weak_point
	best.damage_target.weak_point = false  # a jump never crits
	var r := Damage.resolve_hit(dmg, element, best.damage_target)
	best.damage_target.weak_point = wp
	_hurt(best, r.amount, element)
	StatusFX.chain_arc(src.get_parent(), src.global_position + Vector3.UP, best.global_position + Vector3.UP)
	chains += 1
	return best


## Damage outside a bolt (chain jumps, blasts); a co-op client's puppet is also queued in
## puppet_hits so CoopWorld can tell the host (step 142).
static func _hurt(e: Enemy, amount: float, element: ElementTable.Element) -> void:
	if e.hold_death:
		puppet_hits.append([e, amount, element])
	e.apply_damage(amount, element)


## Step 138 (Moss & Berg boulders, Hexler's cursed orb): every other live hostile enemy within
## blast_radius of the impact takes blast_fraction x the bolt's damage, x1 at the centre down
## to blast_falloff at the edge, resolved against its own resist (never a crit). Earth blasts
## stagger, orbs roll Dark once per enemy. Allies and the player are never hurt. Returns the
## number of enemies struck.
static func blast(h: SpellBolts.Hit, tree: SceneTree) -> int:
	var s := h.spawn
	if s == null or s.blast_radius <= 0.0 or tree == null:
		return 0
	var n := 0
	for node in tree.get_nodes_in_group(Enemy.GROUP):
		var e := node as Enemy
		if e == null or e == h.collider or not e.alive() or e.is_ally() or e.damage_target == null:
			continue
		var d := e.global_position.distance_to(h.point)
		if d > s.blast_radius:
			continue
		var k := lerpf(1.0, s.blast_falloff, clampf(d / s.blast_radius, 0.0, 1.0))
		var wp := e.damage_target.weak_point
		e.damage_target.weak_point = false
		var r := Damage.resolve_hit(s.blast_fraction * h.damage * k, h.element, e.damage_target)
		e.damage_target.weak_point = wp
		_hurt(e, r.amount, h.element)
		n += 1
		if h.element == ElementTable.Element.EARTH and e.alive():
			e.stagger_left = maxf(e.stagger_left, STAGGER_SECONDS * (1.0 - Damage.clamp_resist(r.resist)))
		if s.is_orb:
			try_corrupt(e, h.dark_bonus)
	n += Capstones.fault_line(h, tree)  # step 148
	blasts += n
	if n > 0 or s.is_orb:
		StatusFX.blast(tree.current_scene, h.point, s.blast_radius, h.element)
	return n


## Step 139 (Hexler & Koch): a weak-point hit gets x crit_mult on top of the weak-point x2;
## any other hit crits on a crit_chance roll for x crit_mult. Updates h.result.
static func apply_crit(h: SpellBolts.Hit, weak_point: bool) -> void:
	var s := h.spawn
	if h.result == null or s == null or s.crit_mult <= 1.0:
		return
	if not weak_point:
		var roll := float(crit_roll.call()) if crit_roll.is_valid() else randf()
		if roll >= s.crit_chance:
			return
	h.result.crit *= s.crit_mult
	h.result.amount *= s.crit_mult
	crits += 1
