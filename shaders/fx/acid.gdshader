// FX F5 (step 131): acid blob / pool. Wobbling bright green core with a wet rim; `pool`
// flattens it into a puddle ring that fades with `life`.
shader_type spatial;
render_mode blend_mix, cull_back, shadows_disabled, depth_draw_opaque;

uniform vec4 acid_color : source_color = vec4(0.45, 0.95, 0.15, 1.0);
uniform float life = 1.0;

void vertex() {
	VERTEX += NORMAL * 0.12 * sin(TIME * 9.0 + VERTEX.y * 14.0 + VERTEX.x * 11.0);
}

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = acid_color.rgb * 0.4;
	EMISSION = acid_color.rgb * (0.8 + rim * 2.0) * life;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	ALPHA = 0.85 * life;
}
