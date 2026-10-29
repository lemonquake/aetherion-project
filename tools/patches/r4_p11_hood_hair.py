"""r4: the hoodie's hood is its own piece (left off under headwear); a Hair slot (buzz cut, short, mohawk, bun)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

f = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'blender', 'make_gear.py')
patch(f, '''    # Hoodie: the original, hood and strings included.
    bm = extract(body, {'Hoodie black', 'Hoodie rib', 'Hood lining', 'Hoodie drawstring'})
    fl = bm.faces.layers.int.new('spec')
    for f in bm.faces:
        f[fl] = {'Hoodie black': 0, 'Hoodie rib': 1, 'Hood lining': 2, 'Hoodie drawstring': 3}[names[f.material_index]]
    fit_bmesh(bm, arm, body, limb=1.0, torso=1.0, offset=0.003, torso_y=torso_y)
    face_spec = [f[fl] for f in bm.faces]
    ob = make_object('jacket_hoodie', bm, arm, body, [(COTTON, 0.95, (1, 1, 1), 1.0), (KNIT, 0.95, (1, 1, 1), 1.0),
                                                      (COTTON, 0.95, (0.35, 0.35, 0.35), 0.0), (COTTON, 0.8, (0.85, 0.85, 0.82), 0.0)], face_spec=face_spec, uv_scale=6.0)
    bm.free()
    decimate(ob, 0.45)''', '''    # Hoodie: the original, strings included; the hood is a piece of its own (left off under a helmet or cap).
    for part, keep_hood in (('jacket_hoodie', False), ('jacket_hoodie_hood', True)):
        bm = extract(body, {'Hoodie black', 'Hoodie rib', 'Hood lining', 'Hoodie drawstring'},
                     lambda f, bm, kh=keep_hood: (f.calc_center_median().z > 1.53 or names[f.material_index] == 'Hood lining') == kh)
        fl = bm.faces.layers.int.new('spec')
        for f in bm.faces:
            f[fl] = {'Hoodie black': 0, 'Hoodie rib': 1, 'Hood lining': 2, 'Hoodie drawstring': 3}[names[f.material_index]]
        fit_bmesh(bm, arm, body, limb=1.0, torso=1.0, offset=0.003, torso_y=torso_y)
        face_spec = [f[fl] for f in bm.faces]
        ob = make_object(part, bm, arm, body, [(COTTON, 0.95, (1, 1, 1), 1.0), (KNIT, 0.95, (1, 1, 1), 1.0),
                                               (COTTON, 0.95, (0.35, 0.35, 0.35), 0.0), (COTTON, 0.8, (0.85, 0.85, 0.82), 0.0)], face_spec=face_spec, uv_scale=6.0)
        bm.free()
        decimate(ob, 0.45)''')
patch(f, '''    # ---------------- face (eyes at about 1.695 m''', '''    # ---------------- hair (on the skull; left off under headwear and the hood)
    hair = (0.06, 0.05, 0.045)
    b = Builder('head').spec(KNIT, 0.95, hair, 1.0, 0.02)
    b.shell(crown + Vector((0, 0.004, 0)), Vector((hr.x + 0.004, hr.y + 0.005, hr.z + 0.003)), 0.003, phi0=0.0, phi1=1.55, segs=20, rings=8, theta0=0.55, theta1=2 * math.pi - 0.55, closed=False)
    b.shell(crown + Vector((0, 0.004, 0)), Vector((hr.x + 0.004, hr.y + 0.005, hr.z + 0.003)), 0.003, phi0=0.0, phi1=0.95, segs=8, rings=4, theta0=-0.55, theta1=0.55, closed=False)
    hard('hair_buzz', b, arm, body)
    b = Builder('head').spec(KNIT, 0.9, hair, 1.0, 0.015)
    b.shell(crown + Vector((0, 0.006, 0.006)), Vector((hr.x + 0.012, hr.y + 0.014, hr.z + 0.014)), 0.008, phi0=0.0, phi1=1.62, segs=22, rings=9, theta0=0.6, theta1=2 * math.pi - 0.6, closed=False)
    b.shell(crown + Vector((0, 0.006, 0.006)), Vector((hr.x + 0.012, hr.y + 0.014, hr.z + 0.014)), 0.008, phi0=0.0, phi1=1.12, segs=8, rings=5, theta0=-0.6, theta1=0.6, closed=False)
    # a fringe over the forehead
    for k in range(5):
        x = -0.04 + k * 0.02
        b.box(Vector((x, crown.y - hr.y - 0.006, crown.z + 0.05 - abs(x) * 0.3)), (0.024, 0.012, 0.03), Matrix.Rotation(0.3, 3, 'X'))
    hard('hair_short', b, arm, body)
    b = Builder('head').spec(KNIT, 0.9, hair, 1.0, 0.015)
    b.shell(crown + Vector((0, 0.004, 0)), Vector((hr.x + 0.003, hr.y + 0.004, hr.z + 0.002)), 0.002, phi0=0.0, phi1=1.5, segs=20, rings=6, theta0=0.55, theta1=2 * math.pi - 0.55, closed=False)
    rings = []
    for k in range(9):
        th = -1.15 + k * (2.3 + 1.2) / 8
        ph = th
        p = Vector((0.0, crown.y - (hr.y + 0.01) * math.sin(ph), crown.z + (hr.z + 0.01) * math.cos(ph)))
        rings.append(p)
    b.tube(rings, 0.02, segs=6, radii=[0.012, 0.02, 0.026, 0.03, 0.03, 0.028, 0.024, 0.018, 0.01])
    hard('hair_mohawk', b, arm, body)
    b = Builder('head').spec(KNIT, 0.9, hair, 1.0, 0.015)
    b.shell(crown + Vector((0, 0.005, 0.004)), Vector((hr.x + 0.01, hr.y + 0.012, hr.z + 0.01)), 0.006, phi0=0.0, phi1=1.6, segs=22, rings=9, theta0=0.55, theta1=2 * math.pi - 0.55, closed=False)
    b.shell(crown + Vector((0, 0.005, 0.004)), Vector((hr.x + 0.01, hr.y + 0.012, hr.z + 0.01)), 0.006, phi0=0.0, phi1=1.05, segs=8, rings=4, theta0=-0.55, theta1=0.55, closed=False)
    b.ellipsoid(Vector((0.0, crown.y + hr.y + 0.035, crown.z + 0.05)), Vector((0.04, 0.035, 0.04)), segs=10, rings=6)
    hard('hair_bun', b, arm, body)

    # ---------------- face (eyes at about 1.695 m''')

# cosmetics: a Hair slot, the hood as part of the hoodie
f2 = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'data', 'cosmetics.json')
patch(f2, '''  {"id": "helmet", "name": "Headwear", "items": [''', '''  {"id": "hair", "name": "Hair", "items": [
   {"id": "short", "name": "Short", "pieces": ["hair_short"], "colors": ["#1a1410", "#3b2a1c", "#6b4a2a", "#8c8c88", "#b8862c"]},
   {"id": "buzz", "name": "Buzz Cut", "pieces": ["hair_buzz"], "colors": ["#1a1410", "#3b2a1c", "#8c8c88"]},
   {"id": "mohawk", "name": "Mohawk", "pieces": ["hair_mohawk"], "colors": ["#1a1410", "#b8292c", "#2c6bd1", "#e0c040"]},
   {"id": "bun", "name": "Bun", "pieces": ["hair_bun"], "colors": ["#1a1410", "#3b2a1c", "#6b4a2a"]},
   {"id": "none", "name": "Bald"}
  ]},
  {"id": "helmet", "name": "Headwear", "items": [''')
patch(f2, '''   {"id": "hoodie", "name": "Hoodie", "pieces": ["jacket_hoodie"],''', '''   {"id": "hoodie", "name": "Hoodie", "pieces": ["jacket_hoodie"], "hood": "jacket_hoodie_hood",''')
patch(f2, '''"default_look": {"helmet": "none",''', '''"default_look": {"hair": "short", "helmet": "none",''')

# outfit: hood and hair only when nothing is on the head
f3 = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'src', 'player', 'outfit.gd')
patch(f3, '''const SLOT_ORDER := ["helmet", "face", "jacket", "shirt", "gloves", "elbow", "knee", "pants", "boots", "pack"]''', '''const SLOT_ORDER := ["hair", "helmet", "face", "jacket", "shirt", "gloves", "elbow", "knee", "pants", "boots", "pack"]''')
patch(f3, '''	var jacket_on := not jacket.is_empty() and str(jacket.get("id", "none")) != "none"
	for s in SLOT_ORDER:
		var it: Dictionary = item(s, str(look.get(s, "none")))
		if it.is_empty() or str(it.id) == "none":
			continue''', '''	var jacket_on := not jacket.is_empty() and str(jacket.get("id", "none")) != "none"
	# The hood goes up when nothing else is on the head; hair shows when neither hood nor headwear covers it.
	var helmet_on := str(look.get("helmet", "none")) != "none"
	var hood_up := jacket.has("hood") and not helmet_on
	for s in SLOT_ORDER:
		var it: Dictionary = item(s, str(look.get(s, "none")))
		if it.is_empty() or str(it.id) == "none":
			continue
		if s == "hair" and (helmet_on or hood_up):
			continue''')
patch(f3, '''		for n in names:
			out.append([str(n), tint])''', '''		for n in names:
			out.append([str(n), tint])
		if s == "jacket" and hood_up:
			out.append([str(it.hood), tint])''')
patch(f3, '''	var odds := {"helmet": 0.45, "face": 0.3, "jacket": 0.55, "gloves": 0.35, "elbow": 0.2, "knee": 0.25, "pack": 0.4}''', '''	var odds := {"hair": 0.85, "helmet": 0.45, "face": 0.3, "jacket": 0.55, "gloves": 0.35, "elbow": 0.2, "knee": 0.25, "pack": 0.4}''')
