// The forcefield at the edge of the safe area (r12, replaced the haze): a sheet of white-blue electric light. A faint
// hexagonal lattice, bands of charge climbing it, arcs crackling across it, a bright seam where it cuts through
// walls and the ground (Forward+ only: the other renderers skip the depth read), and brighter edge-on. Seen from far
// it reads as a glowing line on the horizon; close to it the crackle gets louder; from inside the field (outside = 1)
// the sheet is denser.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

uniform float outside = 0.0;      // 1 when the camera is inside the field
uniform float radius = 100.0;     // the circle's radius (m): keeps the pattern in metres as it shrinks
uniform float base_y = 0.0;       // ground level near the camera: the sheet is brightest from here up a few storeys
uniform float closing = 0.0;      // 1 while the circle is closing
uniform float intensity = 1.0;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
#endif

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Distance to the nearest edge of a hexagonal cell (0 on the edge, ~0.5 in the middle).
float hex_edge(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(mod(p, 1.0) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Metres along the wall and up it.
	vec2 m = vec2(UV.x * 6.2831853 * radius, wpos.y);
	float h = wpos.y - base_y;
	float t = TIME;
	// Lattice: thin cell edges, every so often a cell lit through.
	vec2 hp = m / vec2(2.6, 2.25);
	float lattice = 1.0 - smoothstep(0.0, 0.06, hex_edge(hp));
	vec2 cell = floor(hp + vec2(0.0, mod(floor(hp.x * 1.1547), 2.0) * 0.5));
	float flash = step(0.985, hash(cell + mod(floor(t * 3.0), 251.0)));
	// Bands of charge climbing the sheet.
	float band = pow(0.5 + 0.5 * sin(m.y * 0.55 - t * (2.2 + 2.5 * closing) + vnoise(m * 0.05) * 3.0), 6.0);
	// Arcs: thin bright filaments where a fast-changing noise crosses its middle value.
	float tk = mod(floor(t * 14.0), 997.0);   // wrapped: a large offset loses float precision and the noise goes blocky
	float n1 = vnoise(m * vec2(0.09, 0.22) + vec2(tk * 1.7, tk * 0.9)) * 0.65 + vnoise(m * vec2(0.31, 0.6) - vec2(tk * 0.6, tk * 1.3)) * 0.35;
	float arc = 1.0 - smoothstep(0.0, 0.025, abs(n1 - 0.5));
	arc *= smoothstep(0.3, 0.45, vnoise(m * 0.035 + vec2(tk * 0.37)));   // arcs fade out, no cut-off edge
	// Height: strong from the ground to a few storeys up, fading above.
	float low = 1.0 - smoothstep(6.0, 70.0, h);
	float foot = 1.0 - smoothstep(0.0, 3.5, abs(h));
	// Edge-on the sheet is thicker.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fres = pow(1.0 - facing, 2.0);
	// Close to the camera it thins out (no white blob over the screen: the HUD shows being inside it).
	float near = smoothstep(0.6, 4.0, length(VERTEX));
	float seam = 0.0;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene = -vp.z / vp.w;
	float diff = scene - (-VERTEX.z);
	seam = (1.0 - smoothstep(0.0, 0.9, diff)) * step(0.0, diff + 0.05);
#endif
	float body = 0.05 + 0.13 * outside;
	float a = body + lattice * 0.22 + band * 0.16 + arc * 1.4 + flash * lattice * 0.6 + fres * 0.35;
	a *= mix(0.25, 1.0, low);
	a += foot * 0.5 + seam * 1.6;
	a *= near * intensity;
	vec3 white = vec3(0.92, 0.96, 1.0);
	vec3 blue = vec3(0.55, 0.72, 1.0);
	vec3 col = mix(blue, white, clamp(arc + seam + flash * 0.5 + foot * 0.5, 0.0, 1.0));
	ALBEDO = col * a * (1.0 + 1.5 * (arc + seam));
}
