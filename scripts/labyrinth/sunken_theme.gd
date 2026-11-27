class_name SunkenTheme
extends RefCounted
## Act IV materials and atmosphere. Textures are the CC0 ambientCG sets already
## in the repo. Tints push them toward wet stone, bronze, and coral.

const ROCK := "res://assets/ambientcg/Rock030/"
const PAVE := "res://assets/ambientcg/PavingStones131/"
const BRICK := "res://assets/ambientcg/Bricks076C/"
const MUD := "res://assets/ambientcg/Ground054/"
const METAL := "res://assets/ambientcg/Metal032/"
const WOOD := "res://assets/ambientcg/Wood049/"

var stone: StandardMaterial3D
var masonry: StandardMaterial3D
var paving: StandardMaterial3D
var silt: StandardMaterial3D
var bronze: StandardMaterial3D
var pew: StandardMaterial3D
var water_mat: ShaderMaterial
var violet: StandardMaterial3D
var coral_orange: StandardMaterial3D
var coral_red: StandardMaterial3D
var coral_violet: StandardMaterial3D
var mural: StandardMaterial3D
var tablet: StandardMaterial3D


func _init() -> void:
	stone = _pbr(ROCK, Color(0.62, 0.68, 0.7), 0.22, true)
	stone.cull_mode = BaseMaterial3D.CULL_DISABLED
	masonry = _pbr(BRICK, Color(0.55, 0.58, 0.6), 0.18, false)
	masonry.uv1_scale = Vector3(0.45, 0.45, 0.45)
	paving = _pbr(PAVE, Color(0.86, 0.8, 0.68), 0.12, false)
	paving.uv1_scale = Vector3(0.35, 0.35, 0.35)
	paving.cull_mode = BaseMaterial3D.CULL_DISABLED
	silt = _pbr(MUD, Color(0.28, 0.4, 0.4), 0.05, true)
	bronze = _pbr(METAL, Color(0.78, 0.5, 0.24), 1.0, false)
	bronze.metallic = 0.9
	bronze.roughness = 0.38
	bronze.emission_enabled = true
	bronze.emission = Color(0.45, 0.24, 0.08)
	bronze.emission_energy_multiplier = 0.18
	pew = _pbr(WOOD, Color(0.42, 0.3, 0.2), 0.08, false)
	pew.uv1_scale = Vector3(0.5, 0.5, 0.5)
	water_mat = _water()
	violet = _glow(Color(0.62, 0.28, 0.95), 2.4)
	coral_orange = _coral(Color(0.95, 0.42, 0.16))
	coral_red = _coral(Color(0.82, 0.16, 0.22))
	coral_violet = _coral(Color(0.58, 0.28, 0.78))
	mural = _painted(_mural_image(), Color(0.7, 0.65, 0.8), 0.35)
	tablet = _painted(_tablet_image(), Color(0.55, 0.58, 0.6), 0.05)


func environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.05, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.58, 0.62)
	e.ambient_light_energy = 0.72
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(0.05, 0.16, 0.2)
	e.fog_density = 0.0045
	e.fog_aerial_perspective = 0.35
	return e


func coral(i: int) -> StandardMaterial3D:
	var mats := [coral_orange, coral_red, coral_violet]
	return mats[i % mats.size()]


func _pbr(dir: String, tint: Color, uv: float, triplanar: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "color.jpg")
	m.albedo_color = tint
	m.roughness_texture = load(dir + "roughness.jpg")
	m.normal_enabled = true
	m.normal_texture = load(dir + "normal.jpg")
	m.uv1_scale = Vector3(uv, uv, uv) if uv > 0.0 else Vector3.ONE
	m.uv1_triplanar = triplanar
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


func _coral(c: Color) -> StandardMaterial3D:
	var m := _pbr(ROCK, c, 0.8, true)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.42
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.25
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m


func _painted(img: Image, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = Color(0.85, 0.88, 0.9)
	m.roughness = 0.72
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	m.emission_texture = m.albedo_texture
	return m


func _water() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = world.xz * 0.07;
	float ripple = sin(uv.x * 1.6 + TIME * 0.35) * sin(uv.y * 1.3 - TIME * 0.28);
	float caustic = pow(0.5 + 0.5 * sin(uv.x * 4.0 + TIME * 0.6) * sin(uv.y * 3.4 - TIME * 0.5), 3.0);
	vec3 shallow = vec3(0.16, 0.58, 0.6);
	vec3 deep = vec3(0.03, 0.18, 0.22);
	ALBEDO = mix(deep, shallow, clamp(0.4 + 0.35 * ripple, 0.0, 1.0));
	ALPHA = 0.58;
	ROUGHNESS = 0.07;
	METALLIC = 0.08;
	EMISSION = vec3(0.25, 0.7, 0.72) * caustic * 0.22;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


func _mural_image() -> Image:
	var img := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.16, 0.15, 0.18))
	for x in 256:
		for y in 128:
			var col := Color(0.2, 0.18, 0.22)
			var band := int(x / 28)
			var fx := x - band * 28
			if abs(fx - 14) < 4 and y > 46 and y < 108:
				col = Color(0.32, 0.3, 0.48)
			elif Vector2(fx - 14, y - 40).length() < 5.0 and y < 52:
				col = Color(0.55, 0.5, 0.72)
			elif y > 112:
				col = Color(0.28, 0.26, 0.24)
			if abs(x - 40) < 2 or abs(x - 220) < 2:
				col = col.lerp(Color(0.45, 0.4, 0.32), 0.6)
			img.set_pixel(x, y, col)
	return img


func _tablet_image() -> Image:
	var img := Image.create(128, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.45, 0.44, 0.4))
	for y in range(18, 146, 14):
		for x in range(16, 112):
			var wobble := int(sin(float(x) * 0.35 + float(y)) * 1.5)
			var yy := clampi(y + wobble, 0, 159)
			img.set_pixel(x, yy, Color(0.28, 0.27, 0.25))
	return img
