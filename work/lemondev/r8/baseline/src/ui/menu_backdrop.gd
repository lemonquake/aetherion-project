extends ColorRect
## Menu backdrop: a night sky over a ragged shanty skyline with a few failing bulbs, drawn by a shader.

const SHADER := """
shader_type canvas_item;
uniform float time_scale = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash2(i), b = hash2(i + vec2(1, 0)), c = hash2(i + vec2(0, 1)), d = hash2(i + vec2(1, 1));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float skyline(float x, float seed, float base, float var) {
	float cell = floor(x * 38.0 + seed);
	float h = base + hash(cell * 1.7 + seed) * var;
	float lean = (hash(cell * 3.1) - 0.5) * 0.012;
	float fx = fract(x * 38.0 + seed);
	return h + lean * (fx - 0.5) + step(0.82, hash(cell * 9.3)) * 0.03 * step(0.3, fx) * step(fx, 0.45);
}
void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;
	vec3 top = vec3(0.012, 0.016, 0.03);
	vec3 hor = vec3(0.05, 0.06, 0.08);
	vec3 col = mix(hor, top, pow(1.0 - uv.y, 0.8));
	vec2 moon = vec2(0.78, 0.2);
	float md = distance(uv * vec2(1.78, 1.0), moon * vec2(1.78, 1.0));
	col += vec3(0.5, 0.55, 0.62) * smoothstep(0.045, 0.04, md);
	col += vec3(0.08, 0.1, 0.14) * exp(-md * 7.0);
	float cloud = noise(uv * vec2(4.0, 9.0) + vec2(t * 0.01, 0.0)) * noise(uv * vec2(9.0, 15.0) - vec2(t * 0.006, 0.0));
	col = mix(col, vec3(0.06, 0.07, 0.09), smoothstep(0.25, 0.6, cloud) * (1.0 - uv.y) * 0.8);
	float star = step(0.9975, hash2(floor(uv * vec2(900.0, 500.0)))) * (1.0 - uv.y) * 0.6;
	col += vec3(star) * (0.6 + 0.4 * sin(t * 2.0 + uv.x * 50.0));
	float back = skyline(uv.x, 3.0, 0.6, 0.12);
	float front = skyline(uv.x * 0.7, 11.0, 0.7, 0.14);
	if (uv.y > back) col = mix(col, vec3(0.02, 0.022, 0.026), 0.9);
	if (uv.y > front) col = vec3(0.008, 0.009, 0.011);
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		vec2 p = vec2(0.08 + hash(fi * 7.7) * 0.86, 0.0);
		p.y = skyline(p.x * 0.7, 11.0, 0.7, 0.14) + 0.02 + hash(fi * 3.3) * 0.08;
		float flick = step(0.15, noise(vec2(t * (2.0 + fi), fi * 10.0)));
		float d = distance(uv * vec2(1.78, 1.0), p * vec2(1.78, 1.0));
		vec3 bulb = mix(vec3(1.0, 0.72, 0.38), vec3(0.75, 0.9, 1.0), step(0.6, hash(fi * 5.1)));
		col += bulb * flick * (smoothstep(0.004, 0.0, d) * 0.9 + exp(-d * 70.0) * 0.08);
	}
	float wires = 0.0;
	for (int w = 0; w < 3; w++) {
		float fw = float(w);
		float y = 0.58 + fw * 0.05 + 0.03 * sin(uv.x * 6.0 + fw) - 0.04 * pow(abs(fract(uv.x * 2.0 + fw * 0.3) - 0.5), 2.0) * 8.0;
		wires += smoothstep(0.0016, 0.0, abs(uv.y - y));
	}
	col = mix(col, vec3(0.0), clamp(wires, 0.0, 0.8));
	float grain = (hash2(uv * 1000.0 + fract(t) * 100.0) - 0.5) * 0.02;
	float vig = smoothstep(1.2, 0.3, distance(uv, vec2(0.45, 0.5)));
	COLOR = vec4((col + grain) * mix(0.6, 1.0, vig), 1.0);
}
"""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
	color = Color.BLACK
