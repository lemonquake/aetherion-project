extends RefCounted
## (r28) Deathmatch grenade pickups. At the start of every round the old ones are cleared off the floor (with any frag
## grenade left lying about) and a few single frag grenades are laid out (rules deathmatch.grenade_pickups.count, 4):
## no more than that are in play in a round, since Deathmatch kits carry none and floor loot and containers roll none
## (dynamics.gd).
##
## Where: the map's analysed bot spots (bot_nav.gd: hiding and cover places on the walk grid, so a bot or a player can
## walk there), and of those only a corner (walls on two sides within reach) or a place inside a building (an indoor
## acoustic zone, or a roof overhead with a wall beside it). In a corner the grenade is pushed into it. Each is checked
## against the real collision (a floor under it, no water), kept away from the teams' spawns and spread apart, the
## picks shuffled from the match seed and the round.

const BotNav := preload("res://src/ai/bot_nav.gd")
const ITEM := "frag_grenade"
const DIRS := 8
const WALL_R := 1.4       # a wall this close (from the spot, at knee height) counts as a side of the corner
const MASK := Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS


static func rule(key: String, default_value):
	return Defs.rule("deathmatch.grenade_pickups." + key, default_value)


static func clear(world) -> int:
	## Every frag grenade on the ground goes (the last round's pickups and any dropped since). Returns how many.
	var gone := []
	for id in world.map.dyn.items:
		if str(world.map.dyn.items[id].entry.get("id", "")) == ITEM:
			gone.append(id)
	for id in gone:
		world.map_item_remove(id)
	return gone.size()


static func place(world, rng: RandomNumberGenerator, spawn_info: Dictionary) -> Array:
	## Lays out this round's pickups; returns their positions.
	var want := int(rule("count", 4))
	if want <= 0:
		return []
	var cands := _candidates(world)
	if cands.is_empty():
		return []
	# Hiding places and cover first (the corners and recesses), the rest after; shuffled within each.
	var order := range(cands.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	order.sort_custom(func(a, b): return _rank(cands[a]) < _rank(cands[b]))
	var spawns := []
	for t in spawn_info:
		if spawn_info[t] is Dictionary:
			spawns.append_array(spawn_info[t].get("pts", []))
			if spawn_info[t].has("anchor"):
				spawns.append(spawn_info[t].anchor)
	var clear_m := float(rule("spawn_clear_m", 14.0))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var out := []
	var checked := {}
	for gap in [float(rule("min_gap_m", 18.0)), 8.0, 2.0]:
		for i in order:
			if out.size() >= want:
				break
			var p: Vector3 = cands[i].p
			if _near(p, spawns, clear_m) or _near(p, out, gap):
				continue
			if not checked.has(i):
				checked[i] = _check(world, space, p)
			var at = checked[i]
			if at == null or _near(at, out, gap):
				continue
			out.append(at)
		if out.size() >= want:
			break
	for p in out:
		world.map_item_spawn_server({"id": ITEM, "n": 1}, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
	return out


static func _rank(s: Dictionary) -> int:
	return {"hide": 0, "cover": 0}.get(str(s.get("kind", "")), 1)


static func _near(p: Vector3, pts: Array, r: float) -> bool:
	for q in pts:
		if (q as Vector3).distance_to(p) < r:
			return true
	return false


static func _candidates(world) -> Array:
	## The bot spots of this map: the analysis in memory when it is this map's, else the file shipped with the game (or
	## the one a first match on this build wrote), else the floor-loot places the builders laid down.
	var map_id := str(world.cfg.get("map", "kalinaw"))
	if BotNav.phase == "done" and BotNav.map_id == map_id and not BotNav.spots.is_empty():
		return BotNav.spots.filter(func(s): return str(s.get("src", "")) != "learned")
	for path in ["user://botnav/%s.json" % map_id, "res://data/botnav/%s.json" % map_id]:
		if not FileAccess.file_exists(path):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and d.get("spots") is Array and not (d.spots as Array).is_empty():
			return BotNav._spots_from(d.spots)
	var out := []
	for s in world.map.dyn.loot_spots:
		out.append({"p": s.pos, "kind": "cover"})
	return out


static func _check(world, space: PhysicsDirectSpaceState3D, p: Vector3):
	## Where the grenade lies for the spot p, or null when p is not a corner or indoors (or has no dry floor under it).
	var L = world.map.layout
	var floor_y = _floor(space, p)
	if floor_y == null and L != null and L.has_method("ground_height"):
		# A map whose walk is kept by storey (Hidden Forest: its spots sit at 0 m or 4 m) over uneven ground: the ground
		# under the spot, when it is at ground level.
		var gy := float(L.ground_height(p.x, p.z))
		if absf(gy - p.y) < 3.5:
			floor_y = _floor(space, Vector3(p.x, gy, p.z))
	if floor_y == null:
		return null
	var base := Vector3(p.x, float(floor_y), p.z)
	if world.water_height(base.x, base.z) > base.y - 0.05:
		return null
	if L != null and L.has_method("in_play_area") and not L.in_play_area(Vector2(base.x, base.z)):
		return null
	# The walls round it, at knee height: which of eight directions are closed within WALL_R, and how far.
	var knee := base + Vector3.UP * 0.45
	var shut := []
	var dist := []
	for k in DIRS:
		var a := TAU * k / DIRS
		var d := Vector3(cos(a), 0.0, sin(a))
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(knee, knee + d * WALL_R, Defs.PHYS_WORLD | Defs.PHYS_PROP))
		shut.append(not r.is_empty())
		dist.append(WALL_R if r.is_empty() else knee.distance_to(r.position))
	var corner := -1
	for k in DIRS:
		if shut[k] and shut[(k + 2) % DIRS]:   # two walls at right angles
			corner = k
			break
	var walls := shut.count(true)
	var indoor: bool = world.map.acoustics != null and world.map.acoustics.zone_at(base + Vector3.UP * 0.3) != 0
	var roofed := not space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3.UP * 1.2, base + Vector3.UP * 9.0, Defs.PHYS_WORLD)).is_empty()
	if corner < 0 and not indoor and not (roofed and walls >= 1):
		return null
	if corner < 0:
		return base + Vector3.UP * 0.01
	# Into the corner: along the line between its two walls, to a hand's width from them.
	var a1 := TAU * corner / DIRS
	var a2 := TAU * ((corner + 2) % DIRS) / DIRS
	var into := (Vector3(cos(a1), 0.0, sin(a1)) + Vector3(cos(a2), 0.0, sin(a2))).normalized()
	var room := minf(float(dist[corner]), float(dist[(corner + 2) % DIRS])) - 0.3
	var step := clampf(room * 1.2, 0.0, 0.8)
	if step > 0.05:
		var q := knee + into * step
		var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(knee, q + into * 0.15, MASK))
		var fy = _floor(space, Vector3(q.x, base.y, q.z))
		if ray.is_empty() and fy != null and absf(float(fy) - base.y) < 0.12:
			return Vector3(q.x, float(fy) + 0.01, q.z)
	return base + Vector3.UP * 0.01


static func _floor(space: PhysicsDirectSpaceState3D, p: Vector3):
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.9, Defs.PHYS_WORLD | Defs.PHYS_PROP))
	return null if r.is_empty() else float((r.position as Vector3).y)
