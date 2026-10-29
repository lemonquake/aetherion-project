extends Node3D
## Client-side presentation of combat and destruction. Everything here is cosmetic and driven by events the server
## already decided: shots, impacts, hits, broken glass and props. Pools and caps keep long fights affordable.

const Attach := preload("res://src/weapons/attachments.gd")
const Destruct := preload("res://src/world/destruct.gd")
const Particles := preload("res://src/fx/particles.gd")
const Holes := preload("res://src/fx/holes.gd")
const Blood := preload("res://src/fx/blood.gd")
const Anims := preload("res://src/player/weapon_anims.gd")
const GunModel := preload("res://src/weapons/gun_model.gd")
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
var particles = null
var holes = null
var blood = null
## Ballistics material -> its own impact sound where it has one (otherwise "impact_" + the material's impact kind).
const MAT_SOUND := {"sheet_metal": "impact_metal_sheet", "steel": "impact_metal", "tile": "impact_tile"}
## Impact kind (from the ballistics material) -> particle kinds.
const IMPACT_FX := {
	"metal": ["sparks"], "wood": ["splinters", "sawdust"], "glass": ["shards"], "flesh": ["blood_mist", "blood"],
	"dirt": ["soil", "soil_dust"], "fabric": ["lint"], "plastic": ["chips", "lint"], "foliage": ["leaves"],
	"concrete": ["dust", "chips"],
}


func setup(w) -> void:
	world = w
	_rng.randomize()
	particles = Particles.new()
	particles.name = "Particles"
	add_child(particles)
	particles.setup()
	holes = Holes.new()
	holes.name = "Holes"
	add_child(holes)
	holes.setup()
	blood = Blood.new()
	blood.name = "Blood"
	blood.world = w
	add_child(blood)
	blood.setup()
	# The map's loading warm-up camera looks at this spot for a few frames: draw every particle kind and a hole there
	# so their shaders compile behind the loading screen, not at the first shot.
	var warm := Transform3D(Basis(), Vector3(0, 400, -6))
	particles.warm(warm)
	holes.add_mark(warm.origin + Vector3(0.6, 0, 0), Vector3.BACK, 0, 0.3, 1.0)
	blood.add_mark(warm.origin + Vector3(-0.6, 0, 0), Vector3.BACK, 0, 0.3, 1.0)
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
	# Tracer: same initial conditions and integrator as the server, first pellet only.
	var bright := float(a.get("tracer_brightness", 0.5))
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(origin) < 25.0 and weapon not in ["revolver_357", "shotgun_double", "sumpak"]:
		# The spent case flies out to the right and tinkles on the ground a moment later.
		var right := dir.cross(Vector3.UP).normalized()
		var eject := (flash_pos - dir * (0.32 if local else 0.42)) + right * 0.04 + Vector3.UP * 0.02
		particles.emit("casing", eject, (right * 1.0 + Vector3.UP * 0.7 - dir * 0.2).normalized())
		var floor_at := eject + Vector3.DOWN * 1.3 + right * 0.6
		var case_snd := "shell_drop" if str(d.get("class", "")) == "shotgun" else "casing_drop"
		get_tree().create_timer(0.42 + _rng.randf() * 0.12).timeout.connect(func(): SoundSys.play_at(case_snd, floor_at, 0.0, {"prio": 1}))
	if cam and cam.global_position.distance_to(origin) < 60.0:
		# A wisp of propellant smoke hangs at the muzzle (less from a suppressor).
		if not Attach.flag(w, "suppressed") or _rng.randf() < 0.4:
			particles.emit("muzzle", flash_pos + dir * 0.04, dir, 1.0 if not Attach.flag(w, "suppressed") else 0.5)
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
	var bcam := get_viewport().get_camera_3d()
	blood.update(dt, world.characters, bcam.global_position if bcam else Vector3.ZERO)
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

func impact(pos: Vector3, normal: Vector3, kind: String, what: String, mat: String = "", att: int = 0) -> void:
	if what == "splash" or kind == "water":
		SoundSys.play_at("impact_water", pos, 0.0)
		particles.emit("splash", pos, Vector3.UP)
		particles.emit("mist", pos, Vector3.UP)
		return
	var snd: String = MAT_SOUND.get(mat, "impact_" + kind)
	if not SoundSys.has_sound(snd):
		snd = "impact_" + kind
	SoundSys.play_at("ricochet" if what == "ricochet" else snd, pos, 0.0)
	var cam := get_viewport().get_camera_3d()
	var near := cam == null or cam.global_position.distance_to(pos) < 150.0
	if near:
		for k in IMPACT_FX.get(kind, IMPACT_FX["concrete"]):
			particles.emit(k, pos, normal, 0.6 if what == "exit" else 1.0)
		if what == "ricochet" and kind != "metal":
			particles.emit("sparks", pos, normal, 0.5)
	if what in ["hole", "exit"] and kind not in ["flesh", "foliage", "water"]:
		holes.add(pos, normal, mat if mat != "" else kind, what == "exit", _attach(att))
	if kind == "flesh" and near:
		# A dead body shot again (World.server_corpse_hit sends the round's reversed direction as the normal).
		blood.corpse_hit(pos, -normal)


func _attach(att: int) -> Node3D:
	## The moving thing a mark hangs on (World.server_impact encodes it), or null for the static world.
	if att == 0 or world.map == null:
		return null
	var id := att & 0xFFFFFF
	var dyn = world.map.dyn
	match att >> 24:
		1:
			if id < dyn.doors.size():
				var d = dyn.doors[id].get("node")
				if d and not d.destroyed:
					return d.anchor_node()
		2:
			if id < dyn.windows.size():
				var s = dyn.windows[id].get("door")
				if s and not s.destroyed:
					return s.anchor_node()
		3:
			if id < dyn.props.size():
				var b = dyn.props[id].get("body")
				if b and is_instance_valid(b):
					return b
	return null


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
		SoundSys.play_at(("impact_helmet" if part == "head" else "impact_armor") if not armor_broken else "armor_break", pos, 0.0)
		particles.emit("chips", pos, -dir, 0.6)
		particles.emit("lint", pos, -dir, 0.6)
		if not armor_broken:
			return
	SoundSys.play_at("impact_flesh_head" if part == "head" else "impact_flesh", pos, 0.0)
	particles.emit("blood", pos, dir, clampf(0.4 + damage * 0.02, 0.4, 1.0))
	particles.emit("blood_mist", pos, dir)
	# Spatter on the walls, floor and furniture around them, drops where they stand, then a drip trail.
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(pos) < 120.0:
		var power := clampf(damage / 55.0 + (0.3 if part == "head" else 0.0), 0.15, 1.0)
		blood.shot_through(pos, dir, power, [ch.get_rid()] if ch and is_instance_valid(ch) else [], ch.eid if ch and is_instance_valid(ch) else -1)
	# On the body itself: a stain that follows the character.
	if ch and ch.visual:
		var dd := _decal(pos, -dir, _blood_tex[0], _blood_nrm[0], Vector3(0.22, 0.4, 0.22), Color(0.4, 0.03, 0.02), ch.visual)
		dd.cull_mask = Defs.RENDER_CHARACTERS | Defs.RENDER_LOCAL_BODY


func body_fell(c) -> void:
	## A body going down: the thump when it reaches the ground, about half a second after the ragdoll starts.
	var cid: int = c.get_instance_id()
	get_tree().create_timer(0.45).timeout.connect(func():
		var body = instance_from_id(cid)
		if body != null:
			SoundSys.play_at("bodyfall", body.center(), 0.0, {"prio": 5}))


func gun_cues(ch, wid: String, phase: int, empty: bool, dur: float) -> void:
	## Another character's reload step or worked action (World._reload_sounds): its sounds at the times the hands
	## would make them, from wherever the character is by then.
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(ch.global_position) > 45.0:
		return
	var name := Anims.clip_name(wid, phase, GunModel.parts(wid))
	var oid: int = ch.get_instance_id()
	for c in Anims.cues(name, empty, wid):
		var id := str(c[1])
		get_tree().create_timer(float(c[0]) * dur).timeout.connect(func():
			var who = instance_from_id(oid)
			if who != null and who.mode in [Motor.GROUND, Motor.DOWNED]:
				SoundSys.play_at(id, who.global_position + Vector3.UP * 1.15, 0.0, {"prio": 4}))


func flyby(pos: Vector3, speed: float, dist: float) -> void:
	SoundSys.play_at("flyby_crack" if speed > 343.0 else "flyby_whiz", pos, -dist * 2.0, {"no_prop": true, "prio": 6})
	# Suppression: a round cracking past within a couple of metres darkens the edges of the view and jolts it.
	if dist < 2.2 and world.hud and world.hud.has_method("suppress"):
		world.hud.suppress(clampf(1.0 - dist / 2.2, 0.2, 1.0) * (1.0 if speed > 343.0 else 0.6))
		if world.controller and world.controller.has_method("on_suppressed"):
			world.controller.on_suppressed(dist)


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
	particles.emit("fire", pos + Vector3.UP * 0.3, Vector3.UP)
	particles.emit("sparks", pos + Vector3.UP * 0.1, Vector3.UP)
	particles.emit("blast_debris", pos + Vector3.UP * 0.1, Vector3.UP)
	particles.emit("smoke", pos + Vector3.UP * 0.5, Vector3.UP)
	particles.emit("chunk_dust", pos + Vector3.UP * 0.2, Vector3.UP)
	# A scorch mark where it went off.
	var q2 := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 2.0, Defs.PHYS_WORLD)
	var h := get_world_3d().direct_space_state.intersect_ray(q2)
	if not h.is_empty():
		holes.add_mark(h.position, h.normal, 14, _rng.randf_range(2.2, 2.8), 0.9)


func glass_break(pos: Vector3, dir: Vector3, w: Dictionary) -> void:
	SoundSys.play_at("glass_break", pos, 0.0)
	var xf: Transform3D = w.xf
	particles.emit("shards", xf.origin, dir)
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
	particles.emit("chunk_dust", pos + Vector3.UP * 0.2, Vector3.UP, clampf(size.length(), 0.4, 1.0))
	particles.emit("splinters" if mat_kind == "wood" else ("sparks" if mat_kind in ["steel", "sheet_metal"] else "chips"), pos + Vector3.UP * 0.2, Vector3.UP)
	var n := clampi(int(size.length() * 8.0), 4, 14)
	for i in n:
		var piece := Vector3(_rng.randf_range(0.05, 0.4), _rng.randf_range(0.02, 0.08), _rng.randf_range(0.05, 0.3)) * minf(size.length(), 1.2)
		_debris_piece(pos + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0.0, 0.5), _rng.randf_range(-0.3, 0.3)) * size.length(),
			impulse.normalized() * _rng.randf_range(0.5, 3.0) + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1, 1)), piece, mat)


func chunk_lost(name: String, key: int, xf: Transform3D, box: AABB, impulse: Vector3, spec: Dictionary, body: Node3D) -> void:
	## A chunk knocked off a prop: the real piece of the model falls away, with dust and splinters.
	var info := Destruct.chunks_for(world.map.models, name)
	if info.is_empty():
		return
	var mat_kind := str(spec.get("mat", "wood"))
	var c := xf * box.get_center()
	var dir := impulse.normalized() if impulse.length() > 0.01 else Vector3.UP
	if body and is_instance_valid(body):
		holes.clear_box(body, box.grow(0.04))
	_debris_mesh(xf * Transform3D(Basis(), box.get_center()), Destruct.chunk_mesh(info, key), info.offset - box.get_center(), box.size,
		dir * _rng.randf_range(1.0, 3.0) + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.5, 1.6), _rng.randf_range(-0.6, 0.6)))
	particles.emit("chunk_dust", c, -dir, 0.45)
	particles.emit("splinters" if mat_kind == "wood" else ("sparks" if mat_kind in ["steel", "sheet_metal"] else "chips"), c, dir)
	var fam := "wood" if mat_kind == "wood" else ("plastic" if mat_kind in ["plastic", "fabric"] else ("metal" if mat_kind in ["steel", "sheet_metal"] else "wood"))
	SoundSys.play_at("break_" + fam, c, -7.0)


func door_panel_lost(d, xf: Transform3D, box: AABB, dir: Vector3, fell_boxes: Array) -> void:
	## A panel shot out of a door or shutter flies off; if the leaf came down, what was left of it falls too.
	var mname: String = "planks_paint" if d.is_shutter else str(d.spec.get("mat", "plywood"))
	var metal := mname.contains("metal") or mname.contains("steel")
	var m: Material = world.map.mats.get_material(mname)
	var c := xf * box.get_center()
	_debris_box(xf * Transform3D(Basis(), box.get_center()), box.size, m, dir * _rng.randf_range(1.5, 3.5) + Vector3(0, _rng.randf_range(0.3, 1.2), 0))
	particles.emit("sparks" if metal else "splinters", c, dir)
	particles.emit("sawdust" if not metal else "dust", c, dir, 0.6)
	SoundSys.play_at("break_metal" if metal else "break_wood", c, -6.0)
	if fell_boxes.is_empty():
		return
	for b in fell_boxes:
		_debris_box(xf * Transform3D(Basis(), (b as AABB).get_center()), (b as AABB).size, m, dir * _rng.randf_range(0.5, 1.5) + Vector3(0, 0.3, 0))
	particles.emit("chunk_dust", xf * Vector3(float(d.w) * 0.5, 0.6, 0), Vector3.UP)
	SoundSys.play_at("door_burst", c, 0.0)


func _debris_box(xf: Transform3D, size: Vector3, mat: Material, vel: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	_debris_mesh(xf, bm, Vector3.ZERO, size, vel)


func _debris_mesh(xf: Transform3D, mesh: Mesh, mesh_offset: Vector3, size: Vector3, vel: Vector3) -> void:
	## A piece of something broken, with its own shape: collides with the world but never with characters. Over the
	## cap the oldest piece freezes where it lies.
	var rb := RigidBody3D.new()
	rb.collision_layer = Defs.PHYS_DEBRIS
	rb.collision_mask = Defs.PHYS_WORLD | Defs.PHYS_PROP
	rb.mass = clampf(size.x * size.y * size.z * 600.0, 0.2, 12.0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size.max(Vector3(0.03, 0.03, 0.03))
	cs.shape = bs
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = mesh_offset
	rb.add_child(mi)
	add_child(rb)
	rb.global_transform = xf
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5), _rng.randf_range(-5, 5))
	_debris.append(rb)
	if _debris.size() > MAX_DEBRIS:
		var old: RigidBody3D = _debris.pop_front()
		if is_instance_valid(old):
			old.freeze = true


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

