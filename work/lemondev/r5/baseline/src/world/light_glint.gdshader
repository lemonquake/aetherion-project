// Distant practical lights as small constant-size points (a few pixels), fading in past the range where the real
// lights and emitters are drawn. Instance colour = light colour; alpha = relative strength. Depth-tested.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float fade_near = 85.0;
uniform float fade_far = 110.0;
uniform float pixel_size = 0.0055;   // world size at 1 m from the camera
uniform float haze = 0.0022;         // extinction per metre through the night haze

varying float v_fade;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = distance(origin, CAMERA_POSITION_WORLD);
	v_fade = smoothstep(fade_near, fade_far, d) * exp(-d * haze);
	// Face the camera and keep a constant size on screen.
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = origin + (right * VERTEX.x + up * VERTEX.y) * d * pixel_size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = clamp(1.0 - length(p), 0.0, 1.0);
	ALBEDO = COLOR.rgb * (r * r) * COLOR.a * v_fade * 2.5;
}
