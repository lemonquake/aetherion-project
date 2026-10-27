"""Loot play-through for the autotest (loot run 2026-10-26):

    godot --path game -- --host --bots=11 --autostart=1 --autotest=loot --shots=<dir>

Checks: every droppable id has a real model; loot boxes and floor loot across the map; floor items rest on what is
under them; each attachment kind changes its stat; picking up fits attachments; a loot box opens for everyone; red-dot
alignment with the bullet line; the scope view. Captures each step.

    python -I tools/patches/p54_autotest_loot.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'src', 'debug', 'autotest.gd')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''const WeaponState := preload("res://src/weapons/weapon_state.gd")''', '''const WeaponState := preload("res://src/weapons/weapon_state.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")''')
rep('''	if str(Game.arg("autotest", "")) == "perf":
		await _perf_run()
		_finish()
		return''', '''	if str(Game.arg("autotest", "")) == "perf":
		await _perf_run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "loot":
		await _loot_run()
		_finish()
		return''')
rep('''# ------------------------------------------------------------------ helpers
''', '''# ------------------------------------------------------------------ loot (--autotest=loot)

func _loot_run() -> void:
	_loot_census()
	_attachment_math()
	await _deploy()
	if not is_instance_valid(ch):
		return
	_loot_rest()
	await _loot_box_use()
	await _loot_pickup()
	await _attachment_views()
	await _loot_lineup()


func _droppable_ids() -> Array:
	var ids := {}
	for t in (Defs.loot.get("tables", {}) as Dictionary).values():
		for e in (t.get("entries", []) as Array) + (t.get("guaranteed", []) as Array):
			ids[str(e[0])] = true
	for w in Defs.weapons:
		ids[w] = true
	for a in Defs.attachments:
		ids[a] = true
	ids.erase("nothing")
	var out := ids.keys()
	out.sort()
	return out


func _loot_census() -> void:
	## Every id that can drop has its own model; loot boxes and floor loot across the map.
	var bad := []
	var ids := _droppable_ids()
	for id in ids:
		var md: Dictionary = world.map.item_visual(id)
		if md.get("mesh") == null or md.get("placeholder", false):
			bad.append(id)
	_check("loot_models_census", bad.is_empty(), "%d droppable ids, without a model: %s" % [ids.size(), str(bad)])
	var dyn = world.map.dyn
	var in_houses := 0
	var kinds := {}
	for b in dyn.loot_boxes:
		kinds[b.name] = int(kinds.get(b.name, 0)) + 1
		if int(dyn.containers[int(b.cid)].bid) >= 0:
			in_houses += 1
	var houses := 0
	for b in world.map.buildings:
		if str(b.get("kind", "house")) in ["house", "apartment", "shop"]:
			houses += 1
	_check("loot_boxes_count", dyn.loot_boxes.size() >= 2000 and in_houses >= houses,
		"%d loot boxes (%d inside buildings, %d houses/shops/apartments), by model %s" % [dyn.loot_boxes.size(), in_houses, houses, str(kinds)])
	var cats := {"weapon": 0, "ammo": 0, "attachment": 0, "other": 0}
	for id in dyn.items:
		var k := str(Defs.item(str(dyn.items[id].entry.id)).get("kind", ""))
		cats[k if cats.has(k) else "other"] = int(cats.get(k if cats.has(k) else "other", 0)) + 1
	_check("floor_loot_count", cats.weapon > 300 and cats.ammo > 500 and cats.attachment > 300,
		"%d items on the ground: %s" % [dyn.items.size(), str(cats)])


func _attachment_math() -> void:
	## Each attachment kind changes the stat it is for, measured on a weapon state with no character.
	var ws := WeaponState.new(null)
	var w := WeaponState.new_instance("rifle_556", null, 1.0)
	ws.slots[1] = w
	ws.cur = 1
	var z0 := ws.zoom()
	w.att = ["scope_4x"]
	var z4 := ws.zoom()
	w.att = ["sight_reddot"]
	var z1 := ws.zoom()
	_check("att_sight_zoom", absf(z4 - 4.0) < 0.01 and absf(z1 - 1.3) < 0.01 and ws.scoped() == false,
		"iron %.2f, red dot %.2f (not a scope view), 4x %.2f" % [z0, z1, z4])
	w.att = ["scope_4x", "grip_angled"]
	var ads_m := ws._ads_mult()
	_check("att_ads_time", absf(ads_m - 1.25 * 0.85) < 0.001, "4x scope with angled grip: aiming takes x%.3f" % ads_m)
	# Recoil of one shot, without and with a compensator and a vertical grip.
	var kicks := []
	for kit in [[], ["compensator"], ["compensator", "grip_vertical"]]:
		w.att = kit
		ws.kick = Vector2.ZERO
		ws.climb_pending = 0.0
		ws.burst = 1
		ws._apply_recoil(12345)
		kicks.append(ws.kick.y + ws.climb_pending)
	_check("att_recoil", kicks[1] < kicks[0] * 0.82 and kicks[2] < kicks[1] * 0.87,
		"vertical kick per shot: bare %.3f, compensator %.3f, + vertical grip %.3f deg" % kicks)
	w.att = []
	ws.ads = 0.0
	var sp0 := ws.spread_deg(0.0, false)
	w.att = ["laser_sight"]
	var sp1 := ws.spread_deg(0.0, false)
	_check("att_laser_spread", absf(sp1 - sp0 * 0.65) < 0.001, "hip spread %.2f -> %.2f deg with a laser" % [sp0, sp1])
	w.att = ["mag_ext_rifle"]
	var cap1 := ws.mag_cap()
	w.att = []
	var cap0 := ws.mag_cap()
	_check("att_mag_ext", cap0 == 30 and cap1 == 40, "magazine %d -> %d with the extended magazine" % [cap0, cap1])
	w.att = ["mag_quick_rifle"]
	w.mag = 5
	w.chamber = true
	ws.reserve_cache["556"] = 200
	ws.state = WeaponState.IDLE
	ws.start_reload()
	var t_quick := ws.timer
	w.att = []
	ws.state = WeaponState.IDLE
	ws.start_reload()
	var t_base := ws.timer
	_check("att_quick_reload", absf(t_quick - t_base * 0.7) < 0.01, "reload %.2f s -> %.2f s with the quickdraw magazine" % [t_base, t_quick])
	var sup := {"id": "pistol_9", "att": ["suppressor_light"]}
	_check("att_suppressor", Attach.mult(sup, "loudness_mult") < 0.5 and Attach.mult(sup, "flash_mult") < 0.15 and SoundSys.defs.has("shot_pistol_9_sup"),
		"loudness x%.2f, flash x%.2f, suppressed sound %s" % [Attach.mult(sup, "loudness_mult"), Attach.mult(sup, "flash_mult"), str(SoundSys.defs.has("shot_pistol_9_sup"))])
	_check("att_choke", absf(Attach.mult({"att": ["choke"]}, "pellet_spread_mult") - 0.65) < 0.001, "buckshot pattern x0.65 with a choke")
	# Break action: both barrels load at once.
	var dbl := WeaponState.new_instance("shotgun_double", null, 0.0)
	ws.slots[1] = dbl
	ws.reserve_cache["12buck"] = 10
	ws.state = WeaponState.IDLE
	ws.start_reload()
	ws._reload_step(10.0, false)
	_check("break_action_reload", ws.loaded() == 2 and int(ws.reserve_cache["12buck"]) == 8, "double barrel loaded %d, 8 shells left: %d" % [ws.loaded(), int(ws.reserve_cache["12buck"])])
	# Bitmask round trip (what other players see fitted).
	var kit2 := ["choke", "scope_8x", "weapon_light"]
	var back := Attach.from_bitmask(Attach.bitmask({"att": kit2}))
	back.sort()
	kit2.sort()
	_check("att_replication_mask", back == kit2, "%s -> %s" % [str(kit2), str(back)])


func _loot_rest() -> void:
	## Floor items rest on what is under them: a ray down from each must find a surface 0-5 cm below.
	var space = world.get_world_3d().direct_space_state
	var n := 0
	var ok := 0
	var worst := []
	var dyn = world.map.dyn
	for id in range(1, dyn.floor_count + 1, 7):
		if not dyn.items.has(id):
			continue
		var o: Vector3 = (dyn.items[id].xf as Transform3D).origin
		var q := PhysicsRayQueryParameters3D.create(o + Vector3.UP * 0.3, o + Vector3.DOWN * 0.6, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var r = space.intersect_ray(q)
		n += 1
		var gap := 9.0 if r.is_empty() else o.y - (r.position as Vector3).y
		if gap > -0.005 and gap < 0.05:
			ok += 1
		elif worst.size() < 6:
			worst.append("%s %.2f m at %s" % [str(dyn.items[id].entry.id), gap, str(o.snapped(Vector3.ONE * 0.1))])
	_check("floor_items_rest", n > 100 and ok >= n * 0.95, "%d of %d sampled items 0-5 cm above a surface; e.g. %s" % [ok, n, str(worst)])


func _nearest_box(in_house: bool) -> Dictionary:
	var dyn = world.map.dyn
	var best := {}
	var bd := INF
	for b in dyn.loot_boxes:
		var c: Dictionary = dyn.containers[int(b.cid)]
		if b.open or (in_house and int(c.bid) < 0):
			continue
		var d := (c.pos as Vector3).distance_to(ch.global_position)
		if d < bd:
			bd = d
			best = b
	return best


func _stand_by(target: Vector3, floor_y: float, dist: float = 1.2) -> bool:
	## Puts the player on open floor next to a point, looking at it, with nothing in between.
	var space = world.get_world_3d().direct_space_state
	for k in 12:
		var a := TAU * k / 12.0
		var stand := Vector3(target.x + cos(a) * dist, floor_y, target.z + sin(a) * dist)
		var down := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 1.0, stand + Vector3.DOWN * 0.4, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var hit = space.intersect_ray(down)
		if hit.is_empty() or absf((hit.position as Vector3).y - floor_y) > 0.25:
			continue
		var body := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 1.0, target + Vector3.UP * 0.05, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var head := PhysicsRayQueryParameters3D.create((hit.position as Vector3) + Vector3.UP * 1.65, target, Defs.SIGHT_MASK)
		var h2 = space.intersect_ray(head)
		if not space.intersect_ray(body).is_empty() and (space.intersect_ray(body).position as Vector3).distance_to(target) > 0.45:
			continue
		if not h2.is_empty() and (h2.position as Vector3).distance_to(target) > 0.45:
			continue
		_teleport((hit.position as Vector3) + Vector3.UP * 0.05, 0.0)
		return true
	return false


func _loot_box_use() -> void:
	## Walk up to a loot box in a house, Use it: its contents open on the SmarTab and the lid opens.
	var b := _nearest_box(true)
	if b.is_empty():
		_check("loot_box_opens", false, "no closed loot box")
		return
	var c: Dictionary = world.map.dyn.containers[int(b.cid)]
	var base_y: float = (b.xf as Transform3D).origin.y
	if not _stand_by(c.pos, base_y, 1.0) and not _stand_by(c.pos, base_y, 1.4):
		_check("loot_box_opens", false, "no place to stand by %s at %s" % [str(b.name), str((c.pos as Vector3).snapped(Vector3.ONE * 0.1))])
		return
	if not ch.light.on:
		await _tap("flashlight")
	await _wait(0.6)
	_look_at(c.pos)
	await _wait(0.5)
	await _shot("lootbox_closed")
	var t: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
	var prompt: String = world.hud.prompt.text
	await _tap("interact")
	var ok: bool = await _until(func(): return bool(b.open), 3.0)
	await _wait(0.6)
	await _shot("lootbox_open")
	var shown: Dictionary = world.hud.smartab.container
	_check("loot_box_opens", ok and t.get("kind", "") == "container" and int(t.get("id", -1)) == int(b.cid),
		"%s: target %s %s, prompt '%s', lid open %s, SmarTab shows %d entries" % [str(b.name), str(t.get("kind", "-")), str(t.get("id", "")), prompt,
		str(b.open), (shown.get("entries", []) as Array).size()])
	world.hud.smartab.close_container()


func _spawn_in_front(entry: Dictionary, d: float = 1.0) -> int:
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, ctl.yaw, 0)).z
	var p: Vector3 = ch.global_position + fwd * d
	var space = world.get_world_3d().direct_space_state
	var r = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.DOWN * 2.0, Defs.PHYS_WORLD | Defs.PHYS_PROP))
	if not r.is_empty():
		p = r.position
	var before: int = world.map.dyn._next_item
	world.map_item_spawn_server(entry, Transform3D(Basis(Vector3.UP, 0.4), p + Vector3.UP * 0.01))
	return before


func _loot_pickup() -> void:
	## Floor pickups: a scope goes straight onto the rifle, ammunition is named for the gun it fits, a gun picked up
	## takes compatible attachments from the bag.
	for s in [1, 2, 3]:
		ch.wpn.slots[s] = null
	world.interaction.give(ch, {"id": "rifle_556", "n": 1, "w": WeaponState.new_instance("rifle_556", null, 1.0)})
	ch.inv.mark_dirty()
	var id := _spawn_in_front({"id": "scope_4x", "n": 1})
	var it: Dictionary = world.map.dyn.items[id]
	_look_at((it.xf as Transform3D).origin + Vector3.UP * 0.03)
	await _wait(0.4)
	world.hud._prompt_t = 0.0
	await _wait(0.2)
	var prompt: String = world.hud.prompt.text
	await _shot("floor_scope_prompt")
	await _tap("interact")
	await _wait(0.3)
	_check("pickup_fits_scope", "scope_4x" in ch.wpn.slots[1].att and not world.map.dyn.items.has(id) and "fits your" in prompt,
		"prompt '%s'; rifle now has %s" % [prompt, str(ch.wpn.slots[1].att)])
	id = _spawn_in_front({"id": "ammo_556", "n": 30})
	_look_at((world.map.dyn.items[id].xf as Transform3D).origin + Vector3.UP * 0.02)
	await _wait(0.4)
	world.hud._prompt_t = 0.0
	await _wait(0.2)
	var prompt2: String = world.hud.prompt.text
	await _tap("interact")
	await _wait(0.3)
	_check("pickup_ammo_named", "for your" in prompt2 and ch.inv.count("ammo_556") >= 30, "prompt '%s'; carrying %d rounds" % [prompt2, ch.inv.count("ammo_556")])
	# A spare that fits nothing carried stays in the bag; picking up a gun it fits mounts it.
	world.interaction.give(ch, {"id": "grip_vertical", "n": 1})
	var in_bag: bool = ch.inv.count("grip_vertical") == 1 or "grip_vertical" in ch.wpn.slots[1].att
	world.interaction.give(ch, {"id": "suppressor_light", "n": 1})
	var sup_bag: bool = ch.inv.count("suppressor_light") == 1
	world.interaction.give(ch, {"id": "smg_9", "n": 1, "w": WeaponState.new_instance("smg_9", null, 1.0)})
	var smg = ch.wpn.slots[2] if ch.wpn.slots[2] != null and str(ch.wpn.slots[2].id) == "smg_9" else ch.wpn.slots[1]
	_check("gun_takes_bag_attachments", sup_bag and in_bag and "suppressor_light" in smg.att,
		"suppressor waited in the bag (%s), SMG picked up with %s" % [str(sup_bag), str(smg.att)])


func _sight_screen_error(wid: String, att: String) -> float:
	## Pixels between the reticle (where bullets go) and the fitted sight's optical axis on screen while aiming.
	var vm = ctl.vm
	var ax: Vector3 = AttachVisual.sight_axis(world.map, wid, att) - vm._grip_vis
	var world_pt: Vector3 = vm.weapon_root.global_transform * ax
	var cam: Camera3D = ctl.cam
	var off: Vector2 = ch.wpn.aim_offset_deg(Net.tick)
	var b: Basis = cam.global_transform.basis * Basis(Vector3.UP, deg_to_rad(-off.x)) * Basis(Vector3.RIGHT, deg_to_rad(off.y))
	var aim := cam.unproject_position(cam.global_position - b.z * 50.0)
	# The sight's line: from the eye through its optical centre.
	var through := cam.unproject_position(cam.global_position + (world_pt - cam.global_position).normalized() * 50.0)
	return aim.distance_to(through)


func _attachment_views() -> void:
	## First-person captures of fitted attachments; aiming lines a red dot up with the bullets; the scope view.
	var space = world.get_world_3d().direct_space_state
	# Outdoors under a lamp if the tour found one, else where we are.
	if not ch.light.on:
		await _tap("flashlight")
	for s in [1, 2, 3]:
		ch.wpn.slots[s] = null
	var rifle := WeaponState.new_instance("rifle_556", null, 1.0)
	rifle.att = ["sight_reddot", "suppressor_rifle", "grip_vertical", "mag_ext_rifle", "weapon_light"]
	ch.wpn.slots[1] = rifle
	ch.inv.add({"id": "ammo_556", "n": 60}, true)
	ch.inv.mark_dirty()
	await _tap("weapon_1")
	await _until(func(): return ch.wpn.current_id() == "rifle_556" and ch.wpn.state == WeaponState.IDLE, 4.0)
	ctl.pitch = -0.08
	await _wait(0.6)
	await _shot("rifle_kit_hip")
	_act_press("aim")
	await _wait(0.9)
	var err := _sight_screen_error("rifle_556", "sight_reddot")
	await _shot("rifle_reddot_aim")
	_act_release("aim")
	_check("reddot_on_bullet_line", err < 8.0, "red dot %.1f px from where the bullets go" % err)
	rifle.att = ["sight_holo", "compensator", "grip_angled", "laser_sight"]
	rifle.att.erase("laser_sight")
	rifle.att.append("weapon_light")
	await _wait(0.3)
	_act_press("aim")
	await _wait(0.9)
	var err2 := _sight_screen_error("rifle_556", "sight_holo")
	await _shot("rifle_holo_aim")
	_act_release("aim")
	_check("holo_on_bullet_line", err2 < 8.0, "holographic sight %.1f px from where the bullets go" % err2)
	for kit in [["scope_4x", "flash_hider"], ["scope_6x", "suppressor_rifle"]]:
		rifle.att = kit
		await _wait(0.3)
		_act_press("aim")
		await _wait(1.1)
		var scope_vis: bool = world.hud.scope.visible
		var gun_hidden: bool = not ctl.vm.weapon_root.visible
		var fov: float = ctl.cam.fov
		await _shot("rifle_%s_view" % kit[0])
		_act_release("aim")
		await _wait(0.4)
		var want := float(Settings.get_value("graphics", "fov")) / float(Defs.attachments[kit[0]].zoom)
		_check("scope_view_%s" % kit[0], scope_vis and gun_hidden and absf(fov - want) < 1.0,
			"scope view %s, gun hidden %s, field of view %.1f (want %.1f)" % [str(scope_vis), str(gun_hidden), fov, want])
	# The new guns in hand.
	for wid in ["marksman_308", "shotgun_double", "sumpak"]:
		var w2 := WeaponState.new_instance(wid, null, 1.0)
		if wid == "marksman_308":
			w2.att = ["scope_8x", "cheek_pad", "suppressor_rifle", "mag_ext_sniper"]
		elif wid == "shotgun_double":
			w2.att = ["choke", "bullet_loops"]
		ch.wpn.slots[1] = w2
		await _tap("holster")
		await _wait(0.3)
		await _tap("weapon_1")
		await _wait(1.2)
		await _shot("gun_%s" % wid)
		if wid == "marksman_308":
			_act_press("aim")
			await _wait(1.2)
			await _shot("gun_marksman_8x_view")
			_act_release("aim")
			await _wait(0.4)
	await _tap("holster")


func _loot_lineup() -> void:
	## One of every droppable thing laid out on the ground, captured from above (a work light for the picture).
	var ids := _droppable_ids()
	var p0: Vector3 = ch.global_position
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, ctl.yaw, 0)).z
	var right := fwd.cross(Vector3.UP).normalized()
	var space = world.get_world_3d().direct_space_state
	var cols := 8
	var spawned := 0
	for i in ids.size():
		var r := i / cols
		var c := i % cols
		var p := p0 + fwd * (1.4 + r * 0.75) + right * ((c - cols * 0.5 + 0.5) * 0.7)
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 2.0, Defs.PHYS_WORLD | Defs.PHYS_PROP))
		if hit.is_empty():
			continue
		var e := {"id": ids[i], "n": 1}
		if Defs.is_weapon(ids[i]):
			e.w = WeaponState.new_instance(ids[i], null, 1.0)
		world.map_item_spawn_server(e, Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z) + PI * 0.5), (hit.position as Vector3) + Vector3.UP * 0.01))
		spawned += 1
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 2.5
	lamp.shadow_enabled = true
	world.add_child(lamp)
	lamp.global_position = p0 + fwd * 3.5 + Vector3.UP * 3.0
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(p0 + Vector3.UP * 3.2 - fwd * 0.6, p0 + fwd * 3.2)
	cam.current = true
	await _wait(1.0)
	await _shot("loot_lineup")
	cam.look_at_from_position(p0 + Vector3.UP * 1.0 + fwd * 0.6, p0 + fwd * 2.2)
	await _wait(0.5)
	await _shot("loot_lineup_close")
	cam.current = false
	ctl.cam.current = true
	cam.queue_free()
	lamp.queue_free()
	_check("loot_lineup", spawned >= ids.size() * 0.9, "%d of %d ids laid out" % [spawned, ids.size()])


# ------------------------------------------------------------------ helpers
''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
