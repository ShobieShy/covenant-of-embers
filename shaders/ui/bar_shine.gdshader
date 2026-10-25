// FX F7 (step 133): a soft highlight sweeping across HUD bars every few seconds, plus a top sheen.
shader_type canvas_item;
render_mode blend_add;

uniform float period = 3.5;
uniform float strength = 0.35;

void fragment() {
	float x = fract(TIME / period) * 2.0 - 0.5;
	float band = smoothstep(0.12, 0.0, abs(UV.x - x - (1.0 - UV.y) * 0.08));
	float sheen = smoothstep(0.5, 0.0, UV.y) * 0.15;
	COLOR = vec4(vec3(1.0), (band + sheen) * strength);
}
