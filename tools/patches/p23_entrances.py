"""Patch: entrance steps pass in the map build; reserve_rect can leave occupied cells alone; bots plan from the foot
of the steps."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/world/entrances.gd', [
    ('''	if L.is_water(p.x, p.y) or not _walks.is_empty():''', '''	if L.is_water(p.x, p.y):'''),
    ('''				var bx := Basis(side, dir.cross(side).normalized(), dir)
				mb.sink.box(Transform3D(Basis(side, -dir.cross(side).normalized(), dir) if bx.determinant() < 0.0 else bx, mid),
					Vector3(0.06, 0.12, len), "timber", {"dirt": 0.9, "collide": false, "layer": "ext"})''',
     '''				mb.sink.box(Transform3D(Basis(side, dir.cross(side).normalized(), dir), mid), Vector3(0.06, 0.12, len), "timber",
					{"dirt": 0.9, "collide": false, "layer": "ext"})'''),
])
patch('src/world/layout.gd', [
    ('''func reserve_rect(center: Vector2, half: Vector2, ang: float, value: int, margin: float = 0.0) -> void:''',
     '''func reserve_rect(center: Vector2, half: Vector2, ang: float, value: int, margin: float = 0.0, only_free: bool = false) -> void:'''),
    ('''			if absf(lp.x) <= half.x + margin and absf(lp.y) <= half.y + margin:
				_reserved[iz * _n + ix] = value''', '''			if absf(lp.x) <= half.x + margin and absf(lp.y) <= half.y + margin:
				if not only_free or _reserved[iz * _n + ix] == 0:
					_reserved[iz * _n + ix] = value'''),
])
patch('src/world/map_builder.gd', [
    ('''const PracticalLights := preload("res://src/world/practical_lights.gd")
''', '''const PracticalLights := preload("res://src/world/practical_lights.gd")
const Entrances := preload("res://src/world/entrances.gd")
'''),
    ('''	if opts.get("dress", true):
		StreetDress.new(self).build()''', '''	var ent := Entrances.new(self)
	ent.build()
	stats.entrances = ent.stats
	if opts.get("dress", true):
		StreetDress.new(self).build()'''),
])
patch('src/ai/bot_brain.gd', [(
    '''	plan = [{"p": centre + out_dir * 1.4, "nav": true}, {"p": inside, "nav": false, "door": int(door.id)}]''',
    '''	var foot_of_steps := float(door.get("steps_out", 0.0))
	plan = [{"p": centre + out_dir * (1.2 + foot_of_steps), "nav": true}, {"p": inside, "nav": false, "door": int(door.id)}]''')])
