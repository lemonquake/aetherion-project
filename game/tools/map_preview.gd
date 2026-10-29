extends Node3D
## Builds the map and saves screenshots from fixed viewpoints. Run with a window (needs the GPU):
##   godot --path game res://tools/map_preview.tscn -- --out=<dir> [--views=a,b] [--bright] [--size=1600x900]

const MapBuilder := preload("res://src/world/map_builder.gd")

var is_server := false
var match_info := {}
var characters := {}
var map = null
var out_dir := "user://preview"
var views := []
var bright := false
var cam: Camera3D
var zfight := false
var extra_views := {}

const VIEWS := {
	"overview": [Vector3(140, 160, 260), Vector3(-20, 0, -120)],
	"west_bank": [Vector3(-60, 90, -120), Vector3(-200, 0, -280)],
	"looban_alley": ["street", Vector2(-118, -262), 0.0],
	"looban_alley2": ["street", Vector2(-160, -300), 1.6],
	"river_boardwalk": ["river", -40.0, -1.0],
	"river_east": ["river", 120.0, 1.0],
	"estero": ["estero", -300.0],
	"bridge": [Vector3(-10, 3.2, -205), Vector3(60, 2.0, -190)],
	"rail": [Vector3(-160, 2.6, -432), Vector3(0, 2.0, -440)],
	"market": [Vector3(100, 2.2, -175), Vector3(124, 2.0, -146)],
	"looban_east": ["street", Vector2(300, -24), 0.8],
	"fishing": [Vector3(-330, 3.0, 340), Vector3(-330, 1.0, 420)],
	"canopy_low": [Vector3(-60, 40, -150), Vector3(-90, 0, -230)],
	"canopy_high": [Vector3(-60, 95, -100), Vector3(-60, 0, -230)],
	"freefall": [Vector3(0, 230, 40), Vector3(-40, 0, -150)],
	"plane": [Vector3(250, 320, 200), Vector3(0, 0, -100)],
	# Lawless Sub (--map=lawless_sub).
	"sub_top": ["ortho", Vector2(0, 0), 470.0],
	"sub_air": [Vector3(60, 140, 230), Vector3(-10, 0, 0)],
	"sub_intersection": [Vector3(-2, 7, 18), Vector3(-30, 0, -8)],
	"sub_avenue": [Vector3(-14, 2.2, -60), Vector3(-22, 1.5, 40)],
	"sub_overpass": [Vector3(-8, 3.0, -25), Vector3(-23, 5.0, -49)],
	"sub_overpass_walk": [Vector3(-25, 8.9, -48), Vector3(-20, 3.0, 10)],
	"sub_bridge_detail": [Vector3(-99, 3.2, -9), Vector3(-68, 1.6, 5)],
	"sub_pool": ["lot", "pool", 0],
	"sub_court": ["lot", "court", 0],
	"sub_playground": ["lot", "playground", 0],
	"sub_houses": [Vector3(66, 9, -60), Vector3(100, 2, -100)],
	"sub_street": [Vector3(30, 2.6, -40), Vector3(30, 1.5, -120)],
	"sub_canal": [Vector3(-70, 3.5, -120), Vector3(-80, 0, -40)],
	"sub_south": [Vector3(-100, 40, 160), Vector3(-150, 0, 80)],
	"sub_factory": [Vector3(60, 25, 110), Vector3(130, 0, 170)],
	"sub_tower": ["lot", "office_tower", 0], "sub_mart": ["lot", "store", 0], "sub_strip": ["lot", "strip_shops", 0], "sub_plastics": ["lot", "factory", 0],
	"sub_club": ["lot", "clubhouse", 0], "sub_chapel": ["lot", "chapel", 0], "sub_flats": ["lot", "apartment", 0], "sub_shops": ["lot", "shophouse", 3],
	"in_sala": ["room", "sala", 7], "in_kitchen": ["room", "kitchen", 4], "in_bedroom": ["room", "bedroom", 9], "in_stair": ["room", "stair", 5],
	"in_aisles": ["room", "store_aisles", 0], "in_factory": ["room", "factory_floor", 0], "in_office": ["room", "office", 2], "in_shop": ["room", "shop", 2],
	"in_chapel": ["room", "chapel", 0], "in_hall": ["room", "hall", 0],
	"tunnel0": ["tunnel", 0], "tunnel1": ["tunnel", 7], "tunnel2": ["tunnel", 19], "tunnel3": ["tunnel", 31],
	"looban0": ["looban", 0], "looban1": ["looban", 3], "looban2": ["looban", 8], "walk0": ["walkway", 0], "walk1": ["walkway", 5], "tunnel4": ["tunnel", 44], "tunnel5": ["tunnel", 60], "ladder0": ["ladder", 0], "ladder1": ["ladder", 11], "deck0": ["deck", 4],
}


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	get_tree().create_timer(float(args.get("timeout", 400))).timeout.connect(func(): print("[preview] watchdog timeout"); get_tree().quit(2))
	out_dir = str(args.get("out", out_dir))
	bright = args.has("bright")
	zfight = args.has("zfight")
	views = str(args.get("views", ",".join(VIEWS.keys()))).split(",")
	if args.has("cam"):
		# --cam=x,y,z,tx,ty,tz[,name]: one extra viewpoint (eye, then the point looked at).
		var c := str(args.cam).split(",")
		extra_views[c[6] if c.size() > 6 else "cam"] = [Vector3(float(c[0]), float(c[1]), float(c[2])), Vector3(float(c[3]), float(c[4]), float(c[5]))]
		views = [c[6] if c.size() > 6 else "cam"]
	var size := str(args.get("size", "1600x900")).split("x")
	get_window().size = Vector2i(int(size[0]), int(size[1]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var t0 := Time.get_ticks_msec()
	map = MapBuilder.new()
	map.build(self, int(args.get("seed", 1729)), 1, {"map": str(args.get("map", "kalinaw")), "dump_faces": args.has("dumpfaces")})
	if args.has("dumpfaces"):
		map.sink.save_faces(str(args.dumpfaces))
		print("[preview] dumped %d faces to %s" % [map.sink.faces_names.size(), args.dumpfaces])
		get_tree().quit()
		return
	var build_ms := Time.get_ticks_msec() - t0
	print("[preview] map built in %d ms: %s" % [build_ms, JSON.stringify(map.stats)])
	if args.has("mmstats"):
		_mm_stats()
		get_tree().quit()
		return
	if args.has("doorcheck"):
		await get_tree().physics_frame
		_door_check()
		get_tree().quit()
		return
	if bright:
		map.lighting.env.ambient_light_energy = 6.0
		map.lighting.moon.light_energy = 1.4
	cam = Camera3D.new()
	cam.far = 2000.0
	cam.fov = 75.0
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	if args.has("perf"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		await _perf(str(args.get("perf")))
		get_tree().quit()
		return
	# --times=0,450: each view at those match times (seconds; the artificial sun is up from 300 to 600).
	var times: Array = str(args.get("times", "")).split(",", false)
	if times.is_empty():
		times = [""]
	for v in views:
		if not VIEWS.has(v) and not extra_views.has(v):
			continue
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_place(extra_views[v] if extra_views.has(v) else VIEWS[v])
		for tm in times:
			if str(tm) != "":
				map.lighting.forced_time = float(tm)
			for i in 75:
				await get_tree().process_frame
			if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
				# A plan view from high up: draw every detail at full range and drop the far blocks.
				_full_detail(map.root)
				for i in 3:
					await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			if zfight:
				await _zfight(img, v)
			var path := "%s/%s%s%s.png" % [out_dir, v, "_bright" if bright else "", ("_t" + str(tm)) if str(tm) != "" else ""]
			img.save_png(path)
			print("[preview] saved ", path, " fps ", Engine.get_frames_per_second(), " luma ", _luma(img))
	get_tree().quit()


func _zfight(a: Image, v: String) -> void:
	## Z-fighting finder: the same view with the camera moved 2 mm sideways. Ordinary surfaces barely change; two
	## coplanar surfaces swap which one wins, so their pixels flip between two different colours. Saves a mask (red
	## where it flips) and prints the count. Shadows and swaying things are steadied by pausing the scene clock.
	var tscale := Engine.time_scale
	Engine.time_scale = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	a = get_viewport().get_texture().get_image()
	var p0 := cam.global_position
	var flips := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	var n := 0
	var hits := {}
	for k in 3:
		cam.global_position = p0 + cam.global_basis.x * 0.002 * (k + 1) + cam.global_basis.y * 0.0013 * k
		await get_tree().process_frame
		await get_tree().process_frame
		var b := get_viewport().get_texture().get_image()
		for y in range(0, a.get_height(), 2):
			for x in range(0, a.get_width(), 2):
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.35:
					# A real edge moves by a pixel at most: count it only if neither neighbour in b matches a.
					var edge := false
					for dy in [-2, -1, 0, 1, 2]:
						for dx in [-2, -1, 0, 1, 2]:
							var cn := b.get_pixel(clampi(x + dx, 0, a.get_width() - 1), clampi(y + dy, 0, a.get_height() - 1))
							if absf(ca.r - cn.r) + absf(ca.g - cn.g) + absf(ca.b - cn.b) < 0.15:
								edge = true
					if not edge:
						var key := Vector2i(x, y)
						if not hits.has(key):
							hits[key] = true
							n += 1
							flips.set_pixel(x, y, Color(1, 0, 0))
							flips.set_pixel(x + 1 if x + 1 < a.get_width() else x, y, Color(1, 0, 0))
	cam.global_position = p0
	Engine.time_scale = tscale
	# Mask over a dimmed copy of the frame.
	var out := a.duplicate()
	for y in range(0, out.get_height()):
		for x in range(0, out.get_width()):
			if flips.get_pixel(x, y).r > 0.5:
				out.set_pixel(x, y, Color(1, 0, 0))
			else:
				out.set_pixel(x, y, out.get_pixel(x, y) * 0.6)
	out.save_png("%s/%s_zfight.png" % [out_dir, v])
	print("[zfight] %s %d flipping pixels (of %d sampled)" % [v, n, a.get_width() * a.get_height() / 4])


func _full_detail(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		if g.visibility_range_begin > 0.0:
			g.visible = false
		else:
			g.visibility_range_end = 0.0
			g.visible = true
	for c in n.get_children():
		_full_detail(c)


static func _luma(img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			s += (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			n += 1
	return s / maxf(n, 1)


func _mm_stats() -> void:
	## Instanced models by total triangles (instances x triangles per mesh), plus the cell count.
	var by := {}
	for key in map.dyn._mm:
		var e: Dictionary = map.dyn._mm[key]
		var name := str(key).split("|")[1]
		var mesh: Mesh = e.mesh
		var tris := 0
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var idx = a[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null and idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var lods := 0
		var lod_min := tris
		if mesh is ArrayMesh:
			var sd: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
			lods = (sd.get("lods", []) as Array).size()
			if lods > 0:
				var last: Dictionary = sd.lods[lods - 1]
				lod_min = (last.index_data as PackedByteArray).size() / (2 if int(sd.get("vertex_count", 0)) <= 65536 else 4) / 3
		var r: Dictionary = by.get(name, {"inst": 0, "tris": tris, "cells": 0, "surf": mesh.get_surface_count(), "lods": lods, "lod_min": lod_min})
		r.inst += (e.xforms as Array).size()
		r.cells += 1
		by[name] = r
	var rows := []
	var total := 0
	for k in by:
		rows.append([by[k].inst * by[k].tris, k])
		total += by[k].inst * by[k].tris
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("[mmstats] %d models, %d cells, %d instanced triangles in total" % [by.size(), map.dyn._mm.size(), total])
	for r in rows.slice(0, 45):
		var d: Dictionary = by[r[1]]
		print("[mmstats] %-28s inst %5d  tris %7d  surf %2d  cells %4d  total %9d  lods %d (last ~%d tris in surface 0)" % [r[1], d.inst, d.tris, d.surf, d.cells, r[0], d.lods, d.lod_min])
	# Loot and physics load: containers by table, movable props by name (each is a dormant physics body).
	var tables := {}
	for c in map.dyn.containers:
		tables[c.table] = int(tables.get(c.table, 0)) + 1
	print("[mmstats] %d containers: %s" % [map.dyn.containers.size(), JSON.stringify(tables)])
	var names := {}
	var interior := 0
	for p in map.dyn.props:
		names[p.name] = int(names.get(p.name, 0)) + 1
		interior += 1 if p.get("interior", false) else 0
	var top := names.keys()
	top.sort_custom(func(a, b): return names[a] > names[b])
	print("[mmstats] %d movable props (%d indoors): %s" % [map.dyn.props.size(), interior, ", ".join(top.slice(0, 30).map(func(k): return "%s %d" % [k, names[k]]))])


func _physics_process(dt: float) -> void:
	# Lamps, the light manager and the view tiers run from the map tick, as in a match.
	if map and map.has_method("physics_tick"):
		map.physics_tick(dt)


func _place(spec: Array) -> void:
	## VIEWS are written in the unscaled layout's coordinates; heights are not scaled.
	var L = map.layout
	var k: float = L.MAP_SCALE
	if spec[0] is String and str(spec[0]) in ["tunnel", "looban", "ladder", "deck", "walkway"]:
		_place_feature(str(spec[0]), int(spec[1]))
		return
	if spec[0] is Vector3:
		cam.global_position = (spec[0] as Vector3) * Vector3(k, 1.0, k)
		cam.look_at((spec[1] as Vector3) * Vector3(k, 1.0, k), Vector3.UP)
		return
	match str(spec[0]):
		"ortho":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(spec[2])
			var oc: Vector2 = spec[1]
			cam.global_position = Vector3(oc.x, 300.0, oc.y)
			cam.rotation = Vector3(-PI * 0.5, 0, 0)
			return
		"room":
			var rs: Array = map.rooms.filter(func(r): return str(r.type) == str(spec[1]))
			if rs.is_empty():
				return
			var r: Dictionary = rs[int(spec[2]) % rs.size()]
			var rx: Transform3D = r.xf
			var sz: Vector2 = r.size
			cam.global_position = rx * Vector3(-sz.x * 0.5 + 0.35, 1.6, -sz.y * 0.5 + 0.35)
			cam.look_at(rx * Vector3(sz.x * 0.5, 0.9, sz.y * 0.5), Vector3.UP)
			print("[preview] room %s #%d at %s size %s" % [spec[1], int(spec[2]) % rs.size(), str(rx.origin.round()), str(sz)])
			return
		"lot":
			var ls: Array = L.lots.filter(func(l): return str(l.kind) == str(spec[1]))
			if ls.is_empty():
				return
			var lt: Dictionary = ls[int(spec[2]) % ls.size()]
			var lc: Vector2 = lt.center
			var fv: Vector2 = lt.front
			var hl: Vector2 = lt.half
			var dist := maxf(hl.x, hl.y) * 1.6 + 8.0
			var side := Vector2(-fv.y, fv.x)
			var pos := lc + fv * (hl.y + dist * 0.8) + side * dist * 0.5
			cam.global_position = Vector3(pos.x, float(lt.plinth_y) + 1.7 + dist * 0.18, pos.y)
			cam.look_at(Vector3(lc.x, float(lt.plinth_y) + 3.0, lc.y), Vector3.UP)
			return
		"street":
			var p := _open_spot((spec[1] as Vector2) * k)
			var y: float = _floor_y(p)
			cam.global_position = Vector3(p.x, y + 1.65, p.y)
			cam.rotation = Vector3(-0.05, float(spec[2]), 0)
		"river":
			var z := float(spec[1]) * k
			var side := float(spec[2])
			var x: float = L.river_x(z) + side * (L.river_hw(z) - 0.6)
			cam.global_position = Vector3(x, L.WATER_Y + 1.55 + 1.65, z)
			cam.look_at(Vector3(L.river_x(z + 40.0) + side * (L.river_hw(z + 40.0) - 0.6), L.WATER_Y + 3.0, z + 40.0), Vector3.UP)
		"estero":
			var x2 := float(spec[1]) * k
			var z2: float = L.estero_z(x2) + L.estero_w * 0.5 + 0.7
			cam.global_position = Vector3(x2, L.WATER_Y + 1.5 + 1.65, z2)
			cam.look_at(Vector3(x2 + 30.0, L.WATER_Y + 2.5, L.estero_z(x2 + 30.0) + L.estero_w * 0.5 + 0.7), Vector3.UP)


func _place_feature(kind: String, i: int) -> void:
	## Cameras on the r3 features, by index: inside a roofed lane looking along it, at a looban's edge, in front of a
	## ladder, on a roof deck.
	match kind:
		"tunnel":
			var lanes: Array = map.tunnels.filter(func(t): return t.kind == "lane" and (t.b as Vector2).distance_to(t.a) > 8.0)
			var t: Dictionary = lanes[i % lanes.size()]
			var a: Vector2 = t.a
			var b: Vector2 = t.b
			var p := a.lerp(b, 0.12)
			cam.global_position = Vector3(p.x, map.layout.ground_height(p.x, p.y) + 1.65, p.y)
			cam.look_at(Vector3(b.x, cam.global_position.y - 0.1, b.y), Vector3.UP)
		"looban":
			var lb: Dictionary = map.loobans[i % map.loobans.size()]
			var c: Vector2 = lb.c
			var h: Vector2 = lb.half
			var ang: float = lb.ang
			var corner: Vector2 = c + Vector2(cos(ang), sin(ang)) * (h.x + 1.0) + Vector2(-sin(ang), cos(ang)) * (h.y + 0.5)
			cam.global_position = Vector3(corner.x, map.layout.ground_height(corner.x, corner.y) + 1.7, corner.y)
			cam.look_at(Vector3(c.x, cam.global_position.y - 0.5, c.y), Vector3.UP)
		"walkway":
			var walks: Array = map.tunnels.filter(func(t): return t.kind == "walk" and (t.b as Vector2).distance_to(t.a) > 8.0)
			var tw: Dictionary = walks[i % walks.size()]
			var aw: Vector2 = tw.a
			var bw: Vector2 = tw.b
			var pw := aw.lerp(bw, 0.1)
			cam.global_position = Vector3(pw.x, float(tw.y) + 1.65, pw.y)
			cam.look_at(Vector3(bw.x, float(tw.y) + 1.5, bw.y), Vector3.UP)
		"ladder", "deck":
			var ld: Dictionary = map.ladders[i % map.ladders.size()]
			var b3: Vector3 = ld.base
			var n: Vector3 = ld.n
			if kind == "ladder":
				cam.global_position = b3 + n * 4.5 + Vector3.UP * 1.7 + n.cross(Vector3.UP) * 1.2
				cam.look_at(b3 + Vector3.UP * 2.2, Vector3.UP)
			else:
				cam.global_position = b3 - n * 1.2 + Vector3.UP * (float(ld.top_y) - b3.y + 1.7)
				cam.look_at(b3 - n * 6.0 + Vector3.UP * (float(ld.top_y) - b3.y + 0.8), Vector3.UP)


func _floor_y(p: Vector2) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60, p.y), Vector3(p.x, -10, p.y))
	var r := space.intersect_ray(q)
	return r.position.y if not r.is_empty() else 1.0


func _open_spot(c: Vector2) -> Vector2:
	## Nearest point with open sky and walkable ground (an alley), searching outward.
	var space := get_world_3d().direct_space_state
	for ring in 40:
		for k in 16:
			var a := k * TAU / 16.0
			var p := c + Vector2(cos(a), sin(a)) * ring * 0.8
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40, p.y), Vector3(p.x, -10, p.y))
			var r := space.intersect_ray(q)
			if r.is_empty():
				continue
			if absf(r.position.y - map.layout.ground_height(p.x, p.y)) < 0.4 and not map.layout.is_water(p.x, p.y):
				return p
	return c


func _door_check() -> void:
	## Swings every closed, unlocked outer door through its arc as a player outside would open it (doors swing toward
	## whoever opens them) and reports what stops it. Light props are shoved aside; anything heavier shuts the house.
	var checked := 0
	var blocked := {}
	var examples := []
	for d in map.dyn.doors:
		var dn = d.get("node")
		if dn == null or dn.is_shutter or dn.locked or not d.get("outer", false) or not d.has("outward"):
			continue
		checked += 1
		var outside: Vector3 = dn.center() + (d.outward as Vector3) * 1.1
		var sgn := -float(dn.hinge_side_sign(outside))  # as Door.server_use
		for k in range(1, 12):
			var a: float = dn.MAX_ANGLE * sgn * k / 11.0
			var what := _door_hit(dn, a)
			if what != "":
				blocked[what] = int(blocked.get(what, 0)) + 1
				if examples.size() < 10:
					examples.append("door %d at %s: %s at %.2f rad" % [int(d.id), str(dn.center().snapped(Vector3.ONE * 0.1)), what, a])
				break
	var n := 0
	for k in blocked:
		n += int(blocked[k])
	print("[doorcheck] %d outer doors swung, %d blocked: %s" % [checked, n, JSON.stringify(blocked)])
	for e in examples:
		print("[doorcheck]   " + e)


func _door_hit(dn, a: float) -> String:
	## Door._would_hit without its side effects; names the first thing in the way.
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(dn.w - 0.08, dn.h - 0.1, dn.t + 0.02)
	q.shape = bs
	q.transform = dn.base * Transform3D(Basis(Vector3.UP, a), Vector3.ZERO) * Transform3D(Basis(), Vector3(dn.w * 0.5 + 0.03, dn.h * 0.5, 0))
	q.collision_mask = Defs.PHYS_PROP | Defs.PHYS_CHAR | Defs.PHYS_CORPSE
	q.exclude = [dn.body]
	for r in PhysicsServer3D.space_get_direct_state(map.dyn.space_rid).intersect_shape(q, 4):
		var c = r.collider
		if c != null and c.has_meta("prop_id"):
			if dn.light_resting_prop(int(c.get_meta("prop_id"))):
				continue  # the door shoves it aside
			return str(map.dyn.props[int(c.get_meta("prop_id"))].name)
		return str(c) if c != null else "body %s" % str(r.rid)
	return ""


func _report(label: String, frames: int = 240) -> void:
	## Frame time, the renderer's own CPU / GPU time and the draw count, averaged over frames (after a settle: toggling
	## thousands of instances costs a few slow frames).
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 45:
		await get_tree().process_frame
	var cpu := 0.0
	var gpu := 0.0
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	print("[perf] %-32s %6.2f ms  render cpu %5.2f gpu %5.2f  draws %5d  prims %8d" % [label, (Time.get_ticks_usec() - t0) / 1000.0 / frames,
		cpu / frames, gpu / frames, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _perf(view: String) -> void:
	## Frame cost at one viewpoint with features toggled one at a time.
	_place(VIEWS[view])
	for i in 60:
		await get_tree().process_frame
	var env: Environment = map.lighting.env
	var moon: DirectionalLight3D = map.lighting.moon
	await _report(view + " baseline")
	moon.shadow_enabled = false
	await _report("moon shadows off")
	moon.shadow_enabled = true
	env.volumetric_fog_enabled = false
	await _report("volumetric fog off")
	env.volumetric_fog_enabled = true
	env.ssao_enabled = false
	await _report("ssao off")
	env.ssao_enabled = true
	var mm = map.root.get_children().filter(func(c): return c.name.begins_with("MM_"))
	for c in mm:
		c.visible = false
	await _report("multimesh props hidden")
	# Furnished rooms on their own: the instanced props on the Interior Props layer.
	var inside = mm.filter(func(c): return (c as VisualInstance3D).layers == Defs.RENDER_INTERIOR_PROPS)
	for c in mm:
		c.visible = not inside.has(c)
	await _report("interior props hidden")
	for c in mm:
		c.visible = true
	# Outdoors: trees and plants, then the rest of the street props.
	var green := []
	var street := []
	for key in map.dyn._mm:
		var e: Dictionary = map.dyn._mm[key]
		var parts := str(key).split("|")
		if e.node == null or parts.size() < 3 or parts[2] != "e":
			continue
		(green if str(map.models.spec(parts[1]).get("kind", "")) in ["tree", "plant"] else street).append(e.node)
	for c in green:
		c.visible = false
	await _report("trees and plants hidden")
	for c in green:
		c.visible = true
	for c in street:
		c.visible = false
	await _report("other street props hidden")
	for c in street:
		c.visible = true
	var casting = inside.filter(func(c): return (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for c in casting:
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await _report("interior props cast no shadows")
	for c in casting:
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var chunks = map.root.get_children().filter(func(c): return c.name.begins_with("Chunk_"))
	for c in chunks:
		c.visible = false
	await _report("chunk geometry hidden")
	for c in chunks:
		c.visible = true
