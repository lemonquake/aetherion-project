// Weathered surface for generated architecture.
// Vertex colour: rgb = paint tint (white = unpainted), a = paint coverage (0 = bare material).
// UV2.x = dirt amount for this piece, UV2.y = height of the piece's base above which grime fades.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 base_tint : source_color = vec3(1.0);
uniform float tint_strength = 1.0;
uniform float normal_depth = 1.0;
uniform float rough_offset = 0.0;
uniform float metallic = 0.0;
uniform float grime = 0.6;
uniform float streaks = 0.5;
uniform float water_line = -0.2;
uniform float paint_flake = 0.55;
uniform float darken = 1.0;
uniform bool use_ao = false;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.07; a *= 0.5; }
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb * base_tint;
	float rough = texture(rough_tex, UV).g;
	vec2 wp = world_pos.xz + world_pos.y * vec2(0.37, 0.61);
	// Paint: tinted coat that flakes away to reveal the bare material.
	float flake = fbm(wp * 1.7 + world_pos.y * 0.9);
	float coat = COLOR.a * smoothstep(paint_flake - 0.12, paint_flake + 0.12, flake + 0.25);
	vec3 painted = mix(alb, COLOR.rgb * (0.55 + 0.45 * dot(alb, vec3(0.333))) * 1.25, tint_strength);
	alb = mix(alb, painted, coat);
	rough = mix(rough, 0.75, coat * 0.5);
	// Grime: splashed mud near the base, rain streaks running down from edges, damp below the water line.
	float dirt_amt = UV2.x * grime;
	float base_h = world_pos.y - UV2.y;
	float splash = (1.0 - smoothstep(0.0, 0.9 + fbm(wp * 3.0) * 0.6, base_h)) * dirt_amt;
	float streak = 0.0;
	if (abs(world_nrm.y) < 0.6) {
		float sx = dot(world_pos.xz, normalize(vec2(world_nrm.z, -world_nrm.x)));
		streak = smoothstep(0.55, 0.95, vnoise(vec2(sx * 7.0, world_pos.y * 0.35))) * streaks * (0.4 + dirt_amt);
	}
	float damp = (1.0 - smoothstep(water_line, water_line + 0.8, world_pos.y)) * 0.8;
	float grunge = fbm(wp * 0.6) * 0.35 * dirt_amt;
	vec3 mud = vec3(0.16, 0.13, 0.1);
	alb = mix(alb, alb * mud * 3.0, clamp(splash * 0.85 + grunge, 0.0, 0.9));
	alb *= 1.0 - streak * 0.35;
	alb = mix(alb, alb * vec3(0.55, 0.6, 0.5), damp);
	rough = clamp(rough + rough_offset + splash * 0.15 - damp * 0.35, 0.04, 1.0);
	ALBEDO = alb * darken;
	ROUGHNESS = rough;
	METALLIC = metallic * (1.0 - coat) * (1.0 - splash);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	if (use_ao) { AO = texture(ao_tex, UV).r; AO_LIGHT_AFFECT = 0.3; }
}
