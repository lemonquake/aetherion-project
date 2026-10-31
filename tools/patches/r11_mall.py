"""r11: Lawless Mall (two floors round an open atrium, shop units with wide storefronts, food court, supermarket,
grand stair in the concourse, a service stair core that carries on to the roof deck) and the building-kit features
it needs: floor voids with glass-and-steel balustrades, "front" links (storefront-wide openings), the "concourse"
and "boutique" room types.
    python -I tools/patches/r11_mall.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

# ---------------------------------------------------------------- house_plan.gd
p = Patch('game/src/world/house_plan.gd')
p.rep('''##              stair: {start: Vector2, dir: Vector2 or "+x"|"-x"|"+z"|"-z", w (1.0), side (let-out), to (floor),
##                      rail, mat},''',
      '''##              stair: {start: Vector2, dir: Vector2 or "+x"|"-x"|"+z"|"-z", w (1.0), side (let-out), to (floor),
##                      rail, mat},
##              voids: [Rect2 | [x0, z0, x1, z1]] (r11: open to the floor below, e.g. a mall atrium; balustrade round
##                      each), links may also be "front" (a storefront: the shared wall opened almost end to end),''')
p.rep('''const OPEN_TYPES := ["sala", "living", "dining", "foyer", "stair", "lobby", "corridor", "hall", "shop", "store_aisles", "factory_floor", "warehouse"]
const CIRC_TYPES := ["sala", "living", "dining", "foyer", "stair", "lobby", "corridor", "hall", "shop", "store_aisles", "factory_floor", "warehouse", "kitchen"]''',
      '''const OPEN_TYPES := ["sala", "living", "dining", "foyer", "stair", "lobby", "corridor", "hall", "shop", "store_aisles", "factory_floor", "warehouse",
	"concourse", "boutique"]
const CIRC_TYPES := ["sala", "living", "dining", "foyer", "stair", "lobby", "corridor", "hall", "shop", "store_aisles", "factory_floor", "warehouse", "kitchen",
	"concourse", "boutique"]''')
p.rep('''	"classroom": ["terrazzo", "wall_painted"],
}''', '''	"classroom": ["terrazzo", "wall_painted"], "concourse": ["marble", "wall_painted"], "boutique": ["laminate", "wall_painted"],
}''')
p.rep('''		F.rooms = rs
		F.flights = []
		F.holes = []
		floors.append(F)''', '''		F.rooms = rs
		F.flights = []
		F.holes = []
		var vs := []
		for v in F.get("voids", []):
			vs.append(_rect(v))
		F.voids = vs
		floors.append(F)''')
# Slabs and finishes skip the voids.
p.rep('''		if f > 0:
			var holes := []
			for hz in F.holes:
				holes.append(hz.rect)
			if mezz:''', '''		if f > 0:
			var holes := []
			for hz in F.holes:
				holes.append(hz.rect)
			holes.append_array(F.voids)
			if mezz:''')
p.rep('''			var holes2 := []
			for hz in F.holes:
				holes2.append(hz.rect)
			slab(xf, fr, fy + 0.02, 0.02, str(R.floor_mat), holes2, fopt)''', '''			var holes2 := []
			for hz in F.holes:
				holes2.append(hz.rect)
			holes2.append_array(F.voids)
			slab(xf, fr, fy + 0.02, 0.02, str(R.floor_mat), holes2, fopt)''')
p.rep('''		_hole_rails(xf, floors, f, w, d, te)
		if F.has("balcony"):''', '''		_hole_rails(xf, floors, f, w, d, te)
		_void_rails(xf, F)
		if F.has("balcony"):''')
p.rep('''			for hz in F.holes:
				avoid.append((hz.rect as Rect2).grow(0.35))
				var top_end''', '''			for vr in F.voids:
				avoid.append((vr as Rect2).grow(0.6))
			for hz in F.holes:
				avoid.append((hz.rect as Rect2).grow(0.35))
				var top_end''')
p.rep('''			if typ == "open":
				dw = clampf(length - 0.6, 0.9, 2.4 if (str(Ri.type) in ["sala", "living", "dining"] and str(Rj.type) in ["sala", "living", "dining", "kitchen"]) else 1.4)
				dh = minf(2.2, hgt - 0.2)''', '''			if typ == "open":
				dw = clampf(length - 0.6, 0.9, 2.4 if (str(Ri.type) in ["sala", "living", "dining"] and str(Rj.type) in ["sala", "living", "dining", "kitchen"]) else 1.4)
				dh = minf(2.2, hgt - 0.2)
			elif typ == "front":
				# A storefront: the wall opened end to end but for a pier at each side, up to the shutter box.
				dw = clampf(length - 0.9, 1.2, 9.0)
				dh = minf(3.0, hgt - 0.35)''')
p.rep('''				var op := {"type": "door" if typ == "door" else "opening", "c": c, "w": dw, "h": dh, "y": 0.0, "door_mat": str(plan.get("door_mat", "planks_paint")),''',
      '''				if typ == "front":
					c = length * 0.5
				var op := {"type": "door" if typ == "door" else "opening", "c": c, "w": dw, "h": dh, "y": 0.0, "door_mat": str(plan.get("door_mat", "planks_paint")),''')
p.rep('''func _mezzanine(xf: Transform3D, floors: Array, f: int, w: float, d: float, te: float, dirt: float) -> void:''',
      '''func _void_rails(xf: Transform3D, F: Dictionary) -> void:
	## (r11) A balustrade round each floor void: steel posts and handrail over a glass infill, 1.05 m, with a gap
	## where a stair flight lands through the void's edge.
	var fy := float(F.y)
	for vr in F.voids:
		var r: Rect2 = vr
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k in 4:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % 4]
			railing(xf, a, b, fy, {"h": 1.05})
			var m := (a + b) * 0.5
			var ln := a.distance_to(b)
			var horiz := absf(a.y - b.y) < 0.01
			var gsize := Vector3(ln - 0.1, 0.8, 0.02) if horiz else Vector3(0.02, 0.8, ln - 0.1)
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(m.x, fy + 0.5, m.y)), gsize, "glass",
				{"collide": true, "dirt": 0.1, "what": "balustrade_glass", "layer": "inner"})
		# The slab edge round the void, faced in the trim colour.
		for k in 4:
			var a2: Vector2 = pts[k]
			var b2: Vector2 = pts[(k + 1) % 4]
			var m2 := (a2 + b2) * 0.5
			var ln2 := a2.distance_to(b2)
			var horiz2 := absf(a2.y - b2.y) < 0.01
			var esize := Vector3(ln2 + 0.04, 0.32, 0.04) if horiz2 else Vector3(0.04, 0.32, ln2 + 0.04)
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(m2.x, fy - 0.12, m2.y)), esize, "metal_paint",
				{"collide": false, "tint": Color(0.86, 0.86, 0.84), "paint": 0.8, "dirt": 0.2, "what": "void_edge", "layer": "inner"})


func _mezzanine(xf: Transform3D, floors: Array, f: int, w: float, d: float, te: float, dirt: float) -> void:''')
p.save()

# Stairs up to a flat roof (the roof deck): the flight comes up through the roof slab, railed like a stair opening.
p = Patch('game/src/world/house_plan.gd')
p.rep('''		if to >= n_floors:
			# TODO: a stair house (bulkhead) on a flat roof; until then roofs are reached by ladder.
			report.warnings.append''', '''		if to >= n_floors and str(plan.get("roof", {}).get("type", "hip")) != "flat":
			# Roof stairs only come up through a flat roof deck (r11); pitched roofs are reached by ladder.
			report.warnings.append''')
p.rep('''		else:
			F.roof_hole = hole''', '''		else:
			F.roof_hole = hole
			F.roof_flight = F.flights[-1]''')
p.rep('''		parapet(xf, Rect2(-w * 0.5, -d * 0.5, w, d), top_y + rh, ph, 0.15, ext_mat, gaps, {"tint": ext_tint, "paint": 0.85, "dirt": dirt + 0.2})''',
      '''		parapet(xf, Rect2(-w * 0.5, -d * 0.5, w, d), top_y + rh, ph, 0.15, ext_mat, gaps, {"tint": ext_tint, "paint": 0.85, "dirt": dirt + 0.2})
		if floors[-1].has("roof_flight"):
			_hole_rails(xf, [{"y": top_y + rh, "holes": [{"rect": floors[-1].roof_hole, "flight": floors[-1].roof_flight}]}], 0, w, d, te)''')
p.save()

# ---------------------------------------------------------------- big_plans.gd: the mall
p = Patch('game/src/world/maps/lawless_sub/big_plans.gd')
p.rep('''##   guardhouse / guard_booth  one room, two doors''',
      '''##   guardhouse / guard_booth  one room, two doors
##   mall          Lawless Mall (r11): two floors of shop units round an open atrium, food court, supermarket, grand
##                 stair in the concourse, service stair core up to the roof deck, entrances on three sides''')
p.rep('''const KINDS := ["office_tower", "apartment", "clubhouse", "chapel", "store", "strip_shops", "factory", "warehouse", "guardhouse", "guard_booth"]''',
      '''const KINDS := ["office_tower", "apartment", "clubhouse", "chapel", "store", "strip_shops", "factory", "warehouse", "guardhouse", "guard_booth", "mall"]''')
p.rep('''		"guardhouse":
			plan = _guardhouse(w, d, n, rng)
		_:''', '''		"guardhouse":
			plan = _guardhouse(w, d, n, rng)
		"mall":
			plan = _mall(w, d, n, rng)
		_:''')
p.rep('''static func _guardhouse(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:''',
      '''static func _mall(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	## Lawless Mall. Front (-z) on the avenue side. Each floor: a row of shop units along the front, the concourse
	## (8 m) the length of the building, and the anchors at the back (food court and supermarket downstairs, an
	## arcade hall and the management office upstairs), toilets and the service stair core in the back corner.
	## The concourse floor upstairs is open over an atrium; the grand stair climbs along the concourse beside it.
	var X := w * 0.5
	var Z := d * 0.5
	var zf := -Z + 7.5          # back of the front shop row
	var zb := zf + 9.0          # back of the concourse
	var core_x := X - 4.4       # service core: core_x..X, zb..Z
	var wc_x := core_x - 4.6
	var h0 := 4.4
	var h1 := 4.0
	var shop_w := (X - 3.0) / 3.0
	var g_rooms := []
	var u_rooms := []
	var g_links := []
	var u_links := []
	var g_types := ["boutique", "shop", "dining", "shop", "boutique", "shop"]
	var u_types := ["boutique", "shop", "boutique", "office", "shop", "boutique"]
	for k in 6:
		var x0 := (-X + shop_w * k) if k < 3 else (3.0 + shop_w * (k - 3))
		var x1 := x0 + shop_w
		g_rooms.append({"type": g_types[k], "rect": [x0, -Z, x1, zf], "id": "g%d" % k})
		u_rooms.append({"type": u_types[k], "rect": [x0, -Z, x1, zf], "id": "u%d" % k})
		g_links.append(["g%d" % k, "concourse", "front"])
		u_links.append(["u%d" % k, "concourse", "front" if u_types[k] != "office" else "door"])
		if k != 2 and k != 5:
			g_links.append(["g%d" % k, "g%d" % (k + 1), "none"])
			u_links.append(["u%d" % k, "u%d" % (k + 1), "none"])
	g_rooms.append({"type": "foyer", "rect": [-3.0, -Z, 3.0, zf], "id": "foyer"})
	u_rooms.append({"type": "boutique", "rect": [-3.0, -Z, 3.0, zf], "id": "u_mid"})
	g_links.append_array([["foyer", "concourse", "open"], ["foyer", "g2", "none"], ["foyer", "g3", "none"]])
	u_links.append_array([["u_mid", "concourse", "front"], ["u_mid", "u2", "none"], ["u_mid", "u3", "none"]])
	g_rooms.append({"type": "concourse", "rect": [-X, zf, X, zb], "id": "concourse"})
	u_rooms.append({"type": "concourse", "rect": [-X, zf, X, zb], "id": "concourse", "windows": 0})
	var fc_x := -X + 14.0
	g_rooms.append({"type": "dining", "rect": [-X, zb, fc_x, Z], "id": "food"})
	g_rooms.append({"type": "store_aisles", "rect": [fc_x, zb, wc_x, Z], "id": "market"})
	g_rooms.append({"type": "toilet", "rect": [wc_x, zb, core_x, Z], "id": "wc"})
	g_rooms.append({"type": "stair", "rect": [core_x, zb, X, Z], "id": "core", "windows": 0})
	g_links.append_array([["food", "concourse", "front"], ["market", "concourse", "front"], ["food", "market", "none"],
		["wc", "concourse", "door"], ["core", "concourse", "open"], ["wc", "core", "none"], ["wc", "market", "none"]])
	u_rooms.append({"type": "hall", "rect": [-X, zb, fc_x + 4.0, Z], "id": "arcade"})
	u_rooms.append({"type": "office", "rect": [fc_x + 4.0, zb, wc_x, Z], "id": "mgmt"})
	u_rooms.append({"type": "toilet", "rect": [wc_x, zb, core_x, Z], "id": "wc"})
	u_rooms.append({"type": "stair", "rect": [core_x, zb, X, Z], "id": "core", "windows": 0})
	u_links.append_array([["arcade", "concourse", "front"], ["mgmt", "concourse", "door"], ["arcade", "mgmt", "none"],
		["wc", "concourse", "door"], ["core", "concourse", "open"], ["wc", "core", "none"], ["wc", "mgmt", "none"]])
	var run0 := _run(h0)
	var run1 := _run(h1)
	# Grand stair: in the concourse, east of the atrium, climbing west along its back wall (2 m wide).
	var gs_x := X - 5.4
	var g := {"h": h0, "rooms": g_rooms, "links": g_links, "ext": {
		"front": [{"type": "opening", "x": 0.0, "w": 4.2, "h": 3.2}],
		"left": [{"type": "opening", "x": (zf + zb) * 0.5, "w": 3.2, "h": 3.0}],
		"right": [{"type": "door", "x": (zf + zb) * 0.5, "w": 1.8, "h": 2.6, "door_mat": "metal_paint"}],
		"back": [{"type": "door", "x": (-X + fc_x) * 0.5, "w": 1.2, "role": "back", "door_mat": "metal_paint"},
			{"type": "door", "x": (fc_x + wc_x) * 0.5, "w": 1.6, "role": "back", "door_mat": "metal_paint"},
			{"type": "door", "x": (core_x + X) * 0.5, "w": 1.0, "role": "back", "door_mat": "metal_paint"}],
	}, "stair": {"start": Vector2(gs_x, zb - 1.2), "dir": "-x", "w": 2.0, "to": 1, "side": Vector2(0, -1)}}
	var u := {"h": h1, "rooms": u_rooms, "links": u_links, "voids": [[-X + 7.0, zf + 2.0, gs_x - run0 - 1.4, zb - 4.0]],
		"balcony": {"side": "front", "c0": -2.6, "c1": 2.6, "depth": 1.4},
		"stair": {"start": Vector2(core_x + 1.2, zb + 1.0), "dir": "+z", "w": 1.4, "to": 2, "side": Vector2(1, 0)}}
	# Ground floor service stair (core): up the core's west lane; the grand stair already joins the floors.
	return {"kind": "store", "floors": [g, u], "ext_mat": "cladding", "ext_tint": Color(0.93, 0.93, 0.9), "trim_tint": Color(0.3, 0.42, 0.5),
		"win_mix": {"glass": 0.92, "open": 0.04, "shutter": 0.04},
		"roof": {"type": "flat", "parapet": 1.1, "ladder": {"side": "back", "x": -X + 2.0}, "tank": true}}


static func _guardhouse(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:''')
p.save()

# Tower and flats: the stair core carries on to the roof deck.
p = Patch('game/src/world/maps/lawless_sub/big_plans.gd')
p.rep('''	var run := _run(h)
	for f in floors.size() - 1:''', '''	var run := _run(h)
	for f in floors.size():   # r11: the top floor's flight comes up through the roof deck''')
p.rep('''			floors[f].stair = {"start": Vector2(cx - 0.6, z0 + 1.0), "dir": "+z", "w": 1.0, "to": f + 1, "side": Vector2(1, 0)}''',
      '''			floors[f].stair = {"start": Vector2(cx - 0.6, z0 + 1.0), "dir": "+z", "w": 1.0, "to": f + 1, "side": Vector2(1, 0)}  # to == floors.size(): the roof''')
p.save()

# ---------------------------------------------------------------- dresser: concourse and boutiques
p = Patch('game/src/world/dresser.gd')
p.rep('''		"shop", "store_aisles":
			_aisles(ctx)''', '''		"shop", "store_aisles":
			_aisles(ctx)
		"concourse":
			_concourse(ctx)
		"boutique":
			_boutique(ctx)''')
p.rep('''func _aisles(ctx: Dictionary) -> void:''', '''func _concourse(ctx: Dictionary) -> void:
	## (r11) A mall concourse: back-to-back benches and planters down the middle, a kiosk or two, signs, rubbish.
	var n := int(ctx.w / 6.0)
	for i in n:
		var x := -ctx.w * 0.5 + 3.0 + i * 6.0
		var z := rng.randf_range(-0.4, 0.4)
		match i % 3:
			0:
				_put(ctx, "planter_box", Vector2(x, z), _pick([0.0, PI * 0.5]))
			1:
				_put(ctx, "street_bench", Vector2(x, z - 0.45), 0.0)
				_put(ctx, "street_bench", Vector2(x, z + 0.45), PI)
			2:
				if _put(ctx, "store_display_case", Vector2(x, z), _pick([0.0, PI])):
					mb.dyn.add_container(_world(ctx, Vector2(x, z), 0.6), "store_counter", int(ctx.bid), Vector3(0.6, 0.6, 0.6))
	_clutter(ctx, rng.randi_range(2, 5), ["wet_floor_sign", "potted_plant", "box", "tote_box", "drum_plastic2"])
	_floor_loot(ctx, "floor_weapon", 0.5, 2)
	_floor_loot(ctx, "floor_household", 0.6, 2)


func _boutique(ctx: Dictionary) -> void:
	## (r11) A small mall shop: display shelving round the walls, a counter with the till by the storefront, a
	## sofa or a rack in the middle.
	if _put(ctx, "store_display_case", Vector2(ctx.w * 0.5 - 1.0, -ctx.d * 0.5 + 1.6), -PI * 0.5):
		mb.dyn.add_container(_world(ctx, Vector2(ctx.w * 0.5 - 1.0, -ctx.d * 0.5 + 1.6), 0.6), "store_counter", int(ctx.bid), Vector3(0.6, 0.6, 0.6))
	for wall in ["back", "left", "right"]:
		for k in 2:
			var s := _wall_slot(ctx, _pick(["display_shelves", "store_shelf_wall", "china_cabinet"]), wall)
			if s.is_empty():
				break
			_container_on(ctx, s, "store_shelf", 0.8, Vector3(0.9, 1.2, 0.4))
	_put(ctx, _pick(["sofa_leather", "armchair_modern", "metal_rack", "planter_box"]), Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.6)), _pick([0.0, PI * 0.5]))
	_clutter(ctx, rng.randi_range(1, 3), ["box", "tote_box", "potted_plant2", "wet_floor_sign"])
	_floor_loot(ctx, "floor_household", 0.6, 2)


func _aisles(ctx: Dictionary) -> void:''')
p.save()
print('r11 mall patch done')
