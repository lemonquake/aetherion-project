extends RefCounted
## (r23) `--wpqa=<dir>` on a server (any map): a strict check of the waypoint graph (waypoints.gd), then quit.
##   coverage   every open cell of the walk (storeyed: every 1 m cell of the main walk; flat: every 2 m cell in the play
##              area) needs a node within 6 m (14 m outdoors) that a body can walk to from it in a straight line;
##   edges      every edge swept again now (a shipped or edited file on today's geometry);
##   routes     500 routes between random nodes of the main graph (all must exist) and how much longer they are than
##              the straight line;
##   nodes      a node standing where a body does not fit, or more than 0.6 m off the walk.
## Writes <dir>/<map>_qa.json and one picture per level (<map>_L<n>.png): walk grey, cells no node covers red, edges by
## kind (walk white, tight orange, door cyan, stair / escalator magenta, wade blue), nodes by priority (1 yellow, 2 green,
## 3 dark green), hiding spots violet, sniping spots red, doors cyan, orphans (off the main graph) black.

const Waypoints := preload("res://src/ai/waypoints.gd")

static func run(world, nav, out_dir: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var W = Waypoints
	var levels: bool = nav.get("levels") != null
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rep := {"map": W.map_id, "source": W.source, "from": str(W.stats.get("source", "")), "nodes": W.nodes.size(), "edges": W.edges.size(),
		"kinds": W.stats.get("kinds", {}), "priority": W.stats.get("pri", {}), "edge_kinds": W.stats.get("edge_kinds", {}),
		"orphans": int(W.stats.get("orphans", 0))}
	# --- coverage
	var cov_r := 6.0 if levels else 14.0
	var cells := []   # [lv, Vector3]
	if levels:
		for lv in int(nav.levels):
			for i in nav.open_cells(lv):
				cells.append([lv, nav.cell_pos(lv, i)])
	else:
		var n: int = nav.n
		var L = world.map.layout
		for z in range(0, n):
			for x in range(0, n):
				if nav.walk[z * n + x] == 0:
					continue
				var c: Vector3 = nav._world(Vector2i(x, z))
				if L.in_play_area(Vector2(c.x, c.z)):
					cells.append([0, c])
	var uncovered := []
	var covered := 0
	for e in cells:
		var lv: int = e[0]
		var p: Vector3 = e[1]
		var ok := false
		var tested := 0
		for j in W._near(p, lv, cov_r, true):
			if int(W.nodes[j].comp) != W.main_comp:
				continue
			var q: Vector3 = W.nodes[j].p
			if absf(q.y - p.y) > 1.5:
				continue
			tested += 1
			if tested > 6:
				break
			if q.distance_to(p) < 0.4 or W.clear(p, q) or W.clear(q, p):
				ok = true
				break
		if ok:
			covered += 1
		else:
			uncovered.append(e)
	rep["cells"] = cells.size()
	rep["covered"] = covered
	rep["coverage_pct"] = snappedf(100.0 * covered / maxf(cells.size(), 1), 0.01)
	# where the uncovered cells are: 4 m clusters, biggest first
	var clusters := {}
	for e2 in uncovered:
		var p2: Vector3 = e2[1]
		var k := "%d:%d,%d" % [int(e2[0]), floori(p2.x / 4.0) * 4, floori(p2.z / 4.0) * 4]
		clusters[k] = int(clusters.get(k, 0)) + 1
	var ck := clusters.keys()
	ck.sort_custom(func(a, b): return int(clusters[a]) > int(clusters[b]))
	var worst := []
	for k2 in ck.slice(0, 30):
		worst.append([k2, clusters[k2]])
	rep["uncovered_worst"] = worst
	# --- edges swept again
	var bad_edges := []
	for e3 in W.edges:
		if str(e3.kind) in ["stair", "escalator"]:
			continue
		var v: Dictionary = W.verify(W.nodes[int(e3.a)].p, W.nodes[int(e3.b)].p)
		if v.is_empty():
			bad_edges.append([W.nodes[int(e3.a)].id, W.nodes[int(e3.b)].id, str(e3.kind), W.why(W.nodes[int(e3.a)].p, W.nodes[int(e3.b)].p),
				str((W.nodes[int(e3.a)].p as Vector3).snapped(Vector3.ONE * 0.1))])
	rep["edges_failing_now"] = bad_edges.size()
	rep["edges_failing_list"] = bad_edges.slice(0, 40)
	# --- nodes where a body does not fit
	var bad_nodes := []
	for nd in W.nodes:
		if nd.via:
			continue
		var p3: Vector3 = nd.p
		if not W._fits(p3, W.R_TIGHT) or (levels and not nav.walkable_at(p3)):
			bad_nodes.append([nd.id, str(nd.kind), [snappedf(p3.x, 0.1), snappedf(p3.y, 0.1), snappedf(p3.z, 0.1)]])
	rep["nodes_blocked"] = bad_nodes.size()
	rep["nodes_blocked_list"] = bad_nodes.slice(0, 40)
	# --- why the orphans are cut off: for one node of each 6 m group, what stops it reaching the nearest main nodes
	var seen := {}
	var why_orphans := []
	for i0 in W.nodes.size():
		var nd0: Dictionary = W.nodes[i0]
		if int(nd0.comp) == W.main_comp or nd0.via:
			continue
		var p0: Vector3 = nd0.p
		var gk := "%d:%d,%d" % [int(nd0.lv), floori(p0.x / 6.0), floori(p0.z / 6.0)]
		if seen.has(gk):
			continue
		seen[gk] = true
		var reasons := []
		for j0 in W._near(p0, int(nd0.lv), 10.0):
			if int(W.nodes[j0].comp) != W.main_comp:
				continue
			reasons.append([W.nodes[j0].id, snappedf(p0.distance_to(W.nodes[j0].p), 0.1), W.why(p0, W.nodes[j0].p)])
			if reasons.size() >= 3:
				break
		why_orphans.append({"node": nd0.id, "kind": str(nd0.kind), "p": str(p0.snapped(Vector3.ONE * 0.1)), "name": str(nd0.name), "to_main": reasons})
		if why_orphans.size() >= 30:
			break
	rep["orphans_why"] = why_orphans
	# --- routes
	var mains := []
	for i in W.nodes.size():
		if int(W.nodes[i].comp) == W.main_comp and not W.nodes[i].via:
			mains.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var found := 0
	var tried := 0
	var ratio_sum := 0.0
	var ratio_max := 0.0
	var tms := Time.get_ticks_usec()
	for k3 in 500:
		var a: int = mains[rng.randi_range(0, mains.size() - 1)]
		var b: int = mains[rng.randi_range(0, mains.size() - 1)]
		if a == b:
			continue
		tried += 1
		var ids: PackedInt64Array = W.astar.get_id_path(a, b)
		if ids.is_empty():
			continue
		found += 1
		var plen := 0.0
		for m in range(1, ids.size()):
			plen += (W.nodes[ids[m - 1]].p as Vector3).distance_to(W.nodes[ids[m]].p)
		var straight := (W.nodes[a].p as Vector3).distance_to(W.nodes[b].p)
		if straight > 10.0:
			var r := plen / straight
			ratio_sum += r
			ratio_max = maxf(ratio_max, r)
	rep["routes_tried"] = tried
	rep["routes_found"] = found
	rep["route_ms_avg"] = snappedf((Time.get_ticks_usec() - tms) / 1000.0 / maxf(tried, 1), 0.001)
	rep["route_detour_avg"] = snappedf(ratio_sum / maxf(found, 1), 0.01)
	rep["route_detour_max"] = snappedf(ratio_max, 0.01)
	# --- pictures
	rep["images"] = _draw(world, nav, out_dir, uncovered)
	rep["qa_ms"] = Time.get_ticks_msec() - t0
	var f := FileAccess.open(out_dir.path_join("%s_qa.json" % W.map_id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rep, "  "))
	print("[wpqa] %s: %d nodes, %d edges, coverage %.2f%% of %d cells, %d edges failing now, %d nodes blocked, routes %d/%d (detour avg %.2f, max %.2f), %d orphans, %d ms" % [
		W.map_id, W.nodes.size(), W.edges.size(), float(rep.coverage_pct), cells.size(), bad_edges.size(), bad_nodes.size(), found, tried,
		float(rep.route_detour_avg), float(rep.route_detour_max), int(rep.orphans), int(rep.qa_ms)])
	return rep


static func _draw(world, nav, out_dir: String, uncovered: Array) -> Array:
	var W = Waypoints
	var levels: bool = nav.get("levels") != null
	var x0: float
	var z0: float
	var span_x: float
	var span_z: float
	var ppm: float
	if levels:
		x0 = float(world.map.layout.nav_x0)
		z0 = float(world.map.layout.nav_z0)
		span_x = float(nav.nx) * float(nav.cell)
		span_z = float(nav.nz) * float(nav.cell)
	else:
		x0 = -float(nav.half)
		z0 = -float(nav.half)
		span_x = float(nav.n) * float(nav.cell)
		span_z = span_x
	ppm = clampf(1400.0 / maxf(span_x, span_z), 1.5, 8.0)
	var w := int(span_x * ppm)
	var h := int(span_z * ppm)
	var out := []
	var nlv := int(nav.levels) if levels else 1
	for lv in nlv:
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		img.fill(Color(0.07, 0.07, 0.09))
		# the walk
		if levels:
			for i in nav.open_cells(lv):
				var c: Vector3 = nav.cell_pos(lv, i)
				_rect(img, (c.x - 0.5 - x0) * ppm, (c.z - 0.5 - z0) * ppm, ppm, ppm, Color(0.27, 0.27, 0.3))
		else:
			var n: int = nav.n
			for z in n:
				for x in n:
					if nav.walk[z * n + x] == 1:
						_rect(img, x * nav.cell * ppm, z * nav.cell * ppm, nav.cell * ppm, nav.cell * ppm, Color(0.24, 0.24, 0.27))
		for e in uncovered:
			if int(e[0]) != lv:
				continue
			var p: Vector3 = e[1]
			var cs: float = float(nav.cell)
			_rect(img, (p.x - cs * 0.5 - x0) * ppm, (p.z - cs * 0.5 - z0) * ppm, cs * ppm, cs * ppm, Color(0.85, 0.12, 0.1))
		# edges
		var ecol := {"walk": Color(0.85, 0.85, 0.85), "tight": Color(1.0, 0.55, 0.1), "door": Color(0.2, 0.9, 1.0),
			"stair": Color(1.0, 0.3, 1.0), "escalator": Color(1.0, 0.3, 1.0), "wade": Color(0.3, 0.5, 1.0)}
		for ed in W.edges:
			var a: Dictionary = W.nodes[int(ed.a)]
			var b: Dictionary = W.nodes[int(ed.b)]
			if int(a.lv) != lv and int(b.lv) != lv:
				continue
			_line(img, ((a.p as Vector3).x - x0) * ppm, ((a.p as Vector3).z - z0) * ppm, ((b.p as Vector3).x - x0) * ppm,
				((b.p as Vector3).z - z0) * ppm, ecol.get(str(ed.kind), Color.WHITE))
		# nodes
		for nd in W.nodes:
			if int(nd.lv) != lv:
				continue
			var p2: Vector3 = nd.p
			var col := Color(1.0, 0.85, 0.1)
			var r := 2.0
			match int(nd.pri):
				2:
					col = Color(0.3, 0.85, 0.3)
					r = 1.5
				3:
					col = Color(0.1, 0.45, 0.2)
					r = 1.0
			match str(nd.kind):
				"hide":
					col = Color(0.7, 0.35, 1.0)
					r = 2.5
				"snipe":
					col = Color(1.0, 0.2, 0.2)
					r = 2.5
				"cover":
					col = Color(1.0, 0.6, 0.8)
					r = 2.0
				"door":
					col = Color(0.2, 0.9, 1.0)
					r = 2.0
			if int(nd.comp) != W.main_comp:
				col = Color.BLACK
				r = 2.5
			_rect(img, (p2.x - x0) * ppm - r, (p2.z - z0) * ppm - r, r * 2.0 + 1.0, r * 2.0 + 1.0, col)
		var path := out_dir.path_join("%s_L%d.png" % [W.map_id, lv + 1])
		img.save_png(path)
		out.append(path)
	return out


static func _rect(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	var x1 := clampi(int(x), 0, img.get_width())
	var y1 := clampi(int(y), 0, img.get_height())
	var x2 := clampi(int(ceil(x + w)), 0, img.get_width())
	var y2 := clampi(int(ceil(y + h)), 0, img.get_height())
	if x2 > x1 and y2 > y1:
		img.fill_rect(Rect2i(x1, y1, x2 - x1, y2 - y1), c)


static func _line(img: Image, ax: float, ay: float, bx: float, by: float, c: Color) -> void:
	var n := int(maxf(absf(bx - ax), absf(by - ay))) + 1
	for i in n + 1:
		var t := float(i) / n
		var x := int(lerpf(ax, bx, t))
		var y := int(lerpf(ay, by, t))
		if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
			img.set_pixel(x, y, c)
