extends Control
## The picture through a magnified scope while aiming: the eyepiece (dark beyond the lens, shading toward its rim)
## and the scope's reticle, centred where the weapon actually points (sway and recoil move the whole scope picture,
## as they move the bullets). The camera zoom itself comes from the player controller (field of view / zoom).
##
## Reticles are drawn in black with an illuminated centre, so the aim point stays visible in the dark. Every scope has
## its own (r14: twelve sights, no two alike). Two scopes also change the picture inside the lens: the night vision
## scope amplifies what little light there is into green phosphor, the thermal scope shows the scene as dull grey
## with people standing out white hot (it sees them through smoke and darkness, not through walls).

const Attach := preload("res://src/weapons/attachments.gd")

var ch = null
var cam: Camera3D = null
var world = null
var _shade: ColorRect
var _filter: ColorRect
var _marks: Control
var _center := Vector2.ZERO
var _radius := 100.0
var _style := ""
var _mode := ""                  # "", "night", "thermal"
var _alpha := 0.0
var _heat: Array = []            # thermal: [screen points of a body, radius px, warmth]
var _heat_t := 0
var _zoom_txt := ""

const INK := Color(0.03, 0.03, 0.03, 0.92)
const GLOW := Color(1.0, 0.16, 0.1, 0.95)
const GREEN := Color(0.35, 1.0, 0.3, 0.95)
const AMBER := Color(1.0, 0.62, 0.12, 0.95)
const WHITE := Color(0.95, 0.97, 1.0, 0.95)
const MODES := {"night": 1, "thermal": 2}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The image filter (night vision / thermal) reads what the camera drew, inside the lens only.
	_filter = ColorRect.new()
	_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsh := Shader.new()
	fsh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center = vec2(0.0);
uniform float radius = 100.0;
uniform vec2 size = vec2(1.0);
uniform int mode = 0;
uniform float alpha = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 p = UV * size;
	float inside = 1.0 - smoothstep(radius - 2.0, radius + 1.0, distance(p, center));
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float grain = hash(floor(p * 0.5) + vec2(TIME * 61.0, TIME * 37.0)) - 0.5;
	vec3 o = c;
	if (mode == 1) {
		// Image intensifier with automatic gain: the tube settles on the average light in the lens (about 40x in the
		// dark, little in daylight, so the picture is not one flat glare), soft-clipped; green phosphor, grain and a
		// faint scan pattern.
		vec2 cuv = center / size;
		float avg = 0.0;
		for (int i = 0; i < 5; i++) {
			vec2 o = vec2(float(i == 1) - float(i == 2), float(i == 3) - float(i == 4)) * radius * 0.45 / size;
			avg += dot(textureLod(screen_tex, cuv + o, 6.0).rgb, vec3(0.299, 0.587, 0.114));
		}
		avg /= 5.0;
		float gain = clamp(0.8 / max(avg, 0.002), 1.6, 40.0);
		float v = 1.0 - exp(-lum * gain);
		v = clamp(v + grain * 0.16, 0.0, 1.0);
		v *= 0.92 + 0.08 * sin(p.y * 1.6);
		o = vec3(0.18, 1.0, 0.32) * v + vec3(0.02, 0.07, 0.03);
	} else if (mode == 2) {
		// Thermal background: a flat, cool grey; slightly blurred (low sensor resolution).
		vec3 b = textureLod(screen_tex, SCREEN_UV, 2.0).rgb;
		float l2 = dot(b, vec3(0.299, 0.587, 0.114));
		float v = 0.16 + 0.32 * sqrt(clamp(l2, 0.0, 1.0)) + grain * 0.05;
		o = vec3(v);
	}
	COLOR = vec4(o, inside * alpha);
}"""
	var fm := ShaderMaterial.new()
	fm.shader = fsh
	_filter.material = fm
	_filter.visible = false
	add_child(_filter)
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec2 center = vec2(0.0);
uniform float radius = 100.0;
uniform float alpha = 0.0;
uniform vec2 size = vec2(1.0);
void fragment() {
	vec2 p = UV * size;
	float d = distance(p, center);
	float outside = smoothstep(radius - 2.0, radius + 1.5, d);
	float rim = smoothstep(radius * 0.72, radius, d) * 0.6;
	COLOR = vec4(0.0, 0.0, 0.0, max(outside, rim) * alpha);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_shade.material = m
	add_child(_shade)
	_marks = Control.new()
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	add_child(_marks)


func _process(_dt: float) -> void:
	var on = ch != null and is_instance_valid(ch) and cam != null and ch.wpn.scoped() and ch.mode == Motor.GROUND
	_alpha = clampf((float(ch.wpn.ads) - 0.62) / 0.3, 0.0, 1.0) if on else 0.0
	visible = _alpha > 0.0
	if not visible:
		return
	var off: Vector2 = ch.wpn.aim_offset_deg(Net.tick)
	var b: Basis = cam.global_transform.basis * Basis(Vector3.UP, deg_to_rad(-off.x)) * Basis(Vector3.RIGHT, deg_to_rad(off.y))
	var p := cam.global_position - b.z * 50.0
	var vs := get_viewport_rect().size
	_center = vs * 0.5 if cam.is_position_behind(p) else cam.unproject_position(p)
	_radius = vs.y * 0.46
	var sight: Dictionary = Attach.sight(ch.wpn.weapon())
	_style = str(sight.get("reticle", "duplex"))
	_mode = str(sight.get("filter", ""))
	_zoom_txt = ("%.1fx" % ch.wpn.zoom()) if sight.has("zoom_min") else ""
	for sm in [_shade.material, _filter.material]:
		(sm as ShaderMaterial).set_shader_parameter("center", _center)
		(sm as ShaderMaterial).set_shader_parameter("radius", _radius)
		(sm as ShaderMaterial).set_shader_parameter("alpha", _alpha)
		(sm as ShaderMaterial).set_shader_parameter("size", vs)
	_filter.visible = MODES.has(_mode)
	if _filter.visible:
		(_filter.material as ShaderMaterial).set_shader_parameter("mode", int(MODES[_mode]))
	if _mode == "thermal" and Time.get_ticks_msec() - _heat_t > 33:
		_heat_t = Time.get_ticks_msec()
		_find_heat()
	elif _mode != "thermal":
		_heat.clear()
	_marks.queue_redraw()


func _find_heat() -> void:
	## Living people in the lens, drawn as warm bodies: head, chest, hips, knees and feet joined by soft discs. A
	## body behind a wall is not drawn (thermal does not see through walls); one in the dark or smoke is.
	_heat.clear()
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	var eye := cam.global_position
	var px_per_m := get_viewport_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	if world == null:
		return
	for c in world.characters.values():
		_add_body(c, space, eye, px_per_m)


func _add_body(c, space: PhysicsDirectSpaceState3D, eye: Vector3, px_per_m: float) -> void:
	if c == ch or c.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
		return
	var base: Vector3 = c.get_global_transform_interpolated().origin
	var d := eye.distance_to(base)
	if d > 450.0:
		return
	var h: float = c.height() if c.has_method("height") else 1.75
	if c.mode == Motor.DOWNED:
		h = 0.5
	var chest := base + Vector3.UP * h * 0.72
	if cam.is_position_behind(chest):
		return
	var sp := cam.unproject_position(chest)
	if sp.distance_to(_center) > _radius + 60.0:
		return
	var q := PhysicsRayQueryParameters3D.create(eye, chest, Defs.PHYS_WORLD)
	if not space.intersect_ray(q).is_empty():
		var q2 := PhysicsRayQueryParameters3D.create(eye, base + Vector3.UP * h * 0.95, Defs.PHYS_WORLD)
		if not space.intersect_ray(q2).is_empty():
			return
	var pts := []
	for f in [0.93, 0.72, 0.5, 0.27, 0.05]:
		var wp = base + Vector3.UP * h * f
		pts.append(cam.unproject_position(wp))
	var r := maxf(0.17 * px_per_m / maxf(d, 0.5), 2.0)
	_heat.append([pts, r, 1.0 if c.mode == Motor.GROUND else 0.85])


func _line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var c := Color(col, col.a * _alpha)
	_marks.draw_line(_center + a, _center + b, c, w, true)


func _dot(p: Vector2, r: float, col: Color) -> void:
	_marks.draw_circle(_center + p, r, Color(col, col.a * _alpha))


func _ring(r: float, w: float, col: Color, a0: float = 0.0, a1: float = TAU) -> void:
	_marks.draw_arc(_center, r, a0, a1, 64, Color(col, col.a * _alpha), w, true)


func _text(t: String, p: Vector2, size: int, col: Color) -> void:
	_marks.draw_string(UITheme.font_mono, _center + p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, col.a * _alpha))


func _draw_heat() -> void:
	for hb in _heat:
		var pts: Array = hb[0]
		var r: float = hb[1]
		var w: float = hb[2]
		for i in pts.size():
			var p: Vector2 = pts[i]
			var rr := r * (0.85 if i == 0 else (1.25 if i == 1 else 1.0))
			# Soft edge: a halo ring, then the hot core.
			_marks.draw_circle(p, rr * 1.6, Color(0.85, 0.85, 0.85, 0.18 * w * _alpha))
			_marks.draw_circle(p, rr, Color(1.0, 1.0, 1.0, 0.92 * w * _alpha))
			if i > 0:
				_marks.draw_line(pts[i - 1], p, Color(1, 1, 1, 0.9 * w * _alpha), rr * 1.6, true)


func _draw_marks() -> void:
	var R := _radius
	var px := maxf(R / 300.0, 1.0)
	if _mode == "thermal":
		_draw_heat()
	match _style:
		"circle_dot":
			# 2x: open circle, three posts (none from above), lit dot.
			_ring(R * 0.12, 1.6 * px, INK)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
				_line(d * R * 0.12, d * R * 0.28, 1.6 * px, INK)
			_dot(Vector2.ZERO, 2.4 * px, GLOW)
		"chevron":
			# 3x: lit chevron, posts from three sides.
			var w := R * 0.045
			_line(Vector2(-w, w * 1.1), Vector2.ZERO, 2.4 * px, GLOW)
			_line(Vector2(w, w * 1.1), Vector2.ZERO, 2.4 * px, GLOW)
			for d in [Vector2.RIGHT, Vector2.LEFT]:
				_line(d * R * 0.22, d * R, 1.4 * px, INK)
			_line(Vector2(0, R * 0.22), Vector2(0, R), 1.4 * px, INK)
		"acog":
			# 4x: chevron over a bullet-drop ladder.
			var w2 := R * 0.05
			_line(Vector2(-w2, w2 * 1.2), Vector2.ZERO, 2.6 * px, GLOW)
			_line(Vector2(w2, w2 * 1.2), Vector2.ZERO, 2.6 * px, GLOW)
			_line(Vector2(0, w2 * 1.3), Vector2(0, R * 0.62), 1.2 * px, INK)
			for k in 5:
				var y := R * (0.14 + k * 0.1)
				var hw := R * (0.07 - k * 0.011)
				_line(Vector2(-hw, y), Vector2(hw, y), 1.3 * px, INK)
			for d in [Vector2.RIGHT, Vector2.LEFT]:
				_line(d * R * 0.3, d * R, 1.2 * px, INK)
		"mildot":
			# 6x: fine cross with mil dots.
			_line(Vector2(-R, 0), Vector2(R, 0), 1.0 * px, INK)
			_line(Vector2(0, -R), Vector2(0, R), 1.0 * px, INK)
			for k in range(1, 6):
				for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
					_dot(d * R * 0.09 * k, 2.2 * px, INK)
			_dot(Vector2.ZERO, 2.0 * px, GLOW)
		"horseshoe":
			# 1-4x variable: green horseshoe (open at the bottom) round a dot, fine cross between heavy posts.
			_ring(R * 0.075, 2.2 * px, GREEN, PI * 0.5 + 0.55, PI * 2.5 - 0.55)
			_dot(Vector2.ZERO, 2.2 * px, GREEN)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
				_line(d * R * 0.2, d * R * 0.55, 1.0 * px, INK)
				_line(d * R * 0.55, d * R, 4.5 * px, INK)
			_line(Vector2(0, -R * 0.55), Vector2(0, -R), 4.5 * px, INK)
			for k in range(1, 4):
				_line(Vector2(-R * 0.02, R * (0.2 + k * 0.09)), Vector2(R * 0.02, R * (0.2 + k * 0.09)), 1.0 * px, INK)
		"stadia":
			# Night vision 3x: red open cross with a centre dot and a stadia rangefinder curve lower left (a man
			# 1.8 m tall fits between the curve and the base line at the distance written beside it).
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				_line(d * R * 0.05, d * R * 0.42, 1.6 * px, GLOW)
			_dot(Vector2.ZERO, 2.0 * px, GLOW)
			var base_y := R * 0.55
			var pts := PackedVector2Array()
			for k in 13:
				var x := -R * 0.62 + k * R * 0.035
				var dist := 100.0 + k * 33.0
				var hh := 1.8 / dist * 1000.0 * (R / 300.0) * 0.55
				pts.append(_center + Vector2(x, base_y - hh))
			_marks.draw_polyline(pts, Color(GLOW, GLOW.a * _alpha), 1.4 * px, true)
			_line(Vector2(-R * 0.62, base_y), Vector2(-R * 0.18, base_y), 1.4 * px, GLOW)
			for k in [0, 6, 12]:
				_text(str(100 + k * 33), Vector2(-R * 0.62 + k * R * 0.035 - 8 * px, base_y + 16 * px), int(11 * px), GLOW)
		"thermal":
			# Thermal 4x: digital display: corner brackets, a gapped cross with a small box at the centre, readout.
			var g := R * 0.035
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				_line(d * g * 1.8, d * R * 0.38, 1.4 * px, WHITE)
			_marks.draw_rect(Rect2(_center - Vector2(g, g), Vector2(g, g) * 2.0), Color(GLOW, GLOW.a * _alpha), false, 1.6 * px)
			var bk := R * 0.62
			var bl := R * 0.12
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					_line(Vector2(sx * bk, sy * bk), Vector2(sx * (bk - bl), sy * bk), 1.6 * px, WHITE)
					_line(Vector2(sx * bk, sy * bk), Vector2(sx * bk, sy * (bk - bl)), 1.6 * px, WHITE)
			_text("WHT  4.0x", Vector2(-R * 0.6, -R * 0.68), int(13 * px), WHITE)
			_text("REC  ||||", Vector2(R * 0.28, -R * 0.68), int(13 * px), WHITE)
		"tree":
			# 15x: hairline cross with a holdover tree below: rows of dots widening with range, numbered every other.
			_line(Vector2(-R, 0), Vector2(R, 0), 0.9 * px, INK)
			_line(Vector2(0, -R), Vector2(0, R), 0.9 * px, INK)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP]:
				_line(d * R * 0.62, d * R, 4.0 * px, INK)
			for k in range(1, 9):
				var y := R * 0.06 * k
				var n := k + 1
				for j in range(-n, n + 1):
					if j == 0:
						continue
					_dot(Vector2(j * R * 0.028, y), 1.4 * px, INK)
				if k % 2 == 0:
					_text(str(k), Vector2(n * R * 0.028 + 6 * px, y + 4 * px), int(10 * px), INK)
			for k in range(1, 6):
				_line(Vector2(R * 0.04 * k, -R * 0.012), Vector2(R * 0.04 * k, R * 0.012), 0.9 * px, INK)
				_line(Vector2(-R * 0.04 * k, -R * 0.012), Vector2(-R * 0.04 * k, R * 0.012), 0.9 * px, INK)
			_dot(Vector2.ZERO, 1.6 * px, AMBER)
		_:
			# Duplex (8x): heavy posts outside, fine cross in the middle, lit centre.
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				_line(d * R * 0.32, d * R, 5.0 * px, INK)
				_line(d * R * 0.012, d * R * 0.32, 1.0 * px, INK)
			_dot(Vector2.ZERO, 1.6 * px, GLOW)
	if _zoom_txt != "":
		_text(_zoom_txt, Vector2(R * 0.62, R * 0.8), int(15 * px), GREEN)
