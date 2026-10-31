extends Node
## r14: loot on the ground that suits the local player (ammunition for their guns, attachments that improve them,
## better armour; items/loot_fit.gd) is outlined green, with a cel-shaded rim and a scan line running up it. Ground
## items are bare render instances (dynamics.gd), so the look is an overlay material on the instance: two extra
## draws per highlighted item, only near the player. Rechecked a few times a second (what suits you changes as you
## pick things up). Settings > Gameplay can turn it off.

const Fit := preload("res://src/items/loot_fit.gd")
const RANGE := 24.0

var world = null
var _mat: ShaderMaterial
var _lit: Dictionary = {}   # item id -> RID of the instance carrying the overlay
var _t := 0.0


func setup(w) -> void:
	world = w
	name = "LootHighlight"
	var cel := ShaderMaterial.new()
	cel.shader = load("res://src/fx/loot_cel.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/fx/loot_outline.gdshader")
	_mat.next_pass = cel


func lit_ids() -> Array:
	return _lit.keys()


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.3
	var ch = world.local_char if world else null
	var on = ch != null and is_instance_valid(ch) and ch.mode == Motor.GROUND and bool(Settings.get_value("gameplay", "loot_highlight")) \
		and world.map != null and world.map.dyn != null
	var want := {}
	if on:
		var dyn = world.map.dyn
		for id in dyn.items_near(ch.global_position, RANGE):
			var it: Dictionary = dyn.items[id]
			if it.get("inst", RID()).is_valid() and Fit.suitable(ch, it.entry):
				want[id] = it.inst
	for id in _lit.keys():
		if not want.has(id):
			var rid: RID = _lit[id]
			if world.map and world.map.dyn and world.map.dyn.items.has(id) and rid.is_valid():
				RenderingServer.instance_geometry_set_material_overlay(rid, RID())
			_lit.erase(id)
	for id in want:
		if not _lit.has(id):
			RenderingServer.instance_geometry_set_material_overlay(want[id], _mat.get_rid())
			_lit[id] = want[id]


func clear() -> void:
	for id in _lit:
		if world and world.map and world.map.dyn and world.map.dyn.items.has(id):
			RenderingServer.instance_geometry_set_material_overlay(_lit[id], RID())
	_lit.clear()
