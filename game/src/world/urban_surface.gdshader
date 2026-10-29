// Shared opaque architecture: one material per chunk/layer, independent PBR
// array slices retain repeat UVs and mipmaps without atlas seams.
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray orm_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
varying vec3 world_pos;
varying vec3 world_nrm;
varying flat vec4 surface_info;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	surface_info = CUSTOM0;
}

void fragment() {
	vec3 coords = vec3(UV, surface_info.x);
	vec3 alb = texture(albedo_array, coords).rgb;
	vec3 orm = texture(orm_array, coords).rgb;
	vec2 wp = world_pos.xz + world_pos.y * vec2(0.37, 0.61);
	vec4 weather = texture(noise_tex, wp * (1.7 / 32.0));
	float coat = COLOR.a * smoothstep(surface_info.w - 0.12, surface_info.w + 0.12, weather.r + 0.25);
	// A thin paint coat retains the photographed aggregate/wood/metal detail.
	// An opaque bright coat made different substrates converge to flat plaster.
	vec3 painted = COLOR.rgb * (0.48 + 0.52 * dot(alb, vec3(0.333))) * 1.06;
	alb = mix(alb, painted, coat * 0.55);
	float dirt = UV2.x * surface_info.z;
	float splash = (1.0 - smoothstep(0.0, 1.0 + weather.b * 0.5, world_pos.y - UV2.y)) * dirt;
	float tangent_coord = dot(world_pos.xz, normalize(vec2(world_nrm.z, -world_nrm.x) + vec2(0.00001)));
	float streak = smoothstep(0.6, 0.94, texture(noise_tex, vec2(tangent_coord * 7.0, world_pos.y * 0.32) / 32.0).g);
	streak *= (1.0 - smoothstep(0.3, 0.7, abs(world_nrm.y))) * 0.19;
	float damp = 1.0 - smoothstep(-0.2, 0.6, world_pos.y);
	alb *= 1.0 - splash * 0.48 - streak * dirt;
	alb = mix(alb, alb * vec3(0.55, 0.6, 0.5), damp * 0.65);
	ALBEDO = alb;
	// Preserve each material's roughness range and local wet/worn variation.
	ROUGHNESS = clamp(mix(orm.g, 0.76, coat * 0.12) + (weather.a - 0.5) * 0.16 + splash * 0.1 - damp * 0.25, 0.12, 1.0);
	METALLIC = surface_info.y * (1.0 - coat) * (1.0 - splash);
	SPECULAR = mix(0.3, 0.65, surface_info.y);
	vec2 normal_xy = texture(normal_array, coords).rg * 2.0 - 1.0;
	NORMAL_MAP = vec3(normal_xy * 0.5 + 0.5, 0.5 + 0.5 * sqrt(max(0.0, 1.0 - dot(normal_xy, normal_xy))));
	NORMAL_MAP_DEPTH = mix(1.2, 0.85, surface_info.y);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
}
