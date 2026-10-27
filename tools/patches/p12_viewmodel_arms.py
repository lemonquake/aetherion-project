"""Patch: forearms angle down and away from the camera instead of running back into it; a faint fill light on the
view-model layer only, so hands, weapon and device read as shapes in the dark without lighting the world."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/player/viewmodel.gd', [
    ('''	hand_r = _hand(Color(0.36, 0.26, 0.2), Color(0.07, 0.07, 0.08))
	weapon_root.add_child(hand_r)''', '''	hand_r = _hand(Color(0.36, 0.26, 0.2), Color(0.07, 0.07, 0.08))
	hand_r.rotation = Vector3(0.75, -0.25, 0)  # forearm runs down and out to the lower right
	weapon_root.add_child(hand_r)'''),
    ('''	hand_l.position = Vector3(0.0, -0.085, -0.045)
	hand_l.rotation = Vector3(-0.35, 0, 0)''', '''	hand_l.position = Vector3(0.0, -0.1, -0.02)
	hand_l.rotation = Vector3(0.95, 0.25, 0)  # forearm runs down and out below the device'''),
    ('''	hand.position = Vector3(0, -0.035, 0.05)
	torch_root.add_child(hand)''', '''	hand.position = Vector3(0, -0.035, 0.05)
	hand.rotation = Vector3(0.7, -0.2, 0)
	torch_root.add_child(hand)'''),
    ('''	light.visible = false
	add_child(light)
	_set_layer(self)''', '''	light.visible = false
	add_child(light)
	# Faint fill on the view-model layer only (moonlight on your own hands); never reaches the world.
	var fill := OmniLight3D.new()
	fill.light_cull_mask = Defs.RENDER_VIEWMODEL
	fill.light_color = Color(0.55, 0.65, 0.85)
	fill.light_energy = 0.35
	fill.omni_range = 2.0
	fill.shadow_enabled = false
	fill.position = Vector3(0.35, 0.45, 0.25)
	add_child(fill)
	_set_layer(self)'''),
])
