"""Test changes after the independent review: Tab on a balikbayan box with contents (shown entries must match),
E taking ammo and a gun off the floor, the door push opening further and swinging on, flashlight on for captures,
the frag explosion photographed from where the thrower stands."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

t = Patch('game/src/debug/autotest_fixes.gd')
# Flashlight on after landing: interiors are dark by design and the captures should show what was tested.
t.rep('''	await t._deploy()
	if not is_instance_valid(t.ch):
		return
	for step in [''', '''	await t._deploy()
	if not is_instance_valid(t.ch):
		return
	if not t.ch.light.on:
		await t._tap("flashlight")
	for step in [["use", _use_takes_items], ''')
# Tab: a balikbayan box that has something in it; the SmarTab must list exactly its contents.
t.rep('''	var b: Dictionary = t._nearest_box(true)
	if b.is_empty():
		t._check("tab_opens_box", false, "no loot box")
		return''', '''	var b := {}
	var bd := INF
	for lb in world.map.dyn.loot_boxes:
		var cc: Dictionary = world.map.dyn.containers[int(lb.cid)]
		if lb.open or str(lb.name) != "lootbox_balikbayan" or (cc.entries as Array).is_empty() or int(cc.bid) < 0:
			continue
		var dd := (cc.pos as Vector3).distance_to(t.ch.global_position)
		if dd < bd:
			bd = dd
			b = lb
	if b.is_empty():
		t._check("tab_opens_box", false, "no unopened balikbayan box with something in it")
		return''')
t.rep('''	var shown_id := int(world.hud.smartab.container.get("id", -1)) if ok else -1''', '''	var shown_id := int(world.hud.smartab.container.get("id", -1)) if ok else -1
	var shown_n := (world.hud.smartab.container.get("entries", []) as Array).size() if ok else 0
	var want_n := (world.map.dyn.containers[int(b.cid)].entries as Array).size()''')
t.rep('''	t._check("tab_opens_box", ok and page == "Items" and shown_box and lid_open,''', '''	t._check("tab_opens_box", ok and page == "Items" and shown_box and lid_open and (shown_id != int(b.cid) or shown_n == want_n) and shown_n > 0,''')
t.rep('''"beside %s: container shown %s (id %d, a loot box %s, walked to %d), page %s, its lid opened %s" % [str(b.name), str(ok), shown_id, str(shown_box), int(b.cid), page, str(lid_open)])''',
      '''"beside %s: container shown %s (id %d, a loot box %s, walked to %d), page %s, its lid opened %s, %d entries listed (the box holds %d)" % [str(b.name), str(ok), shown_id, str(shown_box), int(b.cid), page, str(lid_open), shown_n, want_n])''')
# Door push: from the side that opens it further; it must keep swinging after the shove.
t.rep('''	var spot2: Vector3 = leaf_mid - n * 1.2''', '''	var spot2: Vector3 = leaf_mid + n * 1.2''')
t.rep('''	var before: float = dn.angle
	t._act_press("sprint")
	t._act_press("move_forward")
	await t._wait(0.6)
	t._act_release("move_forward")
	t._act_release("sprint")
	var swung := absf(dn.angle - before)
	var still_moving: bool = dn.moving and dn.free''', '''	var before: float = dn.angle
	t._act_press("sprint")
	t._act_press("move_forward")
	await t._until(func(): return absf(dn.angle - before) > 0.15, 1.5)
	t._act_release("move_forward")
	t._act_release("sprint")
	# Step back off the leaf: whatever it does now is its own swing.
	t._teleport(t.ch.global_position + n * 1.0, t.ctl.yaw)
	var a1: float = dn.angle
	await t._wait(0.12)
	var swung := absf(dn.angle - before)
	var still_moving: bool = absf(dn.angle - a1) > 0.01''')
t.rep('''	t._check("door_push_swings", swung > 0.3 or absf(dn.angle) < 0.01,''', '''	t._check("door_push_swings", swung > 0.3 and still_moving,''')
# Grenade: photograph the blast from the thrower's spot.
t.rep('''	await t._wait(0.1)
	await t._shot("frag_explosion")
	var hp1: float = mate.health.health''', '''	var hp1: float = mate.health.health''')
t.rep('''		if t.ch.global_position.distance_to(g.p) < 14.0:
			t.ch.global_position = (g.p as Vector3) + back * 16.0 + Vector3.UP * 0.5''', '''		if t.ch.global_position.distance_to(g.p) < 14.0:
			t.ch.global_position = (g.p as Vector3) + back * 16.0 + Vector3.UP * 0.5
		t._look_at(g.p)
		if float(g.t) < 0.05 and not shot_taken:
			shot_taken = true
			_shoot_later("frag_explosion", 0.06)''')
t.rep('''	var g_pos := Vector3.ZERO''', '''	var g_pos := Vector3.ZERO
	var shot_taken := false''')
t.s += '''

func _shoot_later(name: String, s: float) -> void:
	await t._wait(s)
	await t._shot(name)


# ------------------------------------------------------------------ E takes weapons, ammunition, items

func _use_takes_items() -> void:
	## Items lying in front of the player: E takes a box of rounds, then a gun (T does not pick them up).
	t.ch.inv.bag.clear()
	var got := []
	for e in [{"id": "ammo_556", "n": 30}, {"id": "rifle_scar", "n": 1, "w": WS.new_instance("rifle_scar")}]:
		var id: int = t._spawn_in_front(e, 1.2)
		await t._wait(0.3)
		var it: Dictionary = world.map.dyn.items.get(id, {})
		if it.is_empty():
			got.append("%s: not spawned" % e.id)
			continue
		t._look_at((it.xf as Transform3D).origin + Vector3.UP * 0.03)
		await t._wait(0.2)
		await t._tap("grab")
		await t._wait(0.2)
		var after_t := world.map.dyn.items.has(id)
		await t._tap("interact")
		var taken: bool = await t._until(func(): return not world.map.dyn.items.has(id), 1.0)
		got.append("%s: T left it %s, E took it %s" % [str(e.id), str(after_t), str(taken)])
	var rounds: int = t.ch.inv.count("ammo_556")
	var has_scar := false
	for s in [1, 2, 3]:
		if t.ch.wpn.slots[s] != null and str(t.ch.wpn.slots[s].id) == "rifle_scar":
			has_scar = true
	t._check("use_takes_items", rounds >= 30 and has_scar and not ("T left it false" in str(got)),
		"%s; carrying %d 5.56 rounds, SCAR-L in a slot %s" % [str(got), rounds, str(has_scar)])
'''
t.save()
