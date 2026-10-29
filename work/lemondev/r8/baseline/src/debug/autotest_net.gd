extends Node
## Multi-process network test: two real clients ("net_a" and "net_b") on a dedicated server started with
## --testcheats. They coordinate through a JSON file in the --shots folder and check that what one client changes,
## the other sees: a door, a broken window, a flashlight, a radio transmission, and a contested item that only one
## of them may get. Also checks that floor loot arrived and that client prediction stays close to the server.
##   server:  godot --headless --path game -- --server --bots=6 --autostart=2 --expect_players=2 --testcheats
##   clients: godot --path game -- --join=127.0.0.1 --name=Alpha --autotest=net_a --shots=<dir>
##            godot --path game -- --join=127.0.0.1 --name=Bravo --autotest=net_b --shots=<dir>

var world = null
var ctl = null
var ch = null
var role := "a"
var out_dir := ""
var results: Array = []
var _shot_n := 0
var _voice_in := 0
var _radio_seen := false


func _ready() -> void:
	world = get_parent()
	role = "a" if str(Game.arg("autotest")) == "net_a" else "b"
	out_dir = str(Game.arg("shots", "user://autotest_net"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	Net.voice_received.connect(func(_pid, _b, _s, _k): _voice_in += 1)
	get_tree().create_timer(float(Game.arg("autotest_timeout", 420))).timeout.connect(func(): _check("watchdog", false, "timed out"); _finish())
	_run.call_deferred()


func _run() -> void:
	await _until(func(): return world.local_char != null and world.controller != null, 30.0)
	ch = world.local_char
	ctl = world.controller
	if ch == null:
		_check("spawn", false, "no local character")
		_finish()
		return
	_check("connected_as_client", Net.online and not Net.is_server, "pid %d, rtt %.0f ms" % [Net.local_pid, Net.rtt_s * 1000.0])
	if role == "a":
		await _role_a()
	else:
		await _role_b()
	_finish()


# ------------------------------------------------------------------ Alpha: makes changes

func _role_a() -> void:
	await _until(func(): return not world.match_info.get("plane", {}).is_empty(), 20.0)
	var pl: Dictionary = world.match_info.plane
	await _until(func(): return Net.interp_tick() - float(pl.t0) > (float(pl.get("open_s", 6.0)) + 1.5) * Defs.TICK_RATE, 60.0)
	await _hold("jump", 0.25)
	await _landed()
	_check("floor_items_synced", world.map.dyn.items.size() > 0, "%d floor items known to this client" % world.map.dyn.items.size())
	# Prediction: two seconds of running, then compare with the server's corrections.
	var c0: int = ctl.stats.corrections
	ctl.stats.max_error = 0.0
	await _hold("move_forward", 2.0)
	await _wait(0.5)
	_check("prediction", ctl.stats.max_error < 0.75, "max error %.3f m, %d corrections, %d replayed" % [ctl.stats.max_error, ctl.stats.corrections - c0, ctl.stats.replayed])
	await _door()
	await _window()
	await _ping_and_vault()
	await _ladder_net()
	# Flashlight on: Bravo should see it.
	if not ch.light.on:
		await _tap("flashlight")
	await _wait(0.5)
	_state_put({"light_on": true})
	# Radio: a second of transmission (silent frames); Bravo should hear the cue and get the voice packets.
	for i in 25:
		Net.send_voice(PackedByteArray([0x7f, 0x7f, 0x7f, 0x7f]))
		await _wait(0.04)
	_state_put({"radio": Net.local_pid})
	await _item_race()
	await _shot("alpha_end")
	_state_put({"a_done": true})
	await _until(func(): return _state_get().has("b_done"), 40.0)


func _door() -> void:
	var best = null
	var bd := INF
	for d in world.map.dyn.doors:
		var dn = d.get("node")
		if dn == null or not d.get("outer", false) or dn.locked or absf(dn.target) > 0.02 or not d.has("outward"):
			continue
		# Dry ground to stand on in front of it: on a stilt house's plank walk the player is inside the door's arc
		# (doors swing toward whoever opens them) and blocks it.
		var front: Vector3 = dn.center() + (d.outward as Vector3) * 1.1
		if world.map.layout.is_water(front.x, front.z) or world.map.ground_height(front.x, front.z) < world.map.layout.LAND_Y - 0.4:
			continue
		var dist: float = dn.center().distance_to(ch.global_position)
		if dist < bd:
			bd = dist
			best = d
	if best == null:
		_check("door_open", false, "no closed unlocked door")
		return
	var dn = best.node
	var out: Vector3 = best.outward
	out.y = 0.0
	out = out.normalized()
	var c: Vector3 = dn.center()
	var stand := c + out * 1.1
	stand.y = world.map.ground_height(stand.x, stand.z) + 0.1
	await _teleport(stand, c)
	var tgt: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
	print("[autotest-a] at door: me %s (wanted %s), door centre %s, use ray sees %s" % [str(ch.global_position.snapped(Vector3.ONE * 0.01)),
		str(stand.snapped(Vector3.ONE * 0.01)), str(c.snapped(Vector3.ONE * 0.01)), str(tgt.get("kind", "-"))])
	await _tap("interact")
	await _wait(1.2)
	_check("door_open_local", absf(dn.target) > 0.05, "door %d target %.2f" % [int(best.id), dn.target])
	_state_put({"door": int(best.id)})
	await _shot("alpha_door")


func _window() -> void:
	var best = null
	var bd := INF
	for w in world.map.dyn.windows:
		if str(w.get("type", "")) != "glass" or w.get("broken", false) or not w.has("outward"):
			continue
		var dist: float = (w.xf as Transform3D).origin.distance_to(ch.global_position)
		if dist < bd:
			bd = dist
			best = w
	if best == null:
		_check("window_break", false, "no glass window")
		return
	world.test_cmd({"op": "give", "entry": {"id": "rifle_556", "n": 1}})
	world.test_cmd({"op": "give", "entry": {"id": "ammo_556", "n": 60}})
	await _wait(0.6)
	await _tap("weapon_1")
	await _wait(1.6)
	var c: Vector3 = (best.xf as Transform3D).origin
	var out: Vector3 = best.outward
	out.y = 0.0
	out = out.normalized()
	var stand := c + out * 3.0
	stand.y = world.map.ground_height(stand.x, stand.z) + 0.1
	await _teleport(stand, c)
	await _tap("fire")
	await _wait(1.0)
	_check("window_broken_local", bool(best.get("broken", false)), "window %d" % int(best.id))
	_state_put({"window": int(best.id)})
	await _shot("alpha_window")
	await _tap("holster")


func _item_race() -> void:
	## Both clients press Use on the same item at the same moment; the server must give it to exactly one.
	# An item lying outdoors with open ground on both sides, so both players can stand next to it.
	var best := -1
	var bd := INF
	var space = world.get_world_3d().direct_space_state
	for id in world.map.dyn.items:
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		var d := p.distance_to(ch.global_position)
		if d >= bd or world.map.acoustics.zone_at(p + Vector3.UP * 0.5) != 0:
			continue
		var clear := true
		for side in [1.0, -1.0]:
			var stand := p + Vector3(side, 0, 0.3).normalized() * 0.9
			var eye := stand + Vector3.UP * 1.75
			# Room to stand, and an unobstructed view of the item from eye height.
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, stand + Vector3.UP * 1.0, Defs.PHYS_WORLD | Defs.PHYS_PROP)
			var q2 := PhysicsRayQueryParameters3D.create(eye, p + Vector3.UP * 0.03, Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS)
			var q3 := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.5, stand + Vector3.DOWN * 0.6, Defs.PHYS_WORLD)
			var floor_hit = space.intersect_ray(q3)
			if not space.intersect_ray(q).is_empty() or not space.intersect_ray(q2).is_empty() or floor_hit.is_empty() 					or absf((floor_hit.position as Vector3).y - p.y) > 0.3:
				clear = false
		if clear:
			bd = d
			best = id
	if best < 0:
		_check("item_race", false, "no floor items on this client")
		return
	var go := Time.get_unix_time_from_system() + 4.0
	_state_put({"race_item": best, "go_at": go})
	var got: bool = await _race(best, go, 1.0)
	_state_put({"a_got": got})
	await _until(func(): return _state_get().has("b_got"), 20.0)
	var b_got := bool(_state_get().get("b_got", false))
	_check("item_race_single_owner", int(got) + int(b_got) == 1, "Alpha got it: %s, Bravo got it: %s" % [str(got), str(b_got)])


func _race(id: int, go: float, side: float) -> bool:
	var it: Dictionary = world.map.dyn.items.get(id, {})
	if it.is_empty():
		return false
	var p: Vector3 = (it.xf as Transform3D).origin
	var dir := Vector3(side, 0, 0.3).normalized()
	var stand := p + dir * 0.9 + Vector3.UP * 0.1
	await _teleport(stand, p + Vector3.UP * 0.03)
	var tgt: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
	var node = it.get("node")
	var q := PhysicsRayQueryParameters3D.create(ch.eye_position(), p + Vector3.UP * 0.03, 0xFFFFFFFF)
	q.exclude = [ch.get_rid()]
	var hit = world.get_world_3d().direct_space_state.intersect_ray(q)
	var hc = hit.get("collider")
	print("[autotest-%s] race: item %d at %s (node %s), me %s, eye-to-item %.2f m, use ray sees %s %s; full ray hits %s layer %s at %s" % [role, id,
		str(p.snapped(Vector3.ONE * 0.01)), str(node.global_position.snapped(Vector3.ONE * 0.01)) if node and is_instance_valid(node) else "none",
		str(ch.global_position.snapped(Vector3.ONE * 0.01)), ch.eye_position().distance_to(p), str(tgt.get("kind", "-")), str(tgt.get("id", "")),
		(str(hc.name) if hc is Node else "item body %s" % str(hc.get_meta("item_id", "?"))) if hc else "nothing", str(hc.collision_layer) if hc is Node and "collision_layer" in hc else "-",
		str((hit.get("position", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.01))])
	var item_id := str(it.entry.id)
	var before := _holding(item_id)
	await _until(func(): return Time.get_unix_time_from_system() >= go, 10.0)
	await _tap("interact")
	var used := []
	for pnd in ctl.pending:
		if int(pnd.cmd.btn) & Motor.B_USE:
			used.append(int(pnd.cmd.seq))
	print("[autotest-%s] race: commands carrying Use: %s (tab %s, paused %s, mode %d)" % [role, str(used), str(ctl.tab_held), str(ctl.paused), ch.mode])
	await _wait(1.5)
	return _holding(item_id) > before


func _holding(item_id: String) -> int:
	## How many of this item the character has: in the bag, as gear, or as a weapon in a slot.
	var n: int = ch.inv.count(item_id)
	for g in ch.inv.gear.values():
		if g != null and str(g.get("id", "")) == item_id:
			n += 1
	for sl in ch.wpn.slots:
		if sl != null and str(sl.get("id", "")) == item_id:
			n += 1
	return n


# ------------------------------------------------------------------ Bravo: checks what Alpha changed

func _role_b() -> void:
	await _landed()
	var found := {}   # lambdas cannot assign outer locals; they can fill a dictionary
	await _until(func():
		for o in world.characters.values():
			if o != ch and str(Net.players.get(o.pid, {}).get("name", "")) == "Alpha":
				found.alpha = o
				return true
		return false, 60.0)
	var alpha = found.get("alpha")
	if alpha == null:
		var seen := []
		for o in world.characters.values():
			seen.append("%s/%d/%s" % [o.pname, o.pid, str(Net.players.get(o.pid, {}).get("name", "?"))])
		print("[autotest-b] characters seen: %s; players: %s" % [", ".join(seen), str(Net.players.keys())])
	_check("sees_teammate", alpha != null, "Alpha %s" % ("found" if alpha else "missing"))
	await _until(func(): return _state_get().has("door"), 120.0)
	var did := int(_state_get().get("door", -1))
	if did >= 0:
		var dn = world.map.dyn.doors[did].get("node")
		var ok: bool = await _until(func(): return dn != null and absf(dn.target) > 0.05, 5.0)
		_check("door_open_seen_by_other", ok, "door %d target %.2f" % [did, dn.target if dn else -1.0])
	await _until(func(): return _state_get().has("window"), 60.0)
	var wid := int(_state_get().get("window", -1))
	if wid >= 0:
		var ok2: bool = await _until(func(): return bool(world.map.dyn.windows[wid].get("broken", false)), 5.0)
		_check("window_broken_seen_by_other", ok2, "window %d" % wid)
	await _until(func(): return _state_get().has("ping"), 60.0)
	var pe := int(_state_get().get("ping", -1))
	var ok_ping: bool = await _until(func(): return world.hud.minimap.pings.any(func(p): return int(p.eid) == pe), 3.0)
	_check("ping_seen_by_teammate", ok_ping, "Alpha's ping (eid %d) on Bravo's minimap: %s" % [pe, str(ok_ping)])
	await _until(func(): return _state_get().has("light_on"), 60.0)
	if alpha and is_instance_valid(alpha):
		var ok3: bool = await _until(func(): return is_instance_valid(alpha) and (alpha.flags & Character.F_LIGHT) != 0, 5.0)
		_check("flashlight_seen_by_other", ok3, "Alpha flags %d" % (alpha.flags if is_instance_valid(alpha) else -1))
		# Watch for the radio flag while Alpha transmits.
		var t := 0.0
		while t < 6.0 and not _state_get().has("radio"):
			if is_instance_valid(alpha) and (alpha.flags & Character.F_RADIO) != 0:
				_radio_seen = true
			await get_tree().physics_frame
			t += 1.0 / 60.0
		_check("radio_cue_seen_by_teammate", _radio_seen or _voice_in > 0, "radio flag seen %s, %d voice packets" % [str(_radio_seen), _voice_in])
	await _until(func(): return _state_get().has("race_item"), 60.0)
	var st := _state_get()
	if not st.has("race_item"):
		_check("item_race", false, "Alpha never offered an item")
		return
	var got: bool = await _race(int(st.race_item), float(st.go_at), -1.0)
	_state_put({"b_got": got})
	await _shot("bravo_end")
	await _until(func(): return _state_get().has("a_done"), 40.0)
	_state_put({"b_done": true})


# ------------------------------------------------------------------ helpers

func _landed() -> void:
	var ok: bool = await _until(func(): return is_instance_valid(ch) and ch.mode == Motor.GROUND, 150.0)
	_check("landed", ok, "mode %d at %s" % [ch.mode if is_instance_valid(ch) else -1, str(ch.global_position.round()) if is_instance_valid(ch) else "-"])
	await _wait(1.0)


func _teleport(pos: Vector3, look: Vector3) -> void:
	var to := look - (pos + Vector3.UP * 1.66)
	var yaw := atan2(-to.x, -to.z)
	world.test_cmd({"op": "teleport", "pos": pos, "yaw": yaw})
	ctl.yaw = yaw
	ctl.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	await _until(func(): return ch.global_position.distance_to(pos) < 0.6, 3.0)
	await _wait(0.4)
	var to2 = look - ch.eye_position()
	ctl.yaw = atan2(-to2.x, -to2.z)
	ctl.pitch = atan2(to2.y, Vector2(to2.x, to2.z).length())
	await _wait(0.2)


func _state_path() -> String:
	return out_dir + "/net_state.json"


func _state_get() -> Dictionary:
	if not FileAccess.file_exists(_state_path()):
		return {}
	var f := FileAccess.open(_state_path(), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _state_put(kv: Dictionary) -> void:
	var d := _state_get()
	d.merge(kv, true)
	var f := FileAccess.open(_state_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func _check(name: String, ok: bool, detail: String) -> void:
	results.append([name, ok, detail])
	print("[autotest-%s] %s %s: %s" % [role, "PASS" if ok else "FAIL", name, detail])


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%s_%02d_%s.png" % [out_dir, role, _shot_n, name])


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > timeout:
			return false
	return true


func _act(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _tap(action: String) -> void:
	_act(action, true)
	for i in 3:
		await get_tree().physics_frame
	_act(action, false)
	for i in 2:
		await get_tree().physics_frame


func _hold(action: String, s: float) -> void:
	_act(action, true)
	await _wait(s)
	_act(action, false)


func _finish() -> void:
	var failed := results.filter(func(r): return not r[1]).size()
	print("[autotest-%s] done: %d checks, %d failed" % [role, results.size(), failed])
	var f := FileAccess.open("%s/results_%s.json" % [out_dir, role], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
	get_tree().quit(1 if failed > 0 else 0)


# ------------------------------------------------------------------ 2026-10-27 (r3): a ladder over the network

func _ladder_net() -> void:
	## Alpha climbs a ladder to a roof deck: the client's prediction must agree with the server all the way up.
	var lds: Array = world.map.ladders.duplicate()
	var here: Vector3 = ch.global_position
	lds.sort_custom(func(a, b): return (a.base as Vector3).distance_to(here) < (b.base as Vector3).distance_to(here))
	if lds.is_empty():
		_check("ladder_predicted", false, "no ladders")
		return
	var ld: Dictionary = lds[0]
	var n: Vector3 = ld.n
	var base: Vector3 = ld.base
	var top := float(ld.top_y)
	await _teleport(base + n * 0.35 + Vector3.UP * 0.05, base - n * 3.0 + Vector3.UP * 1.66)
	ctl.pitch = 0.0
	var c0: int = ctl.stats.corrections
	ctl.stats.max_error = 0.0
	_act("move_forward", true)
	var up: bool = await _until(func(): return ch.global_position.y > top - 0.2 and ch.is_on_floor(), 10.0)
	await _wait(0.4)
	_act("move_forward", false)
	await _wait(0.6)
	_check("ladder_predicted", up and ctl.stats.max_error < 0.75,
		"climbed %.1f m to the roof %s (y %.2f / %.2f), max prediction error %.3f m, %d corrections" % [top - base.y, str(up), ch.global_position.y, top,
			ctl.stats.max_error, ctl.stats.corrections - c0])


# ------------------------------------------------------------------ 2026-10-27: ping and vault over the network

func _ping_and_vault() -> void:
	## Alpha pings (Bravo must see it on the minimap), then vaults through an open window from inside a house: the
	## owner's prediction must agree with the server (vault state travels in the owner snapshot).
	await _tap("ping")
	_state_put({"ping": ch.eid})
	await _wait(1.0)
	var space = world.get_world_3d().direct_space_state
	var best := {}
	var bd := INF
	for wnd in world.map.dyn.windows:
		if not (str(wnd.type) in ["open", "plastic"]) or float(wnd.w) < 0.75 or float(wnd.h) < 0.9:
			continue
		var d: float = (wnd.xf as Transform3D).origin.distance_to(ch.global_position)
		if d > bd:
			continue
		var out: Vector3 = wnd.outward
		out.y = 0.0
		out = out.normalized()
		var sill: Vector3 = (wnd.xf as Transform3D).origin - Vector3.UP * float(wnd.h) * 0.5
		var inside = space.intersect_ray(PhysicsRayQueryParameters3D.create(sill - out * 0.75 + Vector3.UP * 0.3, sill - out * 0.75 + Vector3.DOWN * 1.6, Defs.MOVE_MASK))
		var outside = space.intersect_ray(PhysicsRayQueryParameters3D.create(sill + out * 0.95 + Vector3.UP * 0.3, sill + out * 0.95 + Vector3.DOWN * 2.0, Defs.MOVE_MASK))
		var through = space.intersect_ray(PhysicsRayQueryParameters3D.create(sill - out * 0.4 + Vector3.UP * 0.45, sill + out * 1.3 + Vector3.UP * 0.45, Defs.MOVE_MASK))
		if inside.is_empty() or outside.is_empty() or not through.is_empty():
			continue
		var h: float = sill.y - (inside.position as Vector3).y
		if h < 0.6 or h > 1.3:
			continue
		bd = d
		best = {"w": wnd, "feet": inside.position, "out": out}
	if best.is_empty():
		_check("vault_predicted", false, "no open window to vault")
		return
	var out2: Vector3 = best.out
	await _teleport((best.feet as Vector3) + Vector3.UP * 0.05, (best.feet as Vector3) + out2 * 3.0 + Vector3.UP * 1.66)
	ctl.pitch = 0.0
	var c0: int = ctl.stats.corrections
	ctl.stats.max_error = 0.0
	var o: Vector3 = (best.w.xf as Transform3D).origin
	await _tap("jump")
	var vaulted: bool = await _until(func(): return ch.vault_t >= 0.0, 0.5)
	await _wait(1.2)
	var side = (ch.global_position - o).dot(out2)
	_check("vault_predicted", vaulted and side > 0.2 and ctl.stats.max_error < 0.75,
		"vaulted %s, now %.2f m outside the window, max prediction error %.3f m, %d corrections" % [str(vaulted), side, ctl.stats.max_error, ctl.stats.corrections - c0])
