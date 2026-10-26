class_name Capstones
extends RefCounted
## Phase V step 148 (docs/ELEMENT_TREES_PLAN.md section 4): the 7 exclusive element capstones.
## A bolt carries its tree's mods (spawn.mods); "capstone" > 0 means its element's capstone
## is owned. Hit capstones (Convergence, Tidal Hold, Eclipse) run from MagicEffects.on_hit,
## Fault Line from MagicEffects.blast, and the brand capstones from their FireMode
## (Backdraft: HeatMode vent; Cyclone: SpinMode; Dawnchorus: BurstMode).

const CONVERGENCE_EVERY := 5
const BACKDRAFT_HEAT := 0.8
const BACKDRAFT_RADIUS := 4.0
const BACKDRAFT_MULT := 1.2
const TIDAL_SECONDS := 1.2
const TIDAL_BOSS_SLOW := 0.4
const FAULT_EVERY := 4
const FAULT_SPLITS := 3
const FAULT_FRACTION := 0.4
const CYCLONE_FULL_S := 2.0
const CYCLONE_RANGE := 6.0
const CYCLONE_FRACTION := 0.35
const CYCLONE_COOLDOWN := 6.0
const DAWN_RADIUS := 6.0
const DAWN_FRACTION := 0.15
const DAWN_COOLDOWN := 8.0
const ECLIPSE_HEALTH := 0.3
const ECLIPSE_COOLDOWN := 20.0
const META_CONV := &"conv_hits"

static var procs := {}  ## capstone id -> times it fired (tests, playtest PASS line)
static var clock := Callable()  ## tests: func() -> float seconds
static var _eclipse_ready := -1.0
static var _fault_counts := {}  ## source instance id -> boulders


static func has(md: Dictionary) -> bool:
	return ElementSkillMods.value(md, "capstone") > 0.0


static func now() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_ticks_msec() / 1000.0


static func count(id: String) -> int:
	return int(procs.get(id, 0))


static func reset() -> void:
	procs = {}
	_eclipse_ready = -1.0
	_fault_counts = {}


static func _fired(id: String) -> void:
	procs[id] = count(id) + 1


## Called by MagicEffects.on_hit after the element's own status.
static func on_hit(h: SpellBolts.Hit) -> void:
	var md := ElementSkillMods.of_hit(h)
	var e := h.collider as Enemy
	if not has(md) or e == null or not e.alive():
		return
	match h.element:
		ElementTable.Element.ARCANE:
			convergence(e, h, md)
		ElementTable.Element.WATER:
			if h.spawn != null and h.spawn.chain_targets > 0:
				tidal_hold(e)
		ElementTable.Element.DARK:
			eclipse(e, h)


## Arcane: every 5th Arcane hit on one target applies the status of each tree with points.
static func convergence(e: Enemy, h: SpellBolts.Hit, md: Dictionary) -> bool:
	var n := int(e.get_meta(META_CONV, 0)) + 1
	e.set_meta(META_CONV, n)
	if n % CONVERGENCE_EVERY != 0:
		return false
	for el in md.get("conv", []):
		match int(el):
			ElementTable.Element.FIRE:
				e.burn_dps = maxf(e.burn_dps, MagicEffects.BURN_FRACTION * h.damage / MagicEffects.BURN_SECONDS)
				e.burn_left = maxf(e.burn_left, MagicEffects.BURN_SECONDS)
			ElementTable.Element.WATER:
				e.slow_factor = minf(e.slow_factor if e.slow_left > 0.0 else 1.0, MagicEffects.SLOW_FACTOR)
				e.slow_left = maxf(e.slow_left, MagicEffects.SLOW_SECONDS)
			ElementTable.Element.EARTH:
				e.stagger_left = maxf(e.stagger_left, MagicEffects.STAGGER_SECONDS)
			ElementTable.Element.AIR:
				MagicEffects.chain_from(
					e, MagicEffects.CHAIN_FRACTION * h.damage, ElementTable.Element.AIR, MagicEffects.CHAIN_RANGE, []
				)
			ElementTable.Element.DARK:
				e.hex_left = maxf(e.hex_left, 3.0)
				MagicEffects.try_corrupt(e, h.dark_bonus)
			ElementTable.Element.LIGHT:
				var p := h.spawn.source as Player if h.spawn != null else null
				MagicEffects.heal_player(p, MagicEffects.light_heal_amount(h.damage))
			ElementTable.Element.ARCANE:
				e.hex_left = maxf(e.hex_left, 3.0)
	_fired("convergence")
	return true


## Water: a full Sigil charge freezes its first target (bosses: slowed x0.4 instead).
static func tidal_hold(e: Enemy) -> void:
	if e.is_boss():
		e.slow_factor = minf(e.slow_factor if e.slow_left > 0.0 else 1.0, TIDAL_BOSS_SLOW)
		e.slow_left = maxf(e.slow_left, TIDAL_SECONDS)
	else:
		e.stagger_left = maxf(e.stagger_left, TIDAL_SECONDS)
	_fired("tidal_hold")


## Dark: a crit on a Hexed enemy under 30% health turns it, ignoring the 15% cap, at most
## once every 20 s (normal turn rules otherwise: no bosses, brutes only).
static func eclipse(e: Enemy, h: SpellBolts.Hit) -> bool:
	if h.result == null or h.result.crit <= 1.0 or e.hex_left <= 0.0 or e.is_boss():
		return false
	if e.health >= ECLIPSE_HEALTH * e.max_health() or now() < _eclipse_ready:
		return false
	MagicEffects.force_convert = true
	var ok := MagicEffects.try_corrupt(e, 0.0)
	MagicEffects.force_convert = false
	if ok:
		_eclipse_ready = now() + ECLIPSE_COOLDOWN
		_fired("eclipse")
	return ok


## Earth: every 4th boulder (per caster) splits into 3 on impact, each 40% of the bolt in a
## smaller blast around the impact, each able to stagger. Returns enemies struck.
static func fault_line(h: SpellBolts.Hit, tree: SceneTree) -> int:
	var s := h.spawn
	if s == null or h.element != ElementTable.Element.EARTH or not has(s.mods) or tree == null:
		return 0
	var key := s.source.get_instance_id() if s.source != null else 0
	_fault_counts[key] = int(_fault_counts.get(key, 0)) + 1
	if int(_fault_counts[key]) % FAULT_EVERY != 0:
		return 0
	var r := maxf(2.0, s.blast_radius * 0.6)
	var n := 0
	for i in FAULT_SPLITS:
		var a := TAU * float(i) / FAULT_SPLITS
		var at := h.point + Vector3(cos(a), 0.0, sin(a)) * r * 0.5
		n += area(tree, at, r, FAULT_FRACTION * h.damage, ElementTable.Element.EARTH, true)
	_fired("fault_line")
	return n


## Fire: venting at >= 80% heat bursts 4 m around the caster for 120% of one shot and resets
## the burn on everything it hits.
static func backdraft(c: Caster, heat: float) -> int:
	if c == null or heat < BACKDRAFT_HEAT or c.owner_node == null or not c.owner_node.is_inside_tree():
		return 0
	var dmg := c.wieldable.damage() * BACKDRAFT_MULT if c.wieldable != null else 0.0
	var tree := c.owner_node.get_tree()
	var n := area(tree, c.owner_node.global_position, BACKDRAFT_RADIUS, dmg, ElementTable.Element.FIRE, false)
	for node in tree.get_nodes_in_group(Enemy.GROUP):
		var e := node as Enemy
		if e != null and e.alive() and not e.is_ally():
			if e.global_position.distance_to(c.owner_node.global_position) <= BACKDRAFT_RADIUS:
				e.burn_dps = maxf(e.burn_dps, MagicEffects.BURN_FRACTION * dmg / MagicEffects.BURN_SECONDS)
				e.burn_left = MagicEffects.BURN_SECONDS
	_fired("backdraft")
	return n


## Light: heals every player within 6 m of the caster (self included) for 15% of max health.
static func dawnchorus(c: Caster) -> int:
	if c == null or c.owner_node == null or not c.owner_node.is_inside_tree():
		return 0
	var at := c.owner_node.global_position
	var n := 0
	for node in c.owner_node.get_tree().get_nodes_in_group(Player.GROUP):
		var p := node as Player
		if p != null and p.health != null and p.global_position.distance_to(at) <= DAWN_RADIUS:
			MagicEffects.heal_player(p, DAWN_FRACTION * p.health.max_value())
			n += 1
	for node in c.owner_node.get_tree().get_nodes_in_group(RemotePlayer.GROUP):
		var rp := node as RemotePlayer
		if rp != null and rp.global_position.distance_to(at) <= DAWN_RADIUS:
			rp.light_healed.emit(DAWN_FRACTION * 100.0)  # co-op "heal": ~15% of a base 100 HP pool
			n += 1
	_fired("dawnchorus")
	return n


## Damage `amount` (resolved per enemy, never a crit) to live hostiles within `radius` of `at`.
static func area(tree: SceneTree, at: Vector3, radius: float, amount: float, el: int, stagger: bool) -> int:
	var n := 0
	for node in tree.get_nodes_in_group(Enemy.GROUP):
		var e := node as Enemy
		if e == null or not e.alive() or e.is_ally() or e.damage_target == null:
			continue
		if e.global_position.distance_to(at) > radius:
			continue
		var wp := e.damage_target.weak_point
		e.damage_target.weak_point = false
		var r := Damage.resolve_hit(amount, el, e.damage_target)
		e.damage_target.weak_point = wp
		MagicEffects._hurt(e, r.amount, el)
		if stagger and e.alive():
			e.stagger_left = maxf(e.stagger_left, MagicEffects.STAGGER_SECONDS)
		n += 1
	return n
