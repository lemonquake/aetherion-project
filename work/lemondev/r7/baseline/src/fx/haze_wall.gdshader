// The boundary of the safe area: a slow, smoky wall of sulphur-tinted haze. Faint from inside the safe area (a
// warning on the horizon, not a neon fence) and thick when you are caught outside it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform float outside = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV * vec2(60.0, 4.0);
	float n = vnoise(uv + vec2(TIME * 0.05, -TIME * 0.03)) * 0.6 + vnoise(uv * 2.7 - vec2(TIME * 0.08, TIME * 0.02)) * 0.4;
	float h = 1.0 - UV.y;
	float a = smoothstep(0.25, 0.9, n) * (1.0 - smoothstep(0.35, 0.95, h)) * mix(0.1, 0.4, outside);
	ALBEDO = mix(vec3(0.09, 0.08, 0.05), vec3(0.16, 0.13, 0.08), n);
	ALPHA = a;
}
