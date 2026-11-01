@tool
extends RefCounted
## (r27) Open fire for torches and braziers: the flame and its glow as one mesh (flame.gdshader turns its quads to the
## camera). Lighting gives every lit "torch" and "brazier" light one; the map editor shows the same.

const SHADER := preload("res://src/world/flame.gdshader")

static var _meshes := {}


static func mesh(kind: String) -> Mesh:
	## (r27) A fire's flame and its glow: two upright quads (flame.gdshader turns them to the camera), the light's
	## position a third of the way up the flame. The map editor shows the same mesh.
	if _meshes.has(kind):
		return _meshes[kind]
	var big := kind == "brazier"
	var am := ArrayMesh.new()
	var w := 0.62 if big else 0.24
	var y0 := -0.32 if big else -0.14
	var y1 := 0.95 if big else 0.42
	for halo in [false, true]:
		var hw := w * (2.6 if halo else 0.5)
		var a := y0 - (0.5 if halo else 0.0) * (y1 - y0)
		var b := y1 + (0.4 if halo else 0.0) * (y1 - y0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts := [Vector3(-hw, a, 0), Vector3(hw, a, 0), Vector3(hw, b, 0), Vector3(-hw, b, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[i])
			st.set_normal(Vector3.BACK)
			st.add_vertex(pts[i])
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		sm.set_shader_parameter("halo", halo)
		sm.set_shader_parameter("intensity", 3.2 if big else 2.6)
		sm.set_shader_parameter("speed", 0.85 if big else 1.0)
		st.set_material(sm)
		st.commit(am)
	# The quads turn to the camera in the shader: the culling box must hold them at any angle.
	var r := w * 2.6
	am.custom_aabb = AABB(Vector3(-r, y0 - (y1 - y0) * 0.5, -r), Vector3(r * 2.0, (y1 - y0) * 1.9, r * 2.0))
	_meshes[kind] = am
	return am
