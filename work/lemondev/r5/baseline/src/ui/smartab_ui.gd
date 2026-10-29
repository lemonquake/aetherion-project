extends Control
## The SmarTab screen (rendered into a SubViewport and shown on the device in the player's left hand).
## Pages: Status (weapons, ammunition, body diagram, condition, bleeding, armour, light and batteries),
## Weapons (each gun's attachment mounts: fit and remove), Items (carried items and an open container or body),
## Map (terrain, the haze, team positions) and Team.

signal request(req: Dictionary)

const PAGES := ["Status", "Weapons", "Items", "Map", "Team"]
const Attach := preload("res://src/weapons/attachments.gd")
const MOUNTS := [["sight", "Sight"], ["muzzle", "Muzzle"], ["grip", "Grip"], ["mag", "Magazine"], ["stock", "Stock"], ["light", "Light"]]
const GOOD := Color(0.55, 0.85, 0.6)
const WARN := Color(0.95, 0.75, 0.35)
const BAD := Color(0.95, 0.38, 0.32)
const DIM := Color(0.55, 0.62, 0.6)
const INK := Color(0.86, 0.92, 0.88)
const BG := Color(0.03, 0.05, 0.05)

var world = null
var page := 0
var container: Dictionary = {}   # {kind, id, entries}
var selected := -1
var map_tex: ImageTexture
var _buttons: Array = []         # [Rect2, Dictionary action]
var _font: Font
var _mono: Font
var _scale := 1.0


func _ready() -> void:
	UITheme.fonts()
	_font = UITheme.font_medium
	_mono = UITheme.font_mono
	size = Vector2(720, 720)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_world(w) -> void:
	world = w
	if world.map and world.map.map_image:
		map_tex = ImageTexture.create_from_image(world.map.map_image)


func next_page(d: int) -> void:
	page = (page + d + PAGES.size()) % PAGES.size()
	SoundSys.play_local("smartab_tap", -6.0)
	queue_redraw()


func open_page(name: String) -> void:
	page = PAGES.find(name)
	queue_redraw()


func _process(_dt: float) -> void:
	_scale = float(Settings.get_value("accessibility", "smartab_text_scale"))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for b in _buttons:
			if (b[0] as Rect2).has_point(event.position):
				_act(b[1])
				accept_event()
				return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		next_page(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)


func _act(a: Dictionary) -> void:
	SoundSys.play_local("smartab_tap", -4.0)
	match str(a.get("ui", "")):
		"page":
			page = int(a.page)
		"select":
			selected = int(a.index)
		_:
			request.emit(a)
	queue_redraw()


func show_container(kind: String, id: int, entries: Array) -> void:
	container = {"kind": kind, "id": id, "entries": entries}
	page = PAGES.find("Items")
	queue_redraw()


func close_container() -> void:
	if not container.is_empty():
		request.emit({"op": "close"})
	container = {}


# ------------------------------------------------------------------ drawing helpers

func _t(text: String, pos: Vector2, size: int, col: Color = INK, font: Font = null) -> void:
	draw_string(font if font else _font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size * _scale), col)


func _button(r: Rect2, label: String, action: Dictionary, accent: Color = Color(0.25, 0.35, 0.3)) -> void:
	draw_rect(r, Color(accent, 0.55))
	draw_rect(r, Color(accent.lightened(0.3), 0.9), false, 2.0)
	_t(label, r.position + Vector2(10, r.size.y * 0.5 + 8), 22)
	_buttons.append([r, action])


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0.12, 0.15, 0.15))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)


func _draw() -> void:
	_buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	# Faint scanlines give the screen texture without hurting legibility.
	for y in range(0, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.012))
	var ch = world.local_char if world else null
	# Tabs
	for i in PAGES.size():
		var r := Rect2(12 + i * 140, 10, 134, 50)
		var on := i == page
		draw_rect(r, Color(0.16, 0.24, 0.2, 0.9) if on else Color(0.07, 0.1, 0.1, 0.9))
		if on:
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4)), GOOD)
		_t(PAGES[i], r.position + Vector2(12, 34), 24, INK if on else DIM)
		_buttons.append([r, {"ui": "page", "page": i}])
	if ch == null:
		_t("No signal", Vector2(260, 380), 34, DIM)
		return
	match PAGES[page]:
		"Status":
			_status(ch)
		"Weapons":
			_weapons(ch)
		"Items":
			_items(ch)
		"Map":
			_map(ch)
		"Team":
			_team(ch)
	# Clock and battery of the device itself
	var mins := int(world.match_info.get("zone", {}).get("i", 0))
	_t("< >: page    tap: select" if Settings.touch_active() else "Q / E or wheel: page    click: select", Vector2(16, 706), 18, DIM)


# ------------------------------------------------------------------ Status

func _status(ch) -> void:
	var h = ch.health
	var cond: String = h.condition() if h else "NORMAL"
	var cc := GOOD if cond == "NORMAL" else (WARN if cond == "INJURED" else BAD)
	_t(cond, Vector2(24, 112), 46, cc)
	_t("Health %d" % int(h.health), Vector2(24, 146), 24, DIM)
	# Weapons
	var y := 186.0
	var names := ["Primary", "Secondary", "Handgun"]
	for s in [1, 2, 3]:
		var w = ch.wpn.slots[s]
		var active: bool = ch.wpn.cur == s
		var label: String = names[s - 1]
		if w == null:
			_t("%s  —" % label, Vector2(24, y), 22, DIM)
		else:
			var d := Defs.weapon(str(w.id))
			var loaded := int(w.mag) + (1 if w.chamber else 0)
			var ammo := str(d.get("ammo", ""))
			var reserve: int = ch.inv.count("ammo_" + ammo)
			var line := "%s  %s" % [label, str(d.get("name", w.id))]
			_t(line, Vector2(24, y), 24 if active else 22, INK if active else DIM)
			var mode := ""
			if active:
				mode = "  " + ch.wpn.fire_mode().capitalize()
			var feed := str(d.get("feed", "mag"))
			var chamber_txt := ""
			if feed == "mag":
				chamber_txt = "  (%d in magazine%s)" % [int(w.mag), ", +1 chambered" if w.chamber else ""]
			_t("%d loaded%s   %d spare%s" % [loaded, chamber_txt, reserve, mode], Vector2(40, y + 26), 20, INK if active else DIM, _mono)
			var atts: Array = w.get("att", [])
			if not atts.is_empty():
				_t(", ".join(atts.map(func(a): return str(Defs.attachments.get(a, {}).get("name", a)))), Vector2(40, y + 48), 18, DIM)
		y += 74.0
	# Light and batteries
	var c: float = ch.light.charge()
	var light_name := "Weapon light" if ch.light.weapon_mounted else "Flashlight"
	if c < 0.0:
		_t("No light", Vector2(24, 430), 24, DIM)
	else:
		_t("%s %d%%%s" % [light_name, int(c * 100.0), "  LOW" if ch.light.low() else ""], Vector2(24, 430), 24, BAD if ch.light.low() else INK)
		_bar(Rect2(24, 442, 250, 12), c, BAD if ch.light.low() else GOOD)
	var bats: Array = ch.inv.batteries()
	var bt := "Spare batteries: %d" % bats.size()
	if not bats.is_empty():
		bt += "  (" + ", ".join(bats.map(func(b): return "%d%%" % int(float(b.c) * 100.0))) + ")"
	_t(bt, Vector2(24, 486), 20, INK if not bats.is_empty() else DIM)
	_t("Hold Light to change batteries" if Settings.touch_active() else "Hold the light key to change batteries", Vector2(24, 512), 18, DIM)
	# Armour
	var ay := 556.0
	for slot in ["helmet", "vest"]:
		var g = ch.inv.gear.get(slot)
		if g == null:
			_t("%s: none" % slot.capitalize(), Vector2(24, ay), 20, DIM)
		else:
			var d2 := Defs.item(str(g.id))
			var frac := float(g.get("d", 0.0)) / float(d2.get("durability", 100))
			var broken := frac <= 0.0
			_t("%s  %s" % [str(d2.name), "BROKEN" if broken else "%d%%" % int(frac * 100)], Vector2(24, ay), 20, BAD if broken else INK)
			_bar(Rect2(24, ay + 8, 250, 8), frac, BAD if frac < 0.3 else GOOD)
		ay += 44.0
	# Treatment
	var tr: Dictionary = h.treatment if h else {}
	if not tr.is_empty():
		_t("Treating: %s" % Defs.item_name(str(tr.item)), Vector2(24, 660), 22, WARN)
		_bar(Rect2(24, 670, 300, 10), float(tr.t) / maxf(float(tr.total), 0.01), WARN)
	_body(ch, Vector2(470, 120))


func _body(ch, o: Vector2) -> void:
	## Front view body diagram. Colour = part health; drops = bleeding; dashed = broken; outline = armour.
	var h = ch.health
	var shapes := {
		"head": Rect2(o + Vector2(70, 0), Vector2(60, 66)),
		"torso": Rect2(o + Vector2(52, 74), Vector2(96, 150)),
		"arm_r": Rect2(o + Vector2(0, 80), Vector2(44, 160)),
		"arm_l": Rect2(o + Vector2(156, 80), Vector2(44, 160)),
		"leg_r": Rect2(o + Vector2(52, 232), Vector2(44, 200)),
		"leg_l": Rect2(o + Vector2(104, 232), Vector2(44, 200)),
	}
	for part in shapes:
		var r: Rect2 = shapes[part]
		var frac := float(h.parts.get(part, 1.0)) / float(h.max_parts.get(part, 1.0))
		var col := GOOD.lerp(WARN, clampf((1.0 - frac) * 2.0, 0.0, 1.0)).lerp(BAD, clampf((0.5 - frac) * 2.0, 0.0, 1.0))
		if bool(h.fractured.get(part, false)) and not bool(h.splinted.get(part, false)):
			col = BAD
		draw_rect(r, Color(col, 0.75))
		draw_rect(r, Color(1, 1, 1, 0.25), false, 2.0)
		var b := int(h.bleeding.get(part, 0))
		for k in b:
			draw_circle(r.position + Vector2(r.size.x * 0.5 + (k - 0.5) * 16.0, r.size.y * 0.5), 7.0, Color(0.85, 0.08, 0.06))
		if bool(h.fractured.get(part, false)):
			_t("splinted" if bool(h.splinted.get(part, false)) else "broken", r.position + Vector2(-2, r.size.y + 18), 16, WARN if bool(h.splinted.get(part, false)) else BAD)
	var helmet = ch.inv.gear.get("helmet")
	if helmet != null:
		draw_rect((shapes.head as Rect2).grow(5), Color(0.6, 0.7, 0.9, 0.9) if float(helmet.get("d", 0)) > 0 else Color(0.5, 0.2, 0.2), false, 3.0)
	var vest = ch.inv.gear.get("vest")
	if vest != null:
		draw_rect((shapes.torso as Rect2).grow(5), Color(0.6, 0.7, 0.9, 0.9) if float(vest.get("d", 0)) > 0 else Color(0.5, 0.2, 0.2), false, 3.0)
	var bl: int = h.bleeding_level()
	_t("Bleeding" if bl == 1 else ("Bleeding heavily" if bl == 2 else ""), o + Vector2(10, 470), 22, BAD)
	if h.painkiller_t > 0.0:
		_t("Painkillers %ds" % int(h.painkiller_t), o + Vector2(10, 496), 18, GOOD)
	var need: String = h.treatment_need()
	if need != "":
		var heal_hint := "Heal: use %s" if Settings.touch_active() else "H: use %s"
		_t(heal_hint % Defs.item_name(need), o + Vector2(10, 524), 20, WARN if ch.inv.count(need) > 0 else DIM)


# ------------------------------------------------------------------ Weapons

func _weapons(ch) -> void:
	## One card per carried gun: its name, then each mount it takes with what is fitted (Remove) or the best spare
	## in the bag that fits (Fit). Mounts the gun has no rail for are not listed.
	var y := 78.0
	var names := ["Primary", "Secondary", "Handgun"]
	var any := false
	for s in [1, 2, 3]:
		var w = ch.wpn.slots[s]
		if w == null:
			continue
		any = true
		var d := Defs.weapon(str(w.id))
		var title := "%s  %s" % [names[s - 1], str(d.get("name", w.id))]
		_t(title, Vector2(18, y + 26), 26, INK if ch.wpn.cur == s else DIM)
		# Calibre chip in the ammunition's colour: guns sharing a chip share ammunition.
		var cx := 30.0 + _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * _scale)).x
		var chip := Rect2(cx, y + 6, 78, 26)
		draw_rect(chip, Defs.ammo_color(str(w.id)))
		_t(Defs.calibre_name(str(w.id)), chip.position + Vector2(8, 20), 18, Color(1, 1, 1))
		y += 36.0
		var allowed: Array = d.get("attachments", [])
		var x := 18.0
		for m in MOUNTS:
			var kind: String = m[0]
			if not allowed.any(func(a): return Attach.kind(str(a)) == kind):
				continue
			var r := Rect2(x, y, 226, 64)
			draw_rect(r, Color(0.07, 0.11, 0.1, 0.9))
			_t(str(m[1]), r.position + Vector2(8, 20), 17, DIM)
			var fitted := Attach.in_slot(w, kind)
			if fitted != "":
				_t(Defs.item_name(fitted), r.position + Vector2(8, 44), 19, GOOD)
				_button(Rect2(r.position + Vector2(160, 30), Vector2(62, 30)), "Off", {"op": "detach", "slot": s, "att": fitted}, Color(0.35, 0.2, 0.18))
			else:
				var spare := ""
				var best := 0.0
				for e in ch.inv.bag:
					var a := str(e.id)
					if Defs.is_attachment(a) and Attach.kind(a) == kind and Attach.compatible(str(w.id), a) and Attach.score(str(w.id), a) > best:
						best = Attach.score(str(w.id), a)
						spare = a
				if spare != "":
					_t(Defs.item_name(spare), r.position + Vector2(8, 44), 19, WARN)
					_button(Rect2(r.position + Vector2(160, 30), Vector2(62, 30)), "Fit", {"op": "attach", "slot": s, "att": spare})
				else:
					_t("empty", r.position + Vector2(8, 44), 19, DIM)
			x += 232.0
			if x > 600.0:
				x = 18.0
				y += 70.0
		if x > 18.0:
			y += 70.0
		y += 8.0
		if y > 640.0:
			break
	if not any:
		_t("No weapons carried", Vector2(200, 360), 30, DIM)


# ------------------------------------------------------------------ Items

func _items(ch) -> void:
	var inv = ch.inv
	var x0 := 18.0
	var w := 330.0 if not container.is_empty() else 684.0
	_t("Carried  %.1f / %.1f kg" % [inv.bag_mass(), inv.capacity()], Vector2(x0, 100), 22, BAD if inv.bag_mass() > inv.capacity() else DIM)
	var y := 116.0
	for i in inv.bag.size():
		var e: Dictionary = inv.bag[i]
		var r := Rect2(x0, y, w, 40)
		var sel = i == selected
		draw_rect(r, Color(0.14, 0.2, 0.18, 0.9) if sel else Color(0.06, 0.09, 0.09, 0.8))
		var label := Defs.item_name(str(e.id))
		if int(e.get("n", 1)) > 1:
			label += " ×%d" % int(e.n)
		if e.has("c"):
			label += "  %d%%" % int(float(e.c) * 100.0)
		_t(label, r.position + Vector2(10, 28), 21)
		_buttons.append([r, {"ui": "select", "index": i}])
		y += 44.0
		if y > 560.0:
			break
	if selected >= 0 and selected < inv.bag.size():
		var e2: Dictionary = inv.bag[selected]
		var kind := str(Defs.item(str(e2.id)).get("kind", ""))
		var by := 590.0
		if kind == "medical":
			_button(Rect2(x0, by, 100, 44), "Use", {"op": "use", "item": e2.id})
		if kind == "attachment":
			for s in [1, 2, 3]:
				var wv = ch.wpn.slots[s]
				if wv != null and str(e2.id) in Defs.weapon(str(wv.id)).get("attachments", []):
					_button(Rect2(x0 + 110, by, 160, 44), "Attach", {"op": "attach", "slot": s, "att": e2.id})
					break
		_button(Rect2(x0 + (220 if container.is_empty() else 110), by, 100, 44), "Drop", {"op": "drop", "index": selected})
		if not container.is_empty():
			_button(Rect2(x0 + 220, by, 100, 44), "Store", {"op": "put", "index": selected})
	# Weapons strip
	var wy := 650.0
	for s in [1, 2, 3]:
		var wv2 = ch.wpn.slots[s]
		if wv2 != null:
			_button(Rect2(x0 + (s - 1) * 112, wy, 106, 36), "Drop " + ["", "1", "2", "3"][s], {"op": "drop_weapon", "slot": s}, Color(0.35, 0.2, 0.18))
	if container.is_empty():
		return
	# Container / body
	var cx := 366.0
	var title := "Body" if container.kind == "corpse" else "Container"
	_t(title, Vector2(cx, 100), 24, WARN)
	var entries: Array = container.entries
	if entries.is_empty():
		_t("Empty", Vector2(cx, 150), 22, DIM)
	var cy := 116.0
	for i in entries.size():
		var e3: Dictionary = entries[i]
		var r2 := Rect2(cx, cy, 336, 40)
		var label2 := Defs.item_name(str(e3.id))
		if int(e3.get("n", 1)) > 1:
			label2 += " ×%d" % int(e3.n)
		if e3.has("c"):
			label2 += "  %d%%" % int(float(e3.c) * 100.0)
		if e3.has("d"):
			label2 += "  %d%%" % int(float(e3.d) / float(Defs.item(str(e3.id)).get("durability", 100)) * 100.0)
		if e3.has("w"):
			label2 += "  %d rds" % (int(e3.w.get("mag", 0)) + (1 if e3.w.get("chamber", false) else 0))
		_button(r2, label2, {"op": "take", "index": i}, Color(0.2, 0.28, 0.24))
		cy += 44.0
		if cy > 620.0:
			break


# ------------------------------------------------------------------ Map

func _map(ch) -> void:
	var r := Rect2(14, 70, 692, 610)
	if map_tex == null:
		_t("Map unavailable", Vector2(240, 380), 28, DIM)
		return
	var L = world.map.layout
	var half: float = L.HALF
	# North-up, scaled to the whole settlement.
	var s := minf(r.size.x, r.size.y) / (half * 2.0)
	var o := r.position + (r.size - Vector2(half * 2.0, half * 2.0) * s) * 0.5
	draw_texture_rect(map_tex, Rect2(o, Vector2(half * 2.0, half * 2.0) * s), false, Color(0.8, 0.85, 0.82))
	var to_px := func(p: Vector2) -> Vector2: return o + (p + Vector2(half, half)) * s
	for lm in L.landmarks:
		var pp: Vector2 = to_px.call(lm.pos)
		draw_circle(pp, 3.0, DIM)
		_t(str(lm.name), pp + Vector2(5, -4), 15, DIM)
	# The haze: current safe area and the next one, as the SmarTab knows them.
	var z: Dictionary = world.match_info.get("zone", {})
	if not z.is_empty():
		var circ: Array = world.zone_circle(Net.interp_tick() if not world.is_server else float(Net.tick))
		draw_arc(to_px.call(circ[0]), float(circ[1]) * s, 0, TAU, 96, Color(0.9, 0.9, 0.9, 0.9), 2.0)
		if int(z.get("i", -1)) >= 0:
			draw_arc(to_px.call(z.c1), float(z.r1) * s, 0, TAU, 96, Color(0.55, 0.85, 1.0, 0.8), 2.0)
	var pl: Dictionary = world.match_info.get("plane", {})
	if not pl.is_empty() and world.match_info.get("phase", "") == "plane":
		draw_line(to_px.call(Vector2(pl.a.x, pl.a.z)), to_px.call(Vector2(pl.b.x, pl.b.z)), Color(1, 1, 1, 0.5), 2.0)
	# Team markers (own team only).
	for c in world.characters.values():
		if c.team != ch.team or c == ch:
			continue
		var tp: Vector2 = to_px.call(Vector2(c.global_position.x, c.global_position.z))
		draw_circle(tp, 6.0, Color(0.45, 0.8, 1.0) if c.mode != Motor.DOWNED else WARN)
	var mp: Vector2 = to_px.call(Vector2(ch.global_position.x, ch.global_position.z))
	var f := Vector2(-sin(ch.yaw), -cos(ch.yaw))
	var pts := PackedVector2Array([mp + f * 12.0, mp + f.rotated(2.5) * 8.0, mp + f.rotated(-2.5) * 8.0])
	draw_colored_polygon(pts, GOOD)
	_t("N", r.position + Vector2(r.size.x - 30, 30), 22, DIM)


# ------------------------------------------------------------------ Team

func _team(ch) -> void:
	_t("Team %d" % (ch.team + 1), Vector2(24, 112), 32)
	var y := 160.0
	var alive := 0
	for c in world.characters.values():
		if c.mode not in [Motor.DEAD, Motor.SPECTATE]:
			alive += 1
	for c in world.characters.values():
		if c.team != ch.team:
			continue
		var d: float = c.global_position.distance_to(ch.global_position)
		var dir := Vector2(c.global_position.x - ch.global_position.x, c.global_position.z - ch.global_position.z)
		var bearing := fposmod(rad_to_deg(atan2(dir.x, -dir.y)), 360.0)
		var state := "OK"
		var col := GOOD
		if c.mode == Motor.DOWNED:
			state = "DOWN — needs help"
			col = BAD
		elif (c.flags & Character.F_LIMP):
			state = "Injured"
			col = WARN
		elif c.mode in [Motor.PLANE, Motor.FREEFALL, Motor.CHUTE]:
			state = "In the air"
			col = DIM
		var name: String = c.pname + ("  (you)" if c == ch else "")
		_t(name, Vector2(24, y), 26, INK)
		_t(state, Vector2(24, y + 28), 20, col)
		if c != ch:
			_t("%d m  %03d°" % [int(d), int(bearing)], Vector2(400, y + 14), 24, INK, _mono)
		if (c.flags & Character.F_RADIO):
			_t("transmitting", Vector2(560, y + 14), 18, GOOD)
		y += 74.0
	_t("Players remaining: %d" % alive, Vector2(24, 640), 24, DIM)
