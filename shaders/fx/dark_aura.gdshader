// FX F2 (step 128): Dark conversion aura. A flat ring under a corrupted enemy with a
// swirling violet band; `fade` drives the last-seconds fade-out. Visible to every peer
// because it follows the replicated corrupted state.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 aura_color : source_color = vec4(0.45, 0.05, 0.85, 1.0);
uniform float fade = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float band = smoothstep(1.0, 0.8, r) * smoothstep(0.35, 0.65, r);
	float swirl = 0.5 + 0.5 * sin(a * 5.0 + r * 9.0 - TIME * 3.5);
	ALBEDO = aura_color.rgb * band * (0.4 + swirl) * 1.6 * fade;
}
