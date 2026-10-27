"""Loot run perf (2026-10-26): a "loot" feature toggle in --autotest=perf --attrib (ground items and loot boxes hidden,
same view) so the cost of the loot can be measured by subtraction; loot boxes cast no shadows (small, indoors,
each shadowed lamp redrew them); ground items draw to 12 m (22 m for guns and packs).

    python -I tools/patches/p64_loot_perf_toggle.py
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


d = Patch('game/src/world/dynamics.gd')
d.rep('''		var reach := (28.0 if big else 16.0) * clampf(float(Settings.get_value("graphics", "view_distance")), 0.6, 1.3)''',
      '''		var reach := (22.0 if big else 12.0) * clampf(float(Settings.get_value("graphics", "view_distance")), 0.6, 1.3)''')
d.rep('''	var s: Dictionary = models.spec(name)
	var kind := str(s.get("kind", ""))
	var size: float = (md.aabb as AABB).get_longest_axis_size()''', '''	var s: Dictionary = models.spec(name)
	var kind := str(s.get("kind", ""))
	var size: float = (md.aabb as AABB).get_longest_axis_size()
	var no_shadow := kind == "lootbox"''')
d.rep('''	var pol := {"cell": cell, "range": want + cell * 0.7, "shadow": shadow}''', '''	var pol := {"cell": cell, "range": want + cell * 0.7, "shadow": shadow and not no_shadow}''')
d.rep('''func opened_boxes() -> PackedInt32Array:''', '''func set_loot_visible(v: bool) -> void:
	## Shows or hides every ground item and loot box (performance attribution only).
	for it in items.values():
		if it.get("inst", RID()).is_valid():
			RenderingServer.instance_set_visible(it.inst, v)
	for key in _mm:
		if "|lootbox_" in str(key) and _mm[key].node:
			(_mm[key].node as Node3D).visible = v
	for b in loot_boxes:
		if b.get("inst_open", RID()).is_valid():
			RenderingServer.instance_set_visible(b.inst_open, v)


func opened_boxes() -> PackedInt32Array:''')
d.save()

a = Patch('game/src/debug/autotest.gd')
a.rep('''		["scale_0.77", func(): vp.scaling_3d_scale = 0.77, func(): vp.scaling_3d_scale = 1.0],
	]''', '''		["scale_0.77", func(): vp.scaling_3d_scale = 0.77, func(): vp.scaling_3d_scale = 1.0],
		["loot", func(): world.map.dyn.set_loot_visible(false), func(): world.map.dyn.set_loot_visible(true)],
	]''')
a.save()
print('ok')
