extends Control
## The SmarTab (r14): a hologram projected from the watch on the player's left wrist while TAB is held. This control
## draws the picture (1600 x 960 design units) into a SubViewport; the view model shows it on a floating panel with
## the hologram shader (viewmodel.gd), and the HUD passes the mouse through to it.
##
## Pages: Inventory (first: what lies nearby, the bag, worn gear round a body hologram, the guns with their attachment
## mounts), Status (body, wounds, treatment), Map, Team, Voice (radio commands teammate bots answer).
##
## Inventory is drag and drop: nearby items onto the bag, a gun or one of its mounts; bag items onto a mount, the body
## (medical) or back to the ground; attachments between guns; a gun onto the other gun's card to swap them, or onto
## the ground to drop it. Right click (or double click) does the obvious thing with an item. Items in the bag that are
## no use to you (ammunition for no gun you carry, attachments that fit none) are red; things nearby that suit your
## guns (their ammunition, attachments that improve them, better armour) are green.

signal request(req: Dictionary)

const PAGES := ["Inventory", "Status", "Map", "Team", "Voice"]
const VOICE := [["need_help", "Need help!", "Bots near you come to you"], ["follow_me", "Follow me", "The nearest bots follow you"],
	["lets_go", "Let's go!", "Bots move up to where you look"], ["fall_back", "Fall back!", "Bots pull back to you"],
	["enemy_spotted", "Enemy spotted", "Bots look where you look"], ["in_position", "In position", "Tells the team you are set"],
	["affirmative", "Affirmative", "Yes"], ["negative", "Negative", "No"]]
const Attach := preload("res://src/weapons/attachments.gd")
const Fit := preload("res://src/items/loot_fit.gd")
const MOUNTS := [["sight", "SIGHT"], ["muzzle", "MUZZLE"], ["grip", "GRIP"], ["mag", "MAG"], ["stock", "STOCK"], ["light", "LIGHT"]]
const W := 1600.0
const H := 960.0
const HOLO := Color(0.45, 0.88, 1.0)
const HOLO_DIM := Color(0.3, 0.6, 0.74)
const TEXT := Color(0.86, 0.96, 1.0)
const DIM := Color(0.5, 0.68, 0.76)
const GOOD := Color(0.36, 1.0, 0.55)
const WARN := Color(1.0, 0.76, 0.32)
const BAD := Color(1.0, 0.33, 0.3)
const PANEL_BG := Color(0.02, 0.07, 0.11, 0.94)
const CARD_BG := Color(0.03, 0.12, 0.18, 0.9)
const ROW_H := 62.0
const PICKUP_R := 2.6

var world = null
var page := 0
var container: Dictionary = {}   # {kind, id, entries}
var map_tex: ImageTexture
var icons = null                 # item_icons.gd
var _hits: Array = []            # [Rect2, Dictionary] interactive regions this frame (later ones on top)
var _font: Font
var _bold: Font
var _mono: Font
var _scale := 1.0
var _sent := ""
var _sent_t := 0
var _mouse := Vector2(-1, -1)
var _press := {}                 # {hit, pos}
var _drag := {}                  # the hit being dragged
var _hover := {}
var _hover_t := 0.0
var _scroll := {"vic": 0.0, "bag": 0.0}
var _last_click := {"key": "", "t": 0}
var _flash := {}                 # key -> msec: a slot that just took something glows
var _vicinity: Array = []        # [{src: "ground"/"cont", id/index, e}]
var _vic_t := 0


func _ready() -> void:
	UITheme.fonts()
	# Distance-field glyphs: the picture is scaled to whatever size the panel has on screen and stays sharp.
	_font = _msdf(UITheme.font_medium)
	_bold = _msdf(UITheme.font_semibold)
	_mono = _msdf(UITheme.font_mono)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


static func _msdf(f: Font) -> Font:
	if f is FontFile:
		var c: FontFile = (f as FontFile).duplicate()
		c.multichannel_signed_distance_field = true
		c.msdf_pixel_range = 12
		c.msdf_size = 48
		return c
	return f


func set_world(w) -> void:
	world = w
	if world.map and world.map.map_image:
		map_tex = ImageTexture.create_from_image(world.map.map_image)


func next_page(d: int) -> void:
	page = (page + d + PAGES.size()) % PAGES.size()
	_drag = {}
	_press = {}
	SoundSys.play_local("smartab_tap", -6.0)
	queue_redraw()


func open_page(name: String) -> void:
	for i in PAGES.size():
		if PAGES[i].to_lower() == name.to_lower():
			page = i
	queue_redraw()


func show_container(kind: String, id: int, entries: Array) -> void:
	container = {"kind": kind, "id": id, "entries": entries}
	page = 0
	queue_redraw()


func close_container() -> void:
	if not container.is_empty():
		request.emit({"op": "close"})
	container = {}
	_drag = {}
	_press = {}


func _process(dt: float) -> void:
	_scale = float(Settings.get_value("accessibility", "smartab_text_scale"))
	if not _hover.is_empty():
		_hover_t += dt
	queue_redraw()


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		var h := _hit_at(_mouse)
		var hk := _key(h)
		if hk != _key(_hover):
			_hover = h
			_hover_t = 0.0
		if not _press.is_empty() and _drag.is_empty() and (event.position as Vector2).distance_to(_press.pos) > 9.0 and bool(_press.hit.get("drag", false)):
			_drag = _press.hit
			SoundSys.play_local("smartab_tap", -10.0)
		accept_event()
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	_mouse = mb.position
	if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var d := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		var area := _area_at(_mouse)
		if area != "":
			_scroll[area] = maxf(float(_scroll[area]) + d * ROW_H, 0.0)
		else:
			next_page(int(d))
		accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var h := _hit_at(mb.position)
			_press = {"hit": h, "pos": mb.position} if not h.is_empty() else {}
			if mb.double_click and not h.is_empty():
				_quick(h)
				_press = {}
		else:
			if not _drag.is_empty():
				var dst := _hit_at(mb.position, true)
				_drop(_drag, dst)
			elif not _press.is_empty():
				_click(_press.hit)
			_drag = {}
			_press = {}
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var h2 := _hit_at(mb.position)
		if not h2.is_empty():
			_quick(h2)
		accept_event()


func _key(h: Dictionary) -> String:
	if h.is_empty():
		return ""
	return "%s:%s:%s:%s" % [str(h.get("kind", "")), str(h.get("id", "")), str(h.get("slot", "")), str(h.get("mount", ""))]


func _hit_at(p: Vector2, drop_only: bool = false) -> Dictionary:
	for i in range(_hits.size() - 1, -1, -1):
		var r: Rect2 = _hits[i][0]
		var h: Dictionary = _hits[i][1]
		if r.has_point(p) and (not drop_only or bool(h.get("drop", false))):
			return h
	return {}


func _area_at(p: Vector2) -> String:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i][1]
		if (_hits[i][0] as Rect2).has_point(p) and h.get("kind", "") in ["vic_area", "bag_area"]:
			return "vic" if h.kind == "vic_area" else "bag"
	return ""


func _hit(r: Rect2, h: Dictionary) -> void:
	_hits.append([r, h])


func _send(req: Dictionary) -> void:
	SoundSys.play_local("smartab_tap", -4.0)
	request.emit(req)


func _click(h: Dictionary) -> void:
	match str(h.get("kind", "")):
		"tab":
			page = int(h.page)
			SoundSys.play_local("smartab_tap", -4.0)
		"voice":
			_sent = str(h.label)
			_sent_t = Time.get_ticks_msec()
			_send({"op": "voice", "line": h.line, "label": h.label})
		"button":
			_send(h.req)
		"vic", "bag", "att", "gear":
			# A second click on the same item within 0.4 s is a double click (touch screens send no double_click).
			var k := _key(h)
			var now := Time.get_ticks_msec()
			if _last_click.key == k and now - int(_last_click.t) < 400:
				_quick(h)
				_last_click = {"key": "", "t": 0}
			else:
				_last_click = {"key": k, "t": now}


func _quick(h: Dictionary) -> void:
	## Right click / double click: the obvious thing.
	var ch = world.local_char if world else null
	if ch == null:
		return
	match str(h.get("kind", "")):
		"vic":
			_send(_take_req(h, {}))
		"bag":
			var e: Dictionary = h.e
			var id := str(e.id)
			var kind := str(Defs.item(id).get("kind", ""))
			if kind == "medical":
				_send({"op": "use", "item": id})
			elif Defs.is_attachment(id):
				var up: Array = Attach.best_slot_upgrade(ch.wpn.slots, id)
				if int(up[0]) >= 0:
					_send({"op": "attach", "slot": int(up[0]), "att": id})
			elif kind in ["armor", "backpack"]:
				_send({"op": "equip_bag", "index": int(h.index)})
			else:
				_send(_put_or_drop(int(h.index)))
		"att":
			_send({"op": "detach", "slot": int(h.slot), "att": str(h.att)})
		"gear":
			_send({"op": "unequip", "gear": str(h.slot)})


func _take_req(src: Dictionary, extra: Dictionary) -> Dictionary:
	var r := {"op": "pickup", "item": int(src.id)} if src.src == "ground" else {"op": "take", "index": int(src.index)}
	r.merge(extra, true)
	return r


func _put_or_drop(index: int) -> Dictionary:
	return {"op": "put", "index": index} if not container.is_empty() else {"op": "drop", "index": index}


func can_drop(src: Dictionary, dst: Dictionary) -> bool:
	return not _drop_req(src, dst).is_empty()


func _drop_req(src: Dictionary, dst: Dictionary) -> Dictionary:
	## The request a drop makes ({} when nothing happens).
	var ch = world.local_char if world else null
	if ch == null or src.is_empty() or dst.is_empty():
		return {}
	var sk := str(src.get("kind", ""))
	var dk := str(dst.get("kind", ""))
	var sid := ""
	if src.has("e"):
		sid = str(src.e.id)
	elif sk == "att":
		sid = str(src.att)
	elif sk == "weapon":
		sid = str(ch.wpn.slots[int(src.slot)].id) if ch.wpn.slots[int(src.slot)] != null else ""
	var is_att := Defs.is_attachment(sid)
	match sk:
		"vic":
			match dk:
				"bag_area", "bag":
					return _take_req(src, {})
				"mount", "att":
					if is_att and Attach.kind(sid) == str(dst.mount) and Attach.compatible(_gun_id(ch, int(dst.slot)), sid):
						return _take_req(src, {"att_slot": int(dst.slot)})
				"weapon":
					if is_att and Attach.compatible(_gun_id(ch, int(dst.slot)), sid):
						return _take_req(src, {"att_slot": int(dst.slot)})
					if Defs.is_weapon(sid) and _slot_ok(sid, int(dst.slot)):
						return _take_req(src, {"to_slot": int(dst.slot)})
				"gear":
					if str(Defs.item(sid).get("slot", "")) == str(dst.slot) or (str(dst.slot) == "flashlight" and sid == "flashlight"):
						return _take_req(src, {})
				"body":
					if str(Defs.item(sid).get("kind", "")) in ["armor", "backpack"]:
						return _take_req(src, {})
		"bag":
			match dk:
				"vic_area", "vic":
					return _put_or_drop(int(src.index))
				"mount", "att":
					if is_att and Attach.kind(sid) == str(dst.mount) and Attach.compatible(_gun_id(ch, int(dst.slot)), sid):
						return {"op": "attach", "slot": int(dst.slot), "att": sid}
				"weapon":
					if is_att and Attach.compatible(_gun_id(ch, int(dst.slot)), sid):
						return {"op": "attach", "slot": int(dst.slot), "att": sid}
				"body":
					if str(Defs.item(sid).get("kind", "")) == "medical":
						return {"op": "use", "item": sid}
					if str(Defs.item(sid).get("kind", "")) in ["armor", "backpack"]:
						return {"op": "equip_bag", "index": int(src.index)}
				"gear":
					if str(Defs.item(sid).get("slot", "")) == str(dst.slot) or (str(dst.slot) == "flashlight" and sid == "flashlight"):
						return {"op": "equip_bag", "index": int(src.index)}
		"att":
			match dk:
				"bag_area", "bag":
					return {"op": "detach", "slot": int(src.slot), "att": sid}
				"vic_area", "vic":
					return {"op": "drop_att", "slot": int(src.slot), "att": sid}
				"mount", "att", "weapon":
					var to := int(dst.slot)
					if to != int(src.slot) and Attach.compatible(_gun_id(ch, to), sid) and (dk == "weapon" or Attach.kind(sid) == str(dst.mount)):
						return {"op": "move_att", "from": int(src.slot), "to": to, "att": sid}
		"weapon":
			match dk:
				"weapon":
					var a := int(src.slot)
					var b := int(dst.slot)
					if a != b and a in [1, 2] and b in [1, 2]:
						return {"op": "swap_weapons", "a": a, "b": b}
				"vic_area", "vic":
					return {"op": "drop_weapon", "slot": int(src.slot)}
		"gear":
			match dk:
				"bag_area", "bag":
					return {"op": "unequip", "gear": str(src.slot)}
				"vic_area", "vic":
					return {"op": "drop_gear", "gear": str(src.slot)}
	return {}


func _gun_id(ch, slot: int) -> String:
	if slot < 1 or slot > 3 or ch.wpn.slots[slot] == null:
		return ""
	return str(ch.wpn.slots[slot].id)


func _slot_ok(wid: String, slot: int) -> bool:
	var hand := str(Defs.weapon(wid).get("slot", "long")) == "handgun"
	return (slot == 3) == hand


func _drop(src: Dictionary, dst: Dictionary) -> void:
	var req := _drop_req(src, dst)
	if req.is_empty():
		SoundSys.play_local("smartab_tap", -14.0)
		return
	_flash[_key(dst)] = Time.get_ticks_msec()
	_send(req)


# ------------------------------------------------------------------ drawing helpers

func _t(text: String, pos: Vector2, sz: int, col: Color = TEXT, font: Font = null, width: float = -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font if font else _font, pos, text, align, width, int(sz * _scale), col)


func _fit(text: String, sz: int, width: float, font: Font = null) -> String:
	## Shortened with an ellipsis to fit the width.
	var f := font if font else _font
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(sz * _scale)).x <= width:
		return text
	while text.length() > 2 and f.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, int(sz * _scale)).x > width:
		text = text.substr(0, text.length() - 1)
	return text + "…"


func _frame(r: Rect2, col: Color, w: float = 2.0, corner: float = 14.0) -> void:
	## Corner brackets (the hologram's frames are open boxes).
	var c := corner
	for p in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
		var o: Vector2 = p[0]
		var s: Vector2 = p[1]
		draw_line(o, o + Vector2(c * s.x, 0), col, w)
		draw_line(o, o + Vector2(0, c * s.y), col, w)


func _panel(r: Rect2, title: String, sub: String = "") -> void:
	draw_rect(r, PANEL_BG)
	draw_rect(r, Color(HOLO, 0.16), false, 1.0)
	_frame(r.grow(2), Color(HOLO, 0.85), 2.0, 18.0)
	if title != "":
		_t(title, r.position + Vector2(16, 30), 22, HOLO, _bold)
		if sub != "":
			_t(sub, Vector2(r.end.x - 216, r.position.y + 30), 17, DIM, _mono, 200, HORIZONTAL_ALIGNMENT_RIGHT)
		draw_line(r.position + Vector2(12, 42), Vector2(r.end.x - 12, r.position.y + 42), Color(HOLO, 0.3), 1.0)


func _icon(id: String, r: Rect2, mod: Color = Color(1, 1, 1, 1)) -> void:
	var tex: Texture2D = icons.icon(id) if icons else null
	if tex == null:
		# Not rendered yet (or no model): the item's initials in a box.
		draw_rect(r.grow(-6), Color(HOLO, 0.08))
		var short := ""
		for word in Defs.item_name(id).split(" ", false).slice(0, 2):
			short += word.substr(0, 1)
		_t(short, r.position + Vector2(0, r.size.y * 0.5 + 9), 22, Color(HOLO, 0.7), _bold, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var ts := tex.get_size()
	var k := minf(r.size.x / ts.x, r.size.y / ts.y)
	var dr := Rect2(r.get_center() - ts * k * 0.5, ts * k)
	draw_texture_rect(tex, dr, false, mod)


func _entry_label(e: Dictionary) -> String:
	var label := Defs.item_name(str(e.id))
	if e.has("c"):
		label += "  %d%%" % int(float(e.c) * 100.0)
	if e.has("d"):
		label += "  %d%%" % int(float(e.d) / float(Defs.item(str(e.id)).get("durability", 100)) * 100.0)
	return label


func _entry_sub(e: Dictionary) -> String:
	var id := str(e.id)
	if id.begins_with("ammo_"):
		return "Ammunition"
	if Defs.is_attachment(id):
		return str(Attach.kind(id)).capitalize()
	if Defs.is_weapon(id):
		var w: Dictionary = e.get("w", {})
		return "%s  ·  %d rds" % [Defs.calibre_name(id), int(w.get("mag", 0)) + (1 if w.get("chamber", false) else 0)]
	return str(Defs.item(id).get("kind", "")).capitalize()


func _item_row(r: Rect2, e: Dictionary, mark: String, hit: Dictionary) -> void:
	## One item: icon, name, kind, count; a coloured edge (green suits you, red no use, else the calibre colour).
	var hov := _key(_hover) == _key(hit) and _drag.is_empty()
	var dragging := _key(_drag) == _key(hit)
	var bg := CARD_BG
	if mark == "good":
		bg = Color(0.04, 0.22, 0.12, 0.72)
	elif mark == "bad":
		bg = Color(0.26, 0.05, 0.05, 0.72)
	draw_rect(r, Color(bg, bg.a * (0.4 if dragging else 1.0)))
	if hov:
		draw_rect(r, Color(HOLO, 0.12))
		draw_rect(r, Color(HOLO, 0.7), false, 1.5)
	var edge := Color(HOLO, 0.4)
	var id := str(e.id)
	if mark == "good":
		edge = GOOD
	elif mark == "bad":
		edge = BAD
	elif id.begins_with("ammo_"):
		edge = Defs.ammo_color(id)
	draw_rect(Rect2(r.position, Vector2(4, r.size.y)), edge)
	_icon(id, Rect2(r.position + Vector2(8, 3), Vector2(r.size.y * 1.25, r.size.y - 6)))
	var tx := r.position.x + 16 + r.size.y * 1.25
	var tw := r.end.x - tx - 64
	_t(_fit(_entry_label(e), 20, tw), Vector2(tx, r.position.y + 27), 20, TEXT)
	var sub := _entry_sub(e)
	if mark == "bad":
		sub = Fit.why_useless(world.local_char, e)
	elif mark == "good":
		sub = "Suits your guns" if (id.begins_with("ammo_") or Defs.is_attachment(id)) else "Better than yours"
	_t(_fit(sub, 16, tw), Vector2(tx, r.position.y + 50), 16, BAD if mark == "bad" else (GOOD if mark == "good" else DIM))
	if int(e.get("n", 1)) > 1:
		_t(str(int(e.n)), Vector2(r.end.x - 72, r.position.y + 38), 22, TEXT, _mono, 60, HORIZONTAL_ALIGNMENT_RIGHT)


# ------------------------------------------------------------------ the frame

func _draw() -> void:
	_hits.clear()
	# The hologram's own field: a faint grid, brighter toward the middle, and the outer frame.
	draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.045, 0.07, 0.9))
	for x in range(0, int(W), 40):
		draw_line(Vector2(x, 0), Vector2(x, H), Color(HOLO, 0.035), 1.0)
	for y in range(0, int(H), 40):
		draw_line(Vector2(0, y), Vector2(W, y), Color(HOLO, 0.035), 1.0)
	_frame(Rect2(4, 4, W - 8, H - 8), Color(HOLO, 0.9), 3.0, 34.0)
	var ch = world.local_char if world else null
	_header(ch)
	if ch == null:
		_t("NO SIGNAL", Vector2(0, H * 0.5), 48, DIM, _bold, W, HORIZONTAL_ALIGNMENT_CENTER)
		return
	match PAGES[clampi(page, 0, PAGES.size() - 1)]:
		"Inventory":
			_inventory(ch)
		"Status":
			_status_page(ch)
		"Map":
			_map(ch, Rect2(20, 84, W - 40, H - 140))
		"Team":
			_team(ch)
		"Voice":
			_voice(ch)
	_tooltip(ch)
	_drag_ghost()
	var hint := "Drag to move  ·  Hold to drag  ·  Tap twice: quick action  ·  < >: page" if Settings.touch_active() \
		else "Drag to move  ·  Right click: quick action  ·  Wheel: scroll  ·  Q / E: page"
	_t(hint, Vector2(0, H - 18), 17, DIM, _font, W, HORIZONTAL_ALIGNMENT_CENTER)


func _header(ch) -> void:
	_t("SMARTAB", Vector2(26, 50), 30, HOLO, _bold)
	_t("AETHER-OS 4.2", Vector2(178, 50), 15, DIM, _mono)
	var x := 380.0
	for i in PAGES.size():
		var label: String = PAGES[i].to_upper()
		var tw := _bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(21 * _scale)).x + 44.0
		var r := Rect2(x, 16, tw, 50)
		var on := i == page
		if on:
			draw_rect(r, Color(HOLO, 0.18))
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4)), HOLO)
		elif _key(_hover) == "tab:%d" % i:
			draw_rect(r, Color(HOLO, 0.08))
		_t(label, r.position + Vector2(22, 34), 21, TEXT if on else DIM, _bold)
		_hit(r, {"kind": "tab", "page": i, "id": i})
		x += tw + 6.0
	# Right: the match clock and players left.
	if world:
		var alive := 0
		for c in world.characters.values():
			if c.mode not in [Motor.DEAD, Motor.SPECTATE]:
				alive += 1
		var secs := int(float(Net.tick) / Defs.TICK_RATE) % 3600
		_t("%d ALIVE   %02d:%02d" % [alive, secs / 60, secs % 60], Vector2(W - 380, 50), 22, TEXT, _mono, 350, HORIZONTAL_ALIGNMENT_RIGHT)


# ------------------------------------------------------------------ inventory

func _refresh_vicinity(ch) -> void:
	## Ground items within reach (same floor), then what is in the open container or body.
	if Time.get_ticks_msec() - _vic_t < 150:
		return
	_vic_t = Time.get_ticks_msec()
	_vicinity.clear()
	var dyn = world.map.dyn if world.map else null
	if dyn:
		var p: Vector3 = ch.global_position
		var ids: Array = dyn.items_near(p, PICKUP_R)
		ids.sort_custom(func(a, b): return (dyn.items[a].xf as Transform3D).origin.distance_squared_to(p) < (dyn.items[b].xf as Transform3D).origin.distance_squared_to(p))
		for id in ids:
			var it: Dictionary = dyn.items[id]
			if absf((it.xf as Transform3D).origin.y - p.y) > 1.6:
				continue
			_vicinity.append({"src": "ground", "id": id, "e": it.entry})


func _mark(ch, e: Dictionary, near: bool) -> String:
	if near:
		return "good" if Fit.suitable(ch, e) else ""
	return "bad" if Fit.useless(ch, e) else ""


func _inventory(ch) -> void:
	_refresh_vicinity(ch)
	var dragging := not _drag.is_empty()
	# Vicinity
	var vr := Rect2(20, 84, 340, 830)
	var cont_name := ""
	if not container.is_empty():
		cont_name = "BODY" if container.kind == "corpse" else "CONTAINER"
	_panel(vr, "VICINITY", cont_name)
	_hit(vr, {"kind": "vic_area", "drop": true})
	var rows := []
	for v in _vicinity:
		rows.append({"kind": "vic", "src": "ground", "id": v.id, "e": v.e, "drag": true, "drop": true})
	if not container.is_empty():
		for i in (container.entries as Array).size():
			rows.append({"kind": "vic", "src": "cont", "index": i, "id": "c%d" % i, "e": container.entries[i], "drag": true, "drop": true})
	_list(rows, Rect2(vr.position + Vector2(10, 54), Vector2(vr.size.x - 20, vr.size.y - 64)), "vic", ch, true,
		"Nothing in reach.\nStand by a body or a box\nand hold TAB." if container.is_empty() else "")
	if dragging and _drop_area_ok("vic_area"):
		draw_rect(vr, Color(GOOD, 0.08))
		_frame(vr.grow(6), GOOD, 2.0, 22.0)
	# Bag
	var br := Rect2(372, 84, 360, 830)
	var inv = ch.inv
	_panel(br, "BACKPACK", "%.1f / %.1f kg" % [inv.bag_mass(), inv.capacity()])
	var frac: float = inv.bag_mass() / maxf(inv.capacity(), 0.1)
	draw_rect(Rect2(br.position + Vector2(12, 48), Vector2(br.size.x - 24, 5)), Color(HOLO, 0.15))
	draw_rect(Rect2(br.position + Vector2(12, 48), Vector2((br.size.x - 24) * clampf(frac, 0.0, 1.0), 5)), BAD if frac > 1.0 else HOLO)
	_hit(br, {"kind": "bag_area", "drop": true})
	var order := range(inv.bag.size())
	order.sort_custom(func(a, b): return _type_rank(str(inv.bag[a].id)) < _type_rank(str(inv.bag[b].id)) or (_type_rank(str(inv.bag[a].id)) == _type_rank(str(inv.bag[b].id)) and a < b))
	var brows := []
	for i in order:
		brows.append({"kind": "bag", "index": i, "id": i, "e": inv.bag[i], "drag": true, "drop": true})
	_list(brows, Rect2(br.position + Vector2(10, 62), Vector2(br.size.x - 20, br.size.y - 72)), "bag", ch, false, "Empty")
	if dragging and _drop_area_ok("bag_area"):
		draw_rect(br, Color(GOOD, 0.08))
		_frame(br.grow(6), GOOD, 2.0, 22.0)
	_character(ch, Rect2(744, 84, 330, 830))
	_guns(ch, Rect2(1086, 84, 494, 830))


func _drop_area_ok(kind: String) -> bool:
	return can_drop(_drag, {"kind": kind})


func _type_rank(id: String) -> int:
	if Defs.is_weapon(id):
		return 0
	var k := str(Defs.item(id).get("kind", ""))
	return {"medical": 1, "throwable": 2, "attachment": 4, "ammo": 3, "battery": 5, "flashlight": 6, "armor": 7, "backpack": 8}.get(k, 9)


func _list(rows: Array, r: Rect2, area: String, ch, near: bool, empty_text: String) -> void:
	var total := rows.size() * (ROW_H + 6.0)
	_scroll[area] = clampf(float(_scroll[area]), 0.0, maxf(total - r.size.y, 0.0))
	var y := r.position.y - float(_scroll[area])
	if rows.is_empty() and empty_text != "":
		var ly := r.position.y + 40.0
		for line in empty_text.split("\n"):
			_t(line, Vector2(r.position.x, ly), 19, DIM, _font, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			ly += 28.0
	for h in rows:
		var rr := Rect2(r.position.x, y, r.size.x, ROW_H)
		y += ROW_H + 6.0
		if rr.end.y < r.position.y or rr.position.y > r.end.y:
			continue
		if rr.position.y < r.position.y - 2.0 or rr.end.y > r.end.y + 2.0:
			continue  # partly scrolled out: not drawn (no clipping in the picture)
		_item_row(rr, h.e, _mark(ch, h.e, near), h)
		if not _drag.is_empty() and can_drop(_drag, h):
			_frame(rr.grow(2), GOOD, 2.0, 10.0)
		_hit(rr, h)
	if total > r.size.y:
		var bar_h := r.size.y * r.size.y / total
		var by := r.position.y + (r.size.y - bar_h) * float(_scroll[area]) / maxf(total - r.size.y, 1.0)
		draw_rect(Rect2(r.end.x + 3, by, 3, bar_h), Color(HOLO, 0.6))


func _character(ch, r: Rect2) -> void:
	## The body hologram (part colours: health) with worn gear round it, and the vitals under it.
	_panel(r, "CHARACTER")
	var h = ch.health
	var c := r.position + Vector2(r.size.x * 0.5, 120)
	var body_hit := {"kind": "body", "id": "body", "drop": true}
	_body(ch, c, 1.0)
	var brect := Rect2(c + Vector2(-60, -10), Vector2(120, 430))
	_hit(brect, body_hit)
	if not _drag.is_empty() and can_drop(_drag, body_hit):
		_frame(brect.grow(4), GOOD, 2.0, 16.0)
	# Gear slots: helmet, vest, backpack on the left; light, batteries, grenades on the right.
	var gx_l := r.position.x + 14
	var gx_r := r.end.x - 14 - 86
	var slots := [["helmet", gx_l, r.position.y + 60], ["vest", gx_l, r.position.y + 170], ["backpack", gx_l, r.position.y + 280],
		["flashlight", gx_r, r.position.y + 60]]
	for s in slots:
		_gear_slot(ch, str(s[0]), Rect2(float(s[1]), float(s[2]), 86, 96))
	# Batteries and frag grenades (counts).
	var bats: Array = ch.inv.batteries()
	_count_box(Rect2(gx_r, r.position.y + 170, 86, 96), "battery", bats.size(), "BATT")
	_count_box(Rect2(gx_r, r.position.y + 280, 86, 96), "frag_grenade", ch.inv.count("frag_grenade"), "FRAG")
	# Vitals
	var vy := r.position.y + 600
	var cond: String = h.condition() if h else "NORMAL"
	var cc := GOOD if cond == "NORMAL" else (WARN if cond == "INJURED" else BAD)
	_t(cond, Vector2(r.position.x + 16, vy), 30, cc, _bold)
	_t("%d HP" % int(h.health), Vector2(r.end.x - 136, vy), 26, TEXT, _mono, 120, HORIZONTAL_ALIGNMENT_RIGHT)
	var hp := clampf(float(h.health) / 100.0, 0.0, 1.0)
	draw_rect(Rect2(r.position.x + 16, vy + 14, r.size.x - 32, 12), Color(HOLO, 0.15))
	draw_rect(Rect2(r.position.x + 16, vy + 14, (r.size.x - 32) * hp, 12), GOOD.lerp(BAD, 1.0 - hp) if hp < 0.6 else HOLO)
	var line_y := vy + 60
	var bl: int = h.bleeding_level()
	if bl > 0:
		_t("Bleeding heavily" if bl == 2 else "Bleeding", Vector2(r.position.x + 16, line_y), 21, BAD)
		line_y += 30
	if h.painkiller_t > 0.0:
		_t("Painkillers %ds" % int(h.painkiller_t), Vector2(r.position.x + 16, line_y), 19, GOOD)
		line_y += 28
	var tr: Dictionary = h.treatment if h else {}
	if not tr.is_empty():
		_t("Using %s" % Defs.item_name(str(tr.item)), Vector2(r.position.x + 16, line_y), 19, WARN)
		draw_rect(Rect2(r.position.x + 16, line_y + 8, r.size.x - 32, 8), Color(WARN, 0.2))
		draw_rect(Rect2(r.position.x + 16, line_y + 8, (r.size.x - 32) * float(tr.t) / maxf(float(tr.total), 0.01), 8), WARN)
		line_y += 36
	var need: String = h.treatment_need()
	if need != "":
		_t("Drag %s onto the body" % Defs.item_name(need), Vector2(r.position.x + 16, line_y), 17, WARN if ch.inv.count(need) > 0 else DIM)


func _gear_slot(ch, slot: String, r: Rect2) -> void:
	var g = ch.inv.gear.get(slot)
	var hit := {"kind": "gear", "slot": slot, "id": slot, "drop": true, "drag": g != null}
	if g != null:
		hit["e"] = g
	draw_rect(r, CARD_BG)
	draw_rect(r, Color(HOLO, 0.35), false, 1.0)
	if g == null:
		_t(slot.to_upper(), r.position + Vector2(0, r.size.y * 0.5 + 6), 14, Color(HOLO, 0.45), _mono, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_icon(str(g.id), Rect2(r.position + Vector2(4, 4), r.size - Vector2(8, 22)))
		if g.has("d"):
			var frac := float(g.d) / float(Defs.item(str(g.id)).get("durability", 100))
			draw_rect(Rect2(r.position + Vector2(6, r.size.y - 12), Vector2(r.size.x - 12, 6)), Color(HOLO, 0.15))
			draw_rect(Rect2(r.position + Vector2(6, r.size.y - 12), Vector2((r.size.x - 12) * clampf(frac, 0, 1), 6)), BAD if frac < 0.3 else HOLO)
		elif g.has("c"):
			_t("%d%%" % int(maxf(float(g.c), 0.0) * 100.0), r.position + Vector2(0, r.size.y - 6), 15, TEXT, _mono, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _key(_hover) == _key(hit):
		draw_rect(r, Color(HOLO, 0.8), false, 1.5)
	if not _drag.is_empty() and can_drop(_drag, hit):
		_frame(r.grow(3), GOOD, 2.0, 12.0)
	_glow_if_flashed(hit, r)
	_hit(r, hit)


func _count_box(r: Rect2, id: String, n: int, label: String) -> void:
	draw_rect(r, CARD_BG)
	draw_rect(r, Color(HOLO, 0.35), false, 1.0)
	if n > 0:
		_icon(id, Rect2(r.position + Vector2(8, 6), r.size - Vector2(16, 30)))
		_t("×%d" % n, r.position + Vector2(0, r.size.y - 6), 18, TEXT, _mono, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_t(label, r.position + Vector2(0, r.size.y * 0.5 + 6), 14, Color(HOLO, 0.45), _mono, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _body(ch, c: Vector2, k: float) -> void:
	## Front view body hologram from rounded parts; colour = part health, red drops = bleeding, a crack = broken bone,
	## a blue shell = armour (red when it is broken).
	var h = ch.health
	var parts := {
		"head": [Rect2(-26, 0, 52, 60), 26.0],
		"torso": [Rect2(-46, 66, 92, 150), 18.0],
		"arm_r": [Rect2(-86, 72, 34, 160), 16.0],
		"arm_l": [Rect2(52, 72, 34, 160), 16.0],
		"leg_r": [Rect2(-44, 222, 40, 200), 18.0],
		"leg_l": [Rect2(4, 222, 40, 200), 18.0],
	}
	var t := Time.get_ticks_msec() / 1000.0
	for part in parts:
		var pr: Rect2 = parts[part][0]
		var r := Rect2(c + pr.position * k, pr.size * k)
		var frac := float(h.parts.get(part, 1.0)) / float(h.max_parts.get(part, 1.0))
		var col := HOLO.lerp(WARN, clampf((1.0 - frac) * 2.0, 0.0, 1.0)).lerp(BAD, clampf((0.5 - frac) * 2.0, 0.0, 1.0))
		var broken := bool(h.fractured.get(part, false)) and not bool(h.splinted.get(part, false))
		if broken:
			col = BAD
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col, 0.22)
		sb.border_color = Color(col, 0.95)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(float(parts[part][1]) * k))
		draw_style_box(sb, r)
		# Scan line drifting down the body.
		var sy := fposmod(t * 90.0, 440.0 * k)
		if sy > pr.position.y * k and sy < pr.end.y * k:
			draw_line(Vector2(r.position.x + 2, c.y + sy), Vector2(r.end.x - 2, c.y + sy), Color(col, 0.6), 1.5)
		for b in int(h.bleeding.get(part, 0)):
			draw_circle(r.get_center() + Vector2((b - 0.5) * 14.0, 6.0), 6.0, Color(1.0, 0.1, 0.08, 0.95))
		if bool(h.fractured.get(part, false)):
			var mid := r.get_center()
			draw_polyline(PackedVector2Array([mid + Vector2(-8, -14), mid + Vector2(4, -4), mid + Vector2(-4, 4), mid + Vector2(8, 14)]),
				WARN if bool(h.splinted.get(part, false)) else BAD, 2.5)
	for armour in [["helmet", "head"], ["vest", "torso"]]:
		var g = ch.inv.gear.get(armour[0])
		if g == null:
			continue
		var pr2: Rect2 = parts[armour[1]][0]
		var r2 := Rect2(c + pr2.position * k, pr2.size * k).grow(6)
		var sb2 := StyleBoxFlat.new()
		sb2.draw_center = false
		sb2.border_color = Color(0.55, 0.7, 1.0, 0.9) if float(g.get("d", 0)) > 0 else Color(0.8, 0.25, 0.2, 0.9)
		sb2.set_border_width_all(3)
		sb2.set_corner_radius_all(int(float(parts[armour[1]][1]) * k) + 6)
		draw_style_box(sb2, r2)


func _guns(ch, r: Rect2) -> void:
	_panel(r, "WEAPONS")
	var y := r.position.y + 56
	var heights := {1: 262.0, 2: 262.0, 3: 168.0}
	for s in [1, 2, 3]:
		var cr := Rect2(r.position.x + 10, y, r.size.x - 20, float(heights[s]))
		_gun_card(ch, s, cr)
		y += float(heights[s]) + 10.0
	# Throwables
	var tr := Rect2(r.position.x + 10, y, r.size.x - 20, r.end.y - y - 10)
	draw_rect(tr, CARD_BG)
	draw_rect(tr, Color(HOLO, 0.3), false, 1.0)
	_t("4", tr.position + Vector2(14, 34), 22, HOLO, _bold)
	var nf: int = ch.inv.count("frag_grenade")
	_t("Frag grenade" if nf > 0 else "No grenades", tr.position + Vector2(44, 34), 21, TEXT if nf > 0 else DIM)
	if nf > 0:
		_t("×%d   hold %s to cook, release to throw" % [nf, Settings.binding_label("throw_grenade")], tr.position + Vector2(200, 34), 16, DIM)
		_icon("frag_grenade", Rect2(tr.end.x - 62, tr.position.y + 4, 56, tr.size.y - 8))


func _gun_card(ch, s: int, r: Rect2) -> void:
	var w = ch.wpn.slots[s]
	var hit := {"kind": "weapon", "slot": s, "id": s, "drop": true, "drag": w != null}
	var active: bool = ch.wpn.cur == s
	draw_rect(r, CARD_BG if not active else Color(0.05, 0.17, 0.24, 0.72))
	draw_rect(r, Color(HOLO, 0.55 if active else 0.3), false, 1.5 if active else 1.0)
	if _key(_hover) == _key(hit) and _drag.is_empty():
		draw_rect(r, Color(HOLO, 0.06))
	var numr := Rect2(r.position + Vector2(10, 10), Vector2(34, 34))
	draw_rect(numr, Color(HOLO, 0.12))
	draw_rect(numr, Color(HOLO, 0.8), false, 1.5)
	_t(str(s), numr.position + Vector2(0, 26), 22, HOLO, _bold, 34, HORIZONTAL_ALIGNMENT_CENTER)
	if w == null:
		_t(["", "Primary", "Secondary", "Handgun"][s] + "  —  empty", r.position + Vector2(56, 36), 21, DIM)
		if not _drag.is_empty() and can_drop(_drag, hit):
			_frame(r.grow(3), GOOD, 2.0, 14.0)
		_hit(r, hit)
		return
	var d := Defs.weapon(str(w.id))
	_t(_fit(str(d.get("name", w.id)), 24, 220, _bold), r.position + Vector2(56, 36), 24, TEXT, _bold)
	var loaded := int(w.mag) + (1 if w.chamber else 0)
	var reserve: int = ch.inv.count("ammo_" + str(d.get("ammo", "")))
	_t("%d | %d" % [loaded, reserve], Vector2(r.end.x - 164, r.position.y + 36), 24, TEXT, _mono, 150, HORIZONTAL_ALIGNMENT_RIGHT)
	var chip := Rect2(Vector2(r.end.x - 250, r.position.y + 15), Vector2(76, 24))
	draw_rect(chip, Defs.ammo_color(str(w.id)))
	_t(Defs.calibre_name(str(w.id)), chip.position + Vector2(0, 18), 15, Color(1, 1, 1), _font, chip.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# The gun, then its mounts.
	var allowed: Array = d.get("attachments", [])
	var mounts := []
	for m in MOUNTS:
		if allowed.any(func(a): return Attach.kind(str(a)) == m[0]):
			mounts.append(m)
	var hand := s == 3
	var icon_r := Rect2(r.position + Vector2(14, 50), Vector2(r.size.x - 28, r.size.y - 140)) if not hand else Rect2(r.position + Vector2(14, 50), Vector2(180, r.size.y - 60))
	_icon(str(w.id), icon_r)
	_hit(r, hit)
	var sz := 66.0
	var mx := r.position.x + 14.0 if not hand else r.position.x + 206.0
	var my := r.end.y - sz - 12.0
	for m in mounts:
		var mr := Rect2(mx, my, sz, sz)
		_mount(ch, s, w, str(m[0]), str(m[1]), mr)
		mx += sz + 8.0
	if not _drag.is_empty() and can_drop(_drag, hit) and str(_drag.get("kind", "")) == "weapon":
		_frame(r.grow(3), GOOD, 2.0, 14.0)
	_glow_if_flashed(hit, r)


func _mount(ch, s: int, w: Dictionary, kind: String, label: String, r: Rect2) -> void:
	var fitted := Attach.in_slot(w, kind)
	var hit := {"kind": "att" if fitted != "" else "mount", "slot": s, "mount": kind, "att": fitted, "id": "%d%s" % [s, kind],
		"drop": true, "drag": fitted != ""}
	draw_rect(r, Color(0.02, 0.09, 0.14, 0.8))
	draw_rect(r, Color(HOLO, 0.4), false, 1.0)
	if fitted != "":
		_icon(fitted, r.grow(-4))
	else:
		_t(label, r.position + Vector2(0, r.size.y * 0.5 + 5), 12, Color(HOLO, 0.45), _mono, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _key(_hover) == _key(hit) and _drag.is_empty():
		draw_rect(r, Color(HOLO, 0.85), false, 1.5)
	if not _drag.is_empty() and _key(_drag) != _key(hit):
		if can_drop(_drag, hit):
			draw_rect(r, Color(GOOD, 0.18))
			_frame(r.grow(2), GOOD, 2.0, 10.0)
	_glow_if_flashed(hit, r)
	_hit(r, hit)


func _glow_if_flashed(hit: Dictionary, r: Rect2) -> void:
	var t0 := int(_flash.get(_key(hit), 0))
	var age := Time.get_ticks_msec() - t0
	if t0 > 0 and age < 600:
		draw_rect(r, Color(GOOD, 0.35 * (1.0 - age / 600.0)))


func _drag_ghost() -> void:
	if _drag.is_empty() or _mouse.x < 0.0:
		return
	var id := ""
	if _drag.has("e"):
		id = str(_drag.e.id)
	elif str(_drag.get("kind", "")) == "att":
		id = str(_drag.att)
	elif str(_drag.get("kind", "")) == "weapon" and world.local_char and world.local_char.wpn.slots[int(_drag.slot)] != null:
		id = str(world.local_char.wpn.slots[int(_drag.slot)].id)
	if id == "":
		return
	var r := Rect2(_mouse + Vector2(12, 12), Vector2(220, 74))
	draw_rect(r, Color(0.03, 0.14, 0.2, 0.92))
	_frame(r, HOLO, 2.0, 10.0)
	_icon(id, Rect2(r.position + Vector2(6, 6), Vector2(84, 62)))
	_t(_fit(Defs.item_name(id), 18, 120), r.position + Vector2(96, 32), 18, TEXT)
	var dst := _hit_at(_mouse, true)
	var ok := can_drop(_drag, dst)
	_t("release to %s" % _verb(_drop_req(_drag, dst)) if ok else "", r.position + Vector2(96, 56), 14, GOOD)


func _verb(req: Dictionary) -> String:
	return {"pickup": "take", "take": "take", "put": "store", "drop": "drop", "attach": "fit", "detach": "remove", "drop_att": "drop",
		"move_att": "move", "swap_weapons": "swap", "drop_weapon": "drop", "use": "use", "equip_bag": "wear", "unequip": "take off",
		"drop_gear": "drop"}.get(str(req.get("op", "")), "move")


func _tooltip(ch) -> void:
	## What the hovered item is (after a moment): its name, what fits it or what it does, its weight.
	if _hover.is_empty() or not _drag.is_empty() or _hover_t < 0.45:
		return
	var id := ""
	if _hover.has("e"):
		id = str(_hover.e.id)
	elif str(_hover.get("kind", "")) == "att":
		id = str(_hover.att)
	elif str(_hover.get("kind", "")) == "weapon" and ch.wpn.slots[int(_hover.slot)] != null:
		id = str(ch.wpn.slots[int(_hover.slot)].id)
	if id == "":
		return
	var lines := []
	if id.begins_with("ammo_"):
		lines.append("Ammo for " + ", ".join(Fit.guns_for_ammo(id)))
	elif Defs.is_attachment(id):
		lines.append_array(Fit.effects(id))
		var fits := []
		for s in [1, 2, 3]:
			if ch.wpn.slots[s] != null and Attach.compatible(str(ch.wpn.slots[s].id), id):
				fits.append(str(Defs.weapon(str(ch.wpn.slots[s].id)).get("name", "")))
		lines.append(("Fits your " + " and ".join(fits)) if not fits.is_empty() else "Fits none of your guns")
	elif Defs.is_weapon(id):
		var d := Defs.weapon(id)
		lines.append("%s  ·  %s" % [UITheme.GUN_CLASS_NAMES.get(str(d.get("class", "")), str(d.get("class", ""))), Defs.calibre_name(id)])
	lines.append("%.2f kg" % float(Defs.item(id).get("mass", 0.1)))
	var w := 360.0
	var h := 50.0 + lines.size() * 24.0
	var p := _mouse + Vector2(18, 18)
	if p.x + w > W - 10:
		p.x = _mouse.x - w - 18
	if p.y + h > H - 10:
		p.y = H - 10 - h
	var r := Rect2(p, Vector2(w, h))
	draw_rect(r, Color(0.02, 0.1, 0.15, 0.95))
	_frame(r, HOLO, 2.0, 12.0)
	_t(Defs.item_name(id), p + Vector2(14, 32), 21, TEXT, _bold)
	var ly := p.y + 58
	for l in lines:
		_t(_fit(str(l), 17, w - 28), Vector2(p.x + 14, ly), 17, DIM if not str(l).begins_with("Fits none") else BAD)
		ly += 24


# ------------------------------------------------------------------ status

func _status_page(ch) -> void:
	var h = ch.health
	var lr := Rect2(20, 84, 520, 830)
	_panel(lr, "BODY")
	_body(ch, lr.position + Vector2(lr.size.x * 0.5, 80), 1.45)
	var rr := Rect2(552, 84, 1028, 830)
	_panel(rr, "CONDITION")
	var cond: String = h.condition() if h else "NORMAL"
	var cc := GOOD if cond == "NORMAL" else (WARN if cond == "INJURED" else BAD)
	var x := rr.position.x + 24
	_t(cond, Vector2(x, rr.position.y + 100), 48, cc, _bold)
	_t("Health %d / 100" % int(h.health), Vector2(x, rr.position.y + 140), 24, DIM)
	var y := rr.position.y + 190
	var bl: int = h.bleeding_level()
	_t(("Bleeding heavily" if bl == 2 else "Bleeding") if bl > 0 else "No bleeding", Vector2(x, y), 24, BAD if bl > 0 else GOOD)
	y += 36
	var broken := []
	for part in h.fractured:
		if bool(h.fractured[part]):
			broken.append("%s%s" % [str(part).replace("_l", " (left)").replace("_r", " (right)").capitalize(), " (splinted)" if bool(h.splinted.get(part, false)) else ""])
	_t(("Broken: " + ", ".join(broken)) if not broken.is_empty() else "No broken bones", Vector2(x, y), 22, BAD if not broken.is_empty() else GOOD)
	y += 36
	if h.painkiller_t > 0.0:
		_t("Painkillers working: %d s" % int(h.painkiller_t), Vector2(x, y), 22, GOOD)
		y += 36
	# Armour and light
	y += 10
	for slot in ["helmet", "vest"]:
		var g = ch.inv.gear.get(slot)
		if g == null:
			_t("%s: none" % slot.capitalize(), Vector2(x, y), 22, DIM)
		else:
			var d2 := Defs.item(str(g.id))
			var frac := float(g.get("d", 0.0)) / float(d2.get("durability", 100))
			_t("%s  %s" % [str(d2.name), "BROKEN" if frac <= 0.0 else "%d%%" % int(frac * 100)], Vector2(x, y), 22, BAD if frac <= 0.0 else TEXT)
			draw_rect(Rect2(x + 330, y - 14, 260, 10), Color(HOLO, 0.15))
			draw_rect(Rect2(x + 330, y - 14, 260 * clampf(frac, 0, 1), 10), BAD if frac < 0.3 else HOLO)
		y += 36
	var c: float = ch.light.charge()
	_t(("%s %d%%%s" % ["Weapon light" if ch.light.weapon_mounted else "Flashlight", int(c * 100.0), "  LOW" if ch.light.low() else ""]) if c >= 0.0 else "No light",
		Vector2(x, y), 22, BAD if c >= 0.0 and ch.light.low() else (TEXT if c >= 0.0 else DIM))
	y += 36
	_t("Spare batteries: %d" % ch.inv.batteries().size(), Vector2(x, y), 20, DIM)
	# Medical: one button per item carried.
	var my := rr.position.y + 560
	_t("TREAT", Vector2(x, my), 22, HOLO, _bold)
	var need: String = h.treatment_need()
	var bx := x
	for med in ["bandage", "first_aid", "splint", "painkillers"]:
		var n: int = ch.inv.count(med)
		var br := Rect2(bx, my + 18, 236, 150)
		var usable: bool = n > 0 and h.can_use(med)
		draw_rect(br, Color(0.04, 0.2, 0.14, 0.7) if med == need and usable else CARD_BG)
		draw_rect(br, Color(GOOD if med == need and usable else HOLO, 0.6), false, 1.5)
		_icon(med, Rect2(br.position + Vector2(10, 8), Vector2(100, 90)))
		_t(Defs.item_name(med), br.position + Vector2(118, 40), 19, TEXT if n > 0 else DIM)
		_t("×%d" % n, br.position + Vector2(118, 72), 22, TEXT if n > 0 else DIM, _mono)
		_t("%.0f s" % float(Defs.item(med).get("use_time", 3.0)), br.position + Vector2(118, 98), 16, DIM)
		if usable:
			_t("USE", br.position + Vector2(0, 138), 18, GOOD if med == need else HOLO, _bold, br.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			_hit(br, {"kind": "button", "id": "use_" + med, "req": {"op": "use", "item": med}})
		bx += 246
	var tr: Dictionary = h.treatment if h else {}
	if not tr.is_empty():
		_t("Using %s" % Defs.item_name(str(tr.item)), Vector2(x, my + 210), 22, WARN)
		draw_rect(Rect2(x, my + 222, 600, 12), Color(WARN, 0.2))
		draw_rect(Rect2(x, my + 222, 600 * float(tr.t) / maxf(float(tr.total), 0.01), 12), WARN)


# ------------------------------------------------------------------ map

func _map(ch, r: Rect2) -> void:
	_panel(r, "MAP")
	r = Rect2(r.position + Vector2(10, 50), r.size - Vector2(20, 60))
	if map_tex == null:
		_t("Map unavailable", Vector2(r.position.x, r.get_center().y), 28, DIM, _font, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var L = world.map.layout
	var half: float = L.HALF
	var s := minf(r.size.x, r.size.y) / (half * 2.0)
	var o := r.position + (r.size - Vector2(half * 2.0, half * 2.0) * s) * 0.5
	draw_texture_rect(map_tex, Rect2(o, Vector2(half * 2.0, half * 2.0) * s), false, Color(0.62, 0.86, 0.95, 0.92))
	var to_px := func(p: Vector2) -> Vector2: return o + (p + Vector2(half, half)) * s
	for lm in L.landmarks:
		var pp: Vector2 = to_px.call(lm.pos)
		draw_circle(pp, 3.0, DIM)
		_t(str(lm.name), pp + Vector2(6, -4), 15, DIM)
	var z: Dictionary = world.match_info.get("zone", {})
	if not z.is_empty():
		var circ: Array = world.zone_circle(Net.interp_tick() if not world.is_server else float(Net.tick))
		draw_arc(to_px.call(circ[0]), float(circ[1]) * s, 0, TAU, 128, Color(0.95, 0.95, 1.0, 0.9), 2.0)
		if int(z.get("i", -1)) >= 0:
			draw_arc(to_px.call(z.c1), float(z.r1) * s, 0, TAU, 128, Color(HOLO, 0.9), 2.0)
	var pl: Dictionary = world.match_info.get("plane", {})
	if not pl.is_empty() and world.match_info.get("phase", "") == "plane":
		draw_line(to_px.call(Vector2(pl.a.x, pl.a.z)), to_px.call(Vector2(pl.b.x, pl.b.z)), Color(1, 1, 1, 0.5), 2.0)
	for c in world.characters.values():
		if c.team != ch.team or c == ch:
			continue
		var tp: Vector2 = to_px.call(Vector2(c.global_position.x, c.global_position.z))
		draw_circle(tp, 7.0, Color(0.45, 0.8, 1.0) if c.mode != Motor.DOWNED else WARN)
	var mp: Vector2 = to_px.call(Vector2(ch.global_position.x, ch.global_position.z))
	var f := Vector2(-sin(ch.yaw), -cos(ch.yaw))
	draw_colored_polygon(PackedVector2Array([mp + f * 14.0, mp + f.rotated(2.5) * 9.0, mp + f.rotated(-2.5) * 9.0]), GOOD)
	_t("N", Vector2(r.end.x - 30, r.position.y + 30), 24, DIM, _bold)


# ------------------------------------------------------------------ team

func _team(ch) -> void:
	var r := Rect2(20, 84, W - 40, 830)
	_panel(r, "TEAM %d" % (ch.team + 1))
	var y := r.position.y + 100
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
		if c.mode == Motor.DEAD:
			state = "Dead"
			col = DIM
		elif c.mode == Motor.DOWNED:
			state = "DOWN — needs help"
			col = BAD
		elif (c.flags & Character.F_LIMP):
			state = "Injured"
			col = WARN
		elif c.mode in [Motor.PLANE, Motor.FREEFALL, Motor.CHUTE]:
			state = "In the air"
			col = DIM
		var row := Rect2(r.position.x + 20, y - 40, r.size.x - 40, 74)
		draw_rect(row, CARD_BG)
		draw_rect(Rect2(row.position, Vector2(5, row.size.y)), col)
		_t(c.pname + ("  (you)" if c == ch else ""), row.position + Vector2(24, 34), 26, TEXT, _bold)
		_t(state, row.position + Vector2(24, 62), 19, col)
		if c != ch:
			_t("%d m   %03d°" % [int(d), int(bearing)], row.position + Vector2(row.size.x - 420, 46), 26, TEXT, _mono)
		if (c.flags & Character.F_RADIO):
			_t("TRANSMITTING", row.position + Vector2(row.size.x - 170, 46), 18, GOOD, _bold)
		y += 86
	_t("Players remaining: %d" % alive, Vector2(r.position.x + 24, r.end.y - 24), 24, DIM)


# ------------------------------------------------------------------ voice

func _voice(ch) -> void:
	## Quick radio commands, said in your voice on the team radio. Teammate bots answer: "Affirmative" means they are
	## doing it, "Negative" that none of them can (in a fight, holding a spot, too far).
	var r := Rect2(20, 84, W - 40, 830)
	_panel(r, "TEAM RADIO", "teammate bots answer")
	for i in VOICE.size():
		var v: Array = VOICE[i]
		var br := Rect2(r.position.x + 24 + (i % 2) * ((r.size.x - 60) * 0.5 + 12), r.position.y + 64 + (i / 2) * 178, (r.size.x - 60) * 0.5, 164)
		var urgent: bool = v[0] in ["need_help", "fall_back"]
		var hit := {"kind": "voice", "line": v[0], "label": v[1], "id": v[0]}
		draw_rect(br, Color(0.22, 0.06, 0.05, 0.7) if urgent else CARD_BG)
		draw_rect(br, Color(BAD if urgent else HOLO, 0.75 if _key(_hover) == _key(hit) else 0.35), false, 2.0)
		_t(str(v[1]), br.position + Vector2(26, 70), 40, TEXT, _bold)
		_t(str(v[2]), br.position + Vector2(26, 118), 21, DIM)
		_hit(br, hit)
	if _sent != "" and Time.get_ticks_msec() - _sent_t < 2500:
		_t("Said: %s" % _sent, Vector2(r.position.x + 24, r.end.y - 20), 24, GOOD)
