"""The front/back partition ran the full width of the house, straight through the stair flight it was told about."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

p = Patch('game/src/world/shanty.gd')
p.rep("""	var x0 := -w * 0.5 + 0.05
	var x1 := w * 0.5 - 0.05
	var a0 := px - dw * 0.5""", """	var x0 := -w * 0.5 + 0.05
	var x1 := w * 0.5 - 0.05
	# The stair flight along a side wall passes through here when it crosses this depth: the wall stops at its edge.
	if stair and stair_crosses:
		if stair_side > 0:
			x1 = w * 0.5 - stair_w - 0.08
		else:
			x0 = -w * 0.5 + stair_w + 0.08
	var a0 := px - dw * 0.5""")
p.rep("""		dirt: float, bid: int, zf: int, zb: int, stair: bool, stair_side: float, stair_w: float) -> void:""",
      """		dirt: float, bid: int, zf: int, zb: int, stair: bool, stair_side: float, stair_w: float, stair_crosses: bool = true) -> void:""")
p.rep("""		_partition_x(xf, w, z_split, y0, h0, px, 0.8, part_mat, open_kind, dirt, bid, zf, zb, stair, stair_side, stair_w)""",
      """		_partition_x(xf, w, z_split, y0, h0, px, 0.8, part_mat, open_kind, dirt, bid, zf, zb, stair, stair_side, stair_w,
			z_split > d * 0.5 - stair_run - 0.8)""")
p.save()
