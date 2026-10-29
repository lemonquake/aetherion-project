extends RefCounted
## Where the settlement's few working lights are, and what is wrong with them. Power here is patchy: bare bulbs on
## lane posts and over doorways, most of them dim and some flickering, buzzing or dying; inside, about half the
## houses are dark, many of the rest light one room only, often with a battery lantern or a candle.
##
## Placement and every random choice come from the match seed, so a house that is lit is lit for every player and
## the lit houses differ from match to match. Fixtures are static geometry; Lighting creates the lights.

const WARM := Color(1.0, 0.72, 0.42)
const WARM_DIM := Color(1.0, 0.64, 0.34)
const CFL := Color(0.86, 0.93, 1.0)
const TUBE_GREEN := Color(0.78, 1.0, 0.84)
const LED := Color(0.9, 0.95, 1.0)
const CANDLE := Color(1.0, 0.58, 0.26)

var mb = null
var rng := RandomNumberGenerator.new()
var stats := {"pole": 0, "porch": 0, "house_lit": 0, "house_dark": 0, "rooms": 0, "dead": 0}


func _init(map_builder, match_seed: int) -> void:
	mb = map_builder
	rng.seed = hash(match_seed * 7349 + 11)


func _fault(kind: String) -> String:
	## Most lights work; the rest have the usual problems.
	var r := rng.randf()
	match kind:
		"tube":
			return "starter" if r < 0.3 else ("flicker" if r < 0.42 else ("sag" if r < 0.5 else ""))
		"candle":
			return "candle"
		"lamp":
			return "sag" if r < 0.15 else ""
	return "flicker" if r < 0.26 else ("dying" if r < 0.34 else ("sag" if r < 0.42 else ""))


func _bulb_colour() -> Color:
	var r := rng.randf()
	return WARM if r < 0.55 else (WARM_DIM if r < 0.7 else (CFL if r < 0.93 else TUBE_GREEN))


# ------------------------------------------------------------------ lanes

func pole_bulb(top: Vector3, along: Vector2) -> void:
	## A bare bulb hanging from a post's cross-arm, sometimes under a tin shade. Called for about half the posts.
	var side := Vector3(-along.y, 0, along.x).normalized() * rng.randf_range(-0.45, 0.45)
	# Strung low on a long flex so the light reaches the lane (posts are 5.6-7.2 m tall).
	var drop := clampf(top.y - mb.layout.ground_height(top.x, top.z) - rng.randf_range(3.4, 4.3), 0.4, 3.2)
	var at := top + side
	var sink = mb.sink
	sink.box(Transform3D(Basis(), at + Vector3(0, -drop * 0.5, 0)), Vector3(0.012, drop, 0.012), "metal_paint",
		{"collide": false, "tint": Color(0.05, 0.05, 0.05), "layer": "mid"})
	var bulb := at + Vector3(0, -drop - 0.06, 0)
	if rng.randf() < 0.35:
		sink.cylinder(bulb + Vector3(0, 0.03, 0), Vector3.UP, 0.07, 0.13, "metal_paint",
			{"sides": 8, "collide": false, "tint": Color(0.3, 0.32, 0.3), "paint": 0.7, "layer": "mid"})
	stats.pole += 1
	if rng.randf() < 0.22:
		stats.dead += 1
		mb.dyn.add_light({"pos": bulb, "kind": "bulb", "color": WARM, "energy": 0.0, "range": 1.0, "dead": true})
		return
	var col := _bulb_colour()
	mb.dyn.add_light({"pos": bulb, "kind": "bulb", "color": col, "energy": rng.randf_range(0.55, 0.9), "range": rng.randf_range(8.0, 11.0),
		"fault": _fault("bulb"), "outdoor": true})


func porch_lights() -> void:
	## A bulb over some front doors, a tube over most shop fronts.
	var seen := {}
	for d in mb.dyn.doors:
		if not d.get("outer", false) or not d.has("outward") or seen.has(d.bid):
			continue
		seen[d.bid] = true
		var b: Dictionary = _building(int(d.bid))
		var shop: bool = str(b.get("kind", "")) == "store"
		if rng.randf() > (0.6 if shop else 0.24):
			continue
		var out: Vector3 = d.outward
		out.y = 0.0
		out = out.normalized()
		var xf: Transform3D = d.xf
		var above: Vector3 = xf * Vector3(float(d.w) * 0.5, float(d.h) + 0.28, 0.0)
		var at := above + out * 0.24
		mb.sink.box(Transform3D(Basis.looking_at(out, Vector3.UP), above + out * 0.12), Vector3(0.03, 0.03, 0.24), "metal_paint",
			{"collide": false, "tint": Color(0.12, 0.12, 0.12), "layer": "mid"})
		stats.porch += 1
		if shop:
			mb.dyn.add_light({"pos": at + Vector3(0, 0.05, 0), "kind": "tube", "color": CFL if rng.randf() < 0.7 else TUBE_GREEN,
				"energy": rng.randf_range(0.5, 0.75), "range": 7.5, "fault": _fault("tube"), "axis": Vector3(-out.z, 0, out.x)})
		elif rng.randf() < 0.15:
			stats.dead += 1
			mb.dyn.add_light({"pos": at, "kind": "bulb", "color": WARM, "energy": 0.0, "range": 1.0, "dead": true})
		else:
			mb.dyn.add_light({"pos": at + Vector3(0, -0.06, 0), "kind": "bulb", "color": _bulb_colour(), "energy": rng.randf_range(0.35, 0.55),
				"range": rng.randf_range(5.0, 6.5), "fault": _fault("bulb"), "outdoor": true})


func _building(bid: int) -> Dictionary:
	for b in mb.buildings:
		if int(b.id) == bid:
			return b
	return {}


# ------------------------------------------------------------------ houses

func house(spec: Dictionary, rooms: Array) -> void:
	## Called once per building after its rooms are dressed.
	var usable := rooms.filter(func(r): return float(r.h) > 1.9)
	if usable.is_empty():
		return
	var kind := str(spec.get("kind", "house"))
	var lit_p := 0.45
	if kind == "store":
		lit_p = 0.75
	elif kind in ["clinic", "chapel", "church", "hall", "police", "outpost"]:
		lit_p = 0.6
	if rng.randf() > lit_p:
		stats.house_dark += 1
		return
	stats.house_lit += 1
	var n := 1 if rng.randf() < 0.72 or usable.size() < 2 else 2
	# Living rooms, kitchens and shop fronts are the rooms people keep a light in. Scores are drawn once from the
	# match-seeded rng so every machine picks the same rooms.
	var scored := []
	for r in usable:
		scored.append([_room_pref(str(r.type)), r])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(n, scored.size()):
		_room_light(scored[i][1], kind)


func _room_pref(t: String) -> float:
	return {"store": 3.0, "sala": 2.5, "kitchen": 2.2, "workshop": 2.0, "bed": 1.2, "cr": 0.4}.get(t, 1.0) + rng.randf() * 1.5


func _room_light(r: Dictionary, house_kind: String) -> void:
	stats.rooms += 1
	var xf: Transform3D = r.xf
	var size: Vector2 = r.size
	var h := float(r.h)
	var t := str(r.type)
	var reach := clampf(maxf(size.x, size.y) * 0.8 + 0.8, 3.5, 6.5)
	var roll := rng.randf()
	if t in ["store", "workshop", "kitchen"] and roll < 0.45:
		# Ceiling tube along the room's long side.
		var axis_local := Vector3(1, 0, 0) if size.x >= size.y else Vector3(0, 0, 1)
		var at: Vector3 = xf * Vector3(0, h - 0.08, 0)
		var axis: Vector3 = (xf.basis * axis_local).normalized()
		mb.sink.box(Transform3D(Basis.looking_at(axis, Vector3.UP), at + Vector3(0, 0.03, 0)), Vector3(0.09, 0.04, 1.25), "metal_paint",
			{"collide": false, "tint": Color(0.75, 0.75, 0.72), "paint": 0.8, "layer": "int"})
		mb.dyn.add_light({"pos": at - Vector3(0, 0.03, 0), "kind": "tube", "color": CFL if rng.randf() < 0.75 else TUBE_GREEN,
			"energy": rng.randf_range(0.45, 0.7), "range": reach + 1.0, "fault": _fault("tube"), "axis": axis})
	elif roll < 0.62:
		# A bare bulb on a short cord from the ceiling, a little off centre.
		var off := Vector3(rng.randf_range(-0.2, 0.2) * size.x, 0, rng.randf_range(-0.2, 0.2) * size.y)
		var cord := rng.randf_range(0.2, 0.45)
		var top: Vector3 = xf * (off + Vector3(0, h, 0))
		mb.sink.box(Transform3D(Basis(), top + Vector3(0, -cord * 0.5, 0)), Vector3(0.01, cord, 0.01), "metal_paint",
			{"collide": false, "tint": Color(0.05, 0.05, 0.05), "layer": "int"})
		mb.dyn.add_light({"pos": top + Vector3(0, -cord - 0.05, 0), "kind": "bulb", "color": _bulb_colour(),
			"energy": rng.randf_range(0.3, 0.55), "range": reach, "fault": _fault("bulb")})
	elif roll < 0.86:
		# A rechargeable lantern hung on a wall nail: steady, cold and weak.
		var sx := rng.randf_range(-0.25, 0.25) * size.x
		var at2: Vector3 = xf * Vector3(sx, 1.85, size.y * 0.5 - 0.09)
		mb.dyn.add_light({"pos": at2, "kind": "lamp", "color": LED, "energy": rng.randf_range(0.22, 0.32), "range": reach - 0.5,
			"fault": _fault("lamp")})
	else:
		# A candle on a saucer in a corner, left burning.
		var cx := (size.x * 0.5 - 0.28) * (1.0 if rng.randf() < 0.5 else -1.0)
		var cz := (size.y * 0.5 - 0.28) * (1.0 if rng.randf() < 0.5 else -1.0)
		var base: Vector3 = xf * Vector3(cx, 0.0, cz)
		mb.sink.cylinder(base, Vector3.UP, 0.012, 0.06, "metal_paint", {"sides": 10, "collide": false, "tint": Color(0.8, 0.8, 0.78), "paint": 1.0, "layer": "int"})
		mb.sink.cylinder(base + Vector3(0, 0.012, 0), Vector3.UP, 0.07, 0.012, "metal_paint", {"sides": 8, "collide": false, "tint": Color(0.92, 0.9, 0.82), "paint": 1.0, "layer": "int"})
		mb.dyn.add_light({"pos": base + Vector3(0, 0.1, 0), "kind": "candle", "color": CANDLE, "energy": rng.randf_range(0.2, 0.3), "range": 3.2,
			"fault": "candle"})
