extends Node
## Frag grenades (r14: cooked). Holding G pulls the pin and the fuse starts: the grenade stays in the hand, cooking,
## until G is let go, then it is thrown with what is left of the fuse (aim held: an underhand lob). Held past the
## fuse (4 s) it goes off in the hand. Going down or dying with the pin out drops it live at your feet.
##
## The grenade flies, bounces off walls and floors, rolls to a stop and explodes when its fuse runs out. The server
## simulates it and decides the damage; every client simulates the same flight for the visual and is told where it
## went off. Damage needs a clear line from the blast to the body (a wall or a closed door between them stops it):
## anyone within kill_radius_m (4 m) is killed outright, further out to radius_m (10 m) the damage falls off from
## very heavy to nothing. The killed are thrown through the air as ragdolls, harder the closer they were. The blast
## also throws loose props and bodies about, knocks the nearest panels out of a door further off, blows a door close
## by apart altogether, breaks glass, and bots who hear it come to look. Kills count for whoever threw it.
## (r22) A thrown grenade (not one dropped at the feet) is announced by a radio-distorted shout, "Fire in the hole!",
## in the thrower's own voice, heard by everyone within 38 m (sounds fire_hole_<voice>_<take>, tools/make_grenade_shout.py).

const BOUNCE := 0.35
const FRICTION := 0.55
const MASK := Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS | Defs.PHYS_PROJ_ONLY
const WRECK_R := 3.8          # a door this close to the blast (with a clear line) is blown apart
const SHOUT_VOICES := ["m1", "m2", "f1", "f2"]   # the voices of the bot radio (BotBrain.voice)
const SHOUT_TAKES := 2        # takes recorded per voice

var world = null
var live: Dictionary = {}     # id -> {p, v, t, rest, node, owner (eid of the thrower, server)}
var cooking: Dictionary = {}  # eid -> seconds since the pin was pulled (server)
var _next := 1
var _cooldown: Dictionary = {}  # eid -> seconds until the next throw


func setup(w) -> void:
	world = w
	name = "Grenades"


func clear_round() -> void:
	for g in live.values():
		if is_instance_valid(g.node):
			g.node.queue_free()
	live.clear()
	cooking.clear()
	_cooldown.clear()


func fuse_s() -> float:
	return float(Defs.item("frag_grenade").get("fuse_s", 4.0))


func is_cooking(ch) -> bool:
	return cooking.has(ch.eid)


func server_input(ch, btn: int, prev: int, dt: float) -> void:
	## Each tick of a character's command: G pressed pulls the pin, held cooks, released throws.
	var held := (btn & Motor.B_THROW) != 0
	if cooking.has(ch.eid):
		if ch.mode != Motor.GROUND or ch.held_prop_id >= 0:
			_release(ch, Vector3.ZERO)   # dropped at the feet, still live
			return
		cooking[ch.eid] = float(cooking[ch.eid]) + dt
		if float(cooking[ch.eid]) >= fuse_s():
			# Held too long: it goes off in the hand.
			var p: Vector3 = ch.eye_position() + ch.aim_dir() * 0.3 + Vector3.DOWN * 0.25
			cooking.erase(ch.eid)
			ch.flags &= ~Character.F_COOK
			var id := _spawn_live(p, Vector3.ZERO, 0.0, ch.eid)
			explode_server(id)
			return
		if not held:
			var underhand := (btn & Motor.B_AIM) != 0
			_release(ch, ch.aim_dir() * (9.0 if underhand else float(Defs.item("frag_grenade").get("throw_speed", 17.0))) \
				+ Vector3.UP * (3.4 if underhand else 2.5) + ch.velocity * 0.5)
		return
	if held and not (prev & Motor.B_THROW):
		_pull_pin(ch)


func _pull_pin(ch) -> void:
	if ch.mode != Motor.GROUND or float(_cooldown.get(ch.eid, 0.0)) > 0.0 or ch.held_prop_id >= 0:
		return
	if ch.inv == null or ch.inv.take("frag_grenade", 1) != 1:
		return
	cooking[ch.eid] = 0.0
	ch.flags |= Character.F_COOK
	ch.wpn.cancel_reload()
	world.server_sound("grenade_pin", ch.eye_position(), 0.0, -1)


func _release(ch, v: Vector3) -> void:
	## Lets go of the cooking grenade: thrown with velocity v, or dropped at the feet with v zero.
	var cooked := float(cooking.get(ch.eid, 0.0))
	cooking.erase(ch.eid)
	ch.flags &= ~Character.F_COOK
	_cooldown[ch.eid] = 0.8
	var fwd: Vector3 = ch.aim_dir()
	var p: Vector3 = ch.eye_position() + fwd * 0.35 + Vector3.DOWN * 0.1
	if v == Vector3.ZERO:
		p = ch.global_position + Vector3.UP * 0.4 + Vector3(fwd.x, 0, fwd.z).normalized() * 0.25
	else:
		world.server_sound("throw", ch.eye_position(), 0.0, -1)
		world.server_sound(_shout_id(ch), ch.eye_position(), 0.0, -1)   # (r22) "Fire in the hole!"
	_spawn_live(p, v, maxf(fuse_s() - cooked, 0.05), ch.eid)


func _shout_id(ch) -> String:
	## (r22) The sound id of the thrower's shout: a bot shouts in its own voice, a human in one fixed by their player id;
	## one of the takes at random.
	var voice: String = SHOUT_VOICES[absi(hash(ch.pid)) % SHOUT_VOICES.size()]
	if world.bots.has(ch.eid):
		var bv := str(world.bots[ch.eid].voice)
		if bv in SHOUT_VOICES:
			voice = bv
	return "fire_hole_%s_%d" % [voice, randi() % SHOUT_TAKES]


func server_throw(ch) -> void:
	## Without cooking (bots, tests): pin out and straight away thrown.
	_pull_pin(ch)
	if cooking.has(ch.eid):
		_release(ch, ch.aim_dir() * float(Defs.item("frag_grenade").get("throw_speed", 17.0)) + Vector3.UP * 2.5 + ch.velocity * 0.5)


func _spawn_live(p: Vector3, v: Vector3, fuse: float, owner: int = -1) -> int:
	var id := _next
	_next += 1
	world.ev_grenade.rpc(id, p, v, fuse)
	if not world.is_server_dedicated():
		spawn(id, p, v, fuse)
	else:
		live[id] = {"p": p, "v": v, "t": fuse, "rest": false, "node": null}
	live[id]["owner"] = owner
	return id


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
	live[id] = {"p": p, "v": v, "t": fuse, "rest": v == Vector3.ZERO and fuse <= 0.0, "node": node}


func _physics_process(dt: float) -> void:
	for eid in _cooldown.keys():
		_cooldown[eid] = float(_cooldown[eid]) - dt
		if float(_cooldown[eid]) <= 0.0:
			_cooldown.erase(eid)
	if world.is_server:
		for eid in cooking.keys():
			var c = world.characters.get(eid)
			if c == null or c.mode in [Motor.DEAD, Motor.SPECTATE, Motor.DOWNED]:
				# Killed or downed with the pin out: the grenade falls where they are.
				var left := maxf(fuse_s() - float(cooking[eid]), 0.6)
				cooking.erase(eid)
				if c != null:
					c.flags &= ~Character.F_COOK
					_spawn_live(c.global_position + Vector3.UP * 0.5, Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)), left, int(eid))
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
	var radius := float(d.get("radius_m", 10.0))
	var kill_r := float(d.get("kill_radius_m", 4.0))
	var dmg := float(d.get("damage", 260.0))
	var owner := int(g.get("owner", -1))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var bodies_before: Array = world.map.dyn.corpses.keys()   # those killed now are thrown by their own death
	for ch in world.characters.values():
		if ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			continue
		var chest: Vector3 = ch.global_position + Vector3.UP * (1.0 if ch.mode == Motor.GROUND else 0.35)
		var dist := chest.distance_to(pos)
		if dist > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.15, chest, Defs.PHYS_WORLD | Defs.PHYS_GLASS)
		q.exclude = [ch.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue  # a wall or closed door between the blast and the body
		var close := dist <= kill_r
		var amount := 999.0 if close else dmg * pow(1.0 - (dist - kill_r) / maxf(radius - kill_r, 0.1), 1.3)
		if amount < 1.0:
			continue
		# Close by: dead on the spot, not knocked down to be revived.
		ch.health.catastrophic = close
		var res: Dictionary = ch.health.apply_simple(amount, "explosion", "torso" if dist > 1.5 else ["torso", "leg_l", "leg_r"][int(dist * 7.0) % 3],
			owner if owner != ch.eid else -1)
		if not res.killed:
			ch.health.catastrophic = false
		if ch.health.downed and ch.mode == Motor.GROUND:
			res.downed = true
		# Thrown by the blast: away from it and up, much harder the closer it was (every part of the ragdoll gets the
		# speed, so a body flies and tumbles instead of slumping).
		var k := clampf(1.0 - dist / radius, 0.0, 1.0)
		var away := chest - pos
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		away = away.normalized()
		res.hit_dir = (away + Vector3.UP * 0.6).normalized()
		res.impulse = 3.0 + 9.0 * k
		res.blast_vel = away * (5.0 + 17.0 * k * k) + Vector3.UP * (3.0 + 9.0 * k)
		world.server_after_damage(ch, res, owner if owner != ch.eid else -1)
	world.map.server_blast(pos, radius * 0.75, dmg)
	_wreck_doors(pos, space)
	_push_bodies(pos, radius * 0.7, bodies_before)
	_break_glass(pos, radius * 0.6, space)
	for eid in world.bots:
		var b = world.bots[eid]
		b.hear(pos, 120.0)


func _wreck_doors(pos: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	## A door within WRECK_R of the blast, nothing solid between: blown out of its frame in pieces.
	var dyn = world.map.dyn
	for d in dyn.doors:
		var dn = d.get("node")
		if dn == null or dn.destroyed:
			continue
		var c: Vector3 = dn.center()
		var dist := c.distance_to(pos)
		if dist > WRECK_R:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, c, Defs.PHYS_WORLD)
		var r := space.intersect_ray(q)
		if not r.is_empty() and (r.position as Vector3).distance_to(c) > 0.35:
			continue  # something else is in the way (the hit is not on the leaf itself)
		world.server_door_blast(dn, pos, clampf(1.2 - dist / WRECK_R, 0.25, 1.0))


func _push_bodies(pos: Vector3, r: float, only: Array) -> void:
	## Bodies already lying about are thrown (the ragdoll runs on the server; clients follow it).
	for cid in only:
		if not world.map.dyn.corpses.has(cid):
			continue
		var c = world.map.dyn.corpses[cid]
		if c == null or not is_instance_valid(c) or not c.has_method("center"):
			continue
		var cc: Vector3 = c.center()
		var dist := cc.distance_to(pos)
		if dist > r or not ("bodies" in c) or c.bodies.is_empty():
			continue
		var k := 1.0 - dist / r
		var dir := (cc - pos + Vector3.UP * 0.8).normalized()
		for part in c.bodies:
			var rb = c.bodies[part]
			if rb is RigidBody3D and is_instance_valid(rb):
				(rb as RigidBody3D).linear_velocity += dir * (4.0 + 12.0 * k) * randf_range(0.85, 1.15)
				(rb as RigidBody3D).angular_velocity += Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0)) * k


func _break_glass(pos: Vector3, r: float, space: PhysicsDirectSpaceState3D) -> void:
	var dyn = world.map.dyn
	for w in dyn.windows:
		if w.get("broken", false) or w.has("door"):
			continue
		var c: Vector3 = (w.xf as Transform3D).origin
		var dist := c.distance_to(pos)
		if dist > r:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, c, Defs.PHYS_WORLD)
		if not space.intersect_ray(q).is_empty():
			continue
		var dir := (c - pos).normalized()
		if dyn.break_window(int(w.id), c, dir):
			world.map_window_broken.rpc(int(w.id), c, dir)
			if not world.is_server_dedicated() and world.effects:
				world.effects.glass_break(c, dir, w)


func explode_visual(id: int, pos: Vector3) -> void:
	var g: Dictionary = live.get(id, {})
	if g.has("node") and g.node:
		(g.node as Node3D).queue_free()
	live.erase(id)
	if world.effects:
		world.effects.explosion(pos)
	world.local_blast(pos)


func dispose() -> void:
	for id in live:
		if live[id].node:
			(live[id].node as Node3D).queue_free()
	live.clear()
	cooking.clear()
