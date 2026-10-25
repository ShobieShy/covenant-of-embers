// FX F7 (step 133): procedural summoning circle / vortex disc - concentric rings, rotating rune
// ticks and an optional inward swirl. Unshaded, additive, no textures.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.55, 0.35, 1.0, 1.0);
uniform float spin = 0.4;
uniform float swirl = 0.0;
uniform float intensity = 2.0;

float ring(float r, float at, float w) {
	return smoothstep(w, 0.0, abs(r - at));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * spin + swirl * r * 6.0;
	float rings = ring(r, 0.95, 0.03) + ring(r, 0.78, 0.02) + ring(r, 0.45, 0.025);
	float ticks = step(0.8, fract(a * 24.0 / 6.2832)) * step(0.80, r) * step(r, 0.93);
	float star = ring(abs(sin(a * 2.5)) * 0.9, r, 0.02) * step(r, 0.78);
	float arms = swirl > 0.0 ? pow(0.5 + 0.5 * sin(a * 5.0 - TIME * 4.0), 6.0) * (1.0 - r) : 0.0;
	float v = (rings + ticks * 0.8 + star * 0.7 + arms) * step(r, 1.0);
	ALBEDO = tint.rgb * intensity;
	ALPHA = clamp(v, 0.0, 1.0) * tint.a;
}
