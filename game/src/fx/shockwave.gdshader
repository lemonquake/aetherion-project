shader_type spatial;
// r14: the blast's pressure wave: an expanding sphere that bends what is behind it near its rim (screen refraction)
// with a faint warm sheen. The bend fades out toward the very silhouette, so the sphere has no hard edge; strength
// goes 1 -> 0 as it grows.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float ring = pow(1.0 - facing, 2.5) * smoothstep(0.0, 0.3, facing);
	vec2 off = NORMAL.xy * ring * strength * 0.03;
	vec3 bent = textureLod(screen_tex, SCREEN_UV - off, 0.0).rgb;
	ALBEDO = bent + vec3(1.0, 0.85, 0.6) * ring * strength * 0.06;
	ALPHA = clamp(ring * strength * 1.8, 0.0, 0.8);
}
