class_name DeathTint
extends CanvasLayer
## 0.3.1 P5 (L5): a full-screen desaturate + slight darken while the player is dead,
## driven by CameraFeel.death() (0 alive .. 1 fully fallen). Not motion, so it stays on
## under reduced motion. Below the HUD layers; ignores the mouse.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g) * 0.7, amount * 0.85), 1.0);
}
"""

var amount := 0.0
var rect: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	name = "DeathTint"
	layer = 0
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	rect.material = _mat
	rect.visible = false
	add_child(rect)


func sync(a: float) -> void:
	amount = clampf(a, 0.0, 1.0)
	rect.visible = amount > 0.001
	_mat.set_shader_parameter(&"amount", amount)
