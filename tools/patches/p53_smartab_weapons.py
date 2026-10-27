"""SmarTab Weapons page (loot run 2026-10-26): each carried gun with its attachment mounts (sight, muzzle, grip,
magazine, stock, light), what is fitted, Remove buttons, and spare attachments in the bag that fit, with Fit buttons.

    python -I tools/patches/p53_smartab_weapons.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'src', 'ui', 'smartab_ui.gd')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''## Pages: Status (weapons, ammunition, body diagram, condition, bleeding, armour, light and batteries),
## Items (carried items and an open container or body), Map (terrain, the haze, team positions) and Team.''',
    '''## Pages: Status (weapons, ammunition, body diagram, condition, bleeding, armour, light and batteries),
## Weapons (each gun's attachment mounts: fit and remove), Items (carried items and an open container or body),
## Map (terrain, the haze, team positions) and Team.''')
rep('''const PAGES := ["Status", "Items", "Map", "Team"]''', '''const PAGES := ["Status", "Weapons", "Items", "Map", "Team"]
const Attach := preload("res://src/weapons/attachments.gd")
const MOUNTS := [["sight", "Sight"], ["muzzle", "Muzzle"], ["grip", "Grip"], ["mag", "Magazine"], ["stock", "Stock"], ["light", "Light"]]''')
rep('''func show_container(kind: String, id: int, entries: Array) -> void:
	container = {"kind": kind, "id": id, "entries": entries}
	page = 1''', '''func show_container(kind: String, id: int, entries: Array) -> void:
	container = {"kind": kind, "id": id, "entries": entries}
	page = PAGES.find("Items")''')
rep('''	for i in PAGES.size():
		var r := Rect2(12 + i * 176, 10, 168, 50)''', '''	for i in PAGES.size():
		var r := Rect2(12 + i * 140, 10, 134, 50)''')
rep('''		_t(PAGES[i], r.position + Vector2(14, 34), 26, INK if on else DIM)''', '''		_t(PAGES[i], r.position + Vector2(12, 34), 24, INK if on else DIM)''')
rep('''	match page:
		0:
			_status(ch)
		1:
			_items(ch)
		2:
			_map(ch)
		3:
			_team(ch)''', '''	match PAGES[page]:
		"Status":
			_status(ch)
		"Weapons":
			_weapons(ch)
		"Items":
			_items(ch)
		"Map":
			_map(ch)
		"Team":
			_team(ch)''')
rep('''# ------------------------------------------------------------------ Items''', '''# ------------------------------------------------------------------ Weapons

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
		_t("%s  %s" % [names[s - 1], str(d.get("name", w.id))], Vector2(18, y + 26), 26, INK if ch.wpn.cur == s else DIM)
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


# ------------------------------------------------------------------ Items''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
