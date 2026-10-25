class_name StatusFX
extends RefCounted
## FX F3 (step 129): status, hit and death visuals for Enemy. All statics driven from
## Enemy.tick / _die and MagicEffects.chain, so they follow the replicated enemy state and
## every co-op peer sees them.
##
## - Burn: CPU flame particles from the body box, orange (Fire colour).
## - Slow: drifting frost flakes around the body.
## - Stagger: three spinning star sprites over the head.
## - Chain: a jagged Air-coloured arc between the two enemies for ARC_TIME.
## - Death: a dissolve shell (shaders/fx/dissolve.gdshader) the size of the body plus a
##   puff, left in the enemy's parent for DEATH_TIME (the enemy itself hides at once).
## Hit flash stays the per-enemy albedo flash (Enemy.FLASH_TIME); damage numbers are
## DamageNumbers (Label3D with outline).

const DISSOLVE := preload("res://shaders/fx/dissolve.gdshader")
const FIRE := Color(1.0, 0.35, 0.08)
const FROST := Color(0.55, 0.8, 1.0)
const AIR := Color(0.8, 0.95, 1.0)
const STAR := Color(1.0, 0.95, 0.5)
const ARC_TIME := 0.18
const DEATH_TIME := 0.9


## Turn each status child on/off for `e` (names: Burn, Frost, Stars).
static func sync(e: Node3D, size: Vector3, burning: bool, slowed: bool, staggered: bool) -> void:
	_toggle(e, "Burn", burning, func() -> Node3D: return _flames(size))
	_toggle(e, "Frost", slowed, func() -> Node3D: return _frost(size))
	_toggle(e, "Stars", staggered, func() -> Node3D: return _stars(size))
	var s := e.get_node_or_null(^"Stars") as Node3D
	if s:
		s.rotate_y(0.12)


static func _toggle(e: Node3D, n: String, on: bool, make: Callable) -> void:
	var c := e.get_node_or_null(NodePath(n)) as Node3D
	if on and c == null:
		c = make.call()
		c.name = n
		e.add_child(c)
	elif not on and c != null:
		c.queue_free()


static func _particles(amount: int, life: float, c: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	var g := Gradient.new()
	g.set_color(0, Color(c.lerp(Color.WHITE, 0.3), 0.9))
	g.set_color(1, Color(c, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = SpellFX.soft_dot()
	q.material = m
	p.mesh = q
	return p


static func _flames(size: Vector3) -> Node3D:
	var p := _particles(28, 0.7, FIRE, 0.3)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = size * Vector3(0.58, 0.45, 0.58)
	p.position = Vector3(0, size.y * 0.45, 0)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	return p


static func _frost(size: Vector3) -> Node3D:
	var p := _particles(22, 1.4, FROST, 0.13)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = size * Vector3(0.75, 0.5, 0.75)
	p.position = Vector3(0, size.y * 0.5, 0)
	p.gravity = Vector3(0, -0.4, 0)
	p.initial_velocity_max = 0.2
	return p


static func _stars(size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, size.y + 0.25, 0)
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.16
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = STAR
	m.albedo_texture = SpellFX.soft_dot()
	q.material = m
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * i / 3.0
		mi.position = Vector3(cos(a), 0, sin(a)) * maxf(0.25, size.x * 0.5)
		root.add_child(mi)
	return root


## Air chain: jagged arc from a to b under `parent`, freed after ARC_TIME.
static func chain_arc(parent: Node, a: Vector3, b: Vector3) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segs := 8
	for i in segs + 1:
		var t := float(i) / segs
		var j := Vector3.ZERO if i == 0 or i == segs else Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.35
		im.surface_set_color(AIR)
		im.surface_add_vertex(a.lerp(b, t) + j)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.name = "ChainArc"
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	parent.add_child(mi)
	mi.get_tree().create_timer(ARC_TIME).timeout.connect(mi.queue_free)
	return mi


## Death: dissolve shell + puff at `at` under `parent`; frees itself after DEATH_TIME.
static func death(parent: Node, at: Vector3, size: Vector3, base: Color, edge: Color) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var root := Node3D.new()
	root.name = "DeathFX"
	root.top_level = true
	parent.add_child(root)
	root.global_position = at
	var shell := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = maxf(0.15, minf(size.x, size.z) * 0.5)
	cap.height = maxf(cap.radius * 2.0, size.y)
	cap.radial_segments = 10
	cap.rings = 3
	shell.mesh = cap
	shell.position = Vector3(0, size.y * 0.5, 0)
	var sm := ShaderMaterial.new()
	sm.shader = DISSOLVE
	sm.set_shader_parameter(&"base_color", base)
	sm.set_shader_parameter(&"edge_color", edge)
	shell.material_override = sm
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	var puff := _particles(14, 0.6, edge, 0.25)
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.position = shell.position
	puff.spread = 180.0
	puff.initial_velocity_max = 1.5
	puff.emitting = true
	root.add_child(puff)
	var tw := root.create_tween()
	tw.tween_method(func(v: float) -> void: sm.set_shader_parameter(&"progress", v), 0.0, 1.0, DEATH_TIME * 0.85)
	tw.tween_interval(DEATH_TIME * 0.15)
	tw.tween_callback(root.queue_free)
	return root
