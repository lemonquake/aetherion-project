// Wall and ground decals drawn as quads just off the surface: graffiti, census numbers, posters, puddles, stains.
// Alpha comes from the texture; COLOR.a scales opacity; the surface underneath shows through softly.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float roughness = 0.85;
uniform float wet = 0.0;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * tint * COLOR.rgb;
	ALPHA = c.a * COLOR.a;
	ROUGHNESS = mix(roughness, 0.05, wet);
	SPECULAR = mix(0.4, 0.8, wet);
}
