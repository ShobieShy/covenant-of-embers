class_name ActionSkill
extends RefCounted
## 0.8.6 action skill. One 30s cooldown. The verb is the element tree with the most
## points spent. Ties break in element order: Arcane, Fire, Water, Earth, Air, Light,
## Dark. Light summons, Dark converts, Fire and Earth stagger, and Air, Water, and
## Arcane chain. No roll: convert is forced, so a co-op host and joiner cannot disagree.

const COOLDOWN := 30.0
const RANGE := 12.0
const CHAIN_DAMAGE := 4.0
const VERBS := {
	"arcane": "chain",
	"fire": "stagger",
	"water": "chain",
	"earth": "stagger",
	"air": "chain",
	"light": "summon",
	"dark": "convert",
}

var left := 0.0
var casts := 0
var last_verb := ""
var refused_downed := 0
var refused_cooldown := 0


static func verb_for(skills: Skills) -> String:
	var best := "arcane"
	var pts := -1
	for id in ElementTable.IDS:
		var n := skills.el_spent(id) if skills != null else 0
		if n > pts:
			pts = n
			best = id
	return String(VERBS.get(best, "chain"))


static func world_of(p: Node) -> CoopWorld:
	if p == null or not p.is_inside_tree():
		return null
	for n in p.get_tree().get_nodes_in_group(&"coop_world"):
		var w := n as CoopWorld
		if w != null and w.player == p and w.session != null and w.session.state == NetSession.State.IN_GAME:
			return w
	return null


func tick(p: Player, input: PlayerInput, dt: float) -> void:
	left = maxf(0.0, left - dt)
	if input == null or not input.was_pressed(&"action_skill"):
		return
	if p.downed or not p.alive():
		refused_downed += 1
		return
	if left > 0.0:
		refused_cooldown += 1
		return
	var verb := verb_for(p.skills)
	var world := world_of(p)
	if world != null and not world.host:
		world.send_action_skill(verb, p.global_position)
		if verb == "summon":
			var shown := MagicEffects.summon_light(p)
			if shown != null:
				shown.auto_tick = false
		_spend(verb)
		return
	if resolve(p.get_parent(), verb, p.global_position, p):
		_spend(verb)


func _spend(verb: String) -> void:
	left = COOLDOWN
	casts += 1
	last_verb = verb


## Applies `verb` to enemies under `scope`. `follow` is the summon anchor (the caster,
## or a remote player on the host). Summon and convert do not move anybody.
static func resolve(scope: Node, verb: String, at: Vector3, follow: Node3D) -> bool:
	if scope == null:
		return false
	match verb:
		"summon":
			return _summon(scope, follow, at)
		"convert":
			return _convert(scope, at)
		"stagger":
			return _stagger(scope, at)
		_:
			return _chain(scope, at)


static func _summon(scope: Node, follow: Node3D, at: Vector3) -> bool:
	if follow is Player:
		return MagicEffects.summon_light(follow as Player) != null or LightSummon.of(follow) != null
	var parent := follow.get_parent() if follow != null and follow.get_parent() != null else scope
	var s := LightSummon.new()
	s.follow = follow if follow != null else parent
	s.auto_tick = follow != null
	parent.add_child(s)
	s.global_position = (follow.global_position if follow != null else at) + LightSummon.OFFSET
	return true


static func _convert(scope: Node, at: Vector3) -> bool:
	var e := _nearest(scope, at, true)
	if e == null:
		return false
	MagicEffects.force_convert = true
	var ok := MagicEffects.try_corrupt(e, 0.0)
	MagicEffects.force_convert = false
	return ok


static func _stagger(scope: Node, at: Vector3) -> bool:
	var e := _nearest(scope, at, false)
	if e == null:
		return false
	e.stagger_left = maxf(e.stagger_left, MagicEffects.STAGGER_SECONDS)
	return e.stagger_left > 0.0


static func _chain(scope: Node, at: Vector3) -> bool:
	var list := _in_range(scope, at, false)
	if list.is_empty():
		return false
	var src: Enemy = list[0]
	src.apply_damage(CHAIN_DAMAGE, ElementTable.Element.AIR)
	if list.size() > 1:
		MagicEffects.chain_from(src, CHAIN_DAMAGE, ElementTable.Element.AIR, RANGE, [src])
	return true


static func _nearest(scope: Node, at: Vector3, gnawers: bool) -> Enemy:
	var list := _in_range(scope, at, gnawers)
	return list[0] if not list.is_empty() else null


static func _in_range(scope: Node, at: Vector3, gnawers: bool) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if scope == null or not scope.is_inside_tree():
		return out
	var best: Enemy = null
	var best_d := RANGE
	var second: Enemy = null
	var second_d := RANGE
	for n in scope.get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or not e.alive() or e.is_ally() or not scope.is_ancestor_of(e):
			continue
		if gnawers and not (e is Gnawer):
			continue
		var d := e.global_position.distance_to(at)
		if d > RANGE:
			continue
		if d <= best_d:
			second = best
			second_d = best_d
			best = e
			best_d = d
		elif d <= second_d:
			second = e
			second_d = d
	if best != null:
		out.append(best)
	if second != null:
		out.append(second)
	return out
