// FX F4 (step 130): rarity loot beam. Additive open cylinder, soft fresnel edges, vertical
// scroll bands, top fade, tier pulse, Primordial swirl; close-range fade in the shader
// (gone at fade_near, full at fade_far) so the beam never fills the screen.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(1.0);
uniform float tier = 0.0;
uniform float swirl = 0.0;
uniform float fade_near = 0.6;
uniform float fade_far = 3.0;

varying float cam_dist;

void vertex() {
	cam_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5);
	float h = UV.y;  // 0 top .. 1 bottom on CylinderMesh
	float top = smoothstep(0.0, 0.45, h);
	float bands = 0.75 + 0.25 * sin((h * 14.0 + TIME * (1.5 + tier * 0.4)) + swirl * UV.x * 18.85);
	float pulse = 0.85 + 0.15 * sin(TIME * (2.0 + tier));
	float near = smoothstep(fade_near, fade_far, cam_dist);
	ALBEDO = beam_color.rgb * edge * top * bands * pulse * near * (0.9 + tier * 0.12);
}
