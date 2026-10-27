"""Patch: the view model comes back after the plane, a handheld torch is visible when no weapon is drawn, plane and
zone timers use float seconds, and two missing sound ids get aliases."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/player/player_controller.gd', [(
    '''	if ch.mode == Motor.PLANE:
		_plane_camera(dt)
		return''',
    '''	if ch.mode == Motor.PLANE:
		_plane_camera(dt)
		return
	if vm and not vm.visible:
		vm.visible = true''')])

patch('src/match/match_server.gd', [
    ('	var t := (Net.tick - int(plane.t0)) / Defs.TICK_RATE\n',
     '	var t := float(Net.tick - int(plane.t0)) / Defs.TICK_RATE\n'),
    ('		var left := (int(zone.t1) - now) / Defs.TICK_RATE\n',
     '		var left := float(int(zone.t1) - now) / Defs.TICK_RATE\n'),
])

patch('src/player/viewmodel.gd', [
    ('''var hand_r: Node3D
var light: SpotLight3D''', '''var hand_r: Node3D
var torch_root: Node3D
var light: SpotLight3D'''),
    ('''	_build_smartab()
	light = SpotLight3D.new()''', '''	_build_smartab()
	_build_torch()
	light = SpotLight3D.new()'''),
    ('''func _build_smartab() -> void:''', '''func _build_torch() -> void:
	## Right hand holding the flashlight, shown when no weapon is drawn.
	torch_root = Node3D.new()
	add_child(torch_root)
	var hand := _hand(Color(0.36, 0.26, 0.2), Color(0.07, 0.07, 0.08))
	hand.position = Vector3(0, -0.035, 0.05)
	torch_root.add_child(hand)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.016
	cm.bottom_radius = 0.016
	cm.height = 0.16
	body.mesh = cm
	body.rotation = Vector3(PI * 0.5, 0, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.11)
	m.metallic = 0.6
	m.roughness = 0.45
	body.material_override = m
	torch_root.add_child(body)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.024
	hm.bottom_radius = 0.017
	hm.height = 0.045
	head.mesh = hm
	head.rotation = Vector3(PI * 0.5, 0, 0)
	head.position = Vector3(0, 0, -0.095)
	head.material_override = m
	torch_root.add_child(head)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.021
	lm.bottom_radius = 0.021
	lm.height = 0.004
	lens.mesh = lm
	lens.rotation = Vector3(PI * 0.5, 0, 0)
	lens.position = Vector3(0, 0, -0.119)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.9, 0.88, 0.8)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.95, 0.85)
	lmat.emission_energy_multiplier = 0.0
	lens.material_override = lmat
	lens.name = "Lens"
	torch_root.add_child(lens)
	torch_root.visible = false


func _build_smartab() -> void:'''),
    ('''	weapon_root.visible = wid != "" and ch.mode == Motor.GROUND and _lower < 0.98
	_flashlight(dt)''', '''	weapon_root.visible = wid != "" and ch.mode == Motor.GROUND and _lower < 0.98
	# Unarmed with a flashlight: it is held out in the right hand, lowered while the SmarTab is up.
	var has_torch: bool = ch.inv != null and ch.inv.gear.get("flashlight") != null
	torch_root.visible = wid == "" and has_torch and ch.mode == Motor.GROUND and _tab < 0.6
	if torch_root.visible:
		torch_root.position = Vector3(0.19, -0.2, -0.3) + bob + Vector3(0, -0.3 * ease(_tab, -2.0), 0)
		torch_root.rotation = Vector3(0.04, 0.03, 0)
		var lens_m := (torch_root.get_node("Lens") as MeshInstance3D).material_override as StandardMaterial3D
		lens_m.emission_energy_multiplier = 3.0 * ch.light.flicker(Time.get_ticks_msec() / 1000.0, ch.eid) if ch.light.on else 0.0
	_flashlight(dt)'''),
    ('''	else:
		light.position = Vector3(0.2, -0.2, -0.3)
		light.rotation = Vector3.ZERO''', '''	else:
		light.position = torch_root.position + Vector3(0, 0, -0.13)
		light.rotation = torch_root.rotation'''),
])
