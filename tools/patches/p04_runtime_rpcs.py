"""Patch: container lookup grid, corpses, glass breaking, map facade, and the World RPC endpoints for map events,
match state, inventory requests and containers."""
G = 'A:/Python/aetherion-project/game/'


def sub(path, old, new, count=1):
    s = open(G + path, encoding='utf-8').read()
    if old not in s:
        raise SystemExit(f'pattern not found in {path}: {old[:70]!r}')
    s = s.replace(old, new, count)
    open(G + path, 'w', encoding='utf-8').write(s)


def append(path, text):
    s = open(G + path, encoding='utf-8').read()
    open(G + path, 'w', encoding='utf-8').write(s.rstrip('\n') + '\n' + text)


# ---------------------------------------------------------------- dynamics
sub('src/world/dynamics.gd', '''func add_container(pos: Vector3, table: String, bid: int, size: Vector3 = Vector3(0.5, 0.5, 0.5)) -> int:
	var id := containers.size()
	containers.append({"id": id, "pos": pos, "table": table, "bid": bid, "entries": [], "size": size, "searched": false})
	return id''', '''func add_container(pos: Vector3, table: String, bid: int, size: Vector3 = Vector3(0.5, 0.5, 0.5)) -> int:
	var id := containers.size()
	var snd := "search_drawer"
	if table in ["store_shelf", "trash", "crate", "military_crate"]:
		snd = "search_box"
	elif table in ["wardrobe", "weapon_locker", "clinic", "toolbox"]:
		snd = "search_cabinet"
	elif table == "under_bed":
		snd = "search_soft"
	containers.append({"id": id, "pos": pos, "table": table, "bid": bid, "entries": [], "size": size, "searched": false, "sound": snd})
	var k := Vector2i(floori(pos.x / 8.0), floori(pos.z / 8.0))
	if not _cgrid.has(k):
		_cgrid[k] = []
	_cgrid[k].append(id)
	return id


func containers_near(p: Vector3, r: float) -> Array:
	var out := []
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for id in _cgrid.get(k + Vector2i(dx, dz), []):
				var c: Dictionary = containers[id]
				if (c.pos as Vector3).distance_to(p) <= r:
					out.append(c)
	return out''')
sub('src/world/dynamics.gd', '''var _leaf_meshes: Dictionary = {}''', '''var _leaf_meshes: Dictionary = {}
var _cgrid: Dictionary = {}''')
append('src/world/dynamics.gd', '''

# ------------------------------------------------------------------ corpses

func server_spawn_corpse(ch, impulse: Vector3) -> int:
	var id := _next_corpse
	_next_corpse += 1
	var c := Corpse.new()
	root.add_child(c)
	c.setup_server(world, id, ch, impulse)
	c.entries = ch.inv.all_entries()
	# Whatever was in the hands and on the body stays with the body.
	corpses[id] = c
	world.map_corpse_spawn.rpc(id, ch.pname, ch.team, c.pose())
	return id


func client_spawn_corpse(id: int, who: String, team: int, xforms: Array) -> void:
	if corpses.has(id):
		return
	var c := Corpse.new()
	root.add_child(c)
	c.setup_client(world, id, who, team, xforms)
	corpses[id] = c
	_next_corpse = maxi(_next_corpse, id + 1)


# ------------------------------------------------------------------ glass

func break_window(wid: int, pos: Vector3, dir: Vector3) -> bool:
	if wid < 0 or wid >= windows.size():
		return false
	var w: Dictionary = windows[wid]
	if w.get("broken", false):
		return false
	w.broken = true
	if w.has("leaf"):
		set_leaf_transform(w.leaf[0], w.leaf[1], Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
	if w.has("body") and (w.body as RID).is_valid():
		PhysicsServer3D.free_rid(w.body)
		PhysicsServer3D.free_rid(w.shape)
		w.body = RID()
	if w.has("portal"):
		map.acoustics.set_portal_kind(int(w.portal), "opening")
		map.acoustics.set_portal_open(int(w.portal), 1.0)
	return true
''')

# ---------------------------------------------------------------- map facade
append('src/world/map_builder.gd', '''

func server_spawn_corpse(ch, impulse: Vector3) -> int:
	return dyn.server_spawn_corpse(ch, impulse)


func server_break_glass(collider, pos: Vector3, dir: Vector3) -> void:
	if collider == null or not collider.has_meta("window_id"):
		return
	var wid := int(collider.get_meta("window_id"))
	if dyn.break_window(wid, pos, dir):
		world.map_window_broken.rpc(wid, pos, dir)
		if not world.is_server_dedicated() and world.effects:
			world.effects.glass_break(pos, dir, dyn.windows[wid])
		world.server_sound("glass_break", pos, 0.0, -1)


func server_prop_hit(prop_id: int, pos: Vector3, dir: Vector3, energy: float, momentum: float) -> void:
	var body = dyn.server_activate(prop_id)
	if body and is_instance_valid(body):
		body.apply_impulse(dir * minf(momentum * 6.0, 40.0), pos - body.global_position)
		body.take_damage(energy * 0.08, dir)


func server_corpse_hit(corpse_id: int, pos: Vector3, dir: Vector3) -> void:
	var c = dyn.corpses.get(corpse_id)
	if c and c.server and not c.settled:
		(c.bodies.chest as RigidBody3D).apply_impulse(dir * 3.0)


func server_push_prop(prop_id: int, by, dir: Vector3, vel: Vector3) -> void:
	if Vector2(vel.x, vel.z).length() < 0.6:
		return
	var body = dyn.server_activate(prop_id)
	if body and is_instance_valid(body):
		body.on_pushed(by, dir, vel, Defs.TICK_DT)


func server_sync_peer(pid: int) -> void:
	## Late joiners: everything that differs from the deterministic start state.
	for d in dyn.doors:
		var dn = d.get("node")
		if dn and (absf(dn.angle - float(d.get("start_angle", 0.0))) > 0.01 or dn.locked != bool(d.get("locked", false))):
			world.map_door_ev.rpc_id(pid, int(d.id), false, dn.angle, dn.target, dn.locked, "")
	for w in dyn.windows:
		if w.get("broken", false):
			world.map_window_broken.rpc_id(pid, int(w.id), (w.xf as Transform3D).origin, Vector3.FORWARD)
		elif w.has("door"):
			var sd = w.door
			if absf(sd.angle) > 0.01:
				world.map_door_ev.rpc_id(pid, int(w.id), true, sd.angle, sd.target, false, "")
	for id in dyn.items:
		world.map_item_spawn.rpc_id(pid, id, dyn.items[id].entry, dyn.items[id].xf)
	for p in dyn.props:
		if p.state == "broken":
			world.map_prop_break.rpc_id(pid, int(p.id), (p.xf as Transform3D).origin, Vector3.ZERO)
		elif p.state == "active":
			world.map_prop_activate.rpc_id(pid, int(p.id), (p.body as Node3D).global_transform if p.get("body") else p.xf)
	for cid in dyn.corpses:
		var c = dyn.corpses[cid]
		world.map_corpse_spawn.rpc_id(pid, cid, c.pname, c.team, c.pose())
''')

# ---------------------------------------------------------------- world RPCs
append('src/match/world.gd', '''

# ------------------------------------------------------------------ map events

func map_door_state(door, what: String) -> void:
	## Server: a door or shutter changed. Everyone animates the same swing; sounds come from the door.
	var is_shutter: bool = door.is_shutter
	var did: int = int(door.spec.id)
	map_door_ev.rpc(did, is_shutter, door.angle, door.target, door.locked, what)
	match what:
		"open":
			server_sound("door_open" if not is_shutter else "shutter_open", door.center(), 0.0, -1)
		"close":
			pass
		"locked":
			server_sound("door_locked", door.center(), 0.0, -1)
		"unlock":
			server_sound("door_unlock", door.center(), 0.0, -1)
		"forced":
			server_sound("door_burst", door.center(), 0.0, -1)
		"blocked":
			server_sound("door_bump", door.center(), 0.0, -1)


@rpc("authority", "call_remote", "reliable")
func map_door_ev(did: int, is_shutter: bool, angle: float, target: float, locked: bool, what: String) -> void:
	if map == null:
		return
	var d = null
	if is_shutter:
		if did >= 0 and did < map.dyn.windows.size():
			d = map.dyn.windows[did].get("door")
	elif did >= 0 and did < map.dyn.doors.size():
		d = map.dyn.doors[did].get("node")
	if d:
		d.set_target(target, angle, locked)


@rpc("authority", "call_remote", "reliable")
func map_window_broken(wid: int, pos: Vector3, dir: Vector3) -> void:
	if map and map.dyn.break_window(wid, pos, dir) and effects:
		effects.glass_break(pos, dir, map.dyn.windows[wid])


func map_item_spawn_server(e: Dictionary, xf: Transform3D) -> void:
	map.dyn.server_spawn_item(e, xf, true)


@rpc("authority", "call_remote", "reliable")
func map_item_spawn(id: int, e: Dictionary, xf: Transform3D) -> void:
	if map:
		map.dyn.client_spawn_item(id, e, xf)


func map_item_remove(id: int) -> void:
	map.dyn.remove_item(id)
	map_item_removed.rpc(id)


@rpc("authority", "call_remote", "reliable")
func map_item_removed(id: int) -> void:
	if map:
		map.dyn.remove_item(id)


@rpc("authority", "call_remote", "reliable")
func map_prop_activate(id: int, xf: Transform3D) -> void:
	if map:
		map.dyn.client_activate(id, xf)


@rpc("authority", "call_remote", "reliable")
func map_prop_rest(id: int, xf: Transform3D) -> void:
	if map:
		map.dyn.client_prop_rest(id, xf)


@rpc("authority", "call_remote", "reliable")
func map_prop_break(id: int, pos: Vector3, impulse: Vector3) -> void:
	if map:
		map.dyn.client_break_prop(id, pos, impulse)


@rpc("authority", "call_remote", "reliable")
func map_corpse_spawn(id: int, who: String, team: int, xforms: Array) -> void:
	if map:
		map.dyn.client_spawn_corpse(id, who, team, xforms)


func corpse_pose(id: int, xforms: Array, final: bool) -> void:
	map_corpse_pose.rpc(id, xforms, final)


@rpc("authority", "call_remote", "unreliable_ordered")
func map_corpse_pose(id: int, xforms: Array, final: bool) -> void:
	if map and map.dyn.corpses.has(id):
		map.dyn.corpses[id].client_pose(xforms, final)


# ------------------------------------------------------------------ containers and inventory requests

func send_container(ch, kind: String, id: int, entries: Array) -> void:
	if ch.pid == Net.local_pid and not is_server_dedicated():
		_container_view(kind, id, entries)
	elif not Net.is_bot(ch.pid):
		_container_view.rpc_id(ch.pid, kind, id, entries)


@rpc("authority", "call_remote", "reliable")
func _container_view(kind: String, id: int, entries: Array) -> void:
	if hud:
		hud.show_container(kind, id, entries)


func request_inventory(req: Dictionary) -> void:
	## Client (or host) asks the server to change its inventory.
	if is_server:
		if local_char:
			interaction.server_inventory_request(local_char, req)
	else:
		_inv_req.rpc_id(1, req)


@rpc("any_peer", "reliable")
func _inv_req(req: Dictionary) -> void:
	if not is_server:
		return
	var ch := char_by_pid(multiplayer.get_remote_sender_id())
	if ch and ch.mode in [Motor.GROUND, Motor.DOWNED]:
		interaction.server_inventory_request(ch, req)


# ------------------------------------------------------------------ match state

var match_info: Dictionary = {}


@rpc("authority", "call_remote", "reliable")
func match_state(info: Dictionary) -> void:
	match_info = info
	if hud:
		hud.on_match_state(info)
	if effects:
		effects.on_match_state(info)


@rpc("authority", "call_remote", "reliable")
func match_toast(text: String, sound: String) -> void:
	if hud:
		hud.toast(text)
	if sound != "":
		SoundSys.play_local(sound)


func plane_pos(tick: float) -> Vector3:
	return MatchServer.plane_at(match_info.get("plane", {}), tick)


func zone_circle(tick: float) -> Array:
	return MatchServer.circle_at(match_info.get("zone", {}), tick)
''')

# MatchServer static helpers used by clients too
append('src/match/match_server.gd', '''

static func plane_at(pl: Dictionary, tick: float) -> Vector3:
	if pl.is_empty():
		return Vector3.ZERO
	var t := clampf((tick - float(pl.t0)) / Defs.TICK_RATE / float(pl.dur), 0.0, 1.0)
	return (pl.a as Vector3).lerp(pl.b, t)


static func circle_at(z: Dictionary, tick: float) -> Array:
	if z.is_empty():
		return [Vector2.ZERO, 99999.0]
	if z.state != "shrink":
		return [z.c0, z.r0]
	var t := clampf((tick - float(z.t0)) / maxf(float(z.t1) - float(z.t0), 1.0), 0.0, 1.0)
	return [(z.c0 as Vector2).lerp(z.c1, t), lerpf(float(z.r0), float(z.r1), t)]
''')
print('ok')
