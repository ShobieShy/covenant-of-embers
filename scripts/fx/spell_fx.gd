class_name SpellFX
extends Node3D
## FX F2 (step 128): spell visuals on top of SpellBolts' tracers.
##
## - Bolt heads: one pooled low-poly sphere per live bolt with the shared bolt shader
##   (shaders/fx/bolt.gdshader), element colour as an instance uniform (one material).
## - Impacts: a one-shot CPUParticles3D burst per element (fire embers rise, water splashes
##   fall, earth dust, air streaks, light sparks, dark smoke), freed after its lifetime.
##   CPU particles so the Compatibility/Low preset gets them too; capped at MAX_BURSTS.
## - Light heal: green-gold motes rising around a healed player (EventBus.player_healed).
## - Dark conversion aura: a swirl ring under a corrupted enemy (Enemy.tick calls
##   sync_aura), fading over the last AURA_FADE seconds. It follows corrupted_left, which
##   co-op replicates, so every peer sees it.

const BOLT_SHADER := preload("res://shaders/fx/bolt.gdshader")
const AURA_SHADER := preload("res://shaders/fx/dark_aura.gdshader")
const HEAD_RADIUS := 0.11
const MAX_BURSTS := 24
const AURA_FADE := 3.0
const HEAL_COLOR := Color(0.55, 1.0, 0.45)
const LIGHT_GOLD := Color(1.0, 0.92, 0.55)

## Per element: [amount, lifetime, speed, gravity_y, size, spread]
const BURST := {
	ElementTable.Element.FIRE: [18, 0.55, 3.0, 2.5, 0.06, 70.0],
	ElementTable.Element.WATER: [16, 0.5, 3.5, -9.0, 0.05, 60.0],
	ElementTable.Element.EARTH: [12, 0.7, 2.0, -6.0, 0.09, 80.0],
	ElementTable.Element.AIR: [10, 0.3, 6.0, 0.0, 0.04, 25.0],
	ElementTable.Element.LIGHT: [16, 0.45, 2.5, 0.5, 0.05, 180.0],
	ElementTable.Element.DARK: [10, 0.8, 1.0, 0.8, 0.12, 120.0],
}

static var _head_mesh: SphereMesh
static var _head_mat: ShaderMaterial
static var _aura_mesh: PlaneMesh
static var _soft: GradientTexture2D

var elements: ElementTable
var bursts := 0  ## alive bursts (tests)
var _heads: Array[MeshInstance3D] = []


func _ready() -> void:
	var bus := GameEvents.bus()
	if bus and not bus.player_healed.is_connected(_on_healed):
		bus.player_healed.connect(_on_healed)


static func head_mesh() -> SphereMesh:
	if _head_mesh == null:
		_head_mesh = SphereMesh.new()
		_head_mesh.radius = HEAD_RADIUS
		_head_mesh.height = HEAD_RADIUS * 2.0
		_head_mesh.radial_segments = 10
		_head_mesh.rings = 5
		_head_mat = ShaderMaterial.new()
		_head_mat.shader = BOLT_SHADER
	return _head_mesh


func color(e: ElementTable.Element) -> Color:
	var t := elements if elements != null else ElementTable.load_default()
	return t.color(e) if t != null else Color.WHITE


## Place one head per [world position, element]; extra pooled heads hide.
func update_heads(heads: Array) -> void:
	while _heads.size() < heads.size():
		var mi := MeshInstance3D.new()
		mi.name = "BoltHead%d" % _heads.size()
		mi.mesh = head_mesh()
		mi.material_override = _head_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_heads.append(mi)
	for i in _heads.size():
		var mi := _heads[i]
		mi.visible = i < heads.size()
		if mi.visible:
			mi.global_position = heads[i][0]
			mi.set_instance_shader_parameter(&"element_color", color(heads[i][1]))


func visible_heads() -> int:
	var n := 0
	for h in _heads:
		n += 1 if h.visible else 0
	return n


## One-shot impact burst; returns it (null when over the cap).
func impact(at: Vector3, normal: Vector3, e: ElementTable.Element) -> CPUParticles3D:
	if bursts >= mini(MAX_BURSTS, QualityPresets.burst_cap()) or not is_inside_tree():
		return null
	var cfg: Array = BURST.get(e, [10, 0.4, 2.0, 0.0, 0.05, 90.0])
	var c := color(e)
	if e == ElementTable.Element.LIGHT:
		c = LIGHT_GOLD
	var p := _burst(cfg, c, normal)
	add_child(p)
	p.global_position = at + normal * 0.05
	return p


func _burst(cfg: Array, c: Color, normal: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Impact"
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(cfg[0])
	p.lifetime = float(cfg[1])
	p.initial_velocity_min = float(cfg[2]) * 0.5
	p.initial_velocity_max = float(cfg[2])
	p.gravity = Vector3(0, float(cfg[3]), 0)
	p.spread = float(cfg[5])
	p.direction = normal if normal.length() > 0.1 else Vector3.UP
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(c.lerp(Color.WHITE, 0.4), 1.0))
	g.set_color(1, Color(c, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(cfg[4]) * 2.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = soft_dot()
	q.material = m
	p.mesh = q
	p.emitting = true
	bursts += 1
	p.finished.connect(_burst_done.bind(p))
	return p


## Round soft particle sprite (radial white -> clear), shared by every burst.
static func soft_dot() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 32
		_soft.height = 32
	return _soft


func _burst_done(p: Node) -> void:
	bursts = maxi(0, bursts - 1)
	p.queue_free()


func _on_healed(pl: Player, _amount: float) -> void:
	if is_instance_valid(pl) and pl.is_inside_tree() and is_inside_tree():
		heal_motes(pl.global_position)


## Light heal: rising green-gold motes + a ring at the feet.
func heal_motes(at: Vector3) -> CPUParticles3D:
	if bursts >= mini(MAX_BURSTS, QualityPresets.burst_cap()) or not is_inside_tree():
		return null
	var p := _burst([20, 1.1, 1.2, 1.6, 0.05, 25.0], HEAL_COLOR.lerp(LIGHT_GOLD, 0.35), Vector3.UP)
	p.name = "HealMotes"
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.55
	p.emission_ring_inner_radius = 0.4
	p.emission_ring_height = 0.05
	p.explosiveness = 0.3
	add_child(p)
	p.global_position = at + Vector3.UP * 0.1
	return p


## Dark conversion aura under `host` while `seconds_left` > 0 (fades over AURA_FADE).
static func sync_aura(host: Node3D, seconds_left: float, radius := 0.9) -> MeshInstance3D:
	var a := host.get_node_or_null(^"DarkAura") as MeshInstance3D
	if seconds_left <= 0.0:
		if a:
			a.queue_free()
		return null
	if a == null:
		if _aura_mesh == null:
			_aura_mesh = PlaneMesh.new()
			_aura_mesh.size = Vector2(2, 2)
		a = MeshInstance3D.new()
		a.name = "DarkAura"
		a.mesh = _aura_mesh
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = AURA_SHADER
		a.material_override = m
		a.position = Vector3(0, 0.04, 0)
		a.scale = Vector3.ONE * radius
		host.add_child(a)
	(a.material_override as ShaderMaterial).set_shader_parameter(&"fade", clampf(seconds_left / AURA_FADE, 0.0, 1.0))
	return a
