"""r4: props lose chunks where they are hit; doors lose panels; holes and particles; network events and late join."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))

# ------------------------------------------------------------------ PhysicsProp: chunks
f = 'src/props/physics_prop.gd'
patch(f, '''extends RigidBody3D
## A movable prop that has been woken up (pushed, grabbed, shot or hit). Server: a real rigid body with mass,
## friction, impact sounds and damage-dependent breaking. Clients: a kinematic copy following snapshots.
''', '''extends RigidBody3D
## A movable prop that has been woken up (pushed, grabbed, shot or hit). Server: a real rigid body with mass,
## friction, impact sounds and damage-dependent breaking. Clients: a kinematic copy following snapshots.
## Furniture and crates break chunk by chunk (world/destruct.gd): a hit knocks out the chunk nearest the hit once
## that chunk has taken enough, its collision box goes with it (so a table shot through the legs drops), and the
## whole prop collapses when most of it is gone or its strength runs out.

const Destruct := preload("res://src/world/destruct.gd")
const CHUNK_KINDS := ["chair", "table", "crate", "sofa", "small", "heavy", "electronics", "tank", "appliance"]
''')
patch(f, '''var held_by := -1
''', '''var held_by := -1
var chunk_info: Dictionary = {}
var alive: Array = []          # chunk cells still on the prop
var _chunk_hp := {}
var _mi: MeshInstance3D = null
var _shapes: Array = []        # CollisionShape3D nodes
var _base_mass := 1.0
''')
patch(f, '''	hp = float(prop.get("health", s.get("hp", 100)))
	mass = maxf(float(s.get("mass", 5.0)), 0.2)''', '''	if _chunked(s):
		chunk_info = Destruct.chunks_for(d.models, str(prop.name))
		if chunk_info.is_empty() or (chunk_info.keys as Array).size() < 3:
			chunk_info = {}
	# Chunked props take more to bring down whole: they lose pieces on the way.
	hp = float(prop.get("health", float(s.get("hp", 100)) * (2.0 if not chunk_info.is_empty() else 1.0)))
	mass = maxf(float(s.get("mass", 5.0)), 0.2)
	_base_mass = mass''')
patch(f, '''	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = shape.size
	cs.shape = bs
	cs.position = shape.center
	add_child(cs)
	if DisplayServer.get_name() != "headless" and model.has("mesh"):
		var mi := MeshInstance3D.new()
		mi.mesh = model.mesh
		mi.position = model.get("offset", Vector3.ZERO)
		add_child(mi)''', '''	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = shape.size
	cs.shape = bs
	cs.position = shape.center
	add_child(cs)
	_shapes.append(cs)
	if DisplayServer.get_name() != "headless" and model.has("mesh"):
		var mi := MeshInstance3D.new()
		mi.mesh = model.mesh
		mi.position = model.get("offset", Vector3.ZERO)
		add_child(mi)
		_mi = mi
	if not chunk_info.is_empty():
		alive = (chunk_info.keys as Array).duplicate()
		var gone: Array = prop.get("lost", [])
		for k in gone:
			alive.erase(k)
		if not gone.is_empty():
			_rebuild_chunks()''')
patch(f, '''func take_damage(amount: float, impulse: Vector3) -> void:
	hp -= amount
	p.health = hp
	if hp <= 0.0:
		dyn.server_break_prop(int(p.id), impulse)
''', '''func _chunked(s: Dictionary) -> bool:
	return str(s.get("kind", "")) in CHUNK_KINDS and str(s.get("mat", "wood")) != "glass" and not s.get("no_block", false) \\
		and not s.get("glass", false)


func take_damage(amount: float, impulse: Vector3, at: Vector3 = Vector3.INF) -> void:
	hp -= amount
	p.health = hp
	if hp > 0.0 and not chunk_info.is_empty() and at != Vector3.INF and not alive.is_empty():
		var key := Destruct.nearest_chunk(chunk_info, alive, global_transform.affine_inverse() * at)
		if key >= 0:
			var per := float(spec.get("hp", 100)) * 1.2 / maxf((chunk_info.keys as Array).size(), 1.0)
			var left := float(_chunk_hp.get(key, per)) - amount
			_chunk_hp[key] = left
			if left <= 0.0:
				dyn.server_prop_chunk(int(p.id), key, impulse)
				if remaining() < 0.3:
					hp = 0.0
	if hp <= 0.0:
		dyn.server_break_prop(int(p.id), impulse)


func remaining() -> float:
	## Share of the model (by triangles) still on the prop.
	var r := 0.0
	for k in alive:
		r += float(chunk_info.volume.get(k, 0.0))
	return r


func lose_chunk(key: int) -> bool:
	## Server and clients: chunk `key` is knocked off. False if it was already gone.
	if chunk_info.is_empty() or not alive.has(key):
		return false
	alive.erase(key)
	var lost: Array = p.get("lost", [])
	lost.append(key)
	p.lost = lost
	_rebuild_chunks()
	if server:
		sleeping = false
	return true


func _rebuild_chunks() -> void:
	# Collision: one box per chunk still there (a chair shot through a leg tips over, a table without legs drops).
	for c in _shapes:
		remove_child(c)
		c.free()
	_shapes.clear()
	for k in alive:
		var b: AABB = chunk_info.chunks[k].aabb
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size.max(Vector3(0.04, 0.04, 0.04))
		cs.shape = bs
		cs.position = b.get_center()
		add_child(cs)
		_shapes.append(cs)
	mass = maxf(_base_mass * maxf(remaining(), 0.15), 0.2)
	if _mi:
		_mi.mesh = Destruct.build_mesh(chunk_info, alive)


func chunk_box(key: int) -> AABB:
	return chunk_info.chunks[key].aabb if chunk_info.chunks.has(key) else AABB()
''')
patch(f, '''	dyn.world.server_sound("impact_" + _impact_family(mat), global_position, clampf(linear_to_db(speed / 6.0), -18.0, 4.0), -1)
	take_damage(energy * 0.6, linear_velocity)''', '''	dyn.world.server_sound("impact_" + _impact_family(mat), global_position, clampf(linear_to_db(speed / 6.0), -18.0, 4.0), -1)
	take_damage(energy * 0.6, linear_velocity, global_position + linear_velocity.normalized() * 0.2)''')

# ------------------------------------------------------------------ Dynamics: chunk events
f = 'src/world/dynamics.gd'
patch(f, '''func _break_local(id: int) -> void:''', '''func server_prop_chunk(id: int, key: int, impulse: Vector3) -> void:
	world.map_prop_chunk.rpc(id, key, impulse)
	_chunk_local(id, key, impulse)


func client_prop_chunk(id: int, key: int, impulse: Vector3) -> void:
	if id < 0 or id >= props.size():
		return
	var p: Dictionary = props[id]
	if p.state == "broken":
		return
	if p.state != "active" or not (p.get("body") and is_instance_valid(p.body)):
		client_activate(id, p.xf)
	_chunk_local(id, key, impulse)


func client_prop_chunks(id: int, keys: PackedInt32Array) -> void:
	## Late join: the chunks this prop has already lost, without effects.
	if id < 0 or id >= props.size():
		return
	var p: Dictionary = props[id]
	var lost: Array = p.get("lost", [])
	for k in keys:
		if not lost.has(k):
			lost.append(k)
	p.lost = lost
	if p.get("body") and is_instance_valid(p.body):
		for k in keys:
			p.body.lose_chunk(k)


func _chunk_local(id: int, key: int, impulse: Vector3) -> void:
	var p: Dictionary = props[id]
	var body = p.get("body")
	if body == null or not is_instance_valid(body):
		return
	var xf: Transform3D = (body as Node3D).global_transform
	var box: AABB = body.chunk_box(key)
	if not body.lose_chunk(key):
		return
	if world.effects:
		world.effects.chunk_lost(str(p.name), key, xf, box, impulse, models.spec(str(p.name)), body)


func _break_local(id: int) -> void:''')
patch(f, '''	_hide_instance(p)
	if p.get("body") and is_instance_valid(p.body):
		p.body.queue_free()
	_active.erase(id)''', '''	_hide_instance(p)
	if p.get("body") and is_instance_valid(p.body):
		if world and world.effects:
			world.effects.holes.forget(p.body)
		p.body.queue_free()
	_active.erase(id)''')

# ------------------------------------------------------------------ MapBuilder: hits, explosions, late join
f = 'src/world/map_builder.gd'
patch(f, '''func server_prop_hit(prop_id: int, pos: Vector3, dir: Vector3, energy: float, momentum: float) -> void:
	var body = dyn.server_activate(prop_id)
	if body and is_instance_valid(body):
		body.apply_impulse(dir * minf(momentum * 6.0, 40.0), pos - body.global_position)
		body.take_damage(energy * 0.08, dir)
''', '''func server_prop_hit(prop_id: int, pos: Vector3, dir: Vector3, energy: float, momentum: float) -> void:
	var body = dyn.server_activate(prop_id)
	if body and is_instance_valid(body):
		body.apply_impulse(dir * minf(momentum * 6.0, 40.0), pos - body.global_position)
		body.take_damage(energy * 0.08, dir, pos)


func server_blast(pos: Vector3, radius: float, damage: float) -> void:
	## A grenade: loose props within the radius are thrown and knocked apart, doors and shutters lose panels, nearest
	## the blast first.
	var space := PhysicsServer3D.space_get_direct_state(dyn.space_rid)
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	q.shape = sph
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = Defs.PHYS_PROP | Defs.PHYS_WORLD | Defs.PHYS_PROJ_ONLY
	var seen := {}
	for r in space.intersect_shape(q, 96):
		var c = r.collider
		if c == null:
			continue
		if c.has_meta("prop_id"):
			var pid := int(c.get_meta("prop_id"))
			if seen.has("p%d" % pid):
				continue
			seen["p%d" % pid] = true
			var body = dyn.server_activate(pid)
			if body and is_instance_valid(body):
				var bp: Vector3 = body.global_position
				var k := clampf(1.0 - bp.distance_to(pos) / radius, 0.0, 1.0)
				body.apply_central_impulse((bp - pos + Vector3.UP * 0.5).normalized() * 9.0 * k * minf(body.mass, 30.0) * 0.4)
				for i in 3:
					if is_instance_valid(body):
						body.take_damage(damage * k * 0.9, (bp - pos).normalized(), bp.lerp(pos, 0.35))
		elif c.has_meta("door_id") or c.has_meta("shutter_id"):
			var key := str(c.get_instance_id())
			if seen.has(key):
				continue
			seen[key] = true
			var d = c
			if d.destroyed:
				continue
			for i in 4:
				var cc: Vector3 = d.center()
				var k2 := clampf(1.0 - cc.distance_to(pos) / radius, 0.0, 1.0)
				var pi: int = d.server_damage(cc.lerp(pos, 0.5), damage * k2 * 1.2)
				if pi >= 0:
					world.server_door_panel(d, pi, (cc - pos).normalized())
				if d.destroyed:
					break
''')
patch(f, '''	for p in dyn.props:
		if p.state == "broken":
			world.map_prop_break.rpc_id(pid, int(p.id), (p.xf as Transform3D).origin, Vector3.ZERO)
		elif p.state == "active":
			world.map_prop_activate.rpc_id(pid, int(p.id), (p.body as Node3D).global_transform if p.get("body") else p.xf)''', '''	for p in dyn.props:
		if p.state == "broken":
			world.map_prop_break.rpc_id(pid, int(p.id), (p.xf as Transform3D).origin, Vector3.ZERO)
		elif p.state == "active":
			world.map_prop_activate.rpc_id(pid, int(p.id), (p.body as Node3D).global_transform if p.get("body") else p.xf)
			if not (p.get("lost", []) as Array).is_empty():
				world.map_prop_chunks.rpc_id(pid, int(p.id), PackedInt32Array(p.lost))
	for d in dyn.doors:
		var dn2 = d.get("node")
		if dn2 and not dn2.lost.is_empty():
			world.map_door_panels.rpc_id(pid, int(d.id), false, PackedInt32Array(dn2.lost.keys()))
	for w2 in dyn.windows:
		if w2.has("door") and not w2.door.lost.is_empty():
			world.map_door_panels.rpc_id(pid, int(w2.id), true, PackedInt32Array(w2.door.lost.keys()))''')

# ------------------------------------------------------------------ World: RPCs and the door hit path
f = 'src/match/world.gd'
patch(f, '''@rpc("authority", "call_remote", "reliable")
func map_prop_break(id: int, pos: Vector3, impulse: Vector3) -> void:
	if map:
		map.dyn.client_break_prop(id, pos, impulse)
''', '''@rpc("authority", "call_remote", "reliable")
func map_prop_break(id: int, pos: Vector3, impulse: Vector3) -> void:
	if map:
		map.dyn.client_break_prop(id, pos, impulse)


@rpc("authority", "call_remote", "reliable")
func map_prop_chunk(id: int, key: int, impulse: Vector3) -> void:
	if map:
		map.dyn.client_prop_chunk(id, key, impulse)


@rpc("authority", "call_remote", "reliable")
func map_prop_chunks(id: int, keys: PackedInt32Array) -> void:
	if map:
		map.dyn.client_prop_chunks(id, keys)


func _door_by(did: int, is_shutter: bool):
	if map == null:
		return null
	if is_shutter:
		if did >= 0 and did < map.dyn.windows.size():
			return map.dyn.windows[did].get("door")
		return null
	if did >= 0 and did < map.dyn.doors.size():
		return map.dyn.doors[did].get("node")
	return null


func server_door_hit(door, pos: Vector3, dir: Vector3, energy: float) -> void:
	var i: int = door.server_damage(pos, energy * 0.08)
	if i >= 0:
		server_door_panel(door, i, dir)


func server_door_panel(door, i: int, dir: Vector3) -> void:
	map_door_panel.rpc(int(door.spec.id), door.is_shutter, i, dir)
	_door_panel_local(door, i, dir)


@rpc("authority", "call_remote", "reliable")
func map_door_panel(did: int, is_shutter: bool, i: int, dir: Vector3) -> void:
	var d = _door_by(did, is_shutter)
	if d:
		_door_panel_local(d, i, dir)


@rpc("authority", "call_remote", "reliable")
func map_door_panels(did: int, is_shutter: bool, panels: PackedInt32Array) -> void:
	## Late join: panels already shot out, without effects.
	var d = _door_by(did, is_shutter)
	if d:
		for i in panels:
			d.lose_panel(i)


func _door_panel_local(d, i: int, dir: Vector3) -> void:
	var xf: Transform3D = d.current_transform()
	var box: AABB = d.panel_box(i)
	var standing: Array = []
	var fell: bool = d.lose_panel(i)
	if fell:
		for j in d.panels().size():
			if not d.lost.has(j) or j == i:
				standing.append(d.panel_box(j))
	if effects:
		if d.anchor:
			effects.holes.clear_box(d.anchor, box.grow(0.03))
			if fell:
				effects.holes.forget(d.anchor)
		effects.door_panel_lost(d, xf, box, dir, standing)
''')
patch(f, '''func server_impact(pos: Vector3, normal: Vector3, kind: String, what: String, shooter: int, shot_id: int) -> void:
	_ev_impact.rpc(pos, normal, kind, what, shooter)
	if not is_server_dedicated():
		_ev_impact(pos, normal, kind, what, shooter)


@rpc("authority", "call_remote", "unreliable")
func _ev_impact(pos: Vector3, normal: Vector3, kind: String, what: String, shooter: int) -> void:
	if effects:
		effects.impact(pos, normal, kind, what)
''', '''func server_impact(pos: Vector3, normal: Vector3, kind: String, what: String, shooter: int, shot_id: int, mat: String = "", att: int = 0) -> void:
	## att: what the mark hangs on (1 << 24 | door, 2 << 24 | shutter, 3 << 24 | prop), 0 for the static world.
	_ev_impact.rpc(pos, normal, kind, what, shooter, mat, att)
	if not is_server_dedicated():
		_ev_impact(pos, normal, kind, what, shooter, mat, att)


@rpc("authority", "call_remote", "unreliable")
func _ev_impact(pos: Vector3, normal: Vector3, kind: String, what: String, shooter: int, mat: String = "", att: int = 0) -> void:
	if effects:
		effects.impact(pos, normal, kind, what, mat, att)
''')
patch(f, '''	map.server_corpse_hit(corpse_id, pos, dir)
	_ev_impact.rpc(pos, normal, "flesh", "hole", -1)
	if not is_server_dedicated():
		_ev_impact(pos, normal, "flesh", "hole", -1)''', '''	map.server_corpse_hit(corpse_id, pos, dir)
	_ev_impact.rpc(pos, normal, "flesh", "hole", -1, "flesh", 0)
	if not is_server_dedicated():
		_ev_impact(pos, normal, "flesh", "hole", -1, "flesh", 0)''')

# ------------------------------------------------------------------ projectiles: doors take damage; marks know what they hit
f = 'src/weapons/projectile_server.gd'
patch(f, '''		if col and col.has_meta("prop_id"):
			world.server_prop_hit(int(col.get_meta("prop_id")), hit_pos, dir, e, p.mass * speed)''', '''		if col and col.has_meta("prop_id"):
			world.server_prop_hit(int(col.get_meta("prop_id")), hit_pos, dir, e, p.mass * speed)
		if col and (col.has_meta("door_id") or col.has_meta("shutter_id")):
			world.server_door_hit(col, hit_pos, dir, e)
		var att := _attach_code(col)''')
patch(f, '''			world.server_impact(hit_pos, normal, str(mat.get("impact", "concrete")), "ricochet", p.shooter, p.id)''', '''			world.server_impact(hit_pos, normal, str(mat.get("impact", "concrete")), "ricochet", p.shooter, p.id, mat_id, att)''')
patch(f, '''		world.server_impact(hit_pos, normal, str(mat.get("impact", "concrete")), "hole", p.shooter, p.id)''', '''		world.server_impact(hit_pos, normal, str(mat.get("impact", "concrete")), "hole", p.shooter, p.id, mat_id, att)''')
patch(f, '''			world.server_impact(exit_pos, dir, str(mat.get("impact", "concrete")), "exit", p.shooter, p.id)''', '''			world.server_impact(exit_pos, dir, str(mat.get("impact", "concrete")), "exit", p.shooter, p.id, mat_id, att)''')
patch(f, '''func _test_characters(p: Dictionary, from: Vector3, to: Vector3, tick: int) -> Dictionary:''', '''static func _attach_code(col) -> int:
	## What a bullet mark should hang on so it moves with it: a door, a shutter or a loose prop (see World).
	if col == null:
		return 0
	if col.has_meta("door_id"):
		return (1 << 24) | int(col.get_meta("door_id"))
	if col.has_meta("shutter_id"):
		return (2 << 24) | int(col.get_meta("shutter_id"))
	if col.has_meta("prop_id"):
		return (3 << 24) | int(col.get_meta("prop_id"))
	return 0


func _test_characters(p: Dictionary, from: Vector3, to: Vector3, tick: int) -> Dictionary:''')

# ------------------------------------------------------------------ grenades: blast damage (and the old props loop never matched)
f = 'src/weapons/grenades.gd'
patch(f, '''	for body in world.map.awake_props_near(pos, radius):
		if body is RigidBody3D:
			body.apply_central_impulse((body.global_position - pos).normalized() * 6.0)''', '''	world.map.server_blast(pos, radius * 0.75, dmg)''')
