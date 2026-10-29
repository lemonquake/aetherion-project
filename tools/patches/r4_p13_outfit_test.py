"""r4: --autotest=r4 outfits check (a lineup of bots at noon; surfaces per character; variety)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/debug/autotest_r4.gd'
patch(f, '''	for step in [["pa", _pa_schedule], ["holes", _holes],''', '''	for step in [["outfits", _outfits], ["pa", _pa_schedule], ["holes", _holes],''')
patch(f, '''			world.map.lighting.forced_time = 450.0 if step[0] in ["holes", "chunks", "doors", "blast"] else -1.0''', '''			world.map.lighting.forced_time = 450.0 if step[0] in ["holes", "chunks", "doors", "blast", "outfits"] else -1.0''')
ADD = '''

# ------------------------------------------------------------------ outfits

func _outfits() -> void:
	const Outfit := preload("res://src/player/outfit.gd")
	var ch = t.ch
	var others: Array = world.characters.values().filter(func(c): return c != ch and c.visual != null)
	if others.is_empty():
		t._check("outfits", false, "no other characters")
		return
	# Stand somewhere open and line them up 4.5 m ahead, facing us.
	var spot: Vector3 = ch.global_position
	t._teleport(spot + Vector3.UP * 0.1, 0.0)
	await t._wait(0.3)
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, t.ctl.yaw, 0)).z
	var side := fwd.cross(Vector3.UP).normalized()
	var n := mini(others.size(), 7)
	var keys := {}
	var surf_max := 0
	var looks := 0
	for i in n:
		var o = others[i]
		var p := spot + fwd * 4.5 + side * (float(i) - (n - 1) * 0.5) * 1.0
		p.y = world.map.ground_height(p.x, p.z) + 0.05
		o.global_position = p
		o.velocity = Vector3.ZERO
		o.yaw = t.ctl.yaw + PI
		var look: Dictionary = Net.players.get(o.pid, {}).get("look", {})
		if not look.is_empty():
			looks += 1
			keys[Outfit.key(Outfit.normalized(look))] = true
		var surfaces := 0
		for mi in _meshes(o.visual):
			if mi.visible and mi.mesh:
				surfaces += mi.mesh.get_surface_count()
		surf_max = maxi(surf_max, surfaces)
	t._look_at(spot + fwd * 4.5 + Vector3.UP * 1.0)
	await t._wait(0.5)
	for i in n:
		others[i].global_position.y = world.map.ground_height(others[i].global_position.x, others[i].global_position.z) + 0.05
	await t._wait(0.2)
	t._shot("outfits_lineup")
	t._check("outfits_vary", keys.size() >= mini(n, 5), "%d of %d characters carry a look; %d different outfits among them" % [looks, n, keys.size()])
	t._check("outfits_draws", surf_max <= 3, "at most %d mesh surfaces per character (outfit, head, weapon); the hooded body alone had 8" % surf_max)


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
'''
b = open(f, 'rb').read()
crlf = b'\r\n' in b
s = b.decode('utf-8').rstrip('\r\n')
s += ADD.replace('\n', '\r\n') if crlf else ADD
open(f, 'wb').write(s.encode('utf-8'))
print('appended outfits test')
