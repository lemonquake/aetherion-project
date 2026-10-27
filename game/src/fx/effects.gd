extends Node3D
## Client-side presentation of combat and destruction. Everything here is cosmetic and driven by events the server
## already decided: shots, impacts, hits, broken glass and props. Pools and caps keep long fights affordable.

const Attach := preload("res://src/weapons/attachments.gd")
const BLOOD := "res://assets/fx/blood/"
const MAX_DECALS := 220
const MAX_DEBRIS := 140
const MAX_TRACERS := 48

var world = null
var _decals: Array = []
var _debris: Array = []
var _tracers: Array = []    # {node, pos, vel, k, age, alive, bright}
var _hole_tex: Texture2D
var _blood_tex: Array = []
var _blood_nrm: Array = []
var _flash_pool: Array = []
var _zone_wall: MeshInstance3D
var _zone_mat: ShaderMaterial
var _space: PhysicsDirectSpaceState3D
var _rng := RandomNumberGenerator.new()
var _plane: Node3D
var _plane_lights: Array = []  # [{node, kind}]
var _plane_engine := false


func setup(w) -> void:
	world = w
	_rng.randomize()
	_hole_tex = _make_hole()
	for n in ["splat_a", "splat_b", "splat_c", "spatter_floor", "smear_wall"]:
		_blood_tex.append(load(BLOOD + n + "_albedo.png"))
		_blood_nrm.append(load(BLOOD + n + "_normal.png"))
	for i in 6:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.45)
		l.omni_range = 7.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_flash_pool.append({"light": l, "t": 0.0})
	for i in MAX_TRACERS:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.003
		cm.height = 1.0
		cm.radial_segments = 4
		cm.rings = 1
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.82, 0.55, 0.0)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append({"node": mi, "alive": false})
	_build_zone_wall()
	_build_aircraft()


func _make_hole() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
			var a := 0.0
			var c := Color(0.02, 0.02, 0.02)
			if d < 0.22:
				a = 1.0
			elif d < 0.6:
				a = (1.0 - (d - 0.22) / 0.38) * 0.75 * (0.6 + 0.4 * sin(atan2(y - n * 0.5, x - n * 0.5) * 7.0 + d * 9.0))
				c = Color(0.12, 0.11, 0.1)
			img.set_pixel(x, y, Color(c, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ shots

func shot(ch, origin: Vector3, dir: Vector3, velocity: float, ammo: String, weapon: String, seed: int, local: bool = false) -> void:
	var d := Defs.weapon(weapon)
	var a := Defs.ammo(ammo)
	# Muzzle devices on the shooter's gun (own gun: from the inventory; others: the replicated mask).
	var w: Dictionary = {}
	if ch != null and is_instance_valid(ch):
		w = ch.wpn.weapon() if local or ch.is_local else {"att": Attach.from_bitmask(ch.weapon_att)}
	var flash_pos := origin
	if local and world.controller and world.controller.vm:
		flash_pos = world.controller.vm.muzzle_position()
	_flash(flash_pos, Attach.mult(w, "flash_mult"))
	if world.ambience:
		world.ambience.on_loud(origin, float(d.get("loudness", 600)) * 0.25 * Attach.mult(w, "loudness_mult"))
	var snd := "shot_" + str(d.get("sound", "pistol_9"))
	if Attach.flag(w, "suppressed") and SoundSys.defs.has(snd + "_sup"):
		snd += "_sup"
	if local:
		SoundSys.play_at(snd, origin, 0.0, {"no_prop": true, "prio": 6, "delay": false})
	else:
		SoundSys.play_at(snd, origin, 0.0, {"prio": 6})
	if weapon in ["shotgun_pump", "bolt_308"]:
		var cyc := "pump_cycle" if weapon == "shotgun_pump" else "bolt_cycle"
		get_tree().create_timer(0.2).timeout.connect(func(): SoundSys.play_at(cyc, origin, 0.0, {"no_prop": local}))
	# Tracer: same initial conditions and integrator as the server, first pellet only.
	var bright := float(a.get("tracer_brightness", 0.5))
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(origin) > 220.0:
		return
	_spawn_tracer(flash_pos if local else origin, dir * velocity, float(a.get("drag_k", 0.001)), bright)


func _flash(p: Vector3, mult: float = 1.0) -> void:
	if mult < 0.15:
		return  # suppressed: no flash worth lighting a room with
	var reduce := bool(Settings.get_value("accessibility", "reduce_flashes"))
	for f in _flash_pool:
		if f.t <= 0.0:
			var l: OmniLight3D = f.light
			l.global_position = p
			l.light_energy = (2.2 if reduce else 5.0) * minf(mult, 1.3)
			l.visible = true
			f.t = 0.055
			return


func _spawn_tracer(pos: Vector3, vel: Vector3, k: float, bright: float) -> void:
	for t in _tracers:
		if not t.alive:
			t.alive = true
			t.pos = pos
			t.vel = vel
			t.k = k
			t.age = 0.0
			t.bright = bright
			t.node.visible = true
			return


func _process(dt: float) -> void:
	_update_aircraft()
	for f in _flash_pool:
		if f.t > 0.0:
			f.t -= dt
			if f.t <= 0.0:
				f.light.visible = false
	if _space == null:
		_space = get_world_3d().direct_space_state
	for t in _tracers:
		if not t.alive:
			continue
		var r := Ballistics.integrate(t.pos, t.vel, t.k, dt, 2)
		var np: Vector3 = r[0]
		var q := PhysicsRayQueryParameters3D.create(t.pos, np, Defs.SHOT_MASK)
		var hit := _space.intersect_ray(q)
		t.age += dt
		if not hit.is_empty() or t.age > 1.6:
			t.alive = false
			t.node.visible = false
			continue
		var speed := (r[1] as Vector3).length()
		# A short tail: about 25 ms of flight, never a laser beam across the map.
		var tail := clampf(speed * 0.025, 0.5, 22.0)
		var dir := (r[1] as Vector3) / maxf(speed, 1.0)
		var mid := np - dir * tail * 0.5
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var basis := Basis(dir.cross(up).normalized(), dir, dir.cross(dir.cross(up)).normalized() * -1.0)
		t.node.global_transform = Transform3D(basis.scaled(Vector3(1, tail, 1)), mid)
		var fade := clampf(1.0 - t.age / 0.5, 0.15, 1.0)
		(t.node.material_override as StandardMaterial3D).albedo_color.a = 0.55 * t.bright * fade
		t.pos = np
		t.vel = r[1]
	if _zone_wall:
		_update_zone(dt)


# ------------------------------------------------------------------ impacts

func impact(pos: Vector3, normal: Vector3, kind: String, what: String) -> void:
	if what == "splash" or kind == "water":
		SoundSys.play_at("impact_water", pos, 0.0)
		_burst(pos, normal, Color(0.5, 0.55, 0.55), 10, 2.5, 0.5)
		return
	SoundSys.play_at("ricochet" if what == "ricochet" else "impact_" + kind, pos, 0.0)
	match kind:
		"metal":
			_burst(pos, normal, Color(1.0, 0.75, 0.35), 8, 4.0, 0.25, true)
		"wood":
			_burst(pos, normal, Color(0.35, 0.26, 0.18), 7, 2.5, 0.6)
		"glass":
			_burst(pos, normal, Color(0.7, 0.8, 0.8), 6, 2.0, 0.6)
		"flesh":
			_burst(pos, normal, Color(0.35, 0.02, 0.02), 6, 1.8, 0.4)
		_:
			_burst(pos, normal, Color(0.45, 0.42, 0.38), 9, 2.0, 0.8)
	if kind in ["concrete", "wood", "metal", "dirt", "plastic"] and what != "ricochet":
		_decal(pos, normal, _hole_tex, null, Vector3(0.06, 0.06, 0.06), Color(1, 1, 1), null)


func _burst(pos: Vector3, normal: Vector3, col: Color, n: int, speed: float, life: float, glow: bool = false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = n
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.01
	p.scale_amount_max = 0.03
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = m
	p.mesh = mesh
	add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)


func _decal(pos: Vector3, normal: Vector3, tex: Texture2D, nrm: Texture2D, size: Vector3, mod: Color, parent: Node3D) -> Decal:
	var d: Decal
	if _decals.size() >= MAX_DECALS:
		d = _decals.pop_front()
		if not is_instance_valid(d):
			d = Decal.new()
	else:
		d = Decal.new()
	if d.get_parent():
		d.get_parent().remove_child(d)
	d.texture_albedo = tex
	d.texture_normal = nrm
	d.size = size
	d.modulate = mod
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	d.cull_mask = Defs.RENDER_WORLD | Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS
	(parent if parent else self).add_child(d)
	# Decals project along their local -Y: point that into the surface.
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	d.global_transform = Transform3D(Basis(x, up, z) * Basis(Vector3.UP, _rng.randf() * TAU), pos)
	_decals.append(d)
	return d


# ------------------------------------------------------------------ blood

func body_hit(ch, part: String, pos: Vector3, dir: Vector3, absorbed: String, armor_broken: bool, damage: float) -> void:
	if absorbed != "":
		SoundSys.play_at("impact_armor" if not armor_broken else "armor_break", pos, 0.0)
		_burst(pos, -dir, Color(0.4, 0.4, 0.4), 6, 2.0, 0.3)
		if not armor_broken:
			return
	SoundSys.play_at("impact_flesh", pos, 0.0)
	_burst(pos, dir, Color(0.3, 0.015, 0.015), 10 + int(damage * 0.3), 3.0, 0.45)
	if _space == null:
		_space = get_world_3d().direct_space_state
	# Spray onto whatever is behind the victim: wall, floor, furniture (stuck to it, moving with it).
	var q := PhysicsRayQueryParameters3D.create(pos, pos + dir.normalized() * 2.4 + Vector3.DOWN * 0.4, Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS)
	var hit := _space.intersect_ray(q)
	if not hit.is_empty():
		var i := _rng.randi_range(0, 2)
		var s := clampf(0.35 + damage * 0.012, 0.35, 1.1)
		var parent: Node3D = null
		if hit.collider is Node3D and hit.collider.has_meta("prop_id"):
			parent = hit.collider
		_decal(hit.position, hit.normal, _blood_tex[i], _blood_nrm[i], Vector3(s, 0.25, s), Color(0.55, 0.05, 0.04), parent)
	# Drops on the floor below.
	var q2 := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 2.5, Defs.PHYS_WORLD | Defs.PHYS_PROP)
	var h2 := _space.intersect_ray(q2)
	if not h2.is_empty():
		_decal(h2.position, h2.normal, _blood_tex[3], _blood_nrm[3], Vector3(0.5, 0.2, 0.5), Color(0.45, 0.04, 0.03), null)
	# On the body itself: a stain that follows the character.
	if ch and ch.visual:
		var dd := _decal(pos, -dir, _blood_tex[0], _blood_nrm[0], Vector3(0.22, 0.4, 0.22), Color(0.4, 0.03, 0.02), ch.visual)
		dd.cull_mask = Defs.RENDER_CHARACTERS | Defs.RENDER_LOCAL_BODY


func flyby(pos: Vector3, speed: float, dist: float) -> void:
	SoundSys.play_at("flyby_crack" if speed > 343.0 else "flyby_whiz", pos, -dist * 2.0, {"no_prop": true, "prio": 6})


# ------------------------------------------------------------------ glass and props

func explosion(pos: Vector3) -> void:
	## Frag grenade: a hard white-orange flash that lights the street or the room, sparks and a dust cloud.
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.4)
	l.omni_range = 16.0
	l.light_energy = 6.0 if bool(Settings.get_value("accessibility", "reduce_flashes")) else 14.0
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos + Vector3.UP * 0.6
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)
	_burst(pos, Vector3.UP, Color(1.0, 0.7, 0.3), 26, 14.0, 0.45, true)
	_burst(pos, Vector3.UP, Color(0.32, 0.3, 0.28), 18, 3.0, 1.6)
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.amount = 14
	smoke.lifetime = 2.4
	smoke.explosiveness = 0.9
	smoke.direction = Vector3.UP
	smoke.spread = 80.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 2.2
	smoke.gravity = Vector3(0, 0.25, 0)
	smoke.scale_amount_min = 0.9
	smoke.scale_amount_max = 1.8
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.28, 0.27, 0.25, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = sm
	smoke.mesh = q
	add_child(smoke)
	smoke.global_position = pos + Vector3.UP * 0.3
	smoke.emitting = true
	get_tree().create_timer(3.0).timeout.connect(smoke.queue_free)


func glass_break(pos: Vector3, dir: Vector3, w: Dictionary) -> void:
	SoundSys.play_at("glass_break", pos, 0.0)
	var xf: Transform3D = w.xf
	for i in 14:
		_debris_piece(xf * Vector3(_rng.randf_range(-0.4, 0.4) * float(w.w), _rng.randf_range(-0.4, 0.4) * float(w.h), 0),
			dir * _rng.randf_range(0.5, 2.5) + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0, 1), _rng.randf_range(-1, 1)),
			Vector3(_rng.randf_range(0.03, 0.12), 0.004, _rng.randf_range(0.03, 0.1)), world.map.mats.get_material("glass"))
	var q := PhysicsRayQueryParameters3D.create(xf.origin, xf.origin + Vector3.DOWN * 3.0, Defs.PHYS_WORLD)
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	if not h.is_empty():
		_decal(h.position, h.normal, _hole_tex, null, Vector3(0.9, 0.1, 0.9), Color(0.6, 0.7, 0.7, 0.5), null)


func prop_broken(name: String, pos: Vector3, impulse: Vector3, spec: Dictionary) -> void:
	var mat_kind := str(spec.get("mat", "wood"))
	SoundSys.play_at("break_" + ("glass" if mat_kind == "glass" else ("plastic" if mat_kind == "plastic" else ("metal" if mat_kind in ["steel", "sheet_metal"] else "wood"))), pos, 0.0)
	var md: Dictionary = world.map.models.get_model(name)
	var size: Vector3 = (md.aabb as AABB).size if md.has("aabb") else Vector3(0.4, 0.4, 0.4)
	var mat: Material = world.map.mats.get_material("glass" if mat_kind == "glass" else ("planks" if mat_kind == "wood" else "plywood"))
	var n := clampi(int(size.length() * 8.0), 4, 14)
	for i in n:
		var piece := Vector3(_rng.randf_range(0.05, 0.4), _rng.randf_range(0.02, 0.08), _rng.randf_range(0.05, 0.3)) * minf(size.length(), 1.2)
		_debris_piece(pos + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0.0, 0.5), _rng.randf_range(-0.3, 0.3)) * size.length(),
			impulse.normalized() * _rng.randf_range(0.5, 3.0) + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1, 1)), piece, mat)


func _debris_piece(pos: Vector3, vel: Vector3, size: Vector3, mat: Material) -> void:
	## Cosmetic debris: collides with the world but never with characters. The oldest piece freezes in place
	## when the cap is reached, so the aftermath stays visible without costing simulation.
	var rb := RigidBody3D.new()
	rb.collision_layer = Defs.PHYS_DEBRIS
	rb.collision_mask = Defs.PHYS_WORLD | Defs.PHYS_PROP
	rb.mass = 0.2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	rb.add_child(mi)
	add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
	_debris.append(rb)
	if _debris.size() > MAX_DEBRIS:
		var old: RigidBody3D = _debris.pop_front()
		if is_instance_valid(old):
			old.freeze = true


# ------------------------------------------------------------------ the transport aircraft

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
	var show = not pl.is_empty() and info.get("phase", "") in ["plane", "playing"]
	if show:
		var k := (t - float(pl.t0)) / Defs.TICK_RATE / float(pl.dur)
		show = k < 1.05
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
	var k2 := maxf((t - float(pl.t0)) / Defs.TICK_RATE / float(pl.dur), 0.0)
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


# ------------------------------------------------------------------ the haze (zone wall)

func _build_zone_wall() -> void:
	_zone_wall = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 96
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_zone_wall.mesh = cm
	_zone_mat = ShaderMaterial.new()
	_zone_mat.shader = preload("res://src/fx/haze_wall.gdshader")
	_zone_wall.material_override = _zone_mat
	_zone_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone_wall.visible = false
	add_child(_zone_wall)


func on_match_state(info: Dictionary) -> void:
	_zone_wall.visible = not info.get("zone", {}).is_empty()


func _update_zone(dt: float) -> void:
	if not _zone_wall.visible:
		return
	var circ: Array = world.zone_circle(Net.interp_tick() if not world.is_server else float(Net.tick))
	var c: Vector2 = circ[0]
	var r: float = circ[1]
	if r > 4000.0:
		_zone_wall.visible = false
		return
	_zone_wall.position = Vector3(c.x, 60.0, c.y)
	_zone_wall.scale = Vector3(r, 160.0, r)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := Vector2(cam.global_position.x, cam.global_position.z).distance_to(c)
		_zone_mat.set_shader_parameter("outside", 1.0 if d > r else 0.0)

