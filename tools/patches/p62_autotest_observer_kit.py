"""Loot play-through: how another player's fitted attachments look (third person), and their laser dot.
Also frees shutter bodies on teardown.

    python -I tools/patches/p62_autotest_observer_kit.py
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


a = Patch('game/src/debug/autotest.gd')
a.rep('''	await _loot_lineup()
	await _attachment_views()
	if _lamp:
		_lamp.queue_free()''', '''	await _loot_lineup()
	await _attachment_views()
	await _observer_kit()
	if _lamp:
		_lamp.queue_free()''')
a.rep('''func _loot_lineup() -> void:''', '''func _observer_kit() -> void:
	## Another player's rifle with a scope, suppressor, grip, laser and extended magazine, seen by us: the fitted
	## attachments are drawn on their gun (from the replicated mask) and their laser puts a dot on what it points at.
	var target = null
	for o in world.characters.values():
		if o != ch and o.mode == Motor.GROUND and world.bots.has(o.eid):
			target = o
			break
	if target == null:
		_check("observer_attachments", false, "no bot on the ground")
		return
	var brain = world.bots.get(target.eid)
	world.bots.erase(target.eid)
	world._queues[target.eid] = []
	target.last_cmd = {}
	var kit := ["scope_6x", "suppressor_rifle", "grip_vertical", "laser_sight", "mag_ext_rifle"]
	var w := WeaponState.new_instance("rifle_556", null, 1.0)
	w.att = kit.duplicate()
	target.wpn.slots[1] = w
	target.wpn.want = 1
	target.wpn.cur = 1
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, ctl.yaw, 0)).z
	var spot: Vector3 = ch.global_position
	target.global_position = spot + fwd * 3.0 + Vector3.UP * 0.1
	target.yaw = ctl.yaw + PI * 0.75
	target.pitch = -0.1
	await _wait(1.0)
	var vis = target.get("visual")
	var drawn := 0
	var laser := false
	if vis:
		drawn = vis.att_root.get_child_count()
		laser = vis.laser_dot != null and vis.laser_dot.visible
	var cam := Camera3D.new()
	world.add_child(cam)
	var side: Vector3 = fwd.cross(Vector3.UP).normalized()
	cam.look_at_from_position(spot + Vector3.UP * 1.5 + side * 1.2, target.global_position + Vector3.UP * 1.2)
	cam.current = true
	await _wait(0.6)
	await _shot("observer_rifle_kit")
	cam.current = false
	ctl.cam.current = true
	cam.queue_free()
	_check("observer_attachments", drawn == kit.size() and laser and target.weapon_att == Attach.bitmask(w),
		"%d of %d attachments drawn on their gun, laser dot %s, replicated mask %d" % [drawn, kit.size(), "visible" if laser else "not visible", target.weapon_att])
	if brain:
		world.bots[target.eid] = brain


func _loot_lineup() -> void:''')
a.save()

d = Patch('game/src/world/dynamics.gd')
d.rep('''	for w in windows:
		if w.has("body") and (w.body as RID).is_valid():
			PhysicsServer3D.free_rid(w.body)
			PhysicsServer3D.free_rid(w.shape)
			w.body = RID()''', '''	for w in windows:
		if w.has("body") and (w.body as RID).is_valid():
			PhysicsServer3D.free_rid(w.body)
			PhysicsServer3D.free_rid(w.shape)
			w.body = RID()
		if w.get("door") != null and w.door.has_method("free_body"):
			w.door.free_body()''')
d.save()
print('ok')
