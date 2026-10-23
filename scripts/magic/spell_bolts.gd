class_name SpellBolts
extends Node3D
## Spell bolts (BUILD_PLAN step 7, port of the archived C++ game/magic/projectile.*, old
## step 17): fast bolts swept as one ray per physics tick.
##
## Each tick a live bolt moves speed x dt along its direction, clipped to what is left of
## its range; that segment is one PhysicsRayQueryParameters3D that excludes the caster's
## own body (the eye ray starts inside its capsule). The closest hit ends the bolt and is
## reported with the exact distance and travel time (ticks flown before + the fraction of
## this tick), so hits land at the right distance however fast the bolt is (no tunnelling).
## A bolt that flies its full range fizzles. Bolts spawned before a tick move in it.
##
## On a hit whose collider has a `damage_target` (Damage.Target, enemies in step 11, the
## player in step 13) the hit is resolved with Damage.resolve_hit(damage, element, target);
## then the collider's take_hit(hit) is called if it has one and `bolt_hit` is emitted.
##
## Tracers: a short element-coloured line (ElementTable colour) behind each live bolt,
## interpolated between physics ticks, plus the last stretch of each impact for 0.2 s;
## nothing is drawn within 0.6 m of the eye (it would fill the view). Step 10: a spawn
## with a visual origin (the viewmodel's cast point) draws its tracer from there instead:
## the drawn point at distance x along the ray is ray(x) + (visual - origin) x
## max(0, 1 - x / CONVERGE), so the tracer leaves the staff tip and merges into the real
## ray (which stays at the eye, where the crosshair is) by CONVERGE m. No SKIP_NEAR then.
##
## Magewar reference (spell_projectile.tscn/.gd, wieldable_staff.gd; reinterpreted, not
## copied): Magewar fires a 0.1 m RigidBody3D sphere with gravity and an 8 s lifespan from
## the staff's CastPoint toward the camera ray's hit; wieldable_range is never used. Ours
## is a straight ray from the eye (hits go where the crosshair points) that fizzles at the
## wieldable's range (the C++ design). The 0.1 m enemy graze sweep comes with enemies.

signal bolt_hit(hit: Hit)

const TAIL := 2.5            ## m of tracer behind the bolt head
const SKIP_NEAR := 0.6       ## m in front of the eye never drawn
const IMPACT_LINGER := 0.2   ## s an impact's tracer stays
const CONVERGE := 8.0        ## m: a visual origin's offset fades out over this (step 10)

## What a cast launches.
class Spawn:
	extends RefCounted
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD          ## normalised by spawn()
	var speed := 30.0                         ## m/s
	var range_m := 50.0                       ## m
	var element: ElementTable.Element = ElementTable.Element.ARCANE
	var damage := 0.0                         ## wieldable damage, resolved on impact
	var exclude: Array[RID] = []              ## never hit (the caster)
	var collision_mask := 0xFFFFFFFF
	var has_visual_origin := false            ## step 10: tracer drawn from visual_origin
	var visual_origin := Vector3.ZERO

class Bolt:
	extends RefCounted
	var id := 0
	var spawn: Spawn
	var position := Vector3.ZERO              ## after the last tick
	var previous := Vector3.ZERO              ## before it (tracer interpolation)
	var travelled := 0.0
	var ticks := 0                            ## ticks flown; -1 = done

class Hit:
	extends RefCounted
	var bolt := 0
	var collider: Object
	var rid := RID()
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	var distance := 0.0                       ## m from the spawn origin
	var time := 0.0                           ## s from spawn
	var tick := 0                             ## 1-based tick of flight it hit in
	var element: ElementTable.Element = ElementTable.Element.ARCANE
	var damage := 0.0                         ## wieldable damage carried by the bolt
	var direction := Vector3.FORWARD
	var result: Damage.Result                 ## set when the collider had a damage_target

class Line:
	extends RefCounted
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var color := Color.WHITE

var elements: ElementTable                    ## tracer colours (default table when null)
var auto_tick := true                         ## false: the owner (tests) calls tick()
var live: Array[Bolt] = []
var spawned := 0
var hits := 0
var fizzled := 0
var last_hits: Array[Hit] = []                ## hits of the last tick

var _impacts: Array = []                      ## [Line, ttl]
var _next_id := 1
var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D

func _ready() -> void:
	# After the Player (default priority 0), so a bolt cast this tick moves this tick.
	process_physics_priority = 100
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Tracers"
	_mesh_instance.mesh = _mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)

func _process(_delta: float) -> void:
	_draw_tracers(Engine.get_physics_interpolation_fraction())

func spawn(s: Spawn) -> int:
	var b := Bolt.new()
	b.id = _next_id
	_next_id += 1
	b.spawn = s
	s.direction = s.direction.normalized() if s.direction.length() > 1e-6 else Vector3.FORWARD
	b.position = s.origin
	b.previous = s.origin
	live.append(b)
	spawned += 1
	return b.id

## One physics tick: sweeps every live bolt, returns this tick's hits (also last_hits).
func tick(dt: float, space: PhysicsDirectSpaceState3D = null) -> Array[Hit]:
	if space == null:
		space = get_world_3d().direct_space_state
	last_hits = []
	for i in range(_impacts.size() - 1, -1, -1):
		_impacts[i][1] -= dt
		if _impacts[i][1] <= 0.0:
			_impacts.remove_at(i)
	for b in live:
		var s := b.spawn
		var seg := minf(s.speed * dt, s.range_m - b.travelled)
		b.previous = b.position
		if seg <= 0.0:
			fizzled += 1
			b.ticks = -1
			continue
		var from := s.origin + s.direction * b.travelled
		var to := from + s.direction * seg
		var q := PhysicsRayQueryParameters3D.create(from, to, s.collision_mask, s.exclude)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			var h := Hit.new()
			var p: Vector3 = r["position"]
			var frac := clampf(from.distance_to(p) / seg, 0.0, 1.0)
			h.bolt = b.id
			h.collider = r["collider"]
			h.rid = r["rid"]
			h.point = p
			h.normal = r["normal"]
			h.distance = b.travelled + frac * seg
			h.time = b.ticks * dt + frac * seg / s.speed
			h.tick = b.ticks + 1
			h.element = s.element
			h.damage = s.damage
			h.direction = s.direction
			_resolve(h)
			last_hits.append(h)
			hits += 1
			var l := _tracer(s, h.distance)
			if l != null:
				_impacts.append([l, IMPACT_LINGER])
			b.ticks = -1
			continue
		b.travelled += seg
		b.position = to
		b.ticks += 1
		if b.travelled >= s.range_m - 1e-4:
			fizzled += 1
			b.ticks = -1
	live = live.filter(func(x: Bolt) -> bool: return x.ticks >= 0)
	for h in last_hits:
		if is_instance_valid(h.collider) and h.collider.has_method(&"take_hit"):
			h.collider.call(&"take_hit", h)
		bolt_hit.emit(h)
	return last_hits

func _resolve(h: Hit) -> void:
	if not is_instance_valid(h.collider):
		return
	var t = h.collider.get(&"damage_target")
	if t is Damage.Target:
		h.result = Damage.resolve_hit(h.damage, h.element, t)

func _color(e: ElementTable.Element) -> Color:
	var t := elements if elements != null else ElementTable.load_default()
	return t.color(e) if t != null else Color.WHITE

## Where the tracer of `s` is drawn at distance x along its ray (step 10 visual origin).
static func drawn_point(s: Spawn, x: float) -> Vector3:
	var p := s.origin + s.direction * x
	if s.has_visual_origin:
		p += (s.visual_origin - s.origin) * maxf(0.0, 1.0 - x / CONVERGE)
	return p

## Tracer from max(SKIP_NEAR, d - TAIL) (0 with a visual origin) to d metres along a bolt's
## ray; null when empty.
func _tracer(s: Spawn, d: float) -> Line:
	var from := maxf(0.0 if s.has_visual_origin else SKIP_NEAR, d - TAIL)
	if d <= from:
		return null
	var l := Line.new()
	l.a = drawn_point(s, from)
	l.b = drawn_point(s, d)
	l.color = _color(s.element)
	return l

## Live bolt tails (head interpolated by alpha between the last two ticks) + lingering impacts.
func tracer_lines(alpha: float) -> Array[Line]:
	var out: Array[Line] = []
	for b in live:
		var d_prev := b.previous.distance_to(b.spawn.origin)
		var d := d_prev + (b.travelled - d_prev) * clampf(alpha, 0.0, 1.0)
		var l := _tracer(b.spawn, d)
		if l != null:
			out.append(l)
	for i in _impacts:
		out.append(i[0])
	return out

func _draw_tracers(alpha: float) -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	var lines := tracer_lines(alpha)
	if lines.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in lines:
		_mesh.surface_set_color(l.color)
		_mesh.surface_add_vertex(to_local(l.a))
		_mesh.surface_set_color(l.color)
		_mesh.surface_add_vertex(to_local(l.b))
	_mesh.surface_end()
