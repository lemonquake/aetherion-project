extends RefCounted
## Altitude render tiers for whatever camera is drawing the world (player, spectator, aircraft view).
##
## A jumper sees roofs, not rooms. Above the rooftops (LOW_AIR) the interiors leave the camera, local light
## shadows and ambient occlusion are switched off and mesh LODs coarsen; high up (HIGH_AIR, once the ground is out
## of the moon shadow's range) the moon shadow goes too. Back near the ground everything returns as the settings
## say. Thresholds have hysteresis so a canopy hovering at a boundary does not flicker between tiers.

enum { GROUND, LOW_AIR, HIGH_AIR }

const LOW_ENTER := 24.0
const LOW_LEAVE := 18.0
const HIGH_MARGIN := 12.0   # above the moon shadow distance
const LOD_SCALE := [1.0, 1.6, 3.0]
## Where exteriors hand over to the far blocks. On the ground, distant buildings are mostly hidden behind near ones;
## from the air every roof is in view and there is frame time to spare, so detail reaches further.
const EXT_RANGE := [220.0, 300.0, 300.0]

var mb = null
var tier := GROUND
var agl := 0.0
var _base_lod := -1.0
var _cam_id := 0
var _t := 0.0
var _ext_range := 220.0


func _init(map_builder) -> void:
	mb = map_builder
	Settings.changed.connect(_on_setting)


func _on_setting(section: String, key: String) -> void:
	if section == "graphics" and key == "view_distance":
		_cam_id = 0   # re-apply on the next update


func dispose() -> void:
	if Settings.changed.is_connected(_on_setting):
		Settings.changed.disconnect(_on_setting)
	mb = null


func update(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.1
	var vp: Viewport = mb.world.get_viewport() if mb.world and mb.world.is_inside_tree() else null
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam == null:
		return
	if _base_lod < 0.0:
		_base_lod = vp.mesh_lod_threshold
	var p := cam.global_position
	agl = p.y - maxf(float(mb.layout.ground_height(p.x, p.z)), float(mb.layout.WATER_Y))
	var high: float = mb.lighting.moon_shadow_distance() + HIGH_MARGIN
	var t := tier
	if agl > high:
		t = HIGH_AIR
	elif agl > LOW_ENTER or (tier != GROUND and agl > LOW_LEAVE):
		t = LOW_AIR if (tier != HIGH_AIR or agl < high - 8.0) else HIGH_AIR
	else:
		t = GROUND
	if t != tier or cam.get_instance_id() != _cam_id:
		tier = t
		_cam_id = cam.get_instance_id()
		_apply(cam, vp)


func _apply(cam: Camera3D, vp: Viewport) -> void:
	var inside := Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS
	if tier == GROUND:
		cam.cull_mask |= inside
	else:
		cam.cull_mask &= ~inside
	vp.mesh_lod_threshold = _base_lod * float(LOD_SCALE[tier])
	mb.lighting.set_air_tier(tier)
	var r: float = EXT_RANGE[tier]
	if tier == GROUND:
		r *= clampf(float(Settings.get_value("graphics", "view_distance")), 0.6, 1.3)
	if r != _ext_range:
		_ext_range = r
		for mi in mb.sink.ext_meshes:
			(mi as GeometryInstance3D).visibility_range_end = r
		for mi in mb.sink.far_meshes:
			(mi as GeometryInstance3D).visibility_range_begin = r
