// FX F3 (step 129): death dissolve. Noise threshold eats the shell from `progress` 0 -> 1
// with a hot element-coloured edge. Opaque (alpha scissor), so it sorts cheaply.
shader_type spatial;
render_mode cull_back, shadows_disabled;

uniform vec4 base_color : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float progress = 0.0;
uniform float edge_width = 0.08;

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
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = noise(wp * 5.0) * 0.7 + noise(wp * 13.0) * 0.3;
	float cut = n - progress * 1.1 + 0.05;
	ALPHA = 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (cut < 0.0) {
		ALPHA = 0.0;
	}
	ALBEDO = base_color.rgb;
	EMISSION = edge_color.rgb * 4.0 * (1.0 - smoothstep(0.0, edge_width, cut));
}
