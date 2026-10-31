"""r11: Lawless Sub plan and layout for three teams, the spawn yards and Lawless Mall.

- plan: spawn_centres_3 (flats parking NW, East Yard, South Yard), the East Yard (the east Phase 1 block south of
  Ilang-Ilang St, houses removed) and the South Yard (the east end of the Old Barangay's south row) as paved yards,
  Lawless Mall on the Phase 2 block south-east of the intersection (its west and boulevard walls opened to it).
- sub_layout.gd: spawns3 / spawn_yaw3 / dm_centre_for(n); in_spawn_zone covers both sets.
    python -I tools/patches/r11_layout.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch, ROOT

PLAN = os.path.join(ROOT, 'game', 'data', 'maps', 'lawless_sub.json')
raw = open(PLAN, 'rb').read().decode('utf-8')
crlf = '\r\n' in raw
d = json.loads(raw)
if 'spawn_centres_3' not in d:
    d['spawn_centres_3'] = [[-119, -144], [190, -40], [-72, 196]]
    # East Yard: the Phase 1 block x 176.5..206, z -63.5..-13 (front W) loses its houses.
    d['rows'] = [r for r in d['rows'] if not (r.get('district') == 'Phase 1' and r['x'] == [176.5, 206] and r['z'] == [-63.5, -13])]
    # Phase 2 block x -5..23.5, z 13..53.5 becomes the mall.
    d['rows'] = [r for r in d['rows'] if not (r.get('district') == 'Phase 2' and r['x'] == [-5, 23.5] and r['z'] == [13, 53.5])]
    # South Yard: the Old Barangay south row keeps its west end.
    for r in d['rows']:
        if r.get('district') == 'Old Barangay' and r['x'] == [-143.5, -32] and r['z'] == [174.5, 212]:
            r['x'] = [-143.5, -106]
    d['parking'].append({"name": "East Yard", "rect": [177, -63, 206, -14], "mat": "concrete_floor2", "stalls": "none", "yard": True})
    d['parking'].append({"name": "South Yard", "rect": [-102, 176, -36, 214], "mat": "concrete_floor2", "stalls": "none", "yard": True})
    d['lots'].append({"kind": "mall", "name": "Lawless Mall", "c": [9.5, 33.5], "size": [26, 38], "front": "W", "floors": 2})
    for w in d['walls']:
        if w['name'] == 'West wall south':
            w['gaps'].append([12, 58, 'open'])
        if w['name'] == 'Boulevard wall south':
            w['gaps'].append([-6, 24.5, 'open'])
    d['landmarks'].append({"name": "Lawless Mall", "pos": [9.5, 33.5]})
    d['landmarks'].append({"name": "East Yard", "pos": [191, -38]})
    d['landmarks'].append({"name": "South Yard", "pos": [-69, 195]})
    d['note'] = d['note'] + ' r11: spawn_centres_3 are the three-team spawns (flats parking, East Yard, South Yard).'
    out = json.dumps(d, indent=1)
    if crlf:
        out = out.replace('\n', '\r\n')
    open(PLAN, 'wb').write(out.encode('utf-8'))
    print('plan updated')

p = Patch('game/src/world/maps/lawless_sub/sub_layout.gd')
p.rep('''var spawn_centres: Array = []
''', '''var spawn_centres: Array = []
var spawns3: Array = [[], [], []]  # r11: three-team spawns (plan spawn_centres_3)
var spawn_yaw3: Array = [0.0, 0.0, 0.0]
var spawn_centres3: Array = []
''')
p.rep('''	for c in plan.get("spawn_centres", []):
		spawn_centres.append(_v2(c))
''', '''	for c in plan.get("spawn_centres", []):
		spawn_centres.append(_v2(c))
	for c in plan.get("spawn_centres_3", []):
		spawn_centres3.append(_v2(c))
''')
p.rep('''	spawns = [[], []]
	for team in spawn_centres.size():
		var c: Vector2 = spawn_centres[team]''',
      '''	spawns = [[], []]
	_pick_set(spawn_centres, spawns, spawn_yaw, dm_centre)
	spawns3 = [[], [], []]
	_pick_set(spawn_centres3, spawns3, spawn_yaw3, dm_centre_for(3))


func dm_centre_for(n_teams: int) -> Vector2:
	## The middle the teams face and the first circle centres on: the plan's dm_centre for two teams, the middle of
	## the three spawns for three.
	if n_teams == 3 and spawn_centres3.size() == 3:
		return (spawn_centres3[0] + spawn_centres3[1] + spawn_centres3[2]) / 3.0
	return dm_centre


func _pick_set(centres: Array, out_spawns: Array, out_yaw: Array, middle: Vector2) -> void:
	for team in centres.size():
		var c: Vector2 = centres[team]''')
p.rep('''			out.append(Vector3(p2.x, surface_y(p2), p2.y))
		spawns[team] = out
		var to := dm_centre - c
		spawn_yaw[team] = atan2(-to.x, -to.y)''',
      '''			out.append(Vector3(p2.x, surface_y(p2), p2.y))
		out_spawns[team] = out
		var to := middle - c
		out_yaw[team] = atan2(-to.x, -to.y)''')
p.rep('''func in_spawn_zone(p: Vector2, margin: float = 0.0) -> bool:
	for c in spawn_centres:''',
      '''func in_spawn_zone(p: Vector2, margin: float = 0.0) -> bool:
	for c in spawn_centres + spawn_centres3:''')
p.save()
print('r11 layout patch done')
