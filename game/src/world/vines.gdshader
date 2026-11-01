shader_type spatial;
// (r27) Hanging vines (map_nature.gd): leafy strands cut out of a strand picture, swaying more the lower they hang.
// Alpha scissor (no blending), so they sort and shadow like solid leaves and cost one pass.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float sway = 0.14;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	// UV.y runs from 0 where the strand hangs from to 1 at its tip; COLOR.a is the strand's own phase.
	float hang = UV.y * UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.8 + COLOR.a * 6.28 + wp.x * 0.11 + wp.z * 0.13;
	VERTEX.x += sin(t) * sway * hang;
	VERTEX.z += cos(t * 0.77 + 1.3) * sway * 0.7 * hang;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * COLOR.rgb * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.72;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.12, 0.2, 0.05);
}
