extends Node3D
## (r23) Saves Malasugue Mall as the game builds it, for the mall's map editor (editor/malasugue_mall_editor.tscn):
## every mesh of the building and its plaza, grouped by floor (Level1 .. Level5, Plaza) so the editor can hide the
## floors above the one being edited, plus a box for every door. Run with a window (needs the GPU) after any change to
## the mall's builder:
##   godot --path game res://tools/mall_preview_export.tscn -- [--out=res://editor/malasugue_mall/mall_preview.scn]
## The game never loads this file; it is only what the editor shows.

const MapBuilder := preload("res://src/world/map_builder.gd")
const OUT := "res://editor/malasugue_mall/mall_preview.scn"

var is_server := false
var match_info := {}
var characters := {}
var map = null


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	var out := str(args.get("out", OUT))
	var t0 := Time.get_ticks_msec()
	map = MapBuilder.new()
	map.build(self, 1729, 1, {"map": "malasugue_mall"})
	print("[mallexport] built in %d ms" % (Time.get_ticks_msec() - t0))
	await get_tree().process_frame
	var L = map.layout
	var root := Node3D.new()
	root.name = "MallPreview"
	var groups := {}
	for g in ["Plaza", "Level1", "Level2", "Level3", "Level4", "Level5", "Ceilings"]:
		var n := Node3D.new()
		n.name = g
		root.add_child(n)
		n.owner = root
		groups[g] = n
	var tris := 0
	var kept := 0
	var dropped_tex := 0
	var stack: Array = [map.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if not (node is GeometryInstance3D) or not (node is MeshInstance3D or node is MultiMeshInstance3D):
			continue
		var gi := node as GeometryInstance3D
		if not gi.visible:
			continue
		var aabb: AABB = gi.global_transform * gi.get_aabb()
		var c3 := aabb.get_center()
		# the building and its plaza only (the city round it is scenery)
		if absf(c3.x) > float(L.SITE_X) + 2.0 or absf(c3.z) > float(L.SITE_Z) + 2.0:
			continue
		var gname := "Plaza"
		if absf(c3.x) <= float(L.MX) + 1.0 and absf(c3.z) <= float(L.MZ) + 1.0 and aabb.size.y < 30.0:
			gname = "Level%d" % (clampi(int(floor((aabb.position.y + 0.6) / float(L.FH))), 0, 4) + 1)
			# the suspended ceilings (thin and flat, near the top of a storey) hide the floor from above: their own group
			var above := fposmod(c3.y, float(L.FH))
			if aabb.size.y < 0.6 and above > 3.6 and above < 4.9:
				gname = "Ceilings"
		var copy: GeometryInstance3D = gi.duplicate(0)
		copy.transform = gi.global_transform
		copy.visibility_range_end = 0.0
		copy.visibility_range_begin = 0.0
		for ch in copy.get_children():
			copy.remove_child(ch)
			ch.free()
		if copy is MeshInstance3D and (copy as MeshInstance3D).mesh != null:
			var m: Mesh = (copy as MeshInstance3D).mesh
			for s in m.get_surface_count():
				tris += m.surface_get_array_index_len(s) / 3 if m is ArrayMesh else 0
			dropped_tex += _strip_generated(copy as MeshInstance3D)
		(groups[gname] as Node3D).add_child(copy)
		copy.owner = root
		kept += 1
	# doors: a box each (the game makes them on the physics server, not as nodes)
	var doors := Node3D.new()
	doors.name = "Doors"
	root.add_child(doors)
	doors.owner = root
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.2, 0.75, 0.9, 0.55)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for d in map.dyn.doors:
		var dn = d.get("node")
		if dn == null or not (dn.get("base") is Transform3D):
			continue
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(float(dn.w), float(dn.h), 0.06)
		bm.material = dmat
		mi.mesh = bm
		mi.transform = (dn.base as Transform3D) * Transform3D(Basis(), Vector3(float(dn.w) * 0.5, float(dn.h) * 0.5, 0.0))
		doors.add_child(mi)
		mi.owner = root
	var ps := PackedScene.new()
	var err := ps.pack(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var err2 := ResourceSaver.save(ps, out, ResourceSaver.FLAG_COMPRESS)
	print("[mallexport] %d meshes (%d triangles), %d doors, %d generated textures left out -> %s (pack %d, save %d)" % [kept, tris,
		map.dyn.doors.size(), dropped_tex, out, err, err2])
	get_tree().quit()


func _strip_generated(mi: MeshInstance3D) -> int:
	## Textures made in code (no file behind them) would be stored inside the scene: left out (their colour stays).
	var n := 0
	var m: Mesh = mi.mesh
	for s in m.get_surface_count():
		var mat := mi.get_surface_override_material(s)
		if mat == null:
			mat = m.surface_get_material(s)
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS,
					BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_ORM, BaseMaterial3D.TEXTURE_METALLIC]:
				var t: Texture2D = bm.get_texture(slot)
				if t != null and t.resource_path == "":
					bm = bm.duplicate()
					bm.set_texture(slot, null)
					mi.set_surface_override_material(s, bm)
					n += 1
	return n
