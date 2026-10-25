// FX F4 (step 130): ground ring under a drop; Unique adds rotating rune ticks.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 ring_color : source_color = vec4(1.0);
uniform float runes = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.78, 0.86, r) * smoothstep(1.0, 0.9, r);
	float a = atan(p.y, p.x) + TIME * 0.8;
	float tick = runes * step(0.6, sin(a * 12.0)) * smoothstep(0.55, 0.62, r) * smoothstep(0.76, 0.7, r);
	ALBEDO = ring_color.rgb * (ring * 1.2 + tick * 1.5) * (0.85 + 0.15 * sin(TIME * 3.0));
}
