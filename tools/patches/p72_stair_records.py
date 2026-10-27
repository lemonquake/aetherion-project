"""Record each stair flight (foot and landing points) so tests and bots can find them."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

p = Patch('game/src/world/shanty.gd')
p.rep("""var ctx = null
var rng := RandomNumberGenerator.new()
""", """var ctx = null
var rng := RandomNumberGenerator.new()
## Stair flights built by the last build(): {foot, top} in world space (foot: on the floor a step before the first
## tread; top: on the upper floor beside the last tread, where the flight lets out).
var flights: Array = []
""")
p.rep("""	var z_start := z_back - run
	for i in steps:""", """	var z_start := z_back - run
	flights.append({"foot": xf * Vector3(sx, y, z_start - 0.5), "top": xf * Vector3(sx - signf(sx) * sw, y + rise, z_back - 0.45)})
	for i in steps:""")
p.save()

m = Patch('game/src/world/map_builder.gd')
m.rep("""var rooms: Array = []
""", """var rooms: Array = []
var stairs: Array = []  # [{foot, top}] every indoor stair flight
""")
m.rep("""	var out := s.build(spec)
""", """	var out := s.build(spec)
	stairs.append_array(s.flights)
""")
m.save()
