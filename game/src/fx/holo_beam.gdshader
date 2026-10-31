shader_type spatial;
// r14: the light from the watch to the hologram: faint planes and brighter edges, fading away from the watch and
// shimmering. Vertex colour alpha carries the fade (1 at the watch).
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_add, shadows_disabled, fog_disabled;

uniform vec3 tint = vec3(0.45, 0.88, 1.0);
uniform float strength = 1.0;

void fragment() {
	float shimmer = 0.75 + 0.25 * sin(TIME * 23.0 + UV.x * 40.0 + UV.y * 13.0);
	ALBEDO = tint * COLOR.a * strength * shimmer;
	ALPHA = 1.0;
}
