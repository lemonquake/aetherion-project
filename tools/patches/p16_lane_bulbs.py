"""Patch: lane bulbs hang lower on longer drops and fall off more gently, so they light the ground under them;
the SmarTab hand moves fully behind the device."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/world/practical_lights.gd', [
    ('''	var drop := rng.randf_range(0.35, 0.7)''', '''	# Strung low on a long flex so the light reaches the lane (posts are 5.6-7.2 m tall).
	var drop := clampf(top.y - mb.layout.ground_height(top.x, top.z) - rng.randf_range(3.4, 4.3), 0.4, 3.2)'''),
    ('''	mb.dyn.add_light({"pos": bulb, "kind": "bulb", "color": col, "energy": rng.randf_range(0.5, 0.85), "range": rng.randf_range(7.5, 10.5),
		"fault": _fault("bulb")})''', '''	mb.dyn.add_light({"pos": bulb, "kind": "bulb", "color": col, "energy": rng.randf_range(0.55, 0.9), "range": rng.randf_range(8.0, 11.0),
		"fault": _fault("bulb"), "outdoor": true})'''),
    ('''			mb.dyn.add_light({"pos": at + Vector3(0, -0.06, 0), "kind": "bulb", "color": _bulb_colour(), "energy": rng.randf_range(0.35, 0.55),
				"range": rng.randf_range(5.0, 6.5), "fault": _fault("bulb")})''', '''			mb.dyn.add_light({"pos": at + Vector3(0, -0.06, 0), "kind": "bulb", "color": _bulb_colour(), "energy": rng.randf_range(0.35, 0.55),
				"range": rng.randf_range(5.0, 6.5), "fault": _fault("bulb"), "outdoor": true})'''),
])
patch('src/world/lighting.gd', [(
    '''			ol.omni_attenuation = 1.4 if kind != "candle" else 1.8''',
    '''			ol.omni_attenuation = 1.8 if kind == "candle" else (1.0 if spec.get("outdoor", false) else 1.4)''')])
patch('src/player/viewmodel.gd', [(
    '''	hand_l.position = Vector3(0.0, -0.1, -0.02)''', '''	hand_l.position = Vector3(0.0, -0.118, -0.06)''')])
