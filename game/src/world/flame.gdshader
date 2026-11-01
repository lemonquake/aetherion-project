shader_type spatial;
// (r27) A burning torch or brazier: a camera-facing flame drawn from noise, no particles and no textures. The quad
// turns about its own up axis to face the camera (it stays upright), the noise rises through it, the tongue sways
// and narrows to a tip. Every flame burns out of step with the others (its phase comes from where it stands).
// "flick" (an instance uniform Lighting sets on the torches near the camera) follows the light's own flicker, so the
// fire and the light it throws pulse together. Additive, unshaded, so it costs a few noise lookups per pixel.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.74, 0.32, 1.0);
uniform vec4 body_color : source_color = vec4(1.0, 0.38, 0.05, 1.0);
uniform vec4 tip_color : source_color = vec4(0.75, 0.12, 0.02, 1.0);
uniform float intensity = 2.6;
uniform float speed = 1.0;
uniform bool halo = false;           // the soft glow round the flame (a second, larger quad)
instance uniform float flick = 1.0;
varying float phase;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.7) * 0.15;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	phase = hash(origin.xz * 0.37) * 40.0;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_cam = cam - origin;
	to_cam -= up * dot(to_cam, up);
	vec3 fwd = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(up, fwd));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 wp = origin + right * VERTEX.x * sx + up * VERTEX.y * sy;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);    // y = 0 at the flame's foot
	float t = TIME * speed + phase;
	float k = clamp(flick, 0.0, 1.5);
	if (halo) {
		// A warm glow that breathes with the fire: brightest just above the foot, gone at the quad's edge.
		vec2 d = (uv - vec2(0.5, 0.36)) * vec2(1.0, 1.25);
		float g = exp(-dot(d, d) * 9.0) * (0.85 + 0.15 * sin(t * 9.0));
		ALBEDO = body_color.rgb * g * 0.22 * intensity * k;
		ALPHA = g;
	} else {
		float rise = t * 2.3;
		float n = fbm(vec2(uv.x * 3.1, uv.y * 2.4 - rise));
		float n2 = fbm(vec2(uv.x * 6.3 + 3.1, uv.y * 4.6 - rise * 1.6));
		// The tongue leans and sways more toward its tip.
		float sway = (n - 0.5) * 0.42 * uv.y + sin(t * 3.7 + uv.y * 4.0) * 0.035 * uv.y;
		float width = mix(0.42, 0.05, pow(clamp(uv.y, 0.0, 1.0), 0.9));
		float dx = abs(uv.x - 0.5 + sway);
		float body = smoothstep(width, width * 0.25, dx);
		float top = 1.0 - smoothstep(0.35, 0.98, uv.y + (n2 - 0.5) * 0.45);
		float foot = smoothstep(0.0, 0.1, uv.y);
		float shape = body * top * foot;
		// Licks that break off above the flame.
		float lick = smoothstep(0.62, 0.9, n2) * smoothstep(0.25, 0.7, uv.y) * smoothstep(width * 2.2, 0.0, dx);
		shape = max(shape, lick * 0.55);
		float heat = clamp(shape * (1.25 - uv.y) * 1.35, 0.0, 1.0);
		vec3 col = mix(tip_color.rgb, body_color.rgb, smoothstep(0.05, 0.45, heat));
		col = mix(col, core_color.rgb, smoothstep(0.62, 0.98, heat));
		ALBEDO = col * shape * intensity * k;
		ALPHA = shape;
	}
}
