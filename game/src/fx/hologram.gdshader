shader_type spatial;
// r14: the SmarTab hologram projected from the watch. Draws the SmarTab picture (a SubViewport) as projected light:
// colour fringes toward the edges, scanlines, a bright band rolling down, flicker, now and then a torn band shifted
// sideways, glowing edges, and a boot-up sweep from the top as the projection opens (boot 0 -> 1). Drawn over
// everything (no depth test): it is light in front of the eye, it never sinks into a wall.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D ui_tex : source_color, filter_linear, repeat_disable;
uniform float boot = 1.0;
uniform float bright = 1.0;
uniform float opacity = 0.96;   // the least the panel hides of the world behind it (Accessibility > SmarTab opacity)
uniform vec3 tint = vec3(0.45, 0.88, 1.0);
uniform vec2 px = vec2(1600.0, 960.0);   // picture size in pixels

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// Torn bands: a few rows shifted sideways for a frame or two.
	float row = floor(uv.y * 48.0);
	float tick = floor(t * 14.0);
	float tear = step(0.975, hash(vec2(row, tick)));
	uv.x += tear * (hash(vec2(tick, row + 3.0)) - 0.5) * 0.018;
	// Colour fringes, wider toward the edges.
	vec2 dc = uv - 0.5;
	float ca = (1.2 + 5.0 * dot(dc, dc)) / px.x;
	vec4 c = texture(ui_tex, uv);
	float r = texture(ui_tex, uv + vec2(ca, 0.0)).r;
	float b = texture(ui_tex, uv - vec2(ca, 0.0)).b;
	vec3 col = vec3(r, c.g, b);
	// A solid projection: the world shows through only faintly (the picture's own alpha is the floor's minimum).
	float a = max(max(c.a, max(r, b) * 0.6), opacity);
	// Scanlines (one dark line every three picture rows) and a soft bright band rolling down.
	float scan = 0.86 + 0.14 * step(0.33, fract(uv.y * px.y / 3.0));
	float roll = exp(-pow((fract(uv.y - t * 0.22) - 0.5) * 16.0, 2.0));
	float fl = 0.95 + 0.05 * hash(vec2(floor(t * 30.0), 7.0));
	// Edges glow; the projection thins out toward them.
	vec2 e = min(uv, 1.0 - uv);
	float edge_d = min(e.x * px.x / px.y, e.y);
	float edge = 1.0 - smoothstep(0.0, 0.006, edge_d);
	float halo = (1.0 - smoothstep(0.0, 0.04, edge_d)) * 0.35;
	// Boot: a bright line sweeps down; below it nothing yet.
	float sweep = boot * 1.08;
	float shown = 1.0 - smoothstep(sweep - 0.02, sweep, uv.y);
	float line = exp(-pow((uv.y - sweep) * 90.0, 2.0)) * step(boot, 0.999);
	float grain = (hash(uv * px + vec2(t * 61.0, t * 17.0)) - 0.5) * 0.06;
	col = col * scan * fl + tint * (roll * 0.07 + grain) ;
	col += tint * (edge * 0.9 + halo * 0.4 + line * 1.5);
	ALBEDO = col * bright;
	// Flicker and the rolling band play on the picture, never below the opacity floor.
	float body = max(a * (0.97 + roll * 0.03) * fl, opacity);
	ALPHA = clamp((body + edge * 0.85 + halo * 0.25) * shown + line * 0.9, 0.0, 1.0);
}
