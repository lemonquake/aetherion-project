extends RefCounted
## (r21) `--navprobe=x,y,z;x,y,z[;...]` (with --navdebug_quit or not): once the bots' nav is ready, for each pair of
## points prints whether each is on the walk (clearance, what a standing body touches there), the path between them
## with every stretch's band and sweep check, and what straight rays from the first to the second hit (collider, layer,
## position). For finding what a stalled bot is up against.

static func run(world, nav) -> void:
	var pts := []
	for s in str(Game.arg("navprobe", "")).split(";", false):
		var v := s.split(",")
		if v.size() == 3:
			pts.append(Vector3(float(v[0]), float(v[1]), float(v[2])))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	if Game.arg("navgrid") != null and nav.get("levels") != null:
		# --navgrid=x0,z0,x1,z1,level: the walk grid there ('.' open, '#' closed, 'o' pocket), with what is under each
		# cell from 0.5 m over the level ('_' nothing within 1 m below)
		var g := str(Game.arg("navgrid")).split(",")
		var lv := int(g[4])
		var L = nav.layout
		var c0: Vector2i = L.nav_cell(Vector2(float(g[0]), float(g[1])))
		var c1: Vector2i = L.nav_cell(Vector2(float(g[2]), float(g[3])))
		print("[grid] level %d, x %s..%s (cols), z %s..%s (rows), cell %.2f" % [lv, g[0], g[2], g[1], g[3], float(nav.cell)])
		for z in range(c0.y, c1.y + 1):
			var row := ""
			for x in range(c0.x, c1.x + 1):
				var id: int = nav._ids[lv][z * int(nav.nx) + x]
				var ch := "#"
				if id >= 0:
					ch = "o" if nav._astar.is_point_disabled(id) else "."
				if ch == "#":
					var cp: Vector3 = nav.cell_pos(lv, z * int(nav.nx) + x)
					var rq := PhysicsRayQueryParameters3D.create(cp + Vector3.UP * 0.5, cp + Vector3.DOWN * 1.0, Defs.MOVE_MASK)
					if space.intersect_ray(rq).is_empty():
						ch = "_"
				row += ch
			print("[grid] z %6.2f %s" % [float(L.nav_cell_centre(0, z).y), row])
	for p in pts:
		_point(world, nav, space, p)
	for i in range(0, pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var path: Array = nav.find_path(a, b)
		print("[probe] path %s -> %s: %d points" % [str(a), str(b), path.size()])
		var prev := a
		for q in path:
			var qq: Vector3 = q
			var band: bool = nav._band_clear(prev, qq) if nav.has_method("_band_clear") else true
			var sweep: bool = nav._sweep_clear(prev, qq) if nav.has_method("_sweep_clear") else true
			print("[probe]   %s band %s sweep %s" % [str(qq.snapped(Vector3.ONE * 0.1)), str(band), str(sweep)])
			prev = qq
		for h in [0.3, 0.6, 1.0, 1.5]:
			var rq := PhysicsRayQueryParameters3D.create(a + Vector3.UP * h, b + Vector3.UP * h, Defs.MOVE_MASK)
			var r := space.intersect_ray(rq)
			print("[probe]   ray at %.1f m: %s" % [h, _hit(r)])


static func _point(world, nav, space: PhysicsDirectSpaceState3D, p: Vector3) -> void:
	var sh := CylinderShape3D.new()
	sh.radius = 0.32
	sh.height = 1.35
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = Defs.MOVE_MASK
	q.transform = Transform3D(Basis(), p + Vector3.UP * 1.075)
	var hits := space.intersect_shape(q, 6)
	var names := []
	for h in hits:
		names.append(_hit(h))
	print("[probe] %s walkable %s clearance %.2f; a body there touches %s" % [str(p), str(nav.walkable_at(p)),
		nav.clearance_at(p) if nav.has_method("clearance_at") else -1.0, str(names)])


static func _hit(r: Dictionary) -> String:
	if r.is_empty():
		return "nothing"
	var c = r.get("collider")
	var nm := str(c.name) if c is Node else str(c)
	var path := str(c.get_path()) if c is Node and c.is_inside_tree() else ""
	var pos := str((r.position as Vector3).snapped(Vector3.ONE * 0.01)) if r.has("position") else ""
	return "%s %s layer %d at %s" % [nm, path, int(c.collision_layer) if c is CollisionObject3D else -1, pos]
