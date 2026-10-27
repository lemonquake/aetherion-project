// Night sky for Sitio Kalinaw, adapted from the owner's Sleep project (night_sky.gdshader and
// night_common.gdshaderinc): deep blue gradient, a low full moon (NASA LRO colour map) with limb darkening and halo,
// a handful of fixed, faintly twinkling stars, moonlit clouds from layered texture noise (after Velvet Katana
// Studios' CC0 "AAA Fake Volumetric Clouds"), and a warm sodium glow of the city beyond the bay on one horizon.
// As a sky shader it also feeds reflections and ambient light, so water and wet ground reflect this sky.
shader_type sky;
render_mode use_debanding;

uniform sampler2D moon_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 moon_direction = vec3(-0.539, 0.342, 0.770);
uniform float moon_radius = 0.024;
uniform float moon_energy = 4.0;
uniform vec3 moon_tint : source_color = vec3(1.0, 0.97, 0.9);
uniform vec3 zenith_color : source_color = vec3(0.004, 0.007, 0.02);
uniform vec3 sky_color : source_color = vec3(0.012, 0.02, 0.045);
uniform vec3 horizon_color : source_color = vec3(0.032, 0.043, 0.065);
uniform vec3 halo_color : source_color = vec3(0.18, 0.23, 0.33);
uniform vec3 city_glow : source_color = vec3(0.09, 0.055, 0.03);
uniform vec2 city_dir = vec2(0.6, -0.8);
uniform int star_count = 22;
uniform float star_energy = 2.4;
uniform float cloud_cover = 0.55;
uniform float cloud_speed = 0.0015;
uniform float cloud_scale = 0.22;
uniform float cloud_softness = 0.16;
uniform vec2 cloud_direction = vec2(0.8, 0.35);
uniform vec3 cloud_dark : source_color = vec3(0.016, 0.02, 0.03);
uniform vec3 cloud_lit : source_color = vec3(0.06, 0.072, 0.1);
// The artificial sun (day_k 0 = night, 1 = full day): a hard white core inside the thin ring of its frame, a hazy
// tropical sky and white clouds. The radiance pass (reflections) stays dim so rooms and covered lanes do not glow.
uniform float day_k = 0.0;
uniform vec3 sun_direction = vec3(0.3, 0.866, -0.4);
uniform vec3 day_zenith : source_color = vec3(0.17, 0.33, 0.6);
uniform vec3 day_horizon : source_color = vec3(0.6, 0.66, 0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float day_radiance = 0.3;

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

float night_stars(vec3 d, float px) {
	vec3 m = normalize(moon_direction);
	float total = 0.0;
	for (int i = 0; i < star_count; i++) {
		float fi = float(i);
		float h = hash11(fi * 1.37 + 0.5);
		float az = fi * 2.39996 + (hash11(fi + 7.1) - 0.5) * 0.9;
		float el = asin(mix(0.34, 0.98, hash11(fi * 3.1 + 2.0)));
		vec3 s = vec3(cos(el) * sin(az), sin(el), cos(el) * cos(az));
		if (dot(s, m) > 0.93) {
			s = vec3(-s.x, s.y, -s.z);
		}
		float ang = length(d - s);
		if (ang > px * 6.0) {
			continue;
		}
		float brightness = mix(0.3, 1.0, pow(hash11(fi * 5.3 + 1.1), 2.0));
		float twinkle = 0.86 + 0.14 * sin(TIME * (1.1 + h * 2.3) + h * 40.0) * sin(TIME * (0.37 + h * 0.6) + fi);
		float core = exp(-pow(ang / (px * 0.85), 2.0));
		float glow = exp(-pow(ang / (px * 2.6), 2.0)) * 0.12 * brightness;
		total += (core + glow) * brightness * twinkle;
	}
	return total;
}

vec3 moon_disc(vec3 d, vec3 m, out float mask) {
	float c = dot(d, m);
	float ang = acos(clamp(c, -1.0, 1.0));
	mask = 1.0 - smoothstep(moon_radius * 0.96, moon_radius, ang);
	if (mask <= 0.0) {
		return vec3(0.0);
	}
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), m));
	vec3 up = cross(m, right);
	vec2 q = vec2(dot(d, right), dot(d, up)) / sin(moon_radius);
	float r2 = dot(q, q);
	float z = sqrt(max(0.0, 1.0 - r2));
	float lon = atan(q.x, z);
	float lat = asin(clamp(q.y, -1.0, 1.0));
	vec2 uv = vec2(0.5 + lon / TAU, 0.5 - lat / PI);
	vec3 albedo = texture(moon_texture, uv).rgb;
	float limb = mix(0.55, 1.0, pow(z, 0.45));
	return albedo * limb * moon_tint * moon_energy * 1.6;
}

vec3 sky_gradient(vec3 d) {
	vec3 m = normalize(moon_direction);
	float up = clamp(d.y, -1.0, 1.0);
	vec3 c = mix(horizon_color, sky_color, smoothstep(0.0, 0.28, up));
	c = mix(c, zenith_color, smoothstep(0.25, 0.95, up));
	float mc = max(dot(d, m), 0.0);
	c += halo_color * (pow(mc, 12.0) * 0.08 + pow(mc, 90.0) * 0.18 + pow(mc, 900.0) * 0.6);
	vec2 hd = normalize(d.xz + vec2(0.0001));
	c += halo_color * 0.05 * pow(max(dot(hd, normalize(m.xz)), 0.0), 6.0) * (1.0 - smoothstep(0.0, 0.35, up));
	// The city across the bay lights the low clouds orange.
	c += city_glow * pow(max(dot(hd, normalize(city_dir)), 0.0), 3.0) * (1.0 - smoothstep(-0.02, 0.22, up));
	return c;
}

vec4 clouds(vec3 d, vec3 m, float up, out float thick) {
	vec2 plane = d.xz / (up + 0.12);
	vec2 drift = normalize(cloud_direction) * TIME * cloud_speed;
	vec2 uv = plane * cloud_scale + drift;
	vec2 evolve = vec2(sin(TIME * 0.011), cos(TIME * 0.009)) * 0.05;
	vec2 warp = (texture(cloud_noise, uv * 0.5 + evolve).bb - 0.5) * 0.07;
	float base = texture(cloud_noise, uv + warp).r;
	float second = texture(cloud_noise, uv * 0.41 + vec2(0.23, 0.37) - evolve).r;
	float n = base * 0.6 + second * 0.4;
	float threshold = 1.0 - cloud_cover;
	float cover = smoothstep(threshold, threshold + cloud_softness, n);
	float detail = texture(cloud_noise, uv * 2.3 + warp + evolve).g;
	cover *= mix(1.0, smoothstep(0.15, 0.85, detail), 0.45 * (1.0 - cover));
	float thickness = smoothstep(threshold, threshold + cloud_softness * 3.0, n);
	thick = thickness;
	cover *= smoothstep(0.04, 0.3, up);
	float mc = max(dot(d, m), 0.0);
	float scatter = pow(mc, 6.0) * 0.45 + pow(mc, 50.0) * 1.2 + pow(mc, 600.0) * 2.0;
	vec3 col = mix(cloud_lit, cloud_dark, thickness * 0.75);
	col += halo_color * scatter * mix(1.0, 0.35, thickness);
	vec2 hd = normalize(d.xz + vec2(0.0001));
	col += city_glow * 0.6 * pow(max(dot(hd, normalize(city_dir)), 0.0), 2.0) * (1.0 - smoothstep(0.05, 0.5, up));
	col = mix(horizon_color * 0.9, col, smoothstep(0.02, 0.35, up));
	return vec4(col, cover * 0.92);
}

vec3 day_sky(vec3 d, float up, vec4 cl, float thick) {
	vec3 s = normalize(sun_direction);
	vec3 c = mix(day_horizon, day_zenith, smoothstep(-0.02, 0.6, up));
	float sc = max(dot(d, s), 0.0);
	c += sun_color * (pow(sc, 6.0) * 0.18 + pow(sc, 48.0) * 0.45);
	if (up > 0.0) {
		vec3 cloud = mix(vec3(0.94, 0.94, 0.95), vec3(0.5, 0.53, 0.58), thick * 0.8) + sun_color * pow(sc, 10.0) * 0.4;
		c = mix(c, cloud, cl.a * 0.85);
	}
	if (!AT_CUBEMAP_PASS) {
		float ang = acos(clamp(dot(d, s), -1.0, 1.0));
		float core = 1.0 - smoothstep(0.017, 0.02, ang);
		float ring = (1.0 - smoothstep(0.0, 0.0025, abs(ang - 0.047))) * 0.5;
		vec3 r1 = normalize(cross(s, vec3(0.0, 0.0, 1.0)));
		vec3 r2 = cross(s, r1);
		float az = atan(dot(d, r2), dot(d, r1));
		float spoke = smoothstep(0.47, 0.495, abs(fract(az * 6.0 / TAU) - 0.5));
		float struts = spoke * step(0.02, ang) * step(ang, 0.047) * 0.35;
		c += sun_color * (core * 14.0 + ring * 1.6 + struts);
	}
	return mix(day_horizon * 0.85, c, smoothstep(-0.05, 0.0, up));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 m = normalize(moon_direction);
	vec3 c = sky_gradient(d);
	float up = d.y;
	vec4 cl = vec4(0.0);
	float thick = 0.0;
	if (up > 0.0) {
		cl = clouds(d, m, up, thick);
		float moon_mask = 0.0;
		vec3 disc = vec3(0.0);
		float star_light = 0.0;
		if (!AT_CUBEMAP_PASS) {
			disc = moon_disc(d, m, moon_mask);
			float moon_wash = 1.0 - smoothstep(0.8, 0.995, dot(d, m)) * 0.9;
			star_light = night_stars(d, 0.0011) * star_energy * smoothstep(0.05, 0.3, up) * moon_wash;
		}
		star_light *= 1.0 - cl.a;
		c = mix(c, cl.rgb, cl.a);
		moon_mask *= 1.0 - cl.a * mix(0.55, 0.97, cl.a);
		c += vec3(0.85, 0.9, 1.0) * star_light;
		c = mix(c, disc, moon_mask);
	}
	c = mix(horizon_color * 0.8, c, smoothstep(-0.05, 0.0, up));
	if (day_k > 0.0) {
		vec3 dc = day_sky(d, up, cl, thick);
		if (AT_CUBEMAP_PASS) {
			dc *= day_radiance;
		}
		c = mix(c, dc, day_k);
	}
	COLOR = c;
}
