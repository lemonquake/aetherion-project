extends RefCounted
## --autotest=r3: measured checks for the 2026-10-27 polish run - the artificial sun's day/night cycle (luma of the
## same view at night and at noon; roofed lanes still dark at noon; the flashlight still needed there), the map's
## new features (counts from the build), climbing a ladder to a roof deck and back down, vaulting on to a crate stack,
## and the compass under the minimap. Each check measures what the player sees or where they end up.
##   godot --path game -- --host --bots=3 --autostart=1 --autotest=r3 --shots=<dir>   [--r3_only=day,ladder,...]

const DayCycle := preload("res://src/world/day_cycle.gd")
const Compass := preload("res://src/ui/compass.gd")

var t = null
var world = null


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r3_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	if want.call("census"):
		_census()
	if want.call("cycle"):
		_cycle_maths()
	await t._deploy()
	if not is_instance_valid(t.ch):
		return
	for step in [["compass", _compass], ["radio", _radio], ["day", _day_night], ["tunnel", _tunnel_dark], ["ladder", _ladder], ["crate", _crate_vault]]:
		if want.call(step[0]) and is_instance_valid(t.ch):
			await (step[1] as Callable).call()
	world.map.lighting.forced_time = -1.0


# ------------------------------------------------------------------ build census

func _census() -> void:
	var m = world.map
	var st: Dictionary = m.stats
	var tn: Dictionary = st.get("tunnels", {})
	var lb: Dictionary = st.get("looban", {})
	var dc: Dictionary = st.get("decals", {})
	var three := 0
	var houses := 0
	var decks := 0
	for b in m.buildings:
		if str(b.get("kind", "house")) in ["house", "store"]:
			houses += 1
			if int(b.get("floors", 1)) >= 3:
				three += 1
			if b.get("deck", false):
				decks += 1
	var vault_w := 0
	for w in m.dyn.windows:
		if str(w.type) == "open" and float(w.h) >= 1.05 and float(w.w) >= 0.85:
			vault_w += 1
	t._check("map_tunnels", int(tn.get("segments", 0)) >= 50 and float(tn.get("metres", 0.0)) > 700.0,
		"%d roofed lanes and walks, %.0f m, %d lamps (%d dead), %d gaps in the roofs, %d shrines" % [int(tn.get("segments", 0)), float(tn.get("metres", 0.0)),
			int(tn.get("lights", 0)), int(tn.get("dead", 0)), int(tn.get("gaps", 0)), int(tn.get("shrines", 0))])
	t._check("map_three_storey", float(three) / maxf(houses, 1) > 0.12, "%d of %d houses are three storeys (%.0f%%)" % [three, houses, 100.0 * three / maxf(houses, 1)])
	t._check("map_roof_decks", decks >= 80 and m.ladders.size() >= 50, "%d flat roof decks, %d ladders" % [decks, m.ladders.size()])
	t._check("map_vault_cover", int(lb.get("crate_stacks", 0)) >= 20 and int(lb.get("low_walls", 0)) >= 60 and vault_w >= 1000,
		"%d loobans, %d crate stacks, %d low walls, %d sandbag rows, %d barricades; %d glassless windows sized to vault through" % [int(lb.get("loobans", 0)),
			int(lb.get("crate_stacks", 0)), int(lb.get("low_walls", 0)), int(lb.get("sandbags", 0)), int(lb.get("barricades", 0)), vault_w])
	t._check("map_decals", int(dc.get("wall", 0)) + int(dc.get("stains", 0)) >= 3000,
		"%d wall decals (%d under lane roofs), %d stains, %d on the ground" % [int(dc.get("wall", 0)), int(dc.get("covered", 0)), int(dc.get("stains", 0)), int(dc.get("ground", 0))])


func _cycle_maths() -> void:
	var samples := {0.0: 0.0, 150.0: 0.0, 299.0: 0.0, 320.0: 1.0, 450.0: 1.0, 599.5: 0.0, 700.0: 0.0, 920.0: 1.0}
	var bad := []
	for s in samples:
		if absf(DayCycle.daylight(s) - float(samples[s])) > 0.05:
			bad.append("%.0f s -> %.2f" % [s, DayCycle.daylight(s)])
	t._check("day_cycle_schedule", bad.is_empty(), "night 0-300 s, day 300-600 s, repeating%s" % ("" if bad.is_empty() else "; wrong: " + ", ".join(bad)))


# ------------------------------------------------------------------ day and night

func _open_spot() -> Vector3:
	## The middle of a looban: open sky.
	var lb: Dictionary = world.map.loobans[0]
	var c: Vector2 = lb.c
	var space = world.get_world_3d().direct_space_state
	for k in 30:
		var p := c + Vector2(cos(k * 2.4), sin(k * 2.4)) * (0.5 + k * 0.25)
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 60, p.y), Vector3(p.x, -5, p.y), Defs.MOVE_MASK))
		if not hit.is_empty() and absf((hit.position as Vector3).y - world.map.layout.ground_height(p.x, p.y)) < 0.25:
			return hit.position
	return Vector3(c.x, world.map.layout.ground_height(c.x, c.y), c.y)


func _day_night() -> void:
	## The same view of an open courtyard at night and at noon.
	var L = world.map.lighting
	if t.ch.light.on:
		await t._tap("flashlight")
	var p := _open_spot()
	t._teleport(p + Vector3.UP * 0.05, 0.6)
	t.ctl.pitch = -0.08
	L.forced_time = 120.0
	await t._wait(1.2)
	var night: float = await t._view_luma()
	await t._shot("courtyard_night")
	L.forced_time = 450.0
	await t._wait(1.5)
	var noon: float = await t._view_luma()
	await t._shot("courtyard_noon")
	t._check("artificial_sun_lights_map", noon > night * 2.5 and noon > 40.0, "courtyard view luma %.1f at night, %.1f at noon" % [night, noon])
	# Ignition: the sky and light come up within the ignition time.
	L.forced_time = 300.5
	await t._wait(0.4)
	var early: float = await t._view_luma()
	L.forced_time = 312.0
	await t._wait(0.6)
	var lit: float = await t._view_luma()
	t._check("sun_ignites", lit > early * 1.5, "luma %.1f at 0.5 s after ignition, %.1f at 12 s" % [early, lit])
	_open_luma = noon


var _open_luma := 0.0


func _tunnel_dark() -> void:
	## Noon inside a roofed lane: much darker than the open courtyard, and the flashlight makes a clear difference.
	var L = world.map.lighting
	L.forced_time = 450.0
	var lanes: Array = world.map.tunnels.filter(func(x): return x.kind == "lane" and (x.b as Vector2).distance_to(x.a) > 9.0)
	if lanes.is_empty():
		t._check("tunnel_dark_at_noon", false, "no roofed lanes")
		return
	var best := []
	var space = world.get_world_3d().direct_space_state
	var tried := 0
	var results := []
	for tl in lanes:
		if tried >= 3:
			break
		var a: Vector2 = tl.a
		var b: Vector2 = tl.b
		var p := a.lerp(b, 0.45)
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, world.map.layout.ground_height(p.x, p.y) + 1.5, p.y),
			Vector3(p.x, world.map.layout.ground_height(p.x, p.y) - 1.0, p.y), Defs.MOVE_MASK))
		if hit.is_empty():
			continue
		tried += 1
		var dir := (b - a).normalized()
		if t.ch.light.on:
			await t._tap("flashlight")
		t._teleport((hit.position as Vector3) + Vector3.UP * 0.05, atan2(-dir.x, -dir.y))
		t.ctl.pitch = -0.12
		await t._wait(1.2)
		var dark: float = await t._view_luma()
		if tried == 1:
			await t._shot("tunnel_noon")
		await t._tap("flashlight")
		await t._wait(0.6)
		var lit: float = await t._view_luma()
		if tried == 1:
			await t._shot("tunnel_noon_flashlight")
		results.append([dark, lit])
	var ok := 0
	var txt := []
	for r in results:
		if float(r[0]) < _open_luma * 0.3 and float(r[1]) > float(r[0]) + 4.0:
			ok += 1
		txt.append("%.1f -> %.1f" % [float(r[0]), float(r[1])])
	t._check("tunnel_dark_at_noon", ok >= 2, "open courtyard at noon %.1f; inside roofed lanes at noon (flashlight off -> on): %s" % [_open_luma, ", ".join(txt)])


# ------------------------------------------------------------------ ladders

func _ladder() -> void:
	## Walk into a ladder, climb to the roof deck, step off on to it; then walk back off the edge and climb down.
	var lds: Array = world.map.ladders.duplicate()
	var here: Vector3 = t.ch.global_position
	lds.sort_custom(func(a, b): return (a.base as Vector3).distance_to(here) < (b.base as Vector3).distance_to(here))
	var up_ok := 0
	var down_ok := 0
	var tried := 0
	var detail := []
	for ld in lds:
		if tried >= 3:
			break
		var base: Vector3 = ld.base
		var n: Vector3 = ld.n
		var top := float(ld.top_y)
		# Somewhere to stand at the foot.
		var space = world.get_world_3d().direct_space_state
		var foot := base + n * 0.35
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 1.0, foot + Vector3.DOWN * 1.5, Defs.MOVE_MASK))
		if hit.is_empty():
			continue
		tried += 1
		t._teleport((hit.position as Vector3) + Vector3.UP * 0.05, atan2(n.x, n.z))
		await t._wait(0.4)
		t._act_press("move_forward")
		var reached: bool = await t._until(func(): return t.ch.global_position.y > top - 0.2 and t.ch.is_on_floor(), 9.0)
		await t._wait(0.35)
		t._act_release("move_forward")
		var y_up: float = t.ch.global_position.y
		if reached:
			up_ok += 1
			if up_ok == 1:
				await t._shot("ladder_on_roof")
		# Down: turn round and walk off the edge at the ladder; it catches you and you climb down.
		var down := false
		if reached:
			t._teleport(Vector3(base.x, top + 0.05, base.z) - n * 0.75, atan2(-n.x, -n.z))
			await t._wait(0.4)
			t._act_press("move_forward")
			down = await t._until(func(): return t.ch.global_position.y < base.y + 0.4 and t.ch.is_on_floor(), 9.0)
			t._act_release("move_forward")
			if down:
				down_ok += 1
		detail.append("%.1f m ladder: up %s (y %.2f / %.2f), down %s" % [top - base.y, "yes" if reached else "no", y_up, top, "yes" if down else "no"])
	t._check("ladder_climb", up_ok >= 2 and down_ok >= 2, "; ".join(detail))


# ------------------------------------------------------------------ crates

func _crate_vault() -> void:
	## Jump at a crate stack in a looban: the player vaults on to (or over) it.
	var spots: Array = world.map.vault_spots.filter(func(s): return float((s.size as Vector3).y) > 0.85 and float((s.size as Vector3).y) < 1.45)
	var here: Vector3 = t.ch.global_position
	spots.sort_custom(func(a, b): return (a.pos as Vector3).distance_to(here) < (b.pos as Vector3).distance_to(here))
	var tried := 0
	var ok := 0
	var detail := []
	var space = world.get_world_3d().direct_space_state
	for s in spots:
		if tried >= 4:
			break
		var top: Vector3 = s.pos
		var sz: Vector3 = s.size
		var yaw := float(s.yaw)
		# Approach along one of the crate's faces that has open ground in front.
		for k in 4:
			var ax := Basis(Vector3.UP, yaw + k * PI * 0.5) * Vector3(0, 0, 1)
			var halfd := (sz.z if k % 2 == 0 else sz.x) * 0.5
			var stand := Vector3(top.x, top.y - sz.y, top.z) + ax * (halfd + 0.55)
			var g = space.intersect_ray(PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.4, stand + Vector3.DOWN * 0.6, Defs.MOVE_MASK))
			var block = space.intersect_ray(PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 1.0, stand + Vector3.UP * 1.0 + ax * 0.6, Defs.MOVE_MASK))
			if g.is_empty() or not block.is_empty() or absf((g.position as Vector3).y - (top.y - sz.y)) > 0.25:
				continue
			tried += 1
			t._teleport((g.position as Vector3) + Vector3.UP * 0.05, atan2(ax.x, ax.z))
			await t._wait(0.5)
			var y0: float = t.ch.global_position.y
			Vault.find(t.ch)
			var why := Vault.why
			await t._tap("jump")
			await t._wait(1.2)
			var gained: float = t.ch.global_position.y - y0
			var moved: float = Vector2(t.ch.global_position.x - stand.x, t.ch.global_position.z - stand.z).length()
			if gained > sz.y * 0.7 or moved > halfd * 2.0 + 0.3:
				ok += 1
				if ok == 1:
					await t._shot("crate_vault")
			detail.append("%.2f m crate: rose %.2f m, moved %.2f m%s" % [sz.y, gained, moved, "" if why == "" else " (" + why + ")"])
			break
	t._check("crate_vault", ok >= 2, "; ".join(detail) if not detail.is_empty() else "no crate with room in front")


# ------------------------------------------------------------------ radio

func _radio() -> void:
	## A bot of another team keys its radio. The host player (an enemy) stands near one of that bot's teammates
	## (their radio), then next to the speaker, then far away: the server's routing must give them the speech from
	## that radio, the speaker's own voice, and nothing. Then the client side: an overheard frame makes a positional
	## voice at the source.
	var me = t.ch
	var speaker = null
	var mate = null
	for eid in world.bots:
		var b = world.bots[eid].ch
		if b.team == me.team or b.mode not in [Motor.GROUND, Motor.DOWNED]:
			continue
		for o in world.characters.values():
			if o != b and o.team == b.team and o.mode in [Motor.GROUND, Motor.DOWNED] and o.global_position.distance_to(b.global_position) > 30.0:
				speaker = b
				mate = o
				break
		if speaker:
			break
	if speaker == null:
		# Not spread out yet: separate two of a team by hand.
		for eid in world.bots:
			var b2 = world.bots[eid].ch
			if b2.team != me.team and b2.mode == Motor.GROUND:
				for o2 in world.characters.values():
					if o2 != b2 and o2.team == b2.team and o2.mode == Motor.GROUND:
						speaker = b2
						mate = o2
						break
			if speaker:
				break
		if speaker:
			mate.global_position = speaker.global_position + Vector3(60, 0, 0)
	if speaker == null:
		t._check("radio_eavesdrop", false, "no enemy team with two members on the ground")
		return
	var res := []
	var start: Vector3 = me.global_position
	for case in [["radio", mate.global_position + Vector3(4, 0, 0), 1], ["voice", speaker.global_position + Vector3(3, 0, 0), 2], ["far", speaker.global_position + Vector3(0, 0, 45), -1]]:
		if case[0] == "far":
			mate.global_position = speaker.global_position + Vector3(0, 0, -45)
		me.global_position = case[1]
		await t._wait(0.15)
		var tg: Array = world.voice_targets(speaker.pid)
		var got := -1
		var src := -1
		for x in tg:
			if int(x[0]) == Net.local_pid:
				got = int(x[2])
				src = int(x[1])
		res.append("%s: kind %d from %s" % [case[0], got, "-" if src < 0 else ("speaker" if src == speaker.eid else ("teammate" if src == mate.eid else str(src)))])
		if got != int(case[2]):
			res.append("(want %d)" % int(case[2]))
	var routed_ok := not "(want" in " ".join(res)
	# Client: an overheard frame plays positionally from the teammate's radio.
	var vc = world.controller.voice
	var before: int = vc.overheard_players()
	me.global_position = mate.global_position + Vector3(4, 0, 0)
	var frame := PackedByteArray()
	frame.resize(320)
	frame.fill(0x7f)
	vc._on_voice(speaker.pid, frame, mate.eid, 1)
	await t._wait(0.1)
	var placed := false
	for k in vc._players:
		var r: Dictionary = vc._players[k]
		if int(r.kind) == 1 and r.player is AudioStreamPlayer3D:
			placed = (r.player as Node3D).global_position.distance_to(mate.global_position) < 2.0 and str((r.player as AudioStreamPlayer3D).bus) == "Radio"
	me.global_position = start
	t._check("radio_eavesdrop", routed_ok and placed and vc.overheard_players() > before,
		"%s; overheard frame plays at the teammate's radio on the Radio bus: %s; teammates get every frame on their own radio" % [", ".join(res), str(placed)])
	t._check("radio_clicks", SoundSys.defs.has("radio_key") and SoundSys.defs.has("radio_squelch") and AudioServer.get_bus_index("Radio") >= 0,
		"key-down click, squelch tail and a band-limited radio bus are loaded")


# ------------------------------------------------------------------ compass

func _compass() -> void:
	var cp = world.hud.compass
	var bad := []
	for want in [0.0, 90.0, 120.0, 225.0, 330.0]:
		t.ctl.yaw = deg_to_rad(-want)
		await t._wait(0.3)
		await RenderingServer.frame_post_draw
		var got: float = cp.bearing
		if absf(wrapf(got - want, -180.0, 180.0)) > 1.0:
			bad.append("%.0f -> %.1f" % [want, got])
	t.ctl.yaw = deg_to_rad(-120.0)
	await t._wait(0.3)
	await t._shot("compass_120")
	t._check("compass_bearing", cp.visible and bad.is_empty() and cp.size.x > 150.0,
		"compass under the minimap at %s, %d px wide; bearings 0/90/120/225/330 read back%s" % [str(cp.position), int(cp.size.x), "" if bad.is_empty() else " wrong: " + ", ".join(bad)])
