"""r11: three-storey townhouses and shophouses with a roof deck.

About a third of the full-size two-storey houses, and the Canal Row shophouses whose row asks for three floors, get
a third floor: a family room, a bedroom and a bath off a hall, reached by a second flight that switches back beside
the first, and a third flight up through a flat roof deck with a parapet (the stair opening railed on the roof).
    python -I tools/patches/r11_three_storey.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

p = Patch('game/src/world/maps/lawless_sub/houses.gd')
p.rep('''##   shophouse (Canal Row): a store across the ground floor with a wide front opening, stock room and toilet behind,
##     two bedrooms, a bathroom and a hall upstairs; flat roof with a parapet and a ladder.''',
      '''##   shophouse (Canal Row): a store across the ground floor with a wide front opening, stock room and toilet behind,
##     two bedrooms, a bathroom and a hall upstairs; flat roof with a parapet and a ladder.
##   r11: a third of the full-size houses and the shophouses of three-floor rows get a third floor (family room,
##     bedroom, bath, hall) by a switchback flight, and a flight up through a flat roof deck.''')
p.rep('''	if shop:
		w = ehalf.x * 2.0 - 0.1
		d = minf(ehalf.y * 2.0, rng.randf_range(9.6, 11.0))
		plan = _shophouse(w, d, rng)''', '''	if shop:
		w = ehalf.x * 2.0 - 0.1
		d = minf(ehalf.y * 2.0, rng.randf_range(9.6, 11.0))
		plan = _shophouse(w, d, rng)
		if int(lot.floors) >= 3:
			_third_floor(plan, w, d, 2.2, 0.6)''')
p.rep('''	else:
		w = minf(ehalf.x * 2.0, rng.randf_range(8.4, 9.8))
		d = minf(ehalf.y * 2.0, rng.randf_range(9.4, 11.0))
		plan = _two_storey(w, d, rng)''', '''	else:
		w = minf(ehalf.x * 2.0, rng.randf_range(8.4, 9.8))
		d = minf(ehalf.y * 2.0, rng.randf_range(9.4, 11.0))
		plan = _two_storey(w, d, rng)
		if rng.randf() < 0.34 and d >= 9.4:
			_third_floor(plan, w, d, 2.1, 0.55)''')
p.rep('''static func _mirror(plan: Dictionary) -> void:''', '''static func _third_floor(plan: Dictionary, w: float, d: float, hall_w: float, s_off: float) -> void:
	## Adds floor 3 and a flat roof deck to a plan whose first flight climbs +z at x = X - 0.65 from -Z + s_off
	## inside a stair hall/corridor hall_w wide on the east side. The second flight switches back in the hall's
	## west lane (-z); the third climbs the east lane again, up through the roof.
	var X := w * 0.5
	var Z := d * 0.5
	var hx := X - hall_w
	var run := 15 * 0.27
	var s0 := -Z + s_off
	var zc := s0 + run + 0.1
	var u: Dictionary = plan.floors[1]
	# The upstairs hall must reach the second flight's foot: widen its corridor (the room on the east side).
	for R in u.rooms:
		var r: Array = R.rect
		if str(R.type) == "corridor" and float(r[0]) >= hx - 0.05 and float(r[1]) <= -Z + 0.05:
			r[3] = maxf(float(r[3]), zc + 1.7)
		elif float(r[0]) >= hx - 0.05 and float(r[1]) < zc + 1.7 and float(r[3]) > zc + 1.7 and str(R.type) != "corridor":
			r[1] = zc + 1.7
	u.stair = {"start": Vector2(X - hall_w + 0.48, zc + 0.9), "dir": "-z", "w": 0.9, "to": 2}
	var t := {"h": 3.0, "rooms": [
		{"type": "sala", "rect": [-X, -Z, hx, zc]},
		{"type": "corridor", "rect": [hx, -Z, X, zc + 1.7], "windows": 0},
		{"type": "bedroom", "rect": [-X, zc, hx, Z]},
		{"type": "bath", "rect": [hx, zc + 1.7, X, Z]},
	], "stair": {"start": Vector2(X - 0.65, s0), "dir": "+z", "w": 1.0, "to": 3}}
	if plan.floors.size() == 2:
		plan.floors.append(t)
	plan.roof = {"type": "flat", "parapet": 1.05, "tank": true}


static func _mirror(plan: Dictionary) -> void:''')
p.save()
print('r11 three-storey patch done')
