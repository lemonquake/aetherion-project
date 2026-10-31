extends Node
## r14: item icons for the SmarTab, rendered from each item's own 3D model (the one drawn on the ground) the first
## time one is asked for: one small transparent render at a time in an off-screen viewport, cached for the match.
## Guns and attachments are drawn side on, muzzle to the right; everything else from three quarters above.

const SIZE := 192

var map = null
var cache := {}          # id -> Texture2D (null: no model)
var _queue: Array = []
var _vp: SubViewport
var _cam: Camera3D
var _mi: MeshInstance3D
var _pending := ""
var _frames := 0


func setup(m) -> void:
	map = m
	if DisplayServer.get_name() == "headless":
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.72)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	key.rotation = Vector3(-0.8, 0.6, 0.0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.9
	rim.light_color = Color(0.7, 0.85, 1.0)
	rim.rotation = Vector3(-0.3, PI + 0.4, 0.0)
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.01
	_cam.far = 20.0
	_vp.add_child(_cam)
	_mi = MeshInstance3D.new()
	_vp.add_child(_mi)


func icon(id: String) -> Texture2D:
	if cache.has(id):
		return cache[id]
	if _vp != null and id != _pending and not id in _queue:
		_queue.append(id)
	return null


func _process(_dt: float) -> void:
	if _vp == null:
		return
	if _pending != "":
		_frames -= 1
		if _frames > 0:
			return
		var img := _vp.get_texture().get_image()
		cache[_pending] = ImageTexture.create_from_image(img) if img and not img.is_empty() else null
		_pending = ""
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _queue.is_empty():
		return
	var id: String = _queue.pop_front()
	var md: Dictionary = map.item_visual(id) if map else {}
	if md.get("mesh") == null:
		cache[id] = null
		return
	_mi.mesh = md.mesh
	_mi.transform = md.get("xf", Transform3D())
	var aabb: AABB = _mi.transform * (md.mesh as Mesh).get_aabb()
	var c := aabb.get_center()
	var side := Defs.is_weapon(id) or Defs.is_attachment(id)
	var dir := Vector3(1.0, 0.08, 0.0).normalized() if side else Vector3(0.85, 0.75, 0.95).normalized()
	_cam.look_at_from_position(c + dir * 6.0, c, Vector3.UP)
	# Fit the bounds' corners seen from the camera into the square.
	var inv := _cam.global_transform.affine_inverse()
	var ext := 0.0
	for i in 8:
		var p := inv * aabb.get_endpoint(i)
		ext = maxf(ext, maxf(absf(p.x), absf(p.y)))
	_cam.size = maxf(ext * 2.12, 0.02)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_pending = id
	_frames = 2
