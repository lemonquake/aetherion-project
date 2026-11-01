extends RefCounted
## r24 checks on a Deathmatch listen host (`--autotest=r24`, `--r24_only=round,board,scopes,spectate,pause`):
##   godot --path game -- --host --game_mode=deathmatch --bots=20 --autostart=1 --autotest=r24 --shots=<dir>
## round: the enemy teams are wiped; frame times are recorded from the last kill through the round break and the
## next round's start (the lag spike), the winner banner and its countdown are captured and the break measured.
## board: the scoreboard held on ~ (captured), its numbers after a headshot kill, a grenade kill and an assist.
## scopes: each magnified sight aimed level at an enemy standing in the open, captured; the picture inside the lens
## must not be washed out (mean brightness and contrast against the same view without the scope).
## spectate: the player dies aimed through a 4x scope: the death and spectator cameras get the normal field of
## view back; the spectator views and watching everyone (alone vs bots).
## drum (r25): a drum sits in the magazine well in place of the gun's own magazine (first person at rest and while a
## reload carries it, third person, workbench); on a handgun it hangs under the grip.
## pause (last): the pause menu is open when the player leaves the match: nothing of it is left over the main menu.
## Measurements go to <shots>/r24_measure.json.

const R14 := preload("res://src/debug/autotest_r14.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")
const GunModel := preload("res://src/weapons/gun_model.gd")
const WeaponState := preload("res://src/weapons/weapon_state.gd")

var t = null
var world = null
var h = null          # the r14 helpers (guns, bots, open spots, frozen bots)
var measure := {}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world
	h = R14.new(autotest)


func run() -> void:
	var only := str(Game.arg("r24_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 40.0)
	await t._wait(1.5)
	world.map.lighting.forced_time = float(Game.arg("r24_time", 450.0))
	h._freeze_zone()
	for n in ["workbench", "drum", "board", "scopes", "round", "spectate", "pause"]:
		if not want.call(n):
			continue
		if n in ["workbench", "drum", "board", "scopes"]:
			h._holding = true
			h._keep_holding()
			h._freeze_bots(true)
			if is_instance_valid(t.ch):
				t.ch.health.test_invulnerable = true
		await (Callable(self, "_" + n)).call()
		if n == "pause":
			return   # leaving the match freed this test's node; the check finishes from a timer
		h._holding = false
		h._freeze_bots(false)
		await t._wait(0.3)
		_save()


func _save() -> void:
	var f := FileAccess.open(t.out_dir + "/r24_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


func _kill(c, part: String = "torso", cause: String = "test", attacker: int = -1) -> void:
	var res: Dictionary = c.health.apply_simple(9999.0, cause)
	res["hit_part"] = part
	res["hit_dir"] = Vector3.FORWARD
	c.health.last_cause = cause
	world._after_damage(c, res, attacker)


func _enemies() -> Array:
	var out := []
	for c in world.characters.values():
		if c.team != t.ch.team and c.mode == Motor.GROUND:
			out.append(c)
	return out


# ------------------------------------------------------------------ round end

func _round() -> void:
	var ms = world.match_server
	if ms == null or ms.win_by != "wipe":
		t._check("r24_round_banner", false, "not a Team Wipe deathmatch host (win_by %s)" % (ms.win_by if ms else "?"))
		return
	var r0: int = ms.round_number
	var en := _enemies()
	for i in range(en.size() - 1):
		_kill(en[i])
	await t._wait(1.5)
	var last := _enemies()
	# Frame times from the moment the last enemy falls until 2 s into the next round.
	var frames := []
	var t0 := Time.get_ticks_usec()
	var prev := t0
	var shot_banner := false
	var break_start := -1.0
	var round_started := -1.0
	for c in last:
		_kill(c)
	# With tools/prof_instrument.py applied, a slow frame also lists the sections that took the time.
	var prof := ClassDB.class_exists("Prof") or ResourceLoader.exists("res://src/debug/prof.gd")
	var Pf = load("res://src/debug/prof.gd") if prof else null
	if Pf:
		Pf.on = true
		Pf.reset()
	var acc0 := {}
	var slow := []
	while (Time.get_ticks_usec() - t0) / 1.0e6 < 9.0:
		await t.get_tree().process_frame
		var now := Time.get_ticks_usec()
		var s := (now - t0) / 1.0e6
		frames.append([snappedf(s, 0.001), snappedf((now - prev) / 1000.0, 0.1), ms.phase])
		if Pf:
			if (now - prev) > 40000:
				var parts := []
				for k in Pf.acc:
					var dd := int(Pf.acc[k]) - int(acc0.get(k, 0))
					if dd > 3000:
						parts.append([k, snappedf(dd / 1000.0, 0.1)])
				parts.sort_custom(func(a, b): return a[1] > b[1])
				slow.append([snappedf(s, 0.001), snappedf((now - prev) / 1000.0, 0.1), parts.slice(0, 8)])
			acc0 = Pf.acc.duplicate()
		prev = now
		if ms.phase == "round_end" and break_start < 0.0:
			break_start = s
		if ms.phase == "round_end" and not shot_banner and s > 1.2:
			shot_banner = true
			await t._shot("round_won_banner")
			prev = Time.get_ticks_usec()   # the capture's own save time is not the game's
			frames.append([snappedf(s, 0.001), 0.0, "capture"])
		if ms.round_number > r0 and round_started < 0.0:
			round_started = s
		if round_started > 0.0 and s > round_started + 2.0:
			break
	var worst := [0.0, 0.0, ""]
	var at_end := 0.0
	var at_start := 0.0
	var steady := []
	for f in frames:
		if float(f[1]) > float(worst[1]):
			worst = f
		if float(f[0]) < 0.5:
			at_end = maxf(at_end, float(f[1]))
		elif round_started > 0.0 and absf(float(f[0]) - round_started) < 0.5:
			at_start = maxf(at_start, float(f[1]))
		else:
			steady.append(float(f[1]))
	steady.sort()
	var p50: float = steady[steady.size() / 2] if not steady.is_empty() else 0.0
	var break_ticks: int = int(ms.get_meta("r24_break_ticks", -1)) if ms.has_meta("r24_break_ticks") else -1
	if Pf:
		Pf.on = false
	measure["round_slow_frames"] = slow
	measure["round"] = {"break_s": snappedf(round_started - break_start, 0.01) if round_started > 0.0 else -1.0, "worst_frame": worst,
		"max_ms_at_win": at_end, "max_ms_at_next_round": at_start, "median_ms": p50, "frames": frames}
	var banner = world.hud._round_banner
	t._check("r24_round_banner", banner != null and shot_banner and str(world.hud._round_banner_title.text).ends_with("wins the round"),
		"banner '%s' / '%s'" % [world.hud._round_banner_title.text if banner else "", world.hud._round_banner_count.text if banner else ""])
	var rule_s := float(Defs.rule("deathmatch.round_break_s", 4.0))
	t._check("r24_round_break_3s", round_started > 0.0 and absf(round_started - break_start - 3.0) < 0.35 and absf(rule_s - 3.0) < 0.01,
		"round %d -> %d; break %.2f s of wall time (rule %.1f s)" % [r0, ms.round_number, round_started - break_start, rule_s])
	t._check("r24_round_no_spike", at_end < 50.0 and at_start < 50.0,
		"longest frame at the win %.1f ms, at the next round %.1f ms (median %.1f ms); worst %s" % [at_end, at_start, p50, str(worst)])
	await t._until(func(): return is_instance_valid(world.local_char) and world.local_char.mode == Motor.GROUND, 10.0)
	t.ch = world.local_char
	t.ctl = world.controller


# ------------------------------------------------------------------ workbench

func _mouse(p: Vector2, button: int = 0, pressed: bool = false) -> void:
	## A real mouse event at p (UI coordinates of the 1920x1080 layout): motion, or a button press/release.
	var xf: Transform2D = t.get_tree().root.get_final_transform()
	var ev: InputEventMouse
	if button == 0:
		var mm := InputEventMouseMotion.new()
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _held else 0
		# Godot starts a drag (and the workbench turns the gun) from the motion's relative movement.
		mm.relative = (xf * p - _last_px) if _last_px != Vector2.INF else Vector2.ZERO
		mm.screen_relative = mm.relative
		_last_px = xf * p
		ev = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = button
		mb.pressed = pressed
		if button == MOUSE_BUTTON_LEFT:
			_held = pressed
		ev = mb
	ev.position = xf * p
	ev.global_position = ev.position
	Input.parse_input_event(ev)


var _held := false
var _last_px := Vector2.INF


func _drag_mouse(a: Vector2, b: Vector2, steps: int) -> void:
	_mouse(a)
	await t.get_tree().process_frame
	_mouse(a, MOUSE_BUTTON_LEFT, true)
	await t.get_tree().process_frame
	for i in steps:
		_mouse(a.lerp(b, float(i + 1) / steps))
		await t.get_tree().process_frame
		if i == steps / 2:
			var vp: Viewport = t.get_viewport()
			print("[r24] drag probe: dragging %s, data %s, mouse %s, focus %s" % [str(vp.gui_is_dragging()), str(vp.gui_get_drag_data()).left(80),
				str(vp.get_mouse_position()), str(vp.gui_get_focus_owner())])
	_mouse(b, MOUSE_BUTTON_LEFT, false)
	await t.get_tree().process_frame


func _workbench() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await h._gun("rifle_m416", ["sight_reddot"])
	for id in ["scope_4x", "grip_heavy", "mag_drum_rifle", "stock_tactical", "suppressor_rifle", "laser_green", "scope_thermal"]:
		t.ch.inv.add({"id": id, "n": 1}, true)
	t.ch.inv.mark_dirty()
	await t._wait(0.4)
	await t._tap("workbench")
	await t._wait(0.8)
	var wb = t.ctl.workbench
	t._check("r24_wb_opens", wb != null and is_instance_valid(wb) and t.ctl.paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"K opened the workbench %s; player held %s" % [str(wb != null), str(t.ctl.paused)])
	if wb == null:
		return
	await t._shot("workbench_open")
	# Hover a card: the info card says what it does, the numbers preview it.
	var card: Control = null
	for c in wb._list.get_children():
		if c is PanelContainer and c.get_child_count() > 0:
			var lab := _first_label(c)
			if lab and lab.text == Defs.item_name("mag_drum_rifle"):
				card = c
	var info_txt := ""
	if card:
		_mouse(card.get_global_rect().get_center())
		await t._wait(0.5)
		for l in wb._info_v.find_children("*", "Label", true, false):
			info_txt += (l as Label).text + " | "
		await t._shot("workbench_hover_info")
	t._check("r24_wb_info", wb._info.visible and info_txt.contains("rounds per magazine") and info_txt.contains("slower reload"),
		"hover card: %s" % info_txt.left(300))
	# A real drag with the mouse: the drum from the list onto the gun.
	var view: Rect2 = wb._vpc.get_global_rect()
	if card:
		await _drag_mouse(card.get_global_rect().get_center(), view.get_center(), 14)
	await t._wait(0.2)
	await t._shot("workbench_drum_snapping")
	await t._wait(1.0)
	var w = t.ch.wpn.slots[1]
	var dragged: bool = w != null and "mag_drum_rifle" in w.att
	t._check("r24_wb_drag_fits", dragged and Attach_cap(w) == 60, "after dragging the drum onto the gun: fitted %s; magazine %d" % [
		str(w.att if w else []), Attach_cap(w)])
	# The rest through the screen's own drop handler (the same path a drop takes), one at a time.
	for id in ["scope_4x", "grip_heavy", "stock_tactical", "suppressor_rifle", "laser_green"]:
		var e := {}
		for x in wb.source.available(wb.gun_key, wb._wid):
			if str(x.id) == id:
				e = x
		if not e.is_empty():
			wb._drop_on_gun(view.get_center(), {"wb_att": e})
			await t._wait(0.22)
			if id == "grip_heavy":
				await t._shot("workbench_plus_burst")
			await t._wait(0.5)
	await t._wait(0.6)
	w = t.ch.wpn.slots[1]
	var want := ["scope_4x", "grip_heavy", "mag_drum_rifle", "suppressor_rifle", "laser_green"].filter(func(a): return Attach.compatible("rifle_m416", a))
	if Attach.compatible("rifle_m416", "stock_tactical"):
		want.append("stock_tactical")
	var missing := want.filter(func(a): return not a in w.att)
	var reddot_back: bool = t.ch.inv.count("sight_reddot") >= 1
	await t._shot("workbench_full_kit")
	t._check("r24_wb_fits_all", missing.is_empty() and reddot_back, "fitted %s; missing %s; the red dot it replaced went to the bag: %s" % [
		str(w.att), str(missing), str(reddot_back)])
	# Turn and zoom with the mouse.
	var y0: float = wb._yaw
	var z0: float = wb._zoom
	await _drag_mouse(view.get_center() + Vector2(-150, 60), view.get_center() + Vector2(150, 60), 10)
	_mouse(view.get_center(), MOUSE_BUTTON_WHEEL_UP, true)
	_mouse(view.get_center(), MOUSE_BUTTON_WHEEL_UP, false)
	await t._wait(0.3)
	await t._shot("workbench_turned")
	t._check("r24_wb_turn_zoom", absf(wb._yaw - y0) > 1.0 and wb._zoom < z0, "yaw %.2f -> %.2f, zoom %.2f -> %.2f" % [y0, wb._yaw, z0, wb._zoom])
	# Take one off with its x.
	wb._remove("laser_green")
	await t._wait(0.8)
	w = t.ch.wpn.slots[1]
	t._check("r24_wb_remove", not "laser_green" in w.att and t.ch.inv.count("laser_green") >= 1, "after x: fitted %s; laser in bag %d" % [
		str(w.att), t.ch.inv.count("laser_green")])
	# Esc closes it and gives the player back.
	await t._tap("menu")
	await t._wait(0.4)
	t._check("r24_wb_closes", t.ctl.workbench == null and not t.ctl.paused and t.ctl._pause_ui == null,
		"Esc: workbench gone %s, player free %s, no pause menu %s" % [str(t.ctl.workbench == null), str(not t.ctl.paused), str(t.ctl._pause_ui == null)])
	# Game Setup's workbench: the Deathmatch loadout, every attachment the gun takes, models without a map.
	var WB := preload("res://src/ui/workbench_ui.gd")
	var lw = WB.new(WB.LoadoutSource.new(null), "primary")
	Game.ui.add_child(lw)
	await t._wait(0.6)
	var lwid: String = lw._wid
	var opts := Attach.options(lwid, "mag").size() + Attach.options(lwid, "grip").size()
	var e2 := {}
	for x in lw.source.available("primary", lwid):
		if Attach.kind(str(x.id)) == "grip":
			e2 = x
	if not e2.is_empty():
		lw._drop_on_gun(Vector2.ZERO, {"wb_att": e2})
	await t._wait(1.0)
	await t._shot("workbench_game_setup")
	var lo: Dictionary = Profile.get_loadout()
	t._check("r24_wb_loadout", lw._gun_mesh.mesh != null and not e2.is_empty() and str(e2.id) in lo.get("att_primary", []) and lw._list.get_child_count() > opts,
		"Game Setup bench on %s: model %s, fitted %s -> profile %s" % [lwid, str(lw._gun_mesh.mesh != null), str(e2.get("id", "")), str(lo.get("att_primary", []))])
	lw.close()
	await t._wait(0.3)
	Input.mouse_mode = Settings.play_mouse_mode()


func _drum() -> void:
	var vm = t.ctl.vm
	var map = world.map
	var rows := {}
	for pair in [["rifle_m416", "mag_drum_rifle"], ["smg_ump45", "mag_drum_light"], ["pistol_9", "mag_drum_light"]]:
		var wid: String = pair[0]
		var aid: String = pair[1]
		if not Attach.compatible(wid, aid):
			rows[wid] = {"ok": false, "why": "does not take " + aid}
			continue
		await h._gun(wid, [aid])
		t.ctl.pitch = -0.12
		await t._wait(0.8)
		var in_well := not GunModel.well(wid).is_empty()
		var mag = vm._parts.get("mag", {}).get("node")
		var drum: Node3D = mag.get_node_or_null("WellDrum") if mag is MeshInstance3D else null
		var tp_mesh: Mesh = t.ch.visual.weapon_mesh.mesh
		var r := {"well": in_well, "fp_mag_hidden": mag is MeshInstance3D and (mag as MeshInstance3D).mesh == null,
			"fp_drum_on_mag": drum != null, "tp_without_mag": tp_mesh == GunModel.without_mag(wid) if in_well else tp_mesh == map.item_visual(wid).get("mesh")}
		if in_well:
			# The drum's top is up in the well, a little above the lip (weapon item_visual space).
			var amd: Dictionary = map.item_visual(aid)
			var top: Vector3 = (AttachVisual.mount_xf(map, wid, aid) * (amd.get("xf", Transform3D()) as Transform3D).affine_inverse()) * Vector3(0, (amd.size as Vector3).y, 0)
			var lip: Vector3 = (map.item_visual(wid).get("xf", Transform3D()) as Transform3D) * (GunModel.well(wid).lip as Vector3)
			r["seat_m"] = snappedf(top.y - lip.y, 0.001)
		await t._shot("drum_%s_rest" % wid)
		if drum:
			# A reload carries the drum out in the left hand.
			var rest: Vector3 = drum.global_position
			t._act_press("fire")
			await t._wait(0.35)
			t._act_release("fire")
			await t._wait(0.3)
			await t._tap("reload")
			await t._until(func(): return vm._mag_mode == "hand", 4.0)
			await t._wait(0.25)
			r["reload_moved_m"] = snappedf(drum.global_position.distance_to(rest), 0.01)
			r["drum_visible_in_hand"] = drum.is_visible_in_tree()
			await t._shot("drum_%s_reload" % wid)
			await t._until(func(): return t.ch.wpn.state == WeaponState.IDLE, 6.0)
		if in_well:
			r["ok"] = r.fp_mag_hidden and r.fp_drum_on_mag and r.tp_without_mag and float(r.seat_m) > 0.005 and float(r.seat_m) < 0.03 \
				and float(r.get("reload_moved_m", 0.0)) > 0.05 and bool(r.get("drum_visible_in_hand", false))
		else:
			r["ok"] = not r.fp_drum_on_mag and r.tp_without_mag
		rows[wid] = r
	measure["drum"] = rows
	var bad := rows.keys().filter(func(k): return not bool(rows[k].ok))
	t._check("r25_drum_in_well", bad.is_empty(), "%s" % JSON.stringify(rows))
	# The workbench draws the gun without its own magazine too.
	var wb_rows := {}
	for pair in [["rifle_m416", "mag_drum_rifle"], ["smg_ump45", "mag_drum_light"]]:
		await h._gun(pair[0], [pair[1]])
		await t._tap("workbench")
		await t._wait(1.0)
		var wb = t.ctl.workbench
		wb_rows[pair[0]] = wb != null and wb._gun_mesh.mesh == GunModel.without_mag(pair[0])
		await t._shot("drum_workbench_" + str(pair[0]))
		if wb:
			await t._tap("menu")
			await t._wait(0.4)
	t._check("r25_drum_workbench", not false in wb_rows.values(), "workbench gun mesh without its magazine: %s" % str(wb_rows))


static func Attach_cap(w) -> int:
	return Attach.mag_cap(w) if w != null else 0


func _first_label(n: Node) -> Label:
	if n is Label:
		return n
	for c in n.get_children():
		var l := _first_label(c)
		if l:
			return l
	return null


# ------------------------------------------------------------------ scoreboard

func _board() -> void:
	var ms = world.match_server
	var en := _enemies()
	if en.size() < 3:
		t._check("r24_board_stats", false, "not enough enemies (%d)" % en.size())
		return
	var me: int = t.ch.eid
	var mate = null
	for c in world.characters.values():
		if c.team == t.ch.team and c != t.ch and c.mode == Motor.GROUND:
			mate = c
			break
	var before: Dictionary = ms._stats_of_pid(Net.local_pid).duplicate()
	var victim_pid: int = en[0].pid
	# A headshot kill, a grenade kill, and an assist (the player hurts, a teammate finishes).
	_kill(en[0], "head", "gunshot", me)
	_kill(en[1], "torso", "explosion", me)
	var res: Dictionary = en[2].health.apply_simple(30.0, "gunshot")
	world._after_damage(en[2], res, me)
	if mate:
		_kill(en[2], "torso", "gunshot", mate.eid)
	await t._wait(0.3)
	var after: Dictionary = ms._stats_of_pid(Net.local_pid)
	var d := {}
	for k in ["kills", "hs_kills", "nade_kills", "assists", "damage"]:
		d[k] = float(after.get(k, 0)) - float(before.get(k, 0))
	var vs = ms._stats_of_pid(victim_pid)
	t._check("r24_board_stats", d.kills == 2 and d.hs_kills == 1 and d.nade_kills == 1 and (d.assists == 1 or mate == null) and d.damage >= 29.0
		and vs != null and int(vs.hs_deaths) >= 1, "changes for the player %s; headshot victim deaths %d / headshot deaths %d" % [str(d),
		int(vs.deaths) if vs else -1, int(vs.hs_deaths) if vs else -1])
	t._act_press("scoreboard")
	await t._wait(0.8)
	await t._shot("scoreboard_held")
	var sb = world.hud.scoreboard
	var shown: bool = sb != null and sb.visible and sb.size.x > 600.0
	t._act_release("scoreboard")
	await t._wait(0.3)
	t._check("r24_board_shown", shown and not sb.visible, "held: shown %s (%.0f x %.0f), released: hidden %s" % [str(shown),
		sb.size.x if sb else 0.0, sb.size.y if sb else 0.0, str(sb and not sb.visible)])
	# Each team's standing count under its name in the team bar.
	var al: Dictionary = world.match_info.get("alive", {})
	var txt := []
	for row in world.hud._team_labels:
		txt.append(row[2].text)
	var mine := int(al.get(t.ch.team, 0))
	t._check("r24_alive_counts", txt.size() >= 2 and ("%d alive" % mine) in txt, "team bar %s; server %s" % [str(txt), str(al)])
	await t._shot("team_bar_alive")


# ------------------------------------------------------------------ scopes

const SCOPES := ["scope_2x", "scope_3x", "scope_4x", "scope_thermal", "scope_night", "scope_6x", "scope_8x", "scope_lpvo", "scope_15x"]


func _scopes() -> void:
	var en: Array = h._bots(false)
	if en.is_empty():
		t._check("r24_scopes_clear", false, "no enemy bot")
		return
	var target = en[0].ch
	# A spot in the open at the test distance that the player's eye can see (chest high), whichever way that is.
	var dist := float(Game.arg("r24_scope_dist", 30.0))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var spot := Vector3.INF
	for k in 16:
		var yw: float = t.ctl.yaw + k * TAU / 16.0
		var fwd := -Basis.from_euler(Vector3(0, yw, 0)).z
		var p: Vector3 = h._open_spot(t.ch.global_position + fwd * dist, 0.5, 0.0)
		if p.distance_to(t.ch.global_position) < dist * 0.6:
			continue
		var q := PhysicsRayQueryParameters3D.create(t.ch.eye_position(), p + Vector3.UP * 1.2, Defs.SIGHT_MASK)
		q.exclude = [t.ch.get_rid(), target.get_rid()]
		if space.intersect_ray(q).is_empty():
			spot = p
			break
	if spot == Vector3.INF:
		t._check("r24_scopes_clear", false, "no open spot in sight at %.0f m" % dist)
		return
	target.global_position = spot
	target.velocity = Vector3.ZERO
	var rows := {}
	var worst := ["", 0.0]
	# The same view with no scope (iron sights, not aimed) is the reference.
	await h._gun("rifle_556", [])
	t._look_at(spot + Vector3.UP * 1.2)
	await t._wait(0.6)
	var ref := await _lens_stats(spot)
	await t._shot("scope_ref_noscope")
	rows["none"] = ref
	for sid in SCOPES:
		await h._gun("rifle_556", [sid])
		target.global_position = spot
		t._look_at(spot + Vector3.UP * 1.2)
		t._act_press("aim")
		if sid in ["scope_4x", "scope_thermal"]:
			for k in 3:
				await t._wait(0.09)
				await t._shot("scope_aiming_%s_%d" % [sid, k])
		await t._wait(1.4)
		var st := await _lens_stats(spot)
		await t._shot("scope_level_" + sid)
		t._act_release("aim")
		await t._wait(0.3)
		rows[sid] = st
		# Washed out: much brighter than the plain view and with the contrast gone.
		var wash: float = float(st.mean) - float(ref.mean)
		if wash > float(worst[1]):
			worst = [sid, wash]
	measure["scopes"] = rows
	# A filter shows as a lens much brighter than the plain view, the colour gone (grey), or one colour taking over
	# (green): compared with the plain 4x scope, which draws the real picture.
	var bad := []
	var plain: Dictionary = rows.get("scope_4x", ref)
	for sid in SCOPES:
		var st: Dictionary = rows[sid]
		var rgb: Array = st.rgb
		var green: bool = float(rgb[1]) > float(rgb[0]) * 1.35 and float(rgb[1]) > float(rgb[2]) * 1.35
		# (night vision is meant to brighten the dark: only its colour is checked)
		if (float(st.mean) > float(ref.mean) + 25.0 and sid != "scope_night") or float(st.sat) < float(plain.sat) * 0.5 or green:
			bad.append(sid)
	t._check("r24_scopes_clear", bad.is_empty(), "lens mean/contrast/saturation per sight %s (no scope %s); filtered or washed out: %s" % [
		str(rows.keys().map(func(k): return "%s %.0f/%.0f/%.2f" % [k, float(rows[k].mean), float(rows[k].sd), float(rows[k].sat)])),
		str([ref.mean, ref.sd, ref.sat]), str(bad)])


func _lens_stats(spot: Vector3) -> Dictionary:
	## Mean and spread of brightness (0-255) in a box round the target, the middle of the lens.
	var img: Image = await h._grab()
	var sz := img.get_size()
	var box := Rect2i(int(sz.x * 0.5 - sz.y * 0.16), int(sz.y * 0.34), int(sz.y * 0.32), int(sz.y * 0.32))
	var c := img.get_region(box)
	c.convert(Image.FORMAT_RGB8)
	c.resize(48, 48)
	var vals := []
	var sum := 0.0
	var sat := 0.0
	var rgb := Color(0, 0, 0)
	for y in 48:
		for x in 48:
			var px := c.get_pixel(x, y)
			var l := px.get_luminance() * 255.0
			vals.append(l)
			sum += l
			sat += px.s
			rgb += px
	var mean := sum / vals.size()
	var var_sum := 0.0
	for v in vals:
		var_sum += (v - mean) * (v - mean)
	rgb /= float(vals.size())
	return {"mean": snappedf(mean, 0.1), "sd": snappedf(sqrt(var_sum / vals.size()), 0.1), "sat": snappedf(sat / vals.size(), 0.01),
		"rgb": [snappedf(rgb.r, 0.01), snappedf(rgb.g, 0.01), snappedf(rgb.b, 0.01)]}


# ------------------------------------------------------------------ spectate

func _spectate() -> void:
	var base_fov := float(Settings.get_value("graphics", "fov"))
	t.ch.health.test_invulnerable = false
	await h._gun("rifle_556", ["scope_4x"])
	t._act_press("aim")
	await t._wait(1.4)
	var fov_aimed: float = t.ctl.cam.fov
	_kill(t.ch)
	t._act_release("aim")
	await t._wait(1.0)
	var fov_death: float = t.ctl.cam.fov
	await t._shot("spectate_death_cam_after_scope")
	t.ctl._death = {}   # straight to watching
	await t._wait(1.0)
	var fov_spec: float = t.ctl.cam.fov
	var overlay_off: bool = not world.hud.scope.visible
	await t._shot("spectate_after_scope")
	t._check("r24_spectate_fov", fov_aimed < base_fov * 0.5 and absf(fov_death - base_fov) < 0.5 and absf(fov_spec - base_fov) < 0.5 and overlay_off,
		"field of view aimed %.1f, death camera %.1f, spectating %.1f (normal %.1f); scope picture hidden %s" % [fov_aimed, fov_death, fov_spec, base_fov, overlay_off])
	# Views: behind, over the shoulder, overhead, free camera.
	var dists := []
	for i in 4:
		var tgt = world.characters.get(t.ctl.spectating)
		var d: float = t.ctl.cam.global_position.distance_to(tgt.global_position) if tgt else -1.0
		var up: float = t.ctl.cam.global_position.y - tgt.global_position.y if tgt else 0.0
		dists.append([t.ctl.SPECT_VIEW_NAMES[t.ctl.spect_view], snappedf(d, 0.1), snappedf(up, 0.1)])
		await t._shot("spectate_view_%d" % i)
		await t._tap("interact")
		await t._wait(0.6)
	# Overhead is the highest of the three (under a roof it stops at the ceiling), over the shoulder the closest.
	t._check("r24_spectate_views", dists.size() == 4 and float(dists[2][2]) > float(dists[0][2]) + 1.0 and float(dists[1][1]) < float(dists[0][1]),
		"camera [distance, height above] the watched player per view %s" % str(dists))
	# Free camera moves with the move keys.
	while t.ctl.spect_view != t.ctl.SpectView.FREE:
		await t._tap("interact")
	var p0: Vector3 = t.ctl.cam.global_position
	t._act_press("move_forward")
	await t._wait(1.0)
	t._act_release("move_forward")
	var flew: float = t.ctl.cam.global_position.distance_to(p0)
	await t._shot("spectate_free_camera")
	while t.ctl.spect_view != t.ctl.SpectView.BEHIND:
		await t._tap("interact")
	# Alone vs bots: everyone can be watched (enemies too).
	var mates_only: Array = t.ctl.spectate_candidates()
	await t._tap("reload")
	await t._wait(0.3)
	var everyone: Array = t.ctl.spectate_candidates()
	var enemy := -1
	for eid in everyone:
		if world.characters.has(eid) and world.characters[eid].team != int(Net.players[Net.local_pid].team):
			enemy = eid
			break
	if enemy >= 0:
		t.ctl._set_spectate(enemy)
		await t._wait(1.0)
		await t._shot("spectate_enemy")
	t._check("r24_spectate_everyone", flew > 5.0 and everyone.size() > mates_only.size() and enemy >= 0 and t.ctl.spectating == enemy,
		"free camera flew %.1f m in 1 s; watch list %d -> %d (enemy %d watched: %s); hint '%s'" % [flew, mates_only.size(), everyone.size(), enemy,
		str(t.ctl.spectating == enemy), world.hud.spect_hint.text])


# ------------------------------------------------------------------ pause

func _pause() -> void:
	if not is_instance_valid(t.ctl):
		t._check("r24_pause_cleared", false, "no controller")
		return
	await t._tap("menu")
	await t._wait(0.5)
	var open: bool = t.ctl._pause_ui != null and is_instance_valid(t.ctl._pause_ui)
	await t._shot("pause_open")
	# Leaving frees the world and this test with it: the check runs from a SceneTree timer and ends the run.
	var done: Array = t.results.duplicate()
	t.get_tree().create_timer(1.5).timeout.connect(_after_leave.bind(t.out_dir, done, open))
	_save()
	Game.leave_to_menu()


static func _after_leave(out_dir: String, done: Array, was_open: bool) -> void:
	var left := []
	for c in Game.ui.get_children():
		if c.get_script() == preload("res://src/ui/pause_menu.gd"):
			left.append(str(c.name))
	var img := Game.get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/99_menu_after_leave.png")
	var ok := was_open and left.is_empty() and Game.state == "menu"
	print("[autotest] %s r24_pause_cleared: pause menu was open %s; pause menus left over the main menu %s; state %s" % [
		"PASS" if ok else "FAIL", str(was_open), str(left), Game.state])
	done.append(["r24_pause_cleared", ok, "left %s" % str(left)])
	var failed := done.filter(func(r): return not r[1]).size()
	print("[autotest] done: %d checks, %d failed" % [done.size(), failed])
	var f := FileAccess.open(out_dir + "/results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(done, "  "))
	Game.get_tree().quit(1 if failed > 0 else 0)
