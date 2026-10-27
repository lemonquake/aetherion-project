"""Patch: door/shutter leaves carry an unpainted vertex colour (the surface shader paints white otherwise);
slightly stronger moon and sky fill so walls stay readable in moonlight."""
G = 'A:/Python/aetherion-project/game/'


def sub(path, old, new, count=1):
    s = open(G + path, encoding='utf-8').read()
    if old not in s:
        raise SystemExit(f'pattern not found in {path}: {old[:70]!r}')
    s = s.replace(old, new, count)
    open(G + path, 'w', encoding='utf-8').write(s)


sub('src/world/dynamics.gd', '''		"box":
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE
			bm.material = mats.get_material(mat)
			m = bm''', '''		"box":
			var sb := SurfaceTool.new()
			sb.begin(Mesh.PRIMITIVE_TRIANGLES)
			sb.set_color(Color(1, 1, 1, 0))
			sb.set_uv2(Vector2(0.4, -100.0))
			_add_box_st(sb, Transform3D(), Vector3.ONE)
			sb.generate_tangents()
			m = sb.commit()
			m.surface_set_material(0, mats.get_material(mat))''')
sub('src/world/lighting.gd', '''	env.ambient_light_energy = 0.11''', '''	env.ambient_light_energy = 0.2''')
sub('src/world/lighting.gd', '''	moon.light_energy = 0.42''', '''	moon.light_energy = 0.55''')
print('ok')
