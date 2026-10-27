"""Loot run perf fix (2026-10-26): the hidden open-lid box models were MultiMesh instances in every cell (a draw
call per cell, model and surface even when scaled to nothing); now an open box gets its own render instance only
when it is opened. Ground items draw to 16 m (28 m for guns and packs) instead of 24 / 36 m.

    python -I tools/patches/p63_loot_draw_calls.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'src', 'world', 'dynamics.gd')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''var loot_boxes: Array = []     # {cid, name, xf, open, interior, mm, mm_open}''',
    '''var loot_boxes: Array = []     # {cid, name, xf, open, interior, mm, inst_open (render RID once opened)}''')
rep('''func set_box_open(cid: int, open: bool) -> void:
	## Swaps the closed and open models of a loot box (both are MultiMesh instances; the hidden one is scaled to
	## nothing where it stands, so its cell keeps tight bounds).
	if cid < 0 or cid >= containers.size() or not containers[cid].has("box"):
		return
	var b: Dictionary = loot_boxes[int(containers[cid].box)]
	if bool(b.open) == open:
		return
	b.open = open
	_mm_set(b.get("mm", ["", -1]), b.xf, not open, str(b.name))
	_mm_set(b.get("mm_open", ["", -1]), b.xf, open, str(b.name) + "_open")''', '''func set_box_open(cid: int, open: bool) -> void:
	## Swaps a loot box's closed model (a MultiMesh instance, scaled to nothing where it stands so its cell keeps tight
	## bounds) for its open one: a render instance of its own, made the first time the box is opened (thousands of
	## boxes, few open; registering the open models in every cell would cost a draw call per cell even when hidden).
	if cid < 0 or cid >= containers.size() or not containers[cid].has("box"):
		return
	var b: Dictionary = loot_boxes[int(containers[cid].box)]
	if bool(b.open) == open:
		return
	b.open = open
	_mm_set(b.get("mm", ["", -1]), b.xf, not open, str(b.name))
	if DisplayServer.get_name() == "headless":
		return
	if open and not b.get("inst_open", RID()).is_valid():
		var md: Dictionary = models.get_model(str(b.name) + "_open")
		if md.is_empty():
			return
		var inst := RenderingServer.instance_create2((md.mesh as Mesh).get_rid(), root.get_world_3d().scenario)
		RenderingServer.instance_set_transform(inst, (b.xf as Transform3D) * Transform3D(Basis(), md.get("offset", Vector3.ZERO)))
		RenderingServer.instance_set_layer_mask(inst, Defs.RENDER_INTERIOR_PROPS if b.interior else Defs.RENDER_WORLD)
		RenderingServer.instance_geometry_set_cast_shadows_setting(inst, RenderingServer.SHADOW_CASTING_SETTING_OFF)
		var pol := _policy(str(b.name), models.get_model(str(b.name)), bool(b.interior))
		RenderingServer.instance_geometry_set_visibility_range(inst, 0.0, float(pol.range) - float(pol.cell) * 0.7, 0.0, 4.0,
			RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
		b.inst_open = inst
	elif not open and b.get("inst_open", RID()).is_valid():
		RenderingServer.free_rid(b.inst_open)
		b.inst_open = RID()''')
rep('''	for b in loot_boxes:
		b.mm = _instance(str(b.name), b.xf, bool(b.interior))
		b.mm_open = _instance(str(b.name) + "_open", b.xf, bool(b.interior))
		_mm_set(b.mm_open, b.xf, false, str(b.name) + "_open")''', '''	for b in loot_boxes:
		b.mm = _instance(str(b.name), b.xf, bool(b.interior))''')
rep('''		var reach := (36.0 if big else 24.0) * clampf(float(Settings.get_value("graphics", "view_distance")), 0.6, 1.3)''',
    '''		var reach := (28.0 if big else 16.0) * clampf(float(Settings.get_value("graphics", "view_distance")), 0.6, 1.3)''')
rep('''	for sh in _dormant_shapes.values():
		PhysicsServer3D.free_rid(sh)''', '''	for b in loot_boxes:
		if b.get("inst_open", RID()).is_valid():
			RenderingServer.free_rid(b.inst_open)
			b.inst_open = RID()
	for sh in _dormant_shapes.values():
		PhysicsServer3D.free_rid(sh)''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())

# The loot test checks the lid through the render instance now.
p2 = os.path.join(ROOT, 'game', 'src', 'debug', 'autotest.gd')
raw = open(p2, 'rb').read().decode()
crlf2 = '\r\n' in raw
s = raw.replace('\r\n', '\n')
rep('''	var shown: Dictionary = world.hud.smartab.container
	_check("loot_box_opens", ok and t.get("kind", "") == "container" and int(t.get("id", -1)) == int(b.cid),
		"%s: target %s %s, prompt '%s', lid open %s, SmarTab shows %d entries" % [str(b.name), str(t.get("kind", "-")), str(t.get("id", "")), prompt,
		str(b.open), (shown.get("entries", []) as Array).size()])''', '''	var shown: Dictionary = world.hud.smartab.container
	var lid_drawn: bool = b.get("inst_open", RID()).is_valid()
	_check("loot_box_opens", ok and lid_drawn and t.get("kind", "") == "container" and int(t.get("id", -1)) == int(b.cid),
		"%s: target %s %s, prompt '%s', lid open %s (open model drawn %s), SmarTab shows %d entries" % [str(b.name), str(t.get("kind", "-")),
		str(t.get("id", "")), prompt, str(b.open), str(lid_drawn), (shown.get("entries", []) as Array).size()])''')
open(p2, 'wb').write((s.replace('\n', '\r\n') if crlf2 else s).encode())
print('ok')
