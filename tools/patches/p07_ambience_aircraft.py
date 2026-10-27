"""Patch: looping sounds really loop, the night ambience runs on clients, the transport aircraft is visible and audible
during deployment, loud events hush the insects, and reloads make sounds others can hear."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/audio/sound_system.gd', [(
    '''	_last_variant[id] = i
	return _stream("res://" + str(files[i]))''',
    '''	_last_variant[id] = i
	var path := "res://" + str(files[i])
	if d.get("loop", false):
		return _looping(path)
	return _stream(path)


func _looping(path: String) -> AudioStream:
	## A copy of the stream set to loop over its whole length (sounds.json marks hums, static and engines).
	var key := path + "#loop"
	if _streams.has(key):
		return _streams[key]
	var s := _stream(path)
	if s != null:
		s = s.duplicate()
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif "loop" in s:
			s.set("loop", true)
	_streams[key] = s
	return s''')])

patch('src/audio/ambience.gd', [(
    '''			_one_shot("amb_owl_tawny" if rng.randf() < 0.5 else "amb_nightjar", lp + Vector3(cos(a2), 12.0, sin(a2)) * rng.randf_range(60.0, 140.0) / 1.0, -12.0, 70.0)''',
    '''			var r2 := rng.randf_range(60.0, 140.0)
			_one_shot("amb_owl_tawny" if rng.randf() < 0.5 else "amb_nightjar", lp + Vector3(cos(a2) * r2, 12.0, sin(a2) * r2), -12.0, 70.0)''')])

patch('src/match/world.gd', [
    ('''var hud = null
var interaction = null''', '''var hud = null
var ambience = null
var interaction = null'''),
    ('''		effects = Effects.new()
		effects.name = "Effects"
		add_child(effects)
		effects.setup(self)''', '''		effects = Effects.new()
		effects.name = "Effects"
		add_child(effects)
		effects.setup(self)
		ambience = load("res://src/audio/ambience.gd").new()
		ambience.name = "Ambience"
		add_child(ambience)
		ambience.setup(self)'''),
    # Reload sounds: decided by the server's weapon state, heard by everyone nearby including the owner.
    ('''	if ch.mode == Motor.GROUND:
		var shots: Array = ch.wpn.step(cmd, dt, tick)''', '''	if ch.mode == Motor.GROUND:
		var st0: int = ch.wpn.state
		var rounds0: int = int(ch.wpn.weapon().get("mag", 0))
		var shots: Array = ch.wpn.step(cmd, dt, tick)
		_reload_sounds(ch, st0, rounds0)'''),
    ('''func _server_motion_event(ch: Character, kind: String, value: float) -> void:''', '''func _reload_sounds(ch: Character, st0: int, rounds0: int) -> void:
	var feed := str(ch.wpn.def().get("feed", "mag"))
	var rounds := int(ch.wpn.weapon().get("mag", 0))
	var at: Vector3 = ch.global_position + Vector3.UP * 1.1
	if st0 != WeaponState.RELOAD and ch.wpn.state == WeaponState.RELOAD:
		server_sound("mag_out" if feed == "mag" else "switch_click", at, 0.0, -1)
	elif ch.wpn.state == WeaponState.RELOAD and rounds > rounds0 and feed != "mag":
		server_sound("mag_in", at, -6.0, -1)
	elif st0 == WeaponState.RELOAD and ch.wpn.state != WeaponState.RELOAD and feed == "mag" and rounds > rounds0:
		server_sound("mag_in", at, 0.0, -1)


func _server_motion_event(ch: Character, kind: String, value: float) -> void:'''),
])

patch('src/fx/effects.gd', [
    ('''var _space: PhysicsDirectSpaceState3D
var _rng := RandomNumberGenerator.new()''', '''var _space: PhysicsDirectSpaceState3D
var _rng := RandomNumberGenerator.new()
var _plane: Node3D
var _plane_lights: Array = []  # [{node, kind}]
var _plane_engine := false'''),
    ('''	_build_zone_wall()


func _make_hole()''', '''	_build_zone_wall()
	_build_aircraft()


func _make_hole()'''),
    ('''	_flash(flash_pos)
	var snd := "shot_" + str(d.get("sound", "pistol_9"))''', '''	_flash(flash_pos)
	if world.ambience:
		world.ambience.on_loud(origin, float(d.get("loudness", 600)) * 0.25)
	var snd := "shot_" + str(d.get("sound", "pistol_9"))'''),
    ('''# ------------------------------------------------------------------ the haze (zone wall)''', '''# ------------------------------------------------------------------ the transport aircraft

func _build_aircraft() -> void:
	## A four-engine high-wing transport, dark grey, with navigation lights (red port, green starboard, white tail),
	## a red beacon and a white strobe. Seen from the ground it is mostly the lights and the drone of the engines.
	_plane = Node3D.new()
	_plane.name = "Aircraft"
	_plane.visible = false
	add_child(_plane)
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.22, 0.23, 0.24)
	body.roughness = 0.6
	body.metallic = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.06)
	var parts := [
		# [mesh kind, size/params, position, rotation, material]
		["capsule", Vector2(2.0, 30.0), Vector3(0, 0, 0), Vector3(PI * 0.5, 0, 0), body],
		["box", Vector3(40.0, 0.45, 4.0), Vector3(0, 1.6, -1.0), Vector3.ZERO, body],
		["box", Vector3(14.0, 0.3, 2.6), Vector3(0, 1.4, 13.0), Vector3.ZERO, body],
		["box", Vector3(0.35, 6.0, 4.0), Vector3(0, 4.2, 12.8), Vector3(-0.25, 0, 0), body],
		["box", Vector3(1.6, 1.0, 0.8), Vector3(0, 0.6, -14.6), Vector3.ZERO, dark],
	]
	for x in [-14.0, -7.0, 7.0, 14.0]:
		parts.append(["capsule", Vector2(0.7, 5.0), Vector3(x, 1.0, -2.6), Vector3(PI * 0.5, 0, 0), body])
	for p in parts:
		var mi := MeshInstance3D.new()
		if p[0] == "box":
			var bm := BoxMesh.new()
			bm.size = p[1]
			mi.mesh = bm
		else:
			var cm := CapsuleMesh.new()
			cm.radius = (p[1] as Vector2).x
			cm.height = (p[1] as Vector2).y
			mi.mesh = cm
		mi.position = p[2]
		mi.rotation = p[3]
		mi.material_override = p[4]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_plane.add_child(mi)
	for l in [["nav", Vector3(-20.1, 1.6, -1.0), Color(1.0, 0.08, 0.05)], ["nav", Vector3(20.1, 1.6, -1.0), Color(0.1, 1.0, 0.3)],
			["nav", Vector3(0, 2.0, 15.4), Color(1.0, 1.0, 0.95)], ["beacon", Vector3(0, -2.1, 0), Color(1.0, 0.1, 0.05)],
			["beacon", Vector3(0, 2.1, 2.0), Color(1.0, 0.1, 0.05)], ["strobe", Vector3(-20.2, 1.7, -1.4), Color(1, 1, 1)],
			["strobe", Vector3(20.2, 1.7, -1.4), Color(1, 1, 1)]]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		s.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = l[2]
		m.emission_enabled = true
		m.emission = l[2]
		m.emission_energy_multiplier = 6.0
		s.material_override = m
		s.position = l[1]
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_plane.add_child(s)
		_plane_lights.append({"node": s, "kind": l[0]})
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.2, 0.1)
	glow.omni_range = 18.0
	glow.light_energy = 0.0
	glow.position = Vector3(0, -2.4, 0)
	_plane.add_child(glow)
	_plane_lights.append({"node": glow, "kind": "glow"})


func _update_aircraft() -> void:
	var info: Dictionary = world.match_info
	var pl: Dictionary = info.get("plane", {})
	var t: float = Net.interp_tick() if not world.is_server else float(Net.tick)
	var show := not pl.is_empty() and info.get("phase", "") in ["plane", "playing"]
	if show:
		var k := (t - float(pl.t0)) / Defs.TICK_RATE / float(pl.dur)
		show = k > -0.2 and k < 1.05
	_plane.visible = show
	if not show:
		if _plane_engine:
			SoundSys.stop_loop("aircraft")
			_plane_engine = false
		return
	var a: Vector3 = pl.a
	var b: Vector3 = pl.b
	var dir := (b - a).normalized()
	# Keep flying past the end of the path (the jump run is over, the aircraft is not).
	var k2 := (t - float(pl.t0)) / Defs.TICK_RATE / float(pl.dur)
	var pos := a.lerp(b, k2)
	_plane.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	var now := Time.get_ticks_msec() / 1000.0
	for l in _plane_lights:
		var on := true
		match l.kind:
			"beacon":
				on = fmod(now, 1.2) < 0.15
			"strobe":
				on = fmod(now + 0.4, 1.5) < 0.06
			"glow":
				(l.node as OmniLight3D).light_energy = 1.5 if fmod(now, 1.2) < 0.15 else 0.0
				continue
		(l.node as Node3D).visible = on
	if not _plane_engine:
		SoundSys.start_loop("aircraft", "plane_engine", pos)
		_plane_engine = true
	else:
		SoundSys.update_loop("aircraft", pos)


# ------------------------------------------------------------------ the haze (zone wall)'''),
])

# effects._process: drive the aircraft each frame.
s = open(G + 'src/fx/effects.gd', encoding='utf-8').read()
i = s.index('func _process(dt: float) -> void:\n')
j = i + len('func _process(dt: float) -> void:\n')
s = s[:j] + '\t_update_aircraft()\n' + s[j:]
open(G + 'src/fx/effects.gd', 'w', encoding='utf-8').write(s)
print('patched effects _process')
