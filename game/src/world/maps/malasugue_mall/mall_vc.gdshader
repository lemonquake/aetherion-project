// (r15) Malasugue Mall's painted parts in one batch: matte, satin, gloss, cloth and painted metal were five materials
// (five draw calls in every chunk of every storey); they now share this one. The colour is the vertex tint, the
// roughness and metalness come per vertex in CUSTOM0 (Materials.surface_data).
// (r16) After the outbreak: grime at the foot of every painted piece (UV2.x = the piece's dirt, UV2.y = its base
// height, as in surface.gdshader) and mottled dirt over it, from the shared baked noise.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float grime = 0.6;

varying vec2 rm;
varying vec3 world_pos;

void vertex() {
	rm = CUSTOM0.xy;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = world_pos.xz + world_pos.y * vec2(0.37, 0.61);
	float dirt = UV2.x * grime;
	float n = texture(noise_tex, wp * (1.0 / 32.0) * 0.8).r;
	float foot = 1.0 - smoothstep(0.0, 0.7 + n * 0.8, world_pos.y - UV2.y);
	float g = clamp(foot * dirt * 0.8 + smoothstep(0.45, 0.85, n) * dirt * 0.45, 0.0, 0.75);
	ALBEDO = mix(COLOR.rgb, COLOR.rgb * vec3(0.42, 0.37, 0.31), g);
	ROUGHNESS = mix(rm.x, 0.85, g * 0.6);
	METALLIC = rm.y * (1.0 - g);
}
