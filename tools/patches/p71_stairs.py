"""Stairs that can be climbed (user, 2026-10-27: "stairs not working at all and are solid objects").

The ramp under each flight was tipped the wrong way (Basis(RIGHT, ang) sends +z down, so it was high at the
bottom step: a wall across the stair), the railing upstairs ran the full length of the hole and boxed in anyone who
did reach the top, and three-storey buildings had no flight to the top floor.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

p = Patch('game/src/world/shanty.gd')
p.rep("""	var stair_run := h0 * 1.05
""", """	var stair_run := h0 * 1.05
	# A three-storey building climbs on to its top floor by a second flight along the other side wall.
	var stair2 := floors >= 3
	var run2 := h1 * 1.05
	var stair2_box := Rect2()
	if stair2:
		stair2_box = Rect2(Vector2((w * 0.5 - stair_w) if stair_side < 0 else -w * 0.5, d * 0.5 - run2 - 0.2), Vector2(stair_w, run2 + 0.2))
""")
p.rep("""		var floor_hole := Rect2()
		if f == 1 and stair:
			floor_hole = Rect2(Vector2((w * 0.5 - stair_w - 0.05) if stair_side > 0 else -w * 0.5, d * 0.5 - stair_run - 0.05 - fz_off), Vector2(stair_w + 0.05, stair_run + 0.1))
		_upper_floor(fxf, fw, fd, fy, floor_hole, dirt)""", """		var floor_hole := Rect2()
		var hole_side := 0.0     # the side wall the flight up to this floor runs along
		var hole_run := 0.0
		if f == 1 and stair:
			hole_side = stair_side
			hole_run = stair_run
		elif f == 2 and stair2:
			hole_side = -stair_side
			hole_run = run2
		if hole_side != 0.0:
			floor_hole = Rect2(Vector2((w * 0.5 - stair_w - 0.05) if hole_side > 0 else -w * 0.5, d * 0.5 - hole_run - 0.05 - fz_off), Vector2(stair_w + 0.05, hole_run + 0.1))
		_upper_floor(fxf, fw, fd, fy, floor_hole, dirt)
		if f == 1 and stair2:
			_stair(xf, (w * 0.5 - stair_w * 0.5 - 0.02) * -stair_side, d * 0.5 - 0.15, stair_w, run2, h1, fy, dirt)""")
p.rep("""		if f == 1 and stair:
			var sp := xf * Vector3((w * 0.5 - stair_w * 0.5) * stair_side, fy, d * 0.5 - stair_run * 0.5)
			ctx.acoustics.add_portal(prev_zone, uz, sp, "stair", 1.0)
			# Railing around the stair hole.
			var rx := (w * 0.5 - stair_w - 0.05) * stair_side
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(rx, fy + 0.5, d * 0.5 - stair_run * 0.5)), Vector3(0.05, 0.05, stair_run), "timber", {"dirt": dirt, "layer": "int"})
			for k in 3:
				ctx.sink.box(xf * Transform3D(Basis(), Vector3(rx, fy + 0.25, d * 0.5 - stair_run * (0.1 + 0.4 * k))), Vector3(0.05, 0.5, 0.05), "timber", {"dirt": dirt, "layer": "int"})
		else:""", """		if hole_side != 0.0:
			var sp := xf * Vector3((w * 0.5 - stair_w * 0.5) * hole_side, fy, d * 0.5 - hole_run * 0.5)
			ctx.acoustics.add_portal(prev_zone, uz, sp, "stair", 1.0)
			# Railing across the low end of the hole and down its open side, stopping a metre short of the top step
			# so the flight lets out sideways on to the floor.
			var rx := (w * 0.5 - stair_w - 0.05) * hole_side
			var z_lo := d * 0.5 - hole_run - 0.05
			var rail_len := hole_run - 1.0
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(rx, fy + 0.9, z_lo + rail_len * 0.5)), Vector3(0.05, 0.05, rail_len), "timber", {"dirt": dirt, "layer": "int"})
			for k in 3:
				ctx.sink.box(xf * Transform3D(Basis(), Vector3(rx, fy + 0.45, z_lo + 0.03 + (rail_len - 0.06) * k / 2.0)), Vector3(0.05, 0.9, 0.05), "timber", {"dirt": dirt, "layer": "int"})
			var cx := (w * 0.5 - (stair_w + 0.05) * 0.5) * hole_side
			for ry in [0.45, 0.9]:
				ctx.sink.box(xf * Transform3D(Basis(), Vector3(cx, fy + ry, z_lo)), Vector3(stair_w + 0.05, 0.05, 0.05), "timber", {"dirt": dirt, "layer": "int"})
		else:""")
p.rep("""		out.rooms.append({"type": "bed", "xf": fxf * Transform3D(Basis(), Vector3(0, fy, 0)), "size": Vector2(fw - 0.3, fd - 0.3), "h": h1, "bid": bid, "zone": uz,
			"avoid": floor_hole if f == 1 else Rect2(), "local_z": fz_off})""", """		# Furniture keeps off the hole into this floor and off the flight up from it (rects in house coordinates, like
		# the ground floor's: the dresser subtracts local_z).
		var hole_xf := Rect2(floor_hole.position + Vector2(0, fz_off), floor_hole.size) if hole_side != 0.0 else Rect2()
		out.rooms.append({"type": "bed", "xf": fxf * Transform3D(Basis(), Vector3(0, fy, 0)), "size": Vector2(fw - 0.3, fd - 0.3), "h": h1, "bid": bid, "zone": uz,
			"avoid": hole_xf, "avoid2": stair2_box if f == 1 else Rect2(), "local_z": fz_off})""")
p.rep("""		ctx.sink.box(xf * Transform3D(Basis(Vector3.RIGHT, ang), c), Vector3(0.04, 0.2, len), "timber", {"dirt": dirt, "collide": false, "layer": "int"})""",
      """		ctx.sink.box(xf * Transform3D(Basis(Vector3.RIGHT, -ang), c), Vector3(0.04, 0.2, len), "timber", {"dirt": dirt, "collide": false, "layer": "int"})""")
p.rep("""	# Walkable ramp under the steps.
	var rc := Vector3(sx, y + rise * 0.5 - 0.02, z_start + run * 0.5)
	ctx.sink.col_box(xf * Transform3D(Basis(Vector3.RIGHT, ang), rc), Vector3(sw - 0.05, 0.06, len + 0.1), "wood")""",
      """	# Walkable ramp under the steps, rising with them toward the back wall (Basis(RIGHT, -ang) tips +z upward).
	var rc := Vector3(sx, y + rise * 0.5 - 0.02, z_start + run * 0.5)
	ctx.sink.col_box(xf * Transform3D(Basis(Vector3.RIGHT, -ang), rc), Vector3(sw - 0.05, 0.06, len + 0.1), "wood")""")
p.save()

d = Patch('game/src/world/dresser.gd')
d.rep("""	var av: Rect2 = r.get("avoid", Rect2())
	if av.size != Vector2.ZERO:
		ctx.occ.append(Rect2(av.position - Vector2(0, float(r.get("local_z", 0.0))), av.size).grow(0.1))""",
      """	for k in ["avoid", "avoid2"]:
		var av: Rect2 = r.get(k, Rect2())
		if av.size != Vector2.ZERO:
			ctx.occ.append(Rect2(av.position - Vector2(0, float(r.get("local_z", 0.0))), av.size).grow(0.1))""")
d.save()
