// Shallow puddle on dirt or concrete: an irregular mask, near-mirror surface with faint ripples and mud at the edge.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadows_disabled;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float n = vnoise(wpos.xz * 1.7) * 0.5 + vnoise(wpos.xz * 4.3) * 0.25;
	float r = length(c) + (n - 0.35) * 0.7;
	float mask = 1.0 - smoothstep(0.55, 0.85, r);
	if (mask < 0.02) {
		discard;
	}
	float edge = smoothstep(0.35, 0.8, r);
	ALBEDO = mix(vec3(0.015, 0.016, 0.014), vec3(0.08, 0.06, 0.045), edge);
	ROUGHNESS = mix(0.03, 0.7, edge);
	SPECULAR = 0.7;
	float rip = sin(length(wpos.xz - floor(wpos.xz)) * 30.0 - TIME * 3.0) * 0.02 * (1.0 - edge);
	NORMAL = normalize(NORMAL + vec3(rip, 0.0, rip * 0.6));
	ALPHA = mask * 0.92;
}
