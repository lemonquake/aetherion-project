extends RefCounted
## Night lighting: a hazy moon, a nearly black sky with a faint city glow on the horizon, low ambient light,
## depth and volumetric fog, and very few practical lights - failing street lamps, a few bare bulbs and tubes,
## an emergency light at the health centre, sodium lamps at the port and red beacons on the tall landmarks.

const SKY_SHADER := preload("res://src/world/night_sky.gdshader")
const MOON_DIR := Vector3(-0.539, 0.342, 0.770)

var mb = null
var env: Environment
var moon: DirectionalLight3D
var lamps: Array = []  # [{light, base, fault, amount, blink, phase, period, mesh, col, pos, big, kind}]
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _anim: Array = []        # lamps with a fault or a blink
var _near_anim: Array = []   # the ones close enough to the camera to animate, refreshed four times a second
var _shadowed: Array = []
var _budget_t := 0.0
var _meshes := {}
var _mats := {}
var _glint_xf: Array = []
var _glint_col: Array = []
var _headless := false
## Light manager: every fixture (light and emitter) by 32 m cell. Lights past their fade distance still cost
## culling time every frame (there are thousands), so only the ones near the camera stay in the scene.
const GRID := 32.0
const GRID_BIG := 64.0
var _fix: Array = []                    # fixture records {light, em, lamp}; index = id
var _fpos := PackedVector3Array()
var _freach2 := PackedFloat32Array()    # squared distance within which the light is shown (0: no light)
var _femreach2 := PackedFloat32Array()  # same for the emitter (0: not managed)
var _fstate := PackedByteArray()        # 1 = light shown, 2 = emitter shown
var _grid := {}        # Vector2i (32 m) -> PackedInt32Array of small fixtures
var _grid_big := {}    # Vector2i (64 m) -> PackedInt32Array of street lamps, floods, beacons
var _reach := 0.0
var _reach_big := 0.0
var _shown := PackedInt32Array()   # ids whose light or emitter is visible
var _seen := PackedInt32Array()    # per id: the update that last kept it
var _gen := 0
## View tier from ViewLod (0 ground, 1 low air, 2 high air): no local shadows or AO above the rooftops, no moon
## shadow high up.
var air_tier := 0
const GLINT_SHADER := preload("res://src/world/light_glint.gdshader")


func _init(map_builder) -> void:
	mb = map_builder
	rng.seed = mb.layout.rng.seed + 401


func build(parent: Node3D) -> void:
	## Values follow the owner's Sleep night: dark blue haze, a moon at ~20 degrees, very low sky fill.
	var we := WorldEnvironment.new()
	we.name = "Environment"
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sm.set_shader_parameter("moon_texture", load("res://assets/sky/moon_color.jpg"))
	sm.set_shader_parameter("cloud_noise", load("res://assets/sky/cloud_noise.png"))
	sm.set_shader_parameter("moon_direction", MOON_DIR)
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.2, 0.32)
	env.ambient_light_energy = 0.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.018, 0.024, 0.035)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0042
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.007
	env.volumetric_fog_albedo = Color(0.75, 0.8, 0.88)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_length = 72.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.12
	env.volumetric_fog_anisotropy = 0.5
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.85
	we.environment = env
	parent.add_child(we)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.62
	moon.light_angular_distance = 0.5
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 140.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.shadow_blur = 1.4
	moon.light_volumetric_fog_energy = 0.5
	parent.add_child(moon)
	# The light travels from the moon toward the ground.
	moon.global_transform = Transform3D(Basis.looking_at(-MOON_DIR, Vector3.UP), Vector3.ZERO)
	_headless = DisplayServer.get_name() == "headless"
	if not _headless:
		_street_lamps(parent)
		for spec in mb.dyn.lights:
			_add_light(parent, spec)
		_build_glints(parent)
	Settings.changed.connect(_on_setting)
	_apply_settings()


func _on_setting(section: String, key: String) -> void:
	if section == "graphics":
		_apply_settings()


func _apply_settings() -> void:
	if env == null:
		return
	env.volumetric_fog_enabled = bool(Settings.get_value("graphics", "volumetric_fog"))
	env.ssao_enabled = bool(Settings.get_value("graphics", "ssao")) and air_tier == 0
	var b := float(Settings.get_value("graphics", "brightness"))
	env.tonemap_exposure = 1.0 + b * 1.2
	var shadows := clampi(int(Settings.get_value("graphics", "shadows")), 0, 3)
	if moon:
		# Furniture indoors is already in the shade of the house around it: left out of the moon's shadow passes.
		moon.shadow_caster_mask = 0xFFFFF & ~Defs.RENDER_INTERIOR_PROPS
		moon.shadow_enabled = shadows > 0 and air_tier < 2
		# Without its shadow the moon would shine through roofs and walls into every room (on phones and Low,
		# and unfairly so in a match with players whose rooms are dark): it then skips the inside of buildings.
		moon.light_cull_mask = 0xFFFFF if moon.shadow_enabled else 0xFFFFF & ~(Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS)
		moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if shadows >= 3 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		moon.directional_shadow_split_1 = 0.1 if shadows >= 3 else 0.25
		moon.directional_shadow_max_distance = moon_shadow_distance()
	if not _shadowed.is_empty() and air_tier > 0:
		_shadow_budget()


func _show_fixture(id: int, st: int) -> void:
	var f: Dictionary = _fix[id]
	if f.light:
		(f.light as Light3D).visible = (st & 1) != 0
	if f.em:
		(f.em as MeshInstance3D).visible = (st & 2) != 0
	_fstate[id] = st


func moon_shadow_distance() -> float:
	return [60.0, 60.0, 90.0, 150.0][clampi(int(Settings.get_value("graphics", "shadows")), 0, 3)]


func set_air_tier(t: int) -> void:
	if t == air_tier:
		return
	air_tier = t
	_apply_settings()


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
	## A practical light: the Light3D (no shadows until the budget gives it some), a visible emitter, and a glint
	## for the far view. spec: pos, kind, color, energy, range, fault ("", flicker, dying, starter, sag, candle),
	## flicker (legacy amount), blink (beacon period), axis (tubes), dead (fixture only).
	var kind := str(spec.get("kind", "bulb"))
	var col: Color = spec.get("color", Color(1.0, 0.75, 0.5))
	var energy := float(spec.get("energy", 1.0))
	var rng_range := float(spec.get("range", 10.0))
	var dead := bool(spec.get("dead", false)) or energy <= 0.0
	var fault := str(spec.get("fault", ""))
	if fault == "" and float(spec.get("flicker", 0.0)) > 0.0:
		fault = "flicker"
	var big := kind in ["street", "flood", "sodium", "beacon", "emergency"]
	var light: Light3D = null
	if not dead:
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
			ol.omni_attenuation = 1.8 if kind == "candle" else (1.0 if spec.get("outdoor", false) else 1.4)
			ol.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
			light = ol
		light.light_color = col
		light.light_energy = energy
		light.shadow_enabled = false
		# Walls and doors shadow a lamp; furniture does not (each shadowed lamp would redraw every furnished cell in
		# its range, twice). Flashlights keep furniture shadows: their beams are what the rooms are seen by.
		light.shadow_caster_mask = 0xFFFFF & ~Defs.RENDER_INTERIOR_PROPS
		light.shadow_bias = 0.06
		light.light_volumetric_fog_energy = 1.0 if big else 0.5
		light.light_specular = 0.6
		light.distance_fade_enabled = true
		# Lamps leave the scene past their fade distance (the light manager hides them). light_distance shortens it
		# on phones: fewer lights per frame and per mesh (the Mobile renderer lights a mesh with at most 8 omni and
		# 8 spot lights). Read at build time.
		var reach_k := clampf(float(Settings.get_value("graphics", "light_distance")), 0.5, 1.0)
		light.distance_fade_begin = (140.0 if big else 38.0 + rng_range * 3.0) * reach_k
		light.distance_fade_length = 30.0 if big else 15.0
		light.distance_fade_shadow = 32.0
		light.position = spec.pos
		light.visible = false
		parent.add_child(light)
	var em := MeshInstance3D.new()
	em.mesh = _emitter_mesh(kind)
	if kind == "tube" and spec.has("axis"):
		var ax: Vector3 = spec.axis
		em.basis = Basis.looking_at(ax.normalized(), Vector3.UP)
	em.position = spec.pos
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not big:
		em.visibility_range_end = 110.0
		em.visible = false
	var animated := fault != "" or float(spec.get("blink", 0.0)) > 0.0
	var m: StandardMaterial3D = _emitter_material(col, dead, animated)
	em.material_override = m
	parent.add_child(em)
	# Shown while within reach: past the light's fade (plus one update's worth of free fall) it adds nothing.
	var fix := {"light": light, "em": em if not big else null, "lamp": null}
	var reach := (light.distance_fade_begin + light.distance_fade_length + 16.0) if light else 0.0
	var em_reach := 0.0 if big else 115.0
	var cs := GRID_BIG if big else GRID
	var g: Dictionary = _grid_big if big else _grid
	var ck := Vector2i(floori(spec.pos.x / cs), floori(spec.pos.z / cs))
	if not g.has(ck):
		g[ck] = PackedInt32Array()
	g[ck].append(_fix.size())
	_fix.append(fix)
	_fpos.append(spec.pos)
	_freach2.append(reach * reach)
	_femreach2.append(em_reach * em_reach)
	_fstate.append(0)
	_seen.append(0)
	if big:
		_reach_big = maxf(_reach_big, reach)
	else:
		_reach = maxf(_reach, maxf(reach, em_reach))
	if dead:
		return
	var rec := {"light": light, "base": energy, "fault": fault, "amount": float(spec.get("flicker", 0.35)), "blink": float(spec.get("blink", 0.0)),
		"phase": rng.randf() * 100.0, "period": rng.randf_range(7.0, 19.0), "mesh": m, "col": col, "pos": spec.pos, "big": big, "kind": kind,
		"anim": animated}
	fix.lamp = rec
	lamps.append(rec)
	if animated:
		_anim.append(rec)
	if kind != "beacon":
		_glint_xf.append(spec.pos)
		_glint_col.append(Color(col.r, col.g, col.b, clampf(energy * (1.4 if big else 1.0), 0.15, 1.0)))


func _emitter_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"tube":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.032, 0.032, 1.15)
			mesh = bm
		"lamp":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.05
			cm.height = 0.13
			cm.radial_segments = 10
			mesh = cm
		"candle":
			var fm := SphereMesh.new()
			fm.radius = 0.008
			fm.height = 0.03
			fm.radial_segments = 6
			fm.rings = 3
			mesh = fm
		"beacon":
			var sb := SphereMesh.new()
			sb.radius = 0.2
			sb.height = 0.4
			mesh = sb
		_:
			var sp := SphereMesh.new()
			sp.radius = 0.045 if kind == "bulb" else 0.07
			sp.height = sp.radius * 2.3
			sp.radial_segments = 10
			sp.rings = 5
			mesh = sp
	_meshes[kind] = mesh
	return mesh


func _emitter_material(col: Color, dead: bool, unique: bool) -> StandardMaterial3D:
	## Steady emitters of the same colour share a material (they batch); faulty ones get their own to flicker.
	var key := "%s|%s" % [col.to_html(false), "dead" if dead else "lit"]
	if not unique and _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	if dead:
		m.albedo_color = Color(0.55, 0.52, 0.45)
		m.roughness = 0.2
	else:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
	if not unique:
		_mats[key] = m
	return m


func _build_glints(parent: Node3D) -> void:
	## Lights seen from afar (across the river, from the aircraft): constant-size points that fade in beyond the
	## range where the real light and emitter are drawn. Depth-tested, so walls still hide indoor lamps.
	if _glint_xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = _glint_xf.size()
	for i in _glint_xf.size():
		mm.set_instance_transform(i, Transform3D(Basis(), _glint_xf[i]))
		mm.set_instance_color(i, _glint_col[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "LightGlints"
	mi.multimesh = mm
	var sm := ShaderMaterial.new()
	sm.shader = GLINT_SHADER
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 600, 4000))
	parent.add_child(mi)


func tick(dt: float) -> void:
	if _headless:
		return
	_t += dt
	_budget_t -= dt
	if _budget_t <= 0.0:
		_budget_t = 0.25
		_shadow_budget()
	var reduce := bool(Settings.get_value("accessibility", "reduce_flashes"))
	for L in _near_anim:
		# Quantised, and sent to the renderer only when it changes: most faults hold a level for seconds.
		var k := snappedf(_fault_level(L, reduce), 1.0 / 48.0)
		if k == float(L.get("k", -1.0)):
			continue
		L.k = k
		if L.light:
			(L.light as Light3D).light_energy = L.base * k
		(L.mesh as StandardMaterial3D).emission_energy_multiplier = 3.0 * k


func _fault_level(L: Dictionary, reduce: bool) -> float:
	var t: float = _t + float(L.phase)
	if float(L.blink) > 0.0:
		return 1.0 if fmod(t, float(L.blink)) < 0.35 else 0.0
	var k := 1.0
	match str(L.fault):
		"flicker":
			var x := t * 6.0
			var n := sin(x) * 0.5 + sin(x * 2.7 + 1.3) * 0.3 + sin(x * 7.1) * 0.2
			var amt := float(L.amount)
			if n > 1.0 - amt:
				k = 0.15
			elif fmod(t, 9.0) < 0.24 * amt:
				k = 0.0
		"dying":
			# Mostly dark; sputters on for a second or two, crackling.
			var w := sin(t * 0.47) + sin(t * 1.13 + 2.0) * 0.6
			if w > 0.9:
				k = 0.55 + 0.45 * absf(sin(t * 31.0)) * (1.0 if sin(t * 13.0) > -0.3 else 0.0)
			else:
				k = 0.0
		"starter":
			# A fluorescent tube whose starter keeps failing: a burst of blinks, then steady for a while.
			var cyc := fmod(t, float(L.period))
			if cyc < 1.6:
				k = 1.0 if sin(cyc * 47.0) > 0.2 else 0.08
			elif cyc < 1.9:
				k = 0.3
		"sag":
			# Brownout: the voltage wanders and the light breathes.
			k = 0.62 + 0.28 * sin(t * 0.7) + 0.1 * sin(t * 2.9)
			if fmod(t, 13.0) < 0.25:
				k *= 0.35
		"candle":
			k = 0.82 + 0.1 * sin(t * 9.0) + 0.06 * sin(t * 23.0 + 1.0) + 0.05 * sin(t * 3.1)
	if reduce:
		k = lerpf(0.75, 1.0, k)
	return k


func _shadow_budget() -> void:
	## Four times a second: shows the fixtures within reach of the camera and hides the rest, gives shadows to the
	## few lights nearest the camera (they stop light bleeding through walls where it shows), and picks which faulty
	## lights are close enough to animate.
	var vp: Viewport = mb.world.get_viewport() if mb.world and mb.world.is_inside_tree() else null
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam == null:
		return
	var cp := cam.global_position
	var n: int = [0, 4, 8, 12][clampi(int(Settings.get_value("graphics", "shadows")), 0, 3)] if air_tier == 0 else 0
	var near := []
	var now := PackedInt32Array()
	_gen += 1
	_near_anim.clear()
	for pass_i in 2:
		var g: Dictionary = _grid_big if pass_i == 1 else _grid
		var cs := GRID_BIG if pass_i == 1 else GRID
		var r := _reach_big if pass_i == 1 else _reach
		var c0 := Vector2i(floori((cp.x - r) / cs), floori((cp.z - r) / cs))
		var c1 := Vector2i(floori((cp.x + r) / cs), floori((cp.z + r) / cs))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var cell = g.get(Vector2i(cx, cz))
				if cell == null:
					continue
				for id in cell:
					var d2 := cp.distance_squared_to(_fpos[id])
					var st := (1 if d2 < _freach2[id] else 0) | (2 if d2 < _femreach2[id] else 0)
					if st == 0:
						continue
					now.append(id)
					_seen[id] = _gen
					if st != _fstate[id]:
						_show_fixture(id, st)
					if (st & 1) == 0:
						continue
					var L = _fix[id].lamp
					if L == null:
						continue
					if d2 < 1600.0 or (L.big and d2 < 6400.0):
						near.append([d2, L])
					if L.anim and d2 < (25600.0 if L.big else 12100.0):
						_near_anim.append(L)
	for id in _shown:
		if _seen[id] != _gen:
			_show_fixture(id, 0)
	_shown = now
	near.sort_custom(func(a, b): return a[0] < b[0])
	# Shadow-casting lamps by their Light3D (an object key hashes by identity; a Dictionary key by its contents).
	var keep := {}
	for i in mini(n, near.size()):
		keep[near[i][1].light] = near[i][1]
	for L in _shadowed:
		if not keep.has(L.light):
			(L.light as Light3D).shadow_enabled = false
	_shadowed.clear()
	for lt in keep:
		(lt as Light3D).shadow_enabled = true
		_shadowed.append(keep[lt])
