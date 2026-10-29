"""r4: effects.gd uses pooled particles and the hole atlas; chunk and panel debris; explosion pooled."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/fx/effects.gd'
patch(f, '''const Attach := preload("res://src/weapons/attachments.gd")
const BLOOD := "res://assets/fx/blood/"''', '''const Attach := preload("res://src/weapons/attachments.gd")
const Destruct := preload("res://src/world/destruct.gd")
const Particles := preload("res://src/fx/particles.gd")
const Holes := preload("res://src/fx/holes.gd")
const BLOOD := "res://assets/fx/blood/"''')
patch(f, '''var _plane_engine := false
''', '''var _plane_engine := false
var particles = null
var holes = null
## Impact kind (from the ballistics material) -> particle kinds.
const IMPACT_FX := {
	"metal": ["sparks"], "wood": ["splinters", "sawdust"], "glass": ["shards"], "flesh": ["blood_mist", "blood"],
	"dirt": ["soil", "soil_dust"], "fabric": ["lint"], "plastic": ["chips", "lint"], "foliage": ["leaves"],
	"concrete": ["dust", "chips"],
}
''')
patch(f, '''func setup(w) -> void:
	world = w
	_rng.randomize()
	_hole_tex = _make_hole()''', '''func setup(w) -> void:
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
	# The map's loading warm-up camera looks at this spot for a few frames: draw every particle kind and a hole there
	# so their shaders compile behind the loading screen, not at the first shot.
	var warm := Transform3D(Basis(), Vector3(0, 400, -6))
	particles.warm(warm)
	holes.add_mark(warm.origin + Vector3(0.6, 0, 0), Vector3.BACK, 0, 0.3, 1.0)
	_hole_tex = _make_hole()''')
# shot: muzzle smoke
patch(f, '''	var bright := float(a.get("tracer_brightness", 0.5))
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(origin) > 220.0:
		return''', '''	var bright := float(a.get("tracer_brightness", 0.5))
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(origin) < 60.0:
		# A wisp of propellant smoke hangs at the muzzle (less from a suppressor).
		if not Attach.flag(w, "suppressed") or _rng.randf() < 0.4:
			particles.emit("muzzle", flash_pos + dir * 0.04, dir, 1.0 if not Attach.flag(w, "suppressed") else 0.5)
	if cam and cam.global_position.distance_to(origin) > 220.0:
		return''')
# impact
patch(f, '''func impact(pos: Vector3, normal: Vector3, kind: String, what: String) -> void:
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
''', '''func impact(pos: Vector3, normal: Vector3, kind: String, what: String, mat: String = "", att: int = 0) -> void:
	if what == "splash" or kind == "water":
		SoundSys.play_at("impact_water", pos, 0.0)
		particles.emit("splash", pos, Vector3.UP)
		particles.emit("mist", pos, Vector3.UP)
		return
	SoundSys.play_at("ricochet" if what == "ricochet" else "impact_" + kind, pos, 0.0)
	var cam := get_viewport().get_camera_3d()
	var near := cam == null or cam.global_position.distance_to(pos) < 150.0
	if near:
		for k in IMPACT_FX.get(kind, IMPACT_FX["concrete"]):
			particles.emit(k, pos, normal, 0.6 if what == "exit" else 1.0)
		if what == "ricochet" and kind != "metal":
			particles.emit("sparks", pos, normal, 0.5)
	if what in ["hole", "exit"] and kind not in ["flesh", "foliage", "water"]:
		holes.add(pos, normal, mat if mat != "" else kind, what == "exit", _attach(att))


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
''')
patch(f, '''func _burst(pos: Vector3, normal: Vector3, col: Color, n: int, speed: float, life: float, glow: bool = false) -> void:
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


''', '')
# body hits
patch(f, '''		SoundSys.play_at("impact_armor" if not armor_broken else "armor_break", pos, 0.0)
		_burst(pos, -dir, Color(0.4, 0.4, 0.4), 6, 2.0, 0.3)''', '''		SoundSys.play_at("impact_armor" if not armor_broken else "armor_break", pos, 0.0)
		particles.emit("chips", pos, -dir, 0.6)
		particles.emit("lint", pos, -dir, 0.6)''')
patch(f, '''	SoundSys.play_at("impact_flesh", pos, 0.0)
	_burst(pos, dir, Color(0.3, 0.015, 0.015), 10 + int(damage * 0.3), 3.0, 0.45)''', '''	SoundSys.play_at("impact_flesh", pos, 0.0)
	particles.emit("blood", pos, dir, clampf(0.4 + damage * 0.02, 0.4, 1.0))
	particles.emit("blood_mist", pos, dir)''')
# explosion
patch(f, '''	_burst(pos, Vector3.UP, Color(1.0, 0.7, 0.3), 26, 14.0, 0.45, true)
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
	get_tree().create_timer(3.0).timeout.connect(smoke.queue_free)''', '''	particles.emit("fire", pos + Vector3.UP * 0.3, Vector3.UP)
	particles.emit("sparks", pos + Vector3.UP * 0.1, Vector3.UP)
	particles.emit("blast_debris", pos + Vector3.UP * 0.1, Vector3.UP)
	particles.emit("smoke", pos + Vector3.UP * 0.5, Vector3.UP)
	particles.emit("chunk_dust", pos + Vector3.UP * 0.2, Vector3.UP)
	# A scorch mark where it went off.
	var q2 := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 2.0, Defs.PHYS_WORLD)
	var h := get_world_3d().direct_space_state.intersect_ray(q2)
	if not h.is_empty():
		holes.add_mark(h.position, h.normal, 14, _rng.randf_range(2.2, 2.8), 0.9)''')
# glass and props
patch(f, '''func glass_break(pos: Vector3, dir: Vector3, w: Dictionary) -> void:
	SoundSys.play_at("glass_break", pos, 0.0)
	var xf: Transform3D = w.xf''', '''func glass_break(pos: Vector3, dir: Vector3, w: Dictionary) -> void:
	SoundSys.play_at("glass_break", pos, 0.0)
	var xf: Transform3D = w.xf
	particles.emit("shards", xf.origin, dir)''')
patch(f, '''	var n := clampi(int(size.length() * 8.0), 4, 14)
	for i in n:''', '''	particles.emit("chunk_dust", pos + Vector3.UP * 0.2, Vector3.UP, clampf(size.length(), 0.4, 1.0))
	particles.emit("splinters" if mat_kind == "wood" else ("sparks" if mat_kind in ["steel", "sheet_metal"] else "chips"), pos + Vector3.UP * 0.2, Vector3.UP)
	var n := clampi(int(size.length() * 8.0), 4, 14)
	for i in n:''')
patch(f, '''func _debris_piece(pos: Vector3, vel: Vector3, size: Vector3, mat: Material) -> void:''', '''func chunk_lost(name: String, key: int, xf: Transform3D, box: AABB, impulse: Vector3, spec: Dictionary, body: Node3D) -> void:
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


func _debris_piece(pos: Vector3, vel: Vector3, size: Vector3, mat: Material) -> void:''')

# holes: clear marks inside a box (a chunk or panel that is gone); forget frees the set
f = 'src/fx/holes.gd'
patch(f, '''func forget(on: Node3D) -> void:
	## The object is gone (destroyed door, broken prop): its marks go with it.
	var ok: String = _obj_keys.get(on.get_instance_id(), "")
	if ok == "" or not _sets.has(ok):
		return''', '''func clear_box(on: Node3D, box: AABB) -> void:
	## Marks on `on` inside box (its own space) go: the chunk or panel they were on has been knocked off.
	if on == null:
		return
	var ok: String = _obj_keys.get(on.get_instance_id(), "")
	if ok == "" or not _sets.has(ok):
		return
	var s: Dictionary = _sets[ok]
	var mm: MultiMesh = s.mm
	var keep: Array = []
	for e in _order:
		if e[0] == ok and box.has_point(mm.get_instance_transform(int(e[1])).origin):
			_remove(e)
		else:
			keep.append(e)
	_order = keep


func forget(on: Node3D) -> void:
	## The object is gone (destroyed door, broken prop): its marks go with it.
	if on == null:
		return
	var ok: String = _obj_keys.get(on.get_instance_id(), "")
	if ok == "" or not _sets.has(ok):
		return
	if is_instance_valid(_sets[ok].node):
		_sets[ok].node.queue_free()''')
