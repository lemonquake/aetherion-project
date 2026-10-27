"""Patch: record alley segments in districts; colliders for static props; street dressing hook in the map builder."""
G = 'A:/Python/aetherion-project/game/'


def sub(path, old, new, count=1):
    s = open(G + path, encoding='utf-8').read()
    if old not in s:
        raise SystemExit(f'pattern not found in {path}: {old[:70]!r}')
    s = s.replace(old, new, count)
    open(G + path, 'w', encoding='utf-8').write(s)


# Static props get collision while the sink is still open.
sub('src/world/dynamics.gd', '''func add_static_prop(name: String, xf: Transform3D) -> void:
	static_props.append([name, xf])''', '''func add_static_prop(name: String, xf: Transform3D) -> void:
	static_props.append([name, xf])
	var s: Dictionary = models.spec(name)
	if s.get("no_collide", false):
		return
	var sh := _prop_shape(name)
	if s.has("trunk"):
		var tr := float(s.trunk)
		var hgt := minf((sh.size as Vector3).y * 0.55, 4.5)
		map.sink.col_box(xf * Transform3D(Basis(), Vector3(0, hgt * 0.5, 0)), Vector3(tr, hgt, tr), "wood")
	else:
		var md: Dictionary = models.get_model(name)
		var off: Vector3 = md.get("offset", Vector3.ZERO)
		map.sink.col_box(xf * Transform3D(Basis(), sh.center), sh.size, str(s.get("mat", "default")))''')

# MapBuilder: alleys list and street dressing pass.
sub('src/world/map_builder.gd', '''var buildings: Array = []''', '''var buildings: Array = []
var alleys: Array = []  # [{a: Vector2, b: Vector2, w: float, kind}] walkable lanes between houses''')
sub('src/world/map_builder.gd', '''const Lighting := preload("res://src/world/lighting.gd")''', '''const Lighting := preload("res://src/world/lighting.gd")
const StreetDress := preload("res://src/world/street_dress.gd")''')
sub('src/world/map_builder.gd', '''	stats.towns_ms = Time.get_ticks_msec() - t0''', '''	if opts.get("dress", true):
		StreetDress.new(self).build()
	stats.towns_ms = Time.get_ticks_msec() - t0''')

# Districts record their lanes.
sub('src/world/districts.gd', '''	for i in us.size() - 1:
		for j in vs.size() - 1:''', '''	for i in us.size():
		var a: Vector2 = c + xa * float(us[i]) + za * (-half.y)
		var b: Vector2 = c + xa * float(us[i]) + za * half.y
		mb.alleys.append({"a": a, "b": b, "w": float(aw_u[i]), "kind": "alley"})
	for j in vs.size():
		var a2: Vector2 = c + xa * (-half.x) + za * float(vs[j])
		var b2: Vector2 = c + xa * half.x + za * float(vs[j])
		mb.alleys.append({"a": a2, "b": b2, "w": float(aw_v[j]), "kind": "alley"})
	for i in us.size() - 1:
		for j in vs.size() - 1:''')
sub('src/world/districts.gd', '''		_boardwalk(walk_pts, 1.3, deck - 0.05)''', '''		_boardwalk(walk_pts, 1.3, deck - 0.05)
		for k in range(0, walk_pts.size() - 1, 3):
			mb.alleys.append({"a": walk_pts[k], "b": walk_pts[mini(k + 3, walk_pts.size() - 1)], "w": 1.3, "kind": "walk", "y": deck})''')
sub('src/world/districts.gd', '''	_boardwalk(walk_pts, 1.4, deck - 0.05)''', '''	_boardwalk(walk_pts, 1.4, deck - 0.05)
	for k in range(0, walk_pts.size() - 1, 3):
		mb.alleys.append({"a": walk_pts[k], "b": walk_pts[mini(k + 3, walk_pts.size() - 1)], "w": 1.4, "kind": "walk", "y": deck})''')
sub('src/world/districts.gd', '''		v += depth * 2.0 + rng.randf_range(4.0, 5.0)  # a street between double rows''', '''		var sv := v + depth * 2.0 + 2.2
		mb.alleys.append({"a": c + xa * (-half.x) + za * sv, "b": c + xa * half.x + za * sv, "w": 4.0, "kind": "street"})
		v += depth * 2.0 + rng.randf_range(4.0, 5.0)  # a street between double rows''')
print('ok')
