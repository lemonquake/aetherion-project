"""More windows a player fits through (user, 2026-10-27): about 0.75-1.1 m wide and 0.9-1.1 m tall on a 0.9 m sill,
on most walls of every floor; fewer barred ones, more left open. Vaulting (jump close to one) climbs through."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

s = Patch('game/src/world/shanty.gd')
s.rep('''	var r := rng.randf()
	if r < 0.32:
		return "glass"
	if r < 0.56:
		return "shutter"
	if r < 0.78:
		return "bars"
	if r < 0.9:
		return "plastic"
	return "open"''', '''	var r := rng.randf()
	if r < 0.3:
		return "glass"
	if r < 0.54:
		return "shutter"
	if r < 0.66:
		return "bars"
	if r < 0.8:
		return "plastic"
	return "open"''')
s.rep('''				walls0.front.append({"type": "window", "x": wx, "w": rng.randf_range(0.6, 1.0), "y": 1.0, "h": rng.randf_range(0.6, 0.9), "win": _win_type()})''',
      '''				walls0.front.append({"type": "window", "x": wx, "w": rng.randf_range(0.8, 1.05), "y": 0.9, "h": rng.randf_range(0.95, 1.1), "win": _win_type()})''')
s.rep('''	elif rng.randf() < 0.6:
		walls0.back.append({"type": "window", "x": rng.randf_range(-0.25, 0.25) * w, "w": 0.6, "y": 1.2, "h": 0.6, "win": _win_type()})
	for side in ["left", "right"]:
		if rng.randf() < 0.55:
			var zc := rng.randf_range(-0.3, 0.3) * d
			walls0[side].append({"type": "window", "x": zc, "w": rng.randf_range(0.5, 0.9), "y": 1.05, "h": rng.randf_range(0.55, 0.8), "win": _win_type()})''',
      '''	elif rng.randf() < 0.85:
		walls0.back.append({"type": "window", "x": rng.randf_range(-0.25, 0.25) * w, "w": rng.randf_range(0.8, 1.0), "y": 0.95, "h": rng.randf_range(0.9, 1.05), "win": _win_type()})
	for side in ["left", "right"]:
		if rng.randf() < 0.85:
			var zc := rng.randf_range(-0.3, 0.3) * d
			walls0[side].append({"type": "window", "x": zc, "w": rng.randf_range(0.75, 1.0), "y": 0.9, "h": rng.randf_range(0.95, 1.1), "win": _win_type()})''')
s.rep('''		walls1.front.append({"type": "window", "x": rng.randf_range(-0.25, 0.25) * fw, "w": rng.randf_range(0.7, 1.2), "y": 0.9, "h": rng.randf_range(0.6, 0.9), "win": _win_type()})
		if rng.randf() < 0.5:
			walls1.left.append({"type": "window", "x": rng.randf_range(-0.2, 0.2) * fd, "w": 0.6, "y": 1.0, "h": 0.6, "win": _win_type()})
		if rng.randf() < 0.5:
			walls1.right.append({"type": "window", "x": rng.randf_range(-0.2, 0.2) * fd, "w": 0.6, "y": 1.0, "h": 0.6, "win": _win_type()})''',
      '''		walls1.front.append({"type": "window", "x": rng.randf_range(-0.25, 0.25) * fw, "w": rng.randf_range(0.8, 1.2), "y": 0.9, "h": rng.randf_range(0.95, 1.1), "win": _win_type()})
		if rng.randf() < 0.75:
			walls1.left.append({"type": "window", "x": rng.randf_range(-0.2, 0.2) * fd, "w": rng.randf_range(0.75, 0.95), "y": 0.9, "h": rng.randf_range(0.9, 1.05), "win": _win_type()})
		if rng.randf() < 0.75:
			walls1.right.append({"type": "window", "x": rng.randf_range(-0.2, 0.2) * fd, "w": rng.randf_range(0.75, 0.95), "y": 0.9, "h": rng.randf_range(0.9, 1.05), "win": _win_type()})''')
s.save()
