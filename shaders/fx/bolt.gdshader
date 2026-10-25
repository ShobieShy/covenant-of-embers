// FX F2 (step 128): shared spell bolt. Fresnel-bright core + scrolling value noise,
// element colour per instance. Additive, unshaded: cheap on the Steam Deck preset.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

instance uniform vec4 element_color : source_color = vec4(1.0, 0.3, 0.1, 1.0);
uniform float core_power = 2.2;
uniform float noise_speed = 3.0;
uniform float intensity = 2.4;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(facing, core_power);
	float n = noise(VERTEX * 6.0 + vec3(0.0, TIME * noise_speed, TIME * noise_speed * 0.7));
	vec3 hot = mix(element_color.rgb, vec3(1.0), core * 0.7);
	ALBEDO = hot * (0.35 + 0.65 * n) * intensity * (0.4 + core);
}
