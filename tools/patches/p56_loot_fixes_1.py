"""Loot run fixes after loot1 captures (2026-10-26): clear red-dot / holo glass and a closed red-dot tube; lineup and
attachment captures at an open spot under a work light; floor-rest failures name their loot table.

    python -I tools/patches/p56_loot_fixes_1.py
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


b = Patch('tools/blender/make_loot_models.py')
b.rep("""        'lens_red': dict(color=(0.5, 0.05, 0.04), rough=0.1, alpha=0.6),""",
      """        'lens_red': dict(color=(0.5, 0.05, 0.04), rough=0.1, alpha=0.6),
        'lens_clear': dict(color=(0.55, 0.7, 0.85), rough=0.05, alpha=0.1),""")
b.rep("""    p = [(0.0145, 0), (0.0175, 0), (0.0175, L), (0.0145, L)]
    parts = [lathe('tube', p, M('alu'), loc=(0, -L / 2, z), uv='box')]
    parts.append(cyl('lens', 0.0145, 0.0015, (0, L / 2 - 0.004, z), M('lens_red')))""",
      """    p = [(0.0145, 0), (0.0175, 0), (0.0175, L), (0.0145, L), (0.0145, 0.0001)]
    parts = [lathe('tube', p, M('alu'), loc=(0, -L / 2, z), uv='box')]
    parts.append(cyl('lens', 0.0145, 0.0015, (0, L / 2 - 0.004, z), M('lens_clear')))""")
b.rep("""    parts.append(cube('window_f', (0.034, 0.002, 0.03), (0, 0.035, z), M('glass')))
    parts.append(cube('window_r', (0.034, 0.002, 0.03), (0, -0.026, z), M('glass')))""",
      """    parts.append(cube('window_f', (0.034, 0.002, 0.03), (0, 0.035, z), M('lens_clear')))""")
b.save()

a = Patch('game/src/debug/autotest.gd')
a.rep('''	_loot_rest()
	await _loot_box_use()
	await _loot_pickup()
	await _attachment_views()
	await _loot_lineup()''', '''	_loot_rest()
	await _loot_box_use()
	await _loot_pickup()
	await _loot_lineup()
	await _attachment_views()
	if _lamp:
		_lamp.queue_free()''')
a.rep('''		if gap > -0.005 and gap < 0.05:
			ok += 1
		elif worst.size() < 6:
			worst.append("%s %.2f m at %s" % [str(dyn.items[id].entry.id), gap, str(o.snapped(Vector3.ONE * 0.1))])''',
      '''		if gap > -0.005 and gap < 0.05:
			ok += 1
		elif worst.size() < 12:
			var table := "?"
			for sp in dyn.loot_spots:
				if Vector2((sp.pos as Vector3).x - o.x, (sp.pos as Vector3).z - o.z).length() < 0.3:
					table = str(sp.table)
			worst.append("%s %.2f m at %s (%s)" % [str(dyn.items[id].entry.id), gap, str(o.snapped(Vector3.ONE * 0.1)), table])''')
a.rep('''func _loot_lineup() -> void:
	## One of every droppable thing laid out on the ground, captured from above (a work light for the picture).
	var ids := _droppable_ids()
	var p0: Vector3 = ch.global_position''', '''var _lamp: OmniLight3D = null


func _open_patch(near: Vector3) -> Vector3:
	## Open ground with sky above over a 7 x 9 m patch near a point (for laying things out and photographing them).
	var space = world.get_world_3d().direct_space_state
	var L = world.map.layout
	for ring in 60:
		for k in 12:
			var a := k * TAU / 12.0
			var c := Vector2(near.x, near.z) + Vector2(cos(a), sin(a)) * ring * 2.0
			var gy: float = L.ground_height(c.x, c.y)
			var clear := true
			for gx in range(-3, 4):
				for gz in range(-4, 5):
					var p := c + Vector2(gx, gz)
					var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, gy + 30.0, p.y), Vector3(p.x, gy - 5.0, p.y)))
					if hit.is_empty() or absf(hit.position.y - gy) > 0.25 or L.is_water(p.x, p.y):
						clear = false
						break
				if not clear:
					break
			if clear:
				return Vector3(c.x, gy, c.y)
	return near


func _loot_lineup() -> void:
	## One of every droppable thing laid out on open ground, captured from above under a work light (an inspection
	## light for the picture only; it is removed afterwards).
	var ids := _droppable_ids()
	var spot := _open_patch(ch.global_position)
	_teleport(spot + Vector3.UP * 0.1, 0.0)
	await _wait(0.5)
	var p0: Vector3 = ch.global_position''')
a.rep('''	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 2.5
	lamp.shadow_enabled = true
	world.add_child(lamp)
	lamp.global_position = p0 + fwd * 3.5 + Vector3.UP * 3.0''', '''	_lamp = OmniLight3D.new()
	_lamp.omni_range = 10.0
	_lamp.light_energy = 2.5
	_lamp.shadow_enabled = true
	world.add_child(_lamp)
	_lamp.global_position = p0 + fwd * 3.0 + Vector3.UP * 3.0''')
a.rep('''	cam.current = false
	ctl.cam.current = true
	cam.queue_free()
	lamp.queue_free()
	_check("loot_lineup", spawned >= ids.size() * 0.9, "%d of %d ids laid out" % [spawned, ids.size()])''', '''	cam.current = false
	ctl.cam.current = true
	cam.queue_free()
	# The attachment captures follow here, at the edge of the light, facing away from the laid-out loot.
	_lamp.global_position = p0 + Vector3.UP * 2.6 - fwd * 1.5
	ctl.yaw += PI
	_check("loot_lineup", spawned >= ids.size() * 0.95, "%d of %d ids laid out" % [spawned, ids.size()])''')
a.rep('''		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 2.0, Defs.PHYS_WORLD | Defs.PHYS_PROP))''',
      '''		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, p + Vector3.DOWN * 1.5, Defs.PHYS_WORLD | Defs.PHYS_PROP))''')
a.rep('''	## First-person captures of fitted attachments; aiming lines a red dot up with the bullets; the scope view.
	var space = world.get_world_3d().direct_space_state
	# Outdoors under a lamp if the tour found one, else where we are.
	if not ch.light.on:
		await _tap("flashlight")''', '''	## First-person captures of fitted attachments; aiming lines a red dot up with the bullets; the scope view.
	if ch.light.on:
		await _tap("flashlight")''')
a.save()
print('ok')
