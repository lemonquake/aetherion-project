"""Loot run (2026-10-26): loot-box models in the model library, item models from assets/models/loot, loot boxes and
more floor loot in rooms, loot boxes and loot at sites, and a little loot along the lanes.

    python -I tools/patches/p46_loot_placement.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class Patch:
    def __init__(self, rel):
        self.p = os.path.join(ROOT, rel)
        raw = open(self.p, 'rb').read().decode()
        self.crlf = '\r\n' in raw
        self.s = raw.replace('\r\n', '\n')

    def rep(self, a, b, cnt=1):
        assert self.s.count(a) == cnt, (self.p, a[:90], self.s.count(a))
        self.s = self.s.replace(a, b)

    def save(self):
        open(self.p, 'wb').write((self.s.replace('\n', '\r\n') if self.crlf else self.s).encode())


# ------------------------------------------------------------------ model library
m = Patch('game/src/world/model_lib.gd')
boxes = [('lootbox_balikbayan', 8.0, 'fabric'), ('lootbox_bin', 4.0, 'plastic'), ('lootbox_ammocan', 6.0, 'sheet_metal'),
         ('lootbox_footlocker', 20.0, 'wood'), ('lootbox_toolbox', 7.0, 'sheet_metal'), ('lootbox_medcase', 3.0, 'plastic'),
         ('lootbox_riflecase', 9.0, 'plastic'), ('lootbox_cooler', 6.0, 'plastic')]
lines = ''
for name, mass, mat in boxes:
    for suf in ('', '_open'):
        lines += ('\t"%s%s": {"path": "res://assets/models/loot/%s%s.glb", "mass": %.1f, "mat": "%s", "hp": 99999, "kind": "lootbox", "static": true},\n'
                  % (name, suf, name, suf, mass, mat))
m.rep('''	"crate_ammo": {"model": "ammo_box", "mass": 6.0, "mat": "steel", "hp": 300, "kind": "small"},
''', '''	"crate_ammo": {"model": "ammo_box", "mass": 6.0, "mat": "steel", "hp": 300, "kind": "small"},
	# Loot boxes (tools/blender/make_loot_models.py): containers you can see; the _open model replaces the closed one
	# once somebody has searched it.
''' + lines)
m.save()

# ------------------------------------------------------------------ dresser
d = Patch('game/src/world/dresser.gd')
d.rep('''func _put(ctx: Dictionary, name: String, lp: Vector2, yaw: float, y: float = 0.0, pad: float = 0.05, on_top: bool = false) -> bool:
	## Places a prop at room-local (x, z) facing yaw; rejects overlaps and anything outside the room. on_top: it
	## stands on furniture already placed and shares its footprint, so only the room bounds are checked.''',
      '''func _put(ctx: Dictionary, name: String, lp: Vector2, yaw: float, y: float = 0.0, pad: float = 0.05, on_top: bool = false, box_table: String = "") -> bool:
	## Places a prop at room-local (x, z) facing yaw; rejects overlaps and anything outside the room. on_top: it
	## stands on furniture already placed and shares its footprint, so only the room bounds are checked. box_table: the
	## prop is a loot box searched with that loot table.''')
d.rep('''	var xf: Transform3D = (ctx.xf as Transform3D) * Transform3D(rot, Vector3(lp.x, y, lp.y)) * Transform3D(Basis(), -centre)
	if s.get("static", false):
		mb.dyn.add_static_prop(name, xf)''', '''	var xf: Transform3D = (ctx.xf as Transform3D) * Transform3D(rot, Vector3(lp.x, y, lp.y)) * Transform3D(Basis(), -centre)
	if box_table != "":
		mb.dyn.add_loot_box(name, xf, box_table, int(ctx.bid))
		stats.boxes += 1
	elif s.get("static", false):
		mb.dyn.add_static_prop(name, xf)''')
d.rep('''func _wall_slot(ctx: Dictionary, name: String, wall: String, along: float = INF) -> Dictionary:''',
      '''func _wall_slot(ctx: Dictionary, name: String, wall: String, along: float = INF, box_table: String = "") -> Dictionary:''')
d.rep('''		if _put(ctx, name, pos, yaw):
			return {"pos": pos, "yaw": yaw, "top": a.size.y}
	return {}''', '''		if _put(ctx, name, pos, yaw, 0.0, 0.05, false, box_table):
			return {"pos": pos, "yaw": yaw, "top": a.size.y}
	return {}''')
d.rep('''var mb = null
var rng := RandomNumberGenerator.new()
var _item_cache: Dictionary = {}''', '''var mb = null
var rng := RandomNumberGenerator.new()
var _item_cache: Dictionary = {}
var stats := {"boxes": 0, "floor_spots": 0}

## Loot boxes by room: [model, loot table, chance, walls]. Each line is tried once per room.
const BOXES := {
	"sala": [["lootbox_balikbayan", "box_balikbayan", 0.55], ["lootbox_bin", "box_bin", 0.2], ["lootbox_balikbayan", "box_balikbayan", 0.15]],
	"bed": [["lootbox_footlocker", "box_footlocker", 0.35], ["lootbox_balikbayan", "box_balikbayan", 0.35], ["lootbox_bin", "box_bin", 0.25],
		["lootbox_riflecase", "box_riflecase", 0.05]],
	"kitchen": [["lootbox_cooler", "box_cooler", 0.4], ["lootbox_bin", "box_bin", 0.2]],
	"cr": [["lootbox_medcase", "box_medcase", 0.15]],
	"store": [["lootbox_balikbayan", "box_balikbayan", 0.6], ["lootbox_bin", "box_bin", 0.5], ["lootbox_cooler", "box_cooler", 0.35],
		["lootbox_bin", "box_bin", 0.3]],
	"workshop": [["lootbox_toolbox", "box_toolbox", 0.75], ["lootbox_ammocan", "box_ammocan", 0.35], ["lootbox_toolbox", "box_toolbox", 0.25]],
	"clinic": [["lootbox_medcase", "box_medcase", 0.9], ["lootbox_medcase", "box_medcase", 0.6], ["lootbox_medcase", "box_medcase", 0.3]],
	"office": [["lootbox_ammocan", "box_ammocan", 0.3], ["lootbox_footlocker", "box_footlocker", 0.2], ["lootbox_bin", "box_bin", 0.25]],
	"armed": [["lootbox_ammocan", "box_ammocan", 0.85], ["lootbox_ammocan", "box_ammocan", 0.5], ["lootbox_riflecase", "box_riflecase", 0.55],
		["lootbox_footlocker", "box_footlocker", 0.5]],
	"classroom": [["lootbox_bin", "box_bin", 0.3]],
}''')
d.rep('''func _floor_loot(ctx: Dictionary, table: String, chance: float) -> void:
	if rng.randf() > chance:
		return
	for i in 6:
		var lp := Vector2(rng.randf_range(-ctx.w * 0.4, ctx.w * 0.4), rng.randf_range(-ctx.d * 0.4, ctx.d * 0.4))
		var free := true
		for o in ctx.occ:
			if (o as Rect2).has_point(lp):
				free = false
		if free:
			mb.dyn.add_loot_spot(_world(ctx, lp, 0.02), table, int(ctx.bid))
			return''', '''func _floor_loot(ctx: Dictionary, table: String, chance: float, most: int = 1) -> void:
	## Loose loot lying on the floor in the open: up to `most` spots, the first with this chance, each further one
	## with half the chance of the one before.
	for k in most:
		if rng.randf() > chance * pow(0.5, k):
			return
		for i in 6:
			var lp := Vector2(rng.randf_range(-ctx.w * 0.4, ctx.w * 0.4), rng.randf_range(-ctx.d * 0.4, ctx.d * 0.4))
			var free := true
			for o in ctx.occ:
				if (o as Rect2).grow(0.1).has_point(lp):
					free = false
			if free:
				mb.dyn.add_loot_spot(_world(ctx, lp, 0.02), table, int(ctx.bid))
				ctx.occ.append(Rect2(lp - Vector2(0.25, 0.25), Vector2(0.5, 0.5)))
				stats.floor_spots += 1
				break


func _loot_boxes(ctx: Dictionary, kind: String) -> void:
	## Loot boxes against the walls (or anywhere free on the floor when no wall slot fits).
	for line in BOXES.get(kind, []):
		if rng.randf() > float(line[2]):
			continue
		var slot := _wall_slot(ctx, str(line[0]), _pick(["back", "left", "right", "front"]), INF, str(line[1]))
		if slot.is_empty():
			for i in 4:
				var lp := Vector2(rng.randf_range(-ctx.w * 0.35, ctx.w * 0.35), rng.randf_range(-ctx.d * 0.35, ctx.d * 0.35))
				if _put(ctx, str(line[0]), lp, rng.randf_range(-0.4, 0.4) + _pick([0.0, PI * 0.5]), 0.0, 0.05, false, str(line[1])):
					break''')
# hook loot boxes and more floor loot into each room kind
d.rep('''		"classroom":
			_classroom(ctx)
			return
		"clinic":
			_clinic(ctx)
			return
		"chapel", "church":
			_pews(ctx)
			return
		"hall", "police", "outpost", "pump":
			_office(ctx)
			return''', '''		"classroom":
			_classroom(ctx)
			_loot_boxes(ctx, "classroom")
			return
		"clinic":
			_clinic(ctx)
			_loot_boxes(ctx, "clinic")
			return
		"chapel", "church":
			_pews(ctx)
			return
		"hall", "police", "outpost", "pump":
			_office(ctx)
			_loot_boxes(ctx, "armed" if kind in ["police", "outpost"] else "office")
			return''')
d.rep('''	match t:
		"sala":
			_sala(ctx)
		"kitchen":
			_kitchen(ctx)
		"bed":
			_bedroom(ctx)
		"cr":
			_cr(ctx)
		"store":
			_store(ctx)
		"workshop":
			_workshop(ctx)''', '''	match t:
		"sala":
			_sala(ctx)
		"kitchen":
			_kitchen(ctx)
		"bed":
			_bedroom(ctx)
		"cr":
			_cr(ctx)
		"store":
			_store(ctx)
		"workshop":
			_workshop(ctx)
	_loot_boxes(ctx, t)''')
d.rep('''	_clutter(ctx, rng.randi_range(0, 3), ["box", "basket", "bottle", "gallon", "trashbag", "boots", "sungka", "crate_plastic"])
	_floor_loot(ctx, "floor_household", 0.25)''', '''	_clutter(ctx, rng.randi_range(0, 3), ["box", "basket", "bottle", "gallon", "trashbag", "boots", "sungka", "crate_plastic"])
	_floor_loot(ctx, "floor_household", 0.75, 2)''')
d.rep('''	_floor_loot(ctx, "floor_household", 0.15)''', '''	_floor_loot(ctx, "floor_household", 0.5, 2)''')
d.rep('''	_clutter(ctx, rng.randi_range(0, 3), ["suitcase", "box", "basket", "crate_plastic2", "boots"])
	_floor_loot(ctx, "floor_household", 0.2)''', '''	_clutter(ctx, rng.randi_range(0, 3), ["suitcase", "box", "basket", "crate_plastic2", "boots"])
	_floor_loot(ctx, "floor_household", 0.7, 2)''')
d.rep('''	mb.dyn.add_container(_world(ctx, Vector2(-ctx.w * 0.3, 0), 1.2), "bathroom", int(ctx.bid), Vector3(0.4, 0.4, 0.25))''',
      '''	mb.dyn.add_container(_world(ctx, Vector2(-ctx.w * 0.3, 0), 1.2), "bathroom", int(ctx.bid), Vector3(0.4, 0.4, 0.25))
	_floor_loot(ctx, "floor_household", 0.2)''')
d.rep('''	_clutter(ctx, rng.randi_range(2, 5), ["crate_plastic", "crate_plastic2", "box", "gallon", "bottle", "jerrycan"])''',
      '''	_clutter(ctx, rng.randi_range(2, 5), ["crate_plastic", "crate_plastic2", "box", "gallon", "bottle", "jerrycan"])
	_floor_loot(ctx, "floor_household", 0.6, 2)''')
d.rep('''	_floor_loot(ctx, "toolbox", 0.3)''', '''	_floor_loot(ctx, "toolbox", 0.5)
	_floor_loot(ctx, "floor_household", 0.4)''')
d.rep('''	_floor_loot(ctx, "floor_household", 0.3)''', '''	_floor_loot(ctx, "floor_household", 0.6, 2)''')
# item models: procedural loot models first
d.rep('''const ITEM_MODELS := {
	"battery": "", "flashlight": "small_plastic_torch", "bandage": "medical_tape", "first_aid": "medical_box",
	"splint": "", "painkillers": "", "vest_light": "", "vest_heavy": "", "helmet_light": "", "helmet_heavy": "",
	"backpack_small": "", "backpack_large": "", "weapon_light": "", "sight_reddot": "", "sight_holo": "", "scope_4x": "", "scope_6x": "",
	"pistol_9": "service_pistol", "bolt_308": "bolt_action_rifle_7_62",
}''', '''## Items drawn with a Poly Haven prop; everything else uses assets/models/loot/<id>.glb (made by
## tools/blender/make_loot_models.py), then assets/models/items/<id>.glb (processed downloads).
const ITEM_MODELS := {
	"flashlight": "small_plastic_torch", "first_aid": "medical_box", "pistol_9": "service_pistol", "bolt_308": "bolt_action_rifle_7_62",
}''')
d.rep('''	var model := str(ITEM_MODELS.get(id, ""))
	if id.begins_with("ammo_"):
		model = "ammo_box"
	if model != "":''', '''	var model := str(ITEM_MODELS.get(id, ""))
	if model != "":''')
d.rep('''	if res.is_empty():
		var processed := "res://assets/models/items/%s.glb" % id
		if ResourceLoader.exists(processed):
			var md2: Dictionary = mb.models._load_scene_mesh(processed)
			if not md2.is_empty():
				var a2: AABB = md2.aabb
				res = {"mesh": md2.mesh, "size": a2.size, "xf": Transform3D(Basis(), Vector3(-a2.get_center().x, -a2.position.y, -a2.get_center().z))}''',
      '''	for processed in ["res://assets/models/loot/%s.glb" % id, "res://assets/models/items/%s.glb" % id]:
		if not res.is_empty() or not ResourceLoader.exists(processed):
			continue
		var md2: Dictionary = mb.models._load_scene_mesh(processed)
		if not md2.is_empty():
			var a2: AABB = md2.aabb
			res = {"mesh": md2.mesh, "size": a2.size, "xf": Transform3D(Basis(), Vector3(-a2.get_center().x, -a2.position.y, -a2.get_center().z)),
				"model": processed}''')
d.rep('''		res = {"mesh": bm, "size": size, "xf": Transform3D(Basis(), Vector3(0, size.y * 0.5, 0))}''',
      '''		res = {"mesh": bm, "size": size, "xf": Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)), "placeholder": true}''')
d.save()

# ------------------------------------------------------------------ sites
s = Patch('game/src/world/sites.gd')
s.rep('''func _slab(xf: Transform3D, w: float, d: float, mat: String = "cement") -> void:''', '''func _boxes(xf: Transform3D, n: int, half: Vector2, y: float, choices: Array) -> void:
	## Loot boxes scattered on a site floor (xf local, within +-half), each [model, table].
	for k in n:
		var c: Array = _pick(choices)
		var lp := Vector3(rng.randf_range(-half.x, half.x), y, rng.randf_range(-half.y, half.y))
		mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), lp), str(c[1]), -1)


func _slab(xf: Transform3D, w: float, d: float, mat: String = "cement") -> void:''')
s.rep('''			if rng.randf() < 0.3:
				mb.dyn.add_loot_spot(xf * Vector3(lx + rng.randf_range(-0.6, 0.6), 0.88, lz), "floor_household", -1)''',
      '''			if rng.randf() < 0.3:
				mb.dyn.add_loot_spot(xf * Vector3(lx + rng.randf_range(-0.6, 0.6), 0.88, lz), "floor_household", -1)
			if rng.randf() < 0.22:
				var c: Array = _pick([["lootbox_cooler", "box_cooler"], ["lootbox_bin", "box_bin"], ["lootbox_balikbayan", "box_balikbayan"]])
				mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(lx + 1.55, 0.05, lz + rng.randf_range(-0.3, 0.3))), str(c[1]), -1)''')
s.rep('''	mb.dyn.add_container(xf * Vector3(10, 0.5, 6), "military_crate" if rng.randf() < 0.5 else "crate", -1, Vector3(1.2, 0.8, 0.8))
	mb.dyn.add_loot_spot(xf * Vector3(-6, 0.05, 2), "floor_contested", -1)''', '''	mb.dyn.add_container(xf * Vector3(10, 0.5, 6), "military_crate" if rng.randf() < 0.5 else "crate", -1, Vector3(1.2, 0.8, 0.8))
	mb.dyn.add_loot_spot(xf * Vector3(-6, 0.05, 2), "floor_contested", -1)
	mb.dyn.add_loot_spot(xf * Vector3(6, 0.05, -4), "floor_contested", -1)
	_boxes(xf, rng.randi_range(3, 5), Vector2(13, 8), 0.05, [["lootbox_ammocan", "box_ammocan"], ["lootbox_footlocker", "box_footlocker"],
		["lootbox_bin", "box_bin"], ["lootbox_riflecase", "box_riflecase"], ["lootbox_toolbox", "box_toolbox"]])''')
s.rep('''	mb.dyn.add_light({"pos": cxf * Vector3(0, 29.6, 0), "kind": "beacon", "color": Color(1.0, 0.15, 0.05), "energy": 2.0, "range": 8.0, "blink": 1.1})''',
      '''	mb.dyn.add_light({"pos": cxf * Vector3(0, 29.6, 0), "kind": "beacon", "color": Color(1.0, 0.15, 0.05), "energy": 2.0, "range": 8.0, "blink": 1.1})
	# Contested: rifle cases and ammunition left in the aisles between the stacks.
	for k in 5:
		var c: Array = _pick([["lootbox_riflecase", "box_riflecase"], ["lootbox_ammocan", "box_ammocan"], ["lootbox_footlocker", "box_footlocker"]])
		var lp := Vector3(-24.0 + rng.randi_range(0, 5) * 9.0 + 4.5, 0.05, -12.0 + rng.randi_range(0, 3) * 8.0)
		mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.2, 0.2)), lp), str(c[1]), -1)
		mb.dyn.add_loot_spot(xf * (lp + Vector3(0, 0, 1.2)), "floor_contested", -1)''')
s.rep('''	for k in 5:
		mb.dyn.add_static_prop("boat", xf * Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.2, 0.2)), Vector3(-9.0 if k % 2 == 0 else 9.0, -1.9, 10.0 + k * 9.0)))''',
      '''	for k in 5:
		mb.dyn.add_static_prop("boat", xf * Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.2, 0.2)), Vector3(-9.0 if k % 2 == 0 else 9.0, -1.9, 10.0 + k * 9.0)))
	# Fishermen's iceboxes and gear on the pier.
	for k in 6:
		var c: Array = _pick([["lootbox_cooler", "box_cooler"], ["lootbox_cooler", "box_cooler"], ["lootbox_bin", "box_bin"], ["lootbox_toolbox", "box_toolbox"]])
		mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(rng.randf_range(-3.5, 3.5), 0.0, 2.0 + k * 8.0)), str(c[1]), -1)
	mb.dyn.add_loot_spot(xf * Vector3(0, 0.02, 20), "floor_street", -1)''')
s.rep('''		mb.dyn.add_static_prop(_pick(["wheel_rim", "old_tyre", "drum", "plank_pile", "hollow_block_pile"]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), o))''',
      '''		mb.dyn.add_static_prop(_pick(["wheel_rim", "old_tyre", "drum", "plank_pile", "hollow_block_pile"]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), o))
	for k in 3:
		var o2 := Vector3(rng.randf_range(-10, 0), 0.0, rng.randf_range(-10, 10))
		var c: Array = _pick([["lootbox_toolbox", "box_toolbox"], ["lootbox_ammocan", "box_ammocan"]])
		mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), o2), str(c[1]), -1)''')
s.save()

# ------------------------------------------------------------------ lanes
t = Patch('game/src/world/street_dress.gd')
t.rep('''var stats := {"poles": 0, "wires": 0, "laundry": 0, "clutter": 0, "props": 0, "tags": 0, "puddles": 0, "plants": 0, "vehicles": 0, "floating": 0}''',
      '''var stats := {"poles": 0, "wires": 0, "laundry": 0, "clutter": 0, "props": 0, "tags": 0, "puddles": 0, "plants": 0, "vehicles": 0, "floating": 0,
	"loot": 0, "boxes": 0}''')
t.rep('''		elif r < 0.9 and not walk and w > 1.6:
			_puddle(Vector3(pa.x + dir.x * step, y2 + 0.02, pa.y + dir.y * step), rng.randf_range(0.8, 2.2))''',
      '''		elif r < 0.9 and not walk and w > 1.6:
			_puddle(Vector3(pa.x + dir.x * step, y2 + 0.02, pa.y + dir.y * step), rng.randf_range(0.8, 2.2))
		elif r < 0.935:
			# Something dropped or left out: loose loot by the wall.
			dyn.add_loot_spot(Vector3(p2.x, y2 + 0.02, p2.y), "floor_street", -1)
			stats.loot += 1
		elif r < 0.95 and not walk:
			var c: Array = _pick([["lootbox_bin", "box_bin"], ["lootbox_cooler", "box_cooler"], ["lootbox_balikbayan", "box_balikbayan"]])
			if dyn.door_swing_clear(Vector2(p2.x, p2.y), Vector2(0.45, 0.45), 0.0) and dyn.add_loot_box(str(c[0]), xf, str(c[1]), -1) >= 0:
				stats.boxes += 1''')
t.save()
print('ok')
