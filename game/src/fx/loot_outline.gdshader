shader_type spatial;
// r14: the outline round loot that suits the player's guns: the model drawn again, back faces only, pushed outward on
// the screen by a fixed number of pixels, so a green line of the same width shows round its whole silhouette at any
// distance. The push is away from the model's origin on the screen (loot is small and roughly convex), with a little
// of the normal's direction: the far faces of a box have normals pointing anywhere on the screen, which alone left
// gaps along some edges. Pulses gently.
render_mode unshaded, cull_front, shadows_disabled, fog_disabled, depth_draw_opaque;

uniform vec3 color : source_color = vec3(0.16, 1.0, 0.34);
uniform float width_px = 4.2;   // at 1080 lines; scaled with the window height, never under 2.6 px

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 c0 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	vec2 radial = vec2(0.0);
	if (clip.w > 0.001 && c0.w > 0.001) {   // both in front of the camera
		radial = (clip.xy / clip.w - c0.xy / c0.w) * VIEWPORT_SIZE;
	}
	vec2 npx = (PROJECTION_MATRIX * vec4(mat3(MODELVIEW_MATRIX) * NORMAL, 0.0)).xy * VIEWPORT_SIZE;
	vec2 d = vec2(0.0);
	if (length(radial) > 0.001) {
		d += normalize(radial);
	}
	if (length(npx) > 0.00001) {
		d += normalize(npx) * 0.35;
	}
	if (length(d) > 0.00001) {
		d = normalize(d);
	}
	float w = max(width_px * VIEWPORT_SIZE.y / 1080.0, 2.6);
	clip.xy += d * w * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	float pulse = 0.8 + 0.2 * sin(TIME * 4.0);
	ALBEDO = color * (1.8 * pulse);
}
