"""Patch: decal/puddle/wire materials, a 'mid' draw layer, and models reused from the Sleep project."""
G = 'A:/Python/aetherion-project/game/'


def sub(path, old, new, count=1):
    s = open(G + path, encoding='utf-8').read()
    if old not in s:
        raise SystemExit(f'pattern not found in {path}: {old[:60]!r}')
    s = s.replace(old, new, count)
    open(G + path, 'w', encoding='utf-8').write(s)


sub('src/world/materials.gd', '''		"black":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.02, 0.02, 0.02)
			b.roughness = 1.0
			m = b''', '''		"black":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.02, 0.02, 0.02)
			b.roughness = 1.0
			m = b
		"wire":
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.015, 0.015, 0.016)
			wm.roughness = 0.55
			m = wm
		"puddle":
			var pm := ShaderMaterial.new()
			pm.shader = preload("res://src/world/puddle.gdshader")
			m = pm''')
sub('src/world/materials.gd', '''		_:
			m = _surface(name)
	_cache[name] = m
	return m''', '''		_:
			if name.begins_with("decal:"):
				var dm := ShaderMaterial.new()
				dm.shader = preload("res://src/world/decal.gdshader")
				dm.set_shader_parameter("tex", _tex(name.substr(6)))
				m = dm
			else:
				m = _surface(name)
	_cache[name] = m
	return m''')
sub('src/world/materials.gd', '''	if name.begins_with("glass"):
		return "glass"''', '''	if name.begins_with("glass"):
		return "glass"
	if name.begins_with("decal:") or name == "puddle" or name == "wire":
		return "fabric"''')

sub('src/world/geo_sink.gd', '''		var layer := parts[2]
		if layer == "int":''', '''		var layer := parts[2]
		if layer == "mid":
			mi.visibility_range_end = 140.0
			mi.visibility_range_end_margin = 15.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if parts[1].begins_with("decal:") or parts[1] == "puddle":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif layer == "int":''')

MODELS = '''
	"heap_large_a": {"path": "res://assets/models/sleep/kit/heap_large_a.glb", "mass": 400.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true},
	"heap_large_b": {"path": "res://assets/models/sleep/kit/heap_large_b.glb", "mass": 400.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true},
	"heap_medium_a": {"path": "res://assets/models/sleep/kit/heap_medium_a.glb", "mass": 200.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true},
	"heap_medium_b": {"path": "res://assets/models/sleep/kit/heap_medium_b.glb", "mass": 200.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true},
	"heap_small_a": {"path": "res://assets/models/sleep/kit/heap_small_a.glb", "mass": 60.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true},
	"heap_small_b": {"path": "res://assets/models/sleep/kit/heap_small_b.glb", "mass": 60.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true},
	"litter_a": {"path": "res://assets/models/sleep/kit/litter_a.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"litter_b": {"path": "res://assets/models/sleep/kit/litter_b.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"rubble_a": {"path": "res://assets/models/sleep/kit/rubble_a.glb", "mass": 300.0, "mat": "concrete", "hp": 99999, "kind": "fixture", "static": true},
	"rubble_b": {"path": "res://assets/models/sleep/kit/rubble_b.glb", "mass": 300.0, "mat": "concrete", "hp": 99999, "kind": "fixture", "static": true},
	"floating_a": {"path": "res://assets/models/sleep/kit/floating_a.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"floating_b": {"path": "res://assets/models/sleep/kit/floating_b.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"floating_c": {"path": "res://assets/models/sleep/kit/floating_c.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"old_mattress": {"path": "res://assets/models/sleep/kit/mattress.glb", "mass": 10.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true},
	"tricycle_a": {"path": "res://assets/models/sleep/street/tricycle_a.glb", "mass": 300.0, "mat": "sheet_metal", "hp": 99999, "kind": "vehicle", "static": true},
	"tricycle_b": {"path": "res://assets/models/sleep/street/tricycle_b.glb", "mass": 300.0, "mat": "sheet_metal", "hp": 99999, "kind": "vehicle", "static": true},
	"jeepney": {"path": "res://assets/models/sleep/street/jeepney.glb", "mass": 2500.0, "mat": "steel", "hp": 99999, "kind": "vehicle", "static": true},
	"food_cart_a": {"path": "res://assets/models/sleep/street/food_cart_a.glb", "mass": 80.0, "mat": "wood", "hp": 99999, "kind": "vehicle", "static": true},
	"food_cart_b": {"path": "res://assets/models/sleep/street/food_cart_b.glb", "mass": 80.0, "mat": "wood", "hp": 99999, "kind": "vehicle", "static": true},
	"food_stall": {"path": "res://assets/models/sleep/street/food_stall_c.glb", "mass": 120.0, "mat": "wood", "hp": 99999, "kind": "vehicle", "static": true},
	"oil_drum": {"path": "res://assets/models/sleep/street/oil_drum.glb", "mass": 20.0, "mat": "sheet_metal", "hp": 500, "kind": "heavy"},
	"palm_a": {"path": "res://assets/models/sleep/nature/palm_coconut_a.glb", "mass": 500.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.25},
	"palm_b": {"path": "res://assets/models/sleep/nature/palm_coconut_b.glb", "mass": 500.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.25},
	"banana_a": {"path": "res://assets/models/sleep/nature/banana_plant.glb", "mass": 50.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"banana_b": {"path": "res://assets/models/sleep/nature/banana_small.glb", "mass": 50.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"bamboo": {"path": "res://assets/models/sleep/nature/bamboo_clump.glb", "mass": 200.0, "mat": "wood", "hp": 99999, "kind": "plant", "static": true, "trunk": 0.6},
	"reeds": {"path": "res://assets/models/sleep/nature/reeds.glb", "mass": 5.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"cattails": {"path": "res://assets/models/sleep/nature/cattails.glb", "mass": 5.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"fern": {"path": "res://assets/models/sleep/nature/fern.glb", "mass": 2.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"tree_island": {"model": "island_tree_01", "mass": 900.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.35},
	"tree_island2": {"model": "island_tree_02", "mass": 900.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.35},
	"tree_small": {"model": "tree_small_02", "mass": 300.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.2},
	"shrub": {"model": "shrub_02", "mass": 20.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"grass_clump": {"model": "grass_medium_01", "mass": 1.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"weeds": {"model": "weed_plant_02", "mass": 1.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},'''
sub('src/world/model_lib.gd', '''	"pallet": {"prim": "box", "size": Vector3(1.2, 0.14, 1.0), "mass": 18.0, "mat": "wood", "hp": 200, "kind": "heavy", "surface": "planks"},''',
    '''	"pallet": {"prim": "box", "size": Vector3(1.2, 0.14, 1.0), "mass": 18.0, "mat": "wood", "hp": 200, "kind": "heavy", "surface": "planks"},''' + MODELS)
sub('src/world/model_lib.gd', '''	else:
		var id := str(s.get("model", name))
		res = _load_scene_mesh(PH + id + "/" + id + ".gltf")''', '''	elif s.has("path"):
		res = _load_scene_mesh(str(s.path))
	else:
		var id := str(s.get("model", name))
		res = _load_scene_mesh(PH + id + "/" + id + ".gltf")''')
print('ok')
