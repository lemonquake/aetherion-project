// Dark, murky estuary water: slow ripples, moonlight glints, floating scum toward the banks.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.025, 0.032, 0.03);
uniform vec3 scum_color : source_color = vec3(0.09, 0.085, 0.06);
uniform float flow_speed = 0.12;
uniform vec2 flow_dir = vec2(0.0, 1.0);
uniform float wave_scale = 1.0;
uniform float sea = 0.0;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

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
	vec2 f = flow_dir * t * flow_speed;
	vec3 n1 = texture(normal_tex, p * 0.045 + f * 0.3).rgb;
	vec3 n2 = texture(normal_tex, p * 0.11 - f * 0.55 + vec2(0.37, 0.71)).rgb;
	vec3 n3 = texture(normal_tex, p * 0.012 + vec2(t * 0.004, 0.0)).rgb;
	NORMAL_MAP = normalize(mix(mix(n1, n2, 0.5), n3, 0.25 + sea * 0.35));
	NORMAL_MAP_DEPTH = mix(0.35, 0.8, sea) * wave_scale;
	float scum = smoothstep(0.62, 0.8, texture(noise_tex, (p * 0.08 + f * 0.2) * (1.0 / 32.0)).g) * (1.0 - sea);
	ALBEDO = mix(deep_color, scum_color, scum * 0.8);
	ROUGHNESS = mix(0.08, 0.6, scum);
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
