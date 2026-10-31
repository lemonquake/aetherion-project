shader_type spatial;
// r14: second pass over suitable loot (after loot_outline): a cel-shaded green rim in three hard bands, a faint even
// tint, and a bright scan line sweeping up through the item, added on top of its own colours.
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.16, 1.0, 0.34);

void fragment() {
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float band = floor(fres * 3.0 + 0.35) / 3.0;
	float y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float scan = exp(-pow(fract(y * 2.2 - TIME * 0.9) - 0.5, 2.0) * 260.0);
	ALBEDO = color * (0.07 + band * 0.55 + scan * 0.8);
}
