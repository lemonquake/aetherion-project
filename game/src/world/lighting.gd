extends RefCounted
## Night lighting: a hazy moon, a nearly black sky with a faint city glow on the horizon, low ambient light,
## depth and volumetric fog, and very few practical lights - failing street lamps, a few bare bulbs and tubes,
## an emergency light at the health centre, sodium lamps at the port and red beacons on the tall landmarks.

const HDRI := "res://assets/thirdparty/polyhaven/hdri/qwantani_night_puresky/qwantani_night_puresky_2k.hdr"

var mb = null
var env: Environment
var moon: DirectionalLight3D
var lamps: Array = []  # [{light, base, flicker, blink, phase, mesh}]
var rng := RandomNumberGenerator.new()
var _t := 0.0


func _init(map_builder) -> void:
	mb = map_builder
	rng.seed = mb.layout.rng.seed + 401


func build(parent: Node3D) -> void:
	var we := WorldEnvironment.new()
	we.name = "Environment"
	env = Environment.new()
	var sky := Sky.new()
	var sm := PanoramaSkyMaterial.new()
	if ResourceLoader.exists(HDRI):
		sm.panorama = load(HDRI)
	sm.energy_multiplier = 0.32
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.05, 0.06, 0.08)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.08
	env.volumetric_fog_anisotropy = 0.45
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 0.82
	we.environment = env
	parent.add_child(we)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.7, 0.9)
	moon.light_energy = 0.16
	moon.light_angular_distance = 0.5
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 140.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.shadow_blur = 1.6
	moon.light_volumetric_fog_energy = 0.6
	moon.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-140.0), 0.0)
	parent.add_child(moon)
	_street_lamps(parent)
	for spec in mb.dyn.lights:
		_add_light(parent, spec)
	Settings.changed.connect(_on_setting)
	_apply_settings()


func _on_setting(section: String, key: String) -> void:
	if section == "graphics":
		_apply_settings()


func _apply_settings() -> void:
	if env == null:
		return
	env.volumetric_fog_enabled = bool(Settings.get_value("graphics", "volumetric_fog"))
	env.ssao_enabled = bool(Settings.get_value("graphics", "ssao"))
	var b := float(Settings.get_value("graphics", "brightness"))
	env.tonemap_exposure = 1.0 + b * 1.2
	var shadows := int(Settings.get_value("graphics", "shadows"))
	if moon:
		moon.shadow_enabled = shadows > 0
		moon.directional_shadow_max_distance = [60.0, 100.0, 140.0, 200.0][clampi(shadows, 0, 3)]


func _street_lamps(parent: Node3D) -> void:
	## Lamps along the main roads every ~45 m; a third are dead, some flicker.
	for r in mb.layout.roads:
		if float(r.w) < 6.0:
			continue
		var pts: PackedVector2Array = r.pts
		var acc := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var len := a.distance_to(b)
			var dir := (b - a) / len
			var t := 20.0 - acc
			while t < len:
				var p := a + dir * t
				var side := Vector2(-dir.y, dir.x) * (float(r.w) * 0.5 + 0.6)
				var q := p + side
				if not mb.layout.is_water(q.x, q.y) and mb.layout.in_play_area(q):
					var gy: float = mb.layout.ground_height(q.x, q.y)
					var alive := rng.randf() < 0.55
					_lamp_pole(Vector3(q.x, gy, q.y), -side.normalized(), alive)
					if alive:
						_add_light(parent, {"pos": Vector3(q.x - side.normalized().x * 1.4, gy + 7.2, q.y - side.normalized().y * 1.4), "kind": "street",
							"color": Color(1.0, 0.68, 0.38), "energy": 1.6, "range": 17.0, "flicker": 0.4 if rng.randf() < 0.3 else 0.0})
				t += rng.randf_range(38.0, 55.0)
			acc = len - (t - rng.randf_range(38.0, 55.0))


func _lamp_pole(base: Vector3, toward: Vector2, alive: bool) -> void:
	var sink = mb.sink
	sink.cylinder(base, Vector3.UP, 7.4, 0.09, "metal_paint", {"sides": 8, "collide": true, "tint": Color(0.5, 0.55, 0.5), "paint": 0.6, "phys": "steel"})
	var arm := Vector3(toward.x, 0.15, toward.y).normalized()
	sink.cylinder(base + Vector3(0, 7.3, 0), arm, 1.6, 0.05, "metal_paint", {"sides": 6, "tint": Color(0.5, 0.55, 0.5), "paint": 0.6})
	var head := base + Vector3(0, 7.3, 0) + arm * 1.5
	sink.box(Transform3D(Basis.looking_at(Vector3(toward.x, 0, toward.y), Vector3.UP), head + Vector3(0, -0.05, 0)), Vector3(0.28, 0.12, 0.55), "metal_paint", {"collide": false, "tint": Color(0.45, 0.48, 0.45), "paint": 0.6})


func _add_light(parent: Node3D, spec: Dictionary) -> void:
	var kind := str(spec.get("kind", "bulb"))
	var col: Color = spec.get("color", Color(1.0, 0.75, 0.5))
	var energy := float(spec.get("energy", 1.0))
	var rng_range := float(spec.get("range", 10.0))
	var light: Light3D
	if kind in ["street", "flood"]:
		var sl := SpotLight3D.new()
		sl.spot_angle = 62.0 if kind == "street" else 45.0
		sl.spot_range = rng_range
		sl.spot_attenuation = 0.9
		sl.rotation = Vector3(-PI * 0.5 if kind == "street" else -0.9, 0, 0)
		light = sl
	else:
		var ol := OmniLight3D.new()
		ol.omni_range = rng_range
		ol.omni_attenuation = 1.4
		light = ol
	light.light_color = col
	light.light_energy = energy
	light.shadow_enabled = kind in ["street", "flood", "sodium", "tube", "bulb"]
	light.light_volumetric_fog_energy = 1.2
	light.distance_fade_enabled = true
	light.distance_fade_begin = 120.0
	light.distance_fade_length = 40.0
	light.distance_fade_shadow = 50.0
	light.position = spec.pos
	parent.add_child(light)
	# A visible emitter so the light has a source.
	var em := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.06 if kind != "beacon" else 0.2
	sph.height = sph.radius * 2.0
	em.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 4.0
	em.material_override = m
	em.position = spec.pos
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(em)
	lamps.append({"light": light, "base": energy, "flicker": float(spec.get("flicker", 0.0)), "blink": float(spec.get("blink", 0.0)),
		"phase": rng.randf() * 100.0, "mesh": m, "col": col})


func tick(dt: float) -> void:
	_t += dt
	var reduce := bool(Settings.get_value("accessibility", "reduce_flashes"))
	for L in lamps:
		var k := 1.0
		if L.blink > 0.0:
			k = 1.0 if fmod(_t + L.phase, L.blink) < 0.35 else 0.0
		elif L.flicker > 0.0:
			var x: float = _t * 6.0 + L.phase
			var n := sin(x) * 0.5 + sin(x * 2.7 + 1.3) * 0.3 + sin(x * 7.1) * 0.2
			if n > 1.0 - L.flicker:
				k = 0.15 if not reduce else 0.7
			elif fmod(_t + L.phase, 9.0) < 0.12 * L.flicker:
				k = 0.0 if not reduce else 0.6
		(L.light as Light3D).light_energy = L.base * k
		(L.mesh as StandardMaterial3D).emission_energy_multiplier = 4.0 * k
