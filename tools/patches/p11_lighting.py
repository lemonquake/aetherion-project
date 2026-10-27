"""Patch: practical lights with faults (flicker, dying, failing starter, brownout, candle), shadows only for the
nearest few, animation only near the camera, emitters that batch, and distant glints."""
G = 'A:/Python/aetherion-project/game/'
p = G + 'src/world/lighting.gd'
s = open(p, encoding='utf-8').read()

i = s.index('func _add_light(parent: Node3D, spec: Dictionary) -> void:')
s = s[:i] + r'''func _add_light(parent: Node3D, spec: Dictionary) -> void:
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
			ol.omni_attenuation = 1.4 if kind != "candle" else 1.8
			ol.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
			light = ol
		light.light_color = col
		light.light_energy = energy
		light.shadow_enabled = false
		light.shadow_bias = 0.06
		light.light_volumetric_fog_energy = 1.0 if big else 0.5
		light.light_specular = 0.6
		light.distance_fade_enabled = true
		light.distance_fade_begin = 140.0 if big else 38.0 + rng_range * 3.0
		light.distance_fade_length = 30.0 if big else 15.0
		light.distance_fade_shadow = 32.0
		light.position = spec.pos
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
	var animated := fault != "" or float(spec.get("blink", 0.0)) > 0.0
	var m: StandardMaterial3D = _emitter_material(col, dead, animated)
	em.material_override = m
	parent.add_child(em)
	if dead:
		return
	var rec := {"light": light, "base": energy, "fault": fault, "amount": float(spec.get("flicker", 0.35)), "blink": float(spec.get("blink", 0.0)),
		"phase": rng.randf() * 100.0, "period": rng.randf_range(7.0, 19.0), "mesh": m, "col": col, "pos": spec.pos, "big": big, "kind": kind}
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
		var k := _fault_level(L, reduce)
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
	## Shadows for the few lights nearest the camera (they stop light bleeding through walls where it shows);
	## also picks which faulty lights are close enough to animate.
	var vp: Viewport = mb.world.get_viewport() if mb.world and mb.world.is_inside_tree() else null
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam == null:
		return
	var cp := cam.global_position
	var n: int = [0, 4, 8, 12][clampi(int(Settings.get_value("graphics", "shadows")), 0, 3)]
	var near := []
	for L in lamps:
		if L.light == null:
			continue
		var d: float = cp.distance_squared_to(L.pos)
		if d < 1600.0 or (L.big and d < 6400.0):
			near.append([d, L])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	for i in mini(n, near.size()):
		keep[near[i][1]] = true
	for L in _shadowed:
		if not keep.has(L):
			(L.light as Light3D).shadow_enabled = false
	_shadowed.clear()
	for L in keep.keys():
		(L.light as Light3D).shadow_enabled = true
		_shadowed.append(L)
	_near_anim.clear()
	for L in _anim:
		if cp.distance_squared_to(L.pos) < (25600.0 if L.big else 12100.0):
			_near_anim.append(L)
'''


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''var lamps: Array = []  # [{light, base, flicker, blink, phase, mesh}]
var rng := RandomNumberGenerator.new()
var _t := 0.0
''', '''var lamps: Array = []  # [{light, base, fault, amount, blink, phase, period, mesh, col, pos, big, kind}]
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
const GLINT_SHADER := preload("res://src/world/light_glint.gdshader")
''')
sub('''	_street_lamps(parent)
	for spec in mb.dyn.lights:
		_add_light(parent, spec)
	Settings.changed.connect(_on_setting)''', '''	_headless = DisplayServer.get_name() == "headless"
	if not _headless:
		_street_lamps(parent)
		for spec in mb.dyn.lights:
			_add_light(parent, spec)
		_build_glints(parent)
	Settings.changed.connect(_on_setting)''')
sub('	moon.light_energy = 0.55\n', '	moon.light_energy = 0.62\n')
open(p, 'w', encoding='utf-8').write(s)
print('patched lighting.gd')

# Placement: lane posts, doorways, houses.
q = G + 'src/world/street_dress.gd'
t = open(q, encoding='utf-8').read()
old = '''	if rng.randf() < 0.18 and not light:
		# Some lanes have a bare bulb strung from a post; most of them are dead.
		var alive := rng.randf() < 0.3
		if alive:
			dyn.add_light({"pos": top + Vector3(0, -0.9, 0), "kind": "bulb", "color": Color(1.0, 0.72, 0.42), "energy": 0.55, "range": 7.0, "flicker": 0.5 if rng.randf() < 0.5 else 0.0})
	return top'''
new = '''	if not light and mb.practical.rng.randf() < 0.5:
		# About half the posts carry a bare bulb for the lane (some dead, many faulty).
		mb.practical.pole_bulb(top + Vector3(0, -0.12, 0), along)
	return top'''
assert t.count(old) == 1
t = t.replace(old, new)
open(q, 'w', encoding='utf-8').write(t)
print('patched street_dress.gd')

r = G + 'src/world/map_builder.gd'
u = open(r, encoding='utf-8').read()


def subu(old, new):
    global u
    assert u.count(old) == 1, (u.count(old), old[:80])
    u = u.replace(old, new)


subu('''const StreetDress := preload("res://src/world/street_dress.gd")
''', '''const StreetDress := preload("res://src/world/street_dress.gd")
const PracticalLights := preload("res://src/world/practical_lights.gd")
''')
subu('''var lighting = null
''', '''var lighting = null
var practical = null
var match_seed := 0
''')
subu('''	lighting = Lighting.new(self)
''', '''	lighting = Lighting.new(self)
	self.match_seed = match_seed
	practical = PracticalLights.new(self, match_seed)
''')
subu('''	if opts.get("dress", true):
		StreetDress.new(self).build()
''', '''	if opts.get("dress", true):
		StreetDress.new(self).build()
		practical.porch_lights()
	stats.lights = practical.stats
''')
subu('''	rooms.append_array(out.rooms)
	return out''', '''	rooms.append_array(out.rooms)
	practical.house(spec, out.rooms)
	return out''')
open(r, 'w', encoding='utf-8').write(u)
print('patched map_builder.gd')
