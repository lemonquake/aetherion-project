// (r15) Malasugue Mall LED screens: cycles the eight advert frames of assets/mall/ads.png (2 x 4 frames of
// 1024 x 512), each held a few seconds with a quick wipe to the next. The quad's UV covers frame 0 (0..0.5 x 0..0.25);
// vertex colour r offsets this screen's cycle so neighbouring screens do not change together.
// (r16) Vertex colour g: how broken the screen is (0 fine): dead bands, a torn picture, static, blackouts.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D frames : source_color, filter_linear_mipmap;
uniform float hold = 6.5;
uniform float energy = 1.35;

vec2 frame_offset(float i) {
	float k = mod(i, 8.0);
	return vec2(mod(k, 2.0) * 0.5, floor(k / 2.0) * 0.25);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float t = TIME + COLOR.r * 41.0;
	float broken = COLOR.g;
	float k = floor(t / hold);
	float f = fract(t / hold);
	vec2 uv = clamp(UV, vec2(0.002), vec2(0.498, 0.248));
	// a torn picture: rows of LEDs slip sideways for a moment
	float row = floor(uv.y * 48.0);
	float tear = step(1.0 - broken * 0.25, hash(vec2(row, floor(t * 7.0)))) * (hash(vec2(row, 3.0)) - 0.5) * 0.08 * broken;
	uv.x = clamp(uv.x + tear, 0.002, 0.498);
	vec3 a = texture(frames, uv + frame_offset(k)).rgb;
	vec3 b = texture(frames, uv + frame_offset(k + 1.0)).rgb;
	// a left-to-right wipe in the last 6% of the hold
	float w = step(uv.x * 2.0, smoothstep(0.94, 1.0, f) * 1.02);
	vec3 c = mix(a, b, w);
	// the LED grid, faint
	vec2 cell = fract(uv * vec2(640.0, 720.0));
	float grid = 0.82 + 0.18 * step(0.18, cell.x) * step(0.18, cell.y);
	if (broken > 0.0) {
		// dead columns of modules, static, and the whole panel cutting out now and then
		float module = step(0.82, hash(floor(UV * vec2(18.0, 10.0))));
		c *= 1.0 - module * broken;
		float noise = hash(UV * 900.0 + floor(t * 24.0));
		float snow = step(0.55, sin(t * 0.7) * 0.5 + 0.5) * broken * 0.6;
		c = mix(c, vec3(noise) * 0.8, snow * step(0.4, hash(vec2(floor(t * 3.0), 1.0))));
		float out_ = step(1.0 - broken * 0.3, hash(vec2(floor(t * 2.0), 7.0)));
		c *= 1.0 - out_;
		c.g *= 1.0 - broken * 0.25;
	}
	ALBEDO = c * grid * energy;
}
