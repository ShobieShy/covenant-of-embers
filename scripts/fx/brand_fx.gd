class_name BrandFX
extends Node3D
## Step 141 (Brands B7, docs/BRANDS_PLAN.md §7): the held brand's look on the staff Head.
## Driven only by (fx bits, meter, kind, colour), the same data co-op replicates (step 142),
## so local and remote staffs look alike:
##  - bit 1 hot: red-orange glow + light growing with heat; bit 2 overheated/venting: a steam
##    puff on the rising edge and white wisps while it lasts;
##  - bit 4 charging: a glow sphere + light growing with the charge (brand colour);
##  - bit 8 spinning: a ring around the Head turning faster with spin-up.
## Particle counts follow QualityPresets (step 134). All procedural (no texture assets).

const HOT := Color(1.0, 0.35, 0.08)
const STEAM := Color(0.92, 0.95, 1.0, 0.7)
const BIT_HOT := 1
const BIT_VENT := 2
const BIT_CHARGE := 4
const BIT_SPIN := 8

var layer_mask := 1
var glow: MeshInstance3D
var ring: MeshInstance3D
var light: OmniLight3D
var steam: CPUParticles3D
var bits := 0
var meter := 0.0
var color := Color.WHITE
var puffs := 0  ## steam puffs started (tests)
var _glow_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D


func _init(mask := 1) -> void:
	name = "BrandFX"
	layer_mask = mask
	_glow_mat = _additive()
	glow = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	s.radial_segments = 12
	s.rings = 6
	glow.mesh = s
	glow.material_override = _glow_mat
	_ring_mat = _additive()
	ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.075
	t.outer_radius = 0.09
	t.rings = 16
	t.ring_segments = 6
	ring.mesh = t
	ring.material_override = _ring_mat
	ring.rotation_degrees.x = 90.0
	light = OmniLight3D.new()
	light.omni_range = 1.5
	light.shadow_enabled = false
	steam = CPUParticles3D.new()
	steam.emitting = false
	steam.one_shot = false
	steam.lifetime = 0.6
	steam.direction = Vector3.UP
	steam.spread = 35.0
	steam.initial_velocity_min = 0.4
	steam.initial_velocity_max = 0.9
	steam.gravity = Vector3(0, 0.5, 0)
	steam.scale_amount_min = 0.5
	steam.scale_amount_max = 1.2
	steam.color = STEAM
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = SpellFX.soft_dot()
	q.material = qm
	steam.mesh = q
	for n in [glow, ring, light, steam]:
		add_child(n)
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = mask
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light.light_cull_mask = mask
	apply(0, 0.0, Color.WHITE)


static func _additive() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Show `m`'s state (null = nothing branded in hand).
func show_mode(m: FireMode) -> void:
	if m == null or m.brand == null:
		apply(0, 0.0, Color.WHITE)
	else:
		apply(m.fx_bits(), maxf(0.0, m.meter()), m.brand.color)


## The whole look from replicable data; `value` is the 0..1 meter.
func apply(fx_bits: int, value: float, brand_color: Color) -> void:
	var was_venting := (bits & BIT_VENT) != 0
	bits = fx_bits
	meter = clampf(value, 0.0, 1.0)
	color = brand_color
	var hot := (bits & BIT_HOT) != 0 or (bits & BIT_VENT) != 0
	var charging := (bits & BIT_CHARGE) != 0
	var c := HOT if hot else color
	var k := meter if hot or charging else 0.0
	if (bits & BIT_VENT) != 0:
		k = 1.0
	glow.visible = k > 0.02
	glow.scale = Vector3.ONE * lerpf(0.6, 1.6, k)
	_glow_mat.albedo_color = Color(c.r, c.g, c.b, 0.25 + 0.55 * k)
	light.visible = k > 0.02
	light.light_color = c
	light.light_energy = 2.5 * k
	ring.visible = (bits & BIT_SPIN) != 0
	_ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.3 + 0.6 * meter)
	var venting := (bits & BIT_VENT) != 0
	steam.amount = QualityPresets.particle_amount(16)
	if venting and not was_venting:
		puffs += 1
		steam.restart()
	steam.emitting = venting


func _process(dt: float) -> void:
	if ring.visible:
		ring.rotate_object_local(Vector3.UP, dt * lerpf(2.0, 30.0, meter))
