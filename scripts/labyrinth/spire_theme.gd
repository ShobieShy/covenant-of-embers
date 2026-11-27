class_name SpireTheme
extends RefCounted
## Act V look: dark slate, violet glass, a false starry sky. Materials are shared.
## Music stays silent. Nothing here opens the Core.

const ROCK_COLOR := "res://assets/ambientcg/Rock035/color.jpg"
const ROCK_NORMAL := "res://assets/ambientcg/Rock035/normal.jpg"
const ROCK_ROUGH := "res://assets/ambientcg/Rock035/roughness.jpg"
const WOOD_COLOR := "res://assets/ambientcg/Wood049/color.jpg"
const WOOD_NORMAL := "res://assets/ambientcg/Wood049/normal.jpg"
const WOOD_ROUGH := "res://assets/ambientcg/Wood049/roughness.jpg"
const SKY_TEX := "res://assets/spire/textures/false_sky.png"

static var _rock: StandardMaterial3D
static var _tower: StandardMaterial3D
static var _wood: StandardMaterial3D
static var _sky: StandardMaterial3D
static var _glass: StandardMaterial3D
static var _gems := {}
static var _ribbons := {}


static func rock() -> StandardMaterial3D:
	if _rock == null:
		_rock = _stone(Color(0.72, 0.74, 0.82), 0.18)
	return _rock


static func wall() -> StandardMaterial3D:
	var m := _pbr(ROCK_COLOR, ROCK_NORMAL, ROCK_ROUGH, Color(0.28, 0.3, 0.38), 0.06)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


static func tower_stone() -> StandardMaterial3D:
	if _tower == null:
		_tower = _stone(Color(0.42, 0.44, 0.52), 0.32)
		_tower.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _tower


static func wood() -> StandardMaterial3D:
	if _wood == null:
		_wood = _pbr(WOOD_COLOR, WOOD_NORMAL, WOOD_ROUGH, Color(0.45, 0.32, 0.22), 0.4)
	return _wood


static func sky() -> StandardMaterial3D:
	if _sky == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = load(SKY_TEX) as Texture2D
		m.emission_enabled = true
		m.emission = Color(0.85, 0.75, 1.0)
		m.emission_energy_multiplier = 2.0
		m.emission_texture = m.albedo_texture
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.uv1_scale = Vector3(0.5, 0.5, 0.5)
		m.uv1_offset = Vector3(0.5, 0.5, 0)
		_sky = m
	return _sky


static func glass() -> StandardMaterial3D:
	if _glass == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.55, 0.95, 0.85)
		m.emission_enabled = true
		m.emission = Color(0.45, 0.7, 1.0)
		m.emission_energy_multiplier = 4.0
		m.roughness = 0.15
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass = m
	return _glass


static func gem(kind: String) -> StandardMaterial3D:
	if _gems.has(kind):
		return _gems[kind]
	var m := StandardMaterial3D.new()
	var hue := Color(0.55, 0.28, 0.95) if kind != "blue" else Color(0.45, 0.75, 1.0)
	m.albedo_color = hue
	m.roughness = 0.12
	m.metallic = 0.05
	m.clearcoat_enabled = true
	m.clearcoat = 0.55
	m.emission_enabled = true
	m.emission = hue
	m.emission_energy_multiplier = 2.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_gems[kind] = m
	return m


static func ribbon(kind: String) -> StandardMaterial3D:
	if _ribbons.has(kind):
		return _ribbons[kind]
	var m := StandardMaterial3D.new()
	var hue := Color(0.72, 0.45, 1.0) if kind != "blue" else Color(0.55, 0.82, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(hue.r, hue.g, hue.b, 0.9)
	m.emission_enabled = true
	m.emission = hue
	m.emission_energy_multiplier = 3.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	_ribbons[kind] = m
	return m


static func column() -> StandardMaterial3D:
	var m := ribbon("violet")
	return m


static func environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.01, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.38, 0.58)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.15
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(0.08, 0.05, 0.14)
	e.fog_light_energy = 0.35
	e.fog_depth_begin = 48.0
	e.fog_depth_end = 190.0
	e.fog_depth_curve = 1.15
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_strength = 0.85
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.85
	return e


static func _stone(tint: Color, scale: float) -> StandardMaterial3D:
	var m := _pbr(ROCK_COLOR, ROCK_NORMAL, ROCK_ROUGH, tint, scale)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _pbr(color: String, normal: String, rough: String, tint: Color, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load(color) as Texture2D
	m.normal_enabled = true
	m.normal_texture = load(normal) as Texture2D
	m.roughness_texture = load(rough) as Texture2D
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar_sharpness = 1.4
	return m
