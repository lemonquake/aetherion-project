extends Node
## Frag grenades: G throws one from the bag (no need to put the gun away). The grenade flies, bounces off walls and
## floors, rolls to a stop and explodes 4 s after the pin was pulled. The server simulates it and decides the
## damage; every client simulates the same flight for the visual and is told where it went off.
##
## Damage falls off with distance and needs a clear line from the blast to the body: a wall or a closed door between
## them stops it. Loose props are thrown about and bots who hear it come to look.

const BOUNCE := 0.35
const FRICTION := 0.55
const MASK := Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS | Defs.PHYS_PROJ_ONLY

var world = null
var live: Dictionary = {}     # id -> {p, v, t, rest, node}
var _next := 1
var _cooldown: Dictionary = {}  # eid -> seconds until the next throw


func setup(w) -> void:
	world = w
	name = "Grenades"


func server_throw(ch) -> void:
	if ch.mode != Motor.GROUND or float(_cooldown.get(ch.eid, 0.0)) > 0.0 or ch.held_prop_id >= 0:
		return
	if ch.inv == null or ch.inv.take("frag_grenade", 1) != 1:
		return
	var d := Defs.item("frag_grenade")
	_cooldown[ch.eid] = 1.2
	var fwd: Vector3 = ch.aim_dir()
	var p: Vector3 = ch.eye_position() + fwd * 0.35 + Vector3.DOWN * 0.1
	var v: Vector3 = fwd * float(d.get("throw_speed", 17.0)) + Vector3.UP * 2.5 + ch.velocity * 0.5
	var id := _next
	_next += 1
	world.server_sound("grenade_pin", ch.eye_position(), 0.0, -1)
	world.server_sound("throw", ch.eye_position(), 0.0, -1)
	world.ev_grenade.rpc(id, p, v, float(d.get("fuse_s", 4.0)))
	if not world.is_server_dedicated():
		spawn(id, p, v, float(d.get("fuse_s", 4.0)))
	else:
		live[id] = {"p": p, "v": v, "t": float(d.get("fuse_s", 4.0)), "rest": false, "node": null}


func spawn(id: int, p: Vector3, v: Vector3, fuse: float) -> void:
	var node: Node3D = null
	if DisplayServer.get_name() != "headless":
		var md: Dictionary = world.map.item_visual("frag_grenade")
		if md.get("mesh") != null:
			var mi := MeshInstance3D.new()
			mi.mesh = md.mesh
			mi.transform = md.get("xf", Transform3D())
			mi.layers = Defs.RENDER_WORLD
			node = Node3D.new()
			node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			node.add_child(mi)
			add_child(node)
			node.global_position = p
	live[id] = {"p": p, "v": v, "t": fuse, "rest": false, "node": node}


func _physics_process(dt: float) -> void:
	for eid in _cooldown.keys():
		_cooldown[eid] = float(_cooldown[eid]) - dt
		if float(_cooldown[eid]) <= 0.0:
			_cooldown.erase(eid)
	if live.is_empty():
		return
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for id in live.keys():
		var g: Dictionary = live[id]
		g.t = float(g.t) - dt
		if not g.rest:
			_fly(g, dt, space)
		if g.node:
			(g.node as Node3D).global_position = g.p
			if not g.rest:
				(g.node as Node3D).rotate_x(dt * 9.0)
		if world.is_server and float(g.t) <= 0.0:
			explode_server(id)


func _fly(g: Dictionary, dt: float, space: PhysicsDirectSpaceState3D) -> void:
	var v: Vector3 = g.v
	v.y -= 9.81 * dt
	var p: Vector3 = g.p
	var to := p + v * dt
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, to, MASK))
	if r.is_empty():
		g.p = to
		g.v = v
		return
	var n: Vector3 = r.normal
	var vn := n * v.dot(n)
	var vt := v - vn
	v = vt * (1.0 - FRICTION * (0.5 if n.y > 0.7 else 0.2)) - vn * BOUNCE
	g.p = (r.position as Vector3) + n * 0.04
	g.v = v
	if n.y > 0.7 and v.length() < 0.6:
		g.rest = true
		g.v = Vector3.ZERO
	elif v.length() > 2.0 and world.is_server:
		world.server_sound("impact_metal_light", g.p, -8.0, -1)


func explode_server(id: int) -> void:
	var g: Dictionary = live.get(id, {})
	if g.is_empty():
		return
	var pos: Vector3 = g.p
	world.ev_explode.rpc(id, pos)
	if not world.is_server_dedicated():
		explode_visual(id, pos)
	else:
		live.erase(id)
	world.server_sound("explosion", pos, 0.0, -1)
	var d := Defs.item("frag_grenade")
	var radius := float(d.get("radius_m", 9.0))
	var dmg := float(d.get("damage", 130.0))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for ch in world.characters.values():
		if ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			continue
		var chest: Vector3 = ch.global_position + Vector3.UP * 1.0
		var dist := chest.distance_to(pos)
		if dist > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.15, chest, Defs.PHYS_WORLD | Defs.PHYS_GLASS)
		q.exclude = [ch.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue  # a wall or closed door between the blast and the body
		var amount := dmg * pow(1.0 - dist / radius, 1.6)
		if amount < 1.0:
			continue
		var res: Dictionary = ch.health.apply_simple(amount, "explosion", "torso" if dist > 1.5 else ["torso", "leg_l", "leg_r"][int(dist * 7.0) % 3])
		if ch.health.downed and ch.mode == Motor.GROUND:
			res.downed = true
		world.server_after_damage(ch, res, -1)
	for body in world.map.awake_props_near(pos, radius):
		if body is RigidBody3D:
			body.apply_central_impulse((body.global_position - pos).normalized() * 6.0)
	for eid in world.bots:
		var b = world.bots[eid]
		b.hear(pos, 120.0)


func explode_visual(id: int, pos: Vector3) -> void:
	var g: Dictionary = live.get(id, {})
	if g.has("node") and g.node:
		(g.node as Node3D).queue_free()
	live.erase(id)
	if world.effects:
		world.effects.explosion(pos)


func dispose() -> void:
	for id in live:
		if live[id].node:
			(live[id].node as Node3D).queue_free()
	live.clear()
