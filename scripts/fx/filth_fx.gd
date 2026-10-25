class_name FilthFX
extends Node3D
## FX F5 (step 131): The Filth's boss FX, a child of the Filth driven by its state (so every
## co-op peer that simulates/puppets it sees the same):
## - Wobble: the body model squashes/stretches on two sines (cheap jelly; no per-vertex
##   work on the imported mesh).
## - Acid blobs: one pooled wobbling acid sphere per live Filth.Blob; a landed or expired
##   blob leaves an acid pool (flattened, fades over POOL_TIME).
## - Regeneration (phase 2 regen): green motes converge inward while health climbs.
## - Phase shockwave: an expanding translucent sphere + dust ring on phase_changed.
## - Exposed core (phase 3): the weak-point emission pulses and a green OmniLight beats.

const ACID := preload("res://shaders/fx/acid.gdshader")
const ACID_COLOR := Color(0.45, 0.95, 0.15)
const POOL_TIME := 2.5
const WAVE_TIME := 0.7

var filth: Filth
var regen_on := false
var shockwaves := 0
var pools := 0
var _blob_nodes: Array[MeshInstance3D] = []
var _blob_mat: ShaderMaterial
var _regen: CPUParticles3D
var _core_light: OmniLight3D
var _t := 0.0
var _last_regen := 0.0
var _last_blob_count := 0


static func attach(f: Filth) -> FilthFX:
	var fx := FilthFX.new()
	fx.name = "FilthFX"
	fx.filth = f
	f.add_child(fx)
	f.phase_changed.connect(fx._on_phase)
	return fx


func _ready() -> void:
	_blob_mat = ShaderMaterial.new()
	_blob_mat.shader = ACID
	_regen = StatusFX._particles(24, 0.9, Color(0.4, 1.0, 0.4), 0.14)
	_regen.name = "Regen"
	_regen.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_regen.emission_sphere_radius = 1.6
	_regen.radial_accel_min = -4.0
	_regen.radial_accel_max = -3.0
	_regen.gravity = Vector3.ZERO
	_regen.emitting = false
	add_child(_regen)


func _process(dt: float) -> void:
	step(dt)


## One visual update (tests call it directly).
func step(dt: float) -> void:
	if filth == null:
		return
	_t += dt
	_wobble()
	_sync_blobs()
	regen_on = filth.phase == 2 and filth.regenerated > _last_regen + 1e-6 and not filth.dead
	_last_regen = filth.regenerated
	_regen.emitting = regen_on
	if _regen.emitting:
		_regen.position = Vector3(0, filth.def.size.y * 0.5 if filth.def else 1.0, 0)
	_core()


func _wobble() -> void:
	var m := filth.model as Node3D
	if m == null or filth.dead:
		return
	var k := 0.04 if filth.phase < 3 else 0.07
	var s := sin(_t * 3.1) * k
	var base: Vector3 = m.get_meta(&"base_scale", m.scale)
	m.set_meta(&"base_scale", base)
	m.scale = base * Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5 + sin(_t * 2.3) * k * 0.3)


func _sync_blobs() -> void:
	var live: Array = filth.blobs
	if live.size() < _last_blob_count and filth.is_inside_tree():
		for i in range(live.size(), mini(_last_blob_count, _blob_nodes.size())):
			if _blob_nodes[i].visible:
				acid_pool(_blob_nodes[i].global_position)
	_last_blob_count = live.size()
	while _blob_nodes.size() < live.size():
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		sm.radial_segments = 10
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = _blob_mat
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "AcidBlob%d" % _blob_nodes.size()
		add_child(mi)
		_blob_nodes.append(mi)
	for i in _blob_nodes.size():
		var on := i < live.size()
		_blob_nodes[i].visible = on
		if on and _blob_nodes[i].is_inside_tree():
			_blob_nodes[i].global_position = live[i].pos


## A flattened acid puddle that fades out (decorative; the blob's damage is Filth._land).
func acid_pool(at: Vector3) -> MeshInstance3D:
	if not is_inside_tree():
		return null
	var mi := MeshInstance3D.new()
	mi.name = "AcidPool"
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	sm.radial_segments = 12
	sm.rings = 4
	mi.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = ACID
	mi.material_override = m
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(at.x, filth.global_position.y + 0.02 if filth else 0.02, at.z)
	mi.scale = Vector3(1.0, 0.06, 1.0)
	pools += 1
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter(&"life", v), 1.0, 0.0, POOL_TIME)
	tw.tween_callback(mi.queue_free)
	return mi


func _on_phase(_f: Filth, _phase: int) -> void:
	shockwave()


## Expanding shell + dust at the Filth's feet.
func shockwave() -> Node3D:
	shockwaves += 1
	if not is_inside_tree():
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Shockwave"
	var sm := SphereMesh.new()
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(ACID_COLOR, 0.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = Vector3(0, 0.5, 0)
	var dust := StatusFX._particles(30, 0.8, Color(0.55, 0.5, 0.35), 0.5)
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = 1.5
	dust.emission_ring_inner_radius = 1.0
	dust.emission_ring_height = 0.1
	dust.direction = Vector3.UP
	dust.initial_velocity_max = 2.0
	dust.emitting = true
	mi.add_child(dust)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * 8.0, WAVE_TIME).from(Vector3.ONE)
	tw.tween_property(m, "albedo_color:a", 0.0, WAVE_TIME)
	tw.chain().tween_interval(0.3)
	tw.chain().tween_callback(mi.queue_free)
	return mi


func _core() -> void:
	if not filth.core_exposed() or filth.dead:
		if _core_light:
			_core_light.visible = false
		return
	var beat := 0.5 + 0.5 * sin(_t * 6.0)
	if filth._head_mat:
		filth._head_mat.emission_energy_multiplier = 2.0 + 3.0 * beat
	if _core_light == null:
		_core_light = OmniLight3D.new()
		_core_light.name = "CoreLight"
		_core_light.light_color = ACID_COLOR
		_core_light.omni_range = 4.0
		_core_light.shadow_enabled = false
		add_child(_core_light)
	_core_light.visible = true
	if filth.head_shape:
		_core_light.position = filth.head_shape.position
	_core_light.light_energy = 1.0 + 2.0 * beat


func core_light_on() -> bool:
	return _core_light != null and _core_light.visible
