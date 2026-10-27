// Terrain: blends mud, packed dirt, sparse grass, sand and concrete scraps using a baked splat map
// (r = mud/wet bank, g = grass, b = sand, a = hard-packed path) plus world-space noise and wetness near water.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 splat_origin = vec2(-560.0, -560.0);
uniform float splat_size = 1120.0;
uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float water_y = -0.6;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 suv = (wpos.xz - splat_origin) / splat_size;
	vec4 s = texture(splat, suv);
	float n = texture(noise_tex, wpos.xz * (0.15 / 32.0)).g * 0.6 + texture(noise_tex, wpos.xz * (0.6 / 32.0)).a * 0.4;
	vec2 uv = wpos.xz / 4.0;
	vec2 uv2 = wpos.xz / 5.3 + vec2(0.37, 0.11);
	float wm = clamp(s.r + (n - 0.5) * 0.4, 0.0, 1.0);
	float wg = clamp(s.g * smoothstep(0.25, 0.7, n + s.g * 0.5), 0.0, 1.0);
	float ws = clamp(s.b, 0.0, 1.0);
	float wp = clamp(s.a * (0.6 + n * 0.6), 0.0, 1.0);
	vec3 col = texture(dirt_alb, uv).rgb;
	vec3 nrm = texture(dirt_nrm, uv).rgb;
	col = mix(col, texture(mud_alb, uv2).rgb, wm); nrm = mix(nrm, texture(mud_nrm, uv2).rgb, wm);
	col = mix(col, texture(grass_alb, uv).rgb, wg); nrm = mix(nrm, texture(grass_nrm, uv).rgb, wg);
	col = mix(col, texture(sand_alb, uv2).rgb, ws); nrm = mix(nrm, texture(sand_nrm, uv2).rgb, ws);
	col = mix(col, texture(path_alb, uv * 0.75).rgb, wp); nrm = mix(nrm, texture(path_nrm, uv * 0.75).rgb, wp);
	float wet = 1.0 - smoothstep(water_y, water_y + 1.2, wpos.y);
	wet = max(wet, wm * 0.5);
	col *= mix(1.0, 0.55, wet);
	ALBEDO = col * 0.9;
	ROUGHNESS = mix(0.92, 0.35, wet);
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
}
