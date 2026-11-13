class_name Interaction
extends RefCounted
## Look-based interaction (t60u): the player interacts with what the camera centre points at,
## not whatever happens to be nearest the feet. Every interactable (NPC, gate, waystone,
## station, chest, lever) registers into GROUP; item pickups (LootPickup.GROUP) compete too so
## one F press only ever has one target. Pick rule, from the plain eye along look_direction():
##  * within RANGE (+ the target's radius) of the eye, in front of it;
##  * inside CONE_DEG of the look ray, or the ray passes within the target's radius
##    (+ SPHERE) of its aim point (a forgiving sphere-cast for big things like a station);
##  * best = smallest angle off the ray (inside-the-sphere hits count as on-ray), ties by distance.
## Distance math over the groups (no physics query): deterministic in headless tests.

const GROUP := &"interactables"
const RANGE := 4.0
const CONE_DEG := 20.0
const SPHERE := 0.35
const META_HEIGHT := &"interact_height"
const META_RADIUS := &"interact_radius"


static func register(n: Node3D, height := 1.0, radius := 0.5) -> void:
	n.set_meta(META_HEIGHT, height)
	n.set_meta(META_RADIUS, radius)
	n.add_to_group(GROUP)


static func aim_point(n: Node3D) -> Vector3:
	if n is LootPickup:
		return n.global_position + Vector3(0, LootPickup.GEM_SIZE * 0.5, 0)
	return n.global_position + Vector3(0, float(n.get_meta(META_HEIGHT, 1.0)), 0)


## Angle-ish score of `n` for player `p` (lower is better), or INF when not targetable.
static func score(p: Player, n: Node3D) -> float:
	if n == null or not n.is_inside_tree() or n.is_queued_for_deletion():
		return INF
	if n.has_method("can_interact") and not n.can_interact():
		return INF
	var eye := p.eye_position()
	var dir := p.look_direction().normalized()
	var to := aim_point(n) - eye
	var dist := to.length()
	var pickup := n is LootPickup
	var radius := 0.0 if pickup else float(n.get_meta(META_RADIUS, 0.5))
	var rng := PickupCollector.REACH if pickup else RANGE + radius
	if dist > rng:
		return INF
	if dist < 1e-4:
		return 0.0
	var along := to.dot(dir)
	if along <= 0.0:
		return INF
	var c := along / dist
	var cone := cos(deg_to_rad(PickupCollector.LOOK_CONE_DEG if pickup else CONE_DEG))
	var perp := (to - dir * along).length()
	var in_sphere := not pickup and perp <= radius + SPHERE
	if c < cone and not in_sphere:
		return INF
	return (0.0 if in_sphere else 1.0 - c) + dist * 1e-4


## The one thing the player is looking at. Uncached. Tests call this directly.
static func target(p: Player) -> Node3D:
	if p == null or not p.is_inside_tree():
		return null
	var best: Node3D = null
	var best_s := INF
	var tree := p.get_tree()
	for grp in [GROUP, LootPickup.GROUP]:
		for n in tree.get_nodes_in_group(grp):
			var nd := n as Node3D
			if nd == null or (nd is LootPickup and (nd as LootPickup).drop == null):
				continue
			var s := score(p, nd)
			if s < best_s:
				best_s = s
				best = nd
	return best


## One look query for this physics frame. A later HUD read reuses it.
static func refresh_target(p: Player) -> Node3D:
	if p == null:
		return null
	var blocked := p.input_blocked()
	var found: Node3D = null if blocked else target(p)
	p.look_target = found
	p.look_target_frame = Engine.get_physics_frames()
	p.look_target_dir = p.look_direction()
	p.look_target_eye = p.eye_position()
	p.look_target_blocked = blocked
	return found


static func _cached(p: Player) -> bool:
	return (
		p.look_target_frame == Engine.get_physics_frames()
		and p.look_target_dir.is_equal_approx(p.look_direction())
		and p.look_target_eye.is_equal_approx(p.eye_position())
	)


## Cached look target. A blocked player keeps a cleared cache until the next physics frame.
static func current(p: Player) -> Node3D:
	if p == null:
		return null
	if p.input_blocked():
		p.look_target = null
		p.look_target_blocked = true
		p.look_target_frame = Engine.get_physics_frames()
		return null
	if p.look_target_blocked and p.look_target_frame == Engine.get_physics_frames():
		return null
	if _cached(p):
		return p.look_target
	return refresh_target(p)


static func is_target(p: Player, n: Node3D) -> bool:
	if p == null or n == null or not n.is_inside_tree():
		return false
	# score() rechecks can_interact() at press time. The cache only picks who.
	return current(p) == n and score(p, n) < INF


## The HUD prompt for the looked-at target ("" when none, or a UI is open).
static func prompt(p: Player) -> String:
	if p == null or p.input_blocked():
		if p:
			p.look_target = null
			p.look_target_blocked = true
			p.look_target_frame = Engine.get_physics_frames()
		return ""
	var t := current(p)
	if t and t.has_method("interact_prompt"):
		return String(t.interact_prompt())
	return ""


## Turn `p` to look straight at `n`'s aim point (bots, tests, cinematics).
static func face(p: Player, n: Node3D) -> void:
	var d := aim_point(n) - p.eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	refresh_target(p)
