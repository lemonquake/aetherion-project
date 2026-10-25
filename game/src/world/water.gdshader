// Dark, murky estuary water: slow ripples, moonlight glints, floating scum toward the banks.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.025, 0.032, 0.03);
uniform vec3 scum_color : source_color = vec3(0.09, 0.085, 0.06);
uniform float flow_speed = 0.12;
uniform vec2 flow_dir = vec2(0.0, 1.0);
uniform float wave_scale = 1.0;
uniform float sea = 0.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float height(vec2 p, float t) {
	vec2 f = flow_dir * t * flow_speed;
	float h = vnoise(p * 0.35 + f) * 0.5 + vnoise(p * 1.1 - f * 1.7 + 3.1) * 0.3 + vnoise(p * 3.3 + f * 2.3) * 0.2;
	h += sea * (sin(p.x * 0.18 + t * 0.9) * 0.4 + sin(p.y * 0.23 - t * 0.7) * 0.3);
	return h * wave_scale;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sea * (sin(wpos.x * 0.18 + TIME * 0.9) * 0.05 + sin(wpos.z * 0.23 - TIME * 0.7) * 0.04);
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	float e = 0.15;
	float h0 = height(p, t);
	float hx = height(p + vec2(e, 0.0), t);
	float hz = height(p + vec2(0.0, e), t);
	vec3 n = normalize(vec3((h0 - hx) * 0.6, 1.0, (h0 - hz) * 0.6));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float scum = smoothstep(0.62, 0.8, vnoise(p * 0.08 + flow_dir * t * flow_speed * 0.2)) * (1.0 - sea);
	ALBEDO = mix(deep_color, scum_color, scum * 0.8);
	ROUGHNESS = mix(0.06, 0.55, scum);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
