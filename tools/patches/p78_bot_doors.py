"""Bots: an open leaf no longer blocks anyone (it is pushed aside), so only a shut door needs Use."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

b = Patch('game/src/ai/bot_brain.gd')
b.rep('''			var ang := absf(dn.angle)
			var shut: bool = absf(dn.target) < 0.05
			var stuck_half: bool = not dn.moving and ang > 0.05 and ang < 1.0
			var in_reach: bool = ch.eye_position().distance_to(dn.center()) < 2.0
			if (shut or stuck_half) and in_reach:''', '''			var ang := absf(dn.angle)
			var shut: bool = ang <= dn.OPEN_PASS and absf(dn.target) < 0.05 and not dn.free
			var in_reach: bool = ch.eye_position().distance_to(dn.center()) < 2.0
			if shut and in_reach:''')
b.rep('''			if dn.moving and ang < 1.0:
				cmd.my = -0.3
				return
''', '''			if dn.moving and not dn.free and ang <= dn.OPEN_PASS:
				cmd.my = -0.3
				return
''')
b.save()
