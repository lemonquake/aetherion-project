extends Control
## The picture through a magnified scope while aiming: the eyepiece (dark beyond the lens, shading toward its rim)
## and the scope's reticle, centred where the weapon actually points (sway and recoil move the whole scope picture,
## as they move the bullets). The camera zoom itself comes from the player controller (field of view / zoom).
##
## Reticles are drawn in black with an illuminated red centre, so the aim point stays visible in the dark.

const Attach := preload("res://src/weapons/attachments.gd")

var ch = null
var cam: Camera3D = null
var _shade: ColorRect
var _marks: Control
var _center := Vector2.ZERO
var _radius := 100.0
var _style := ""
var _alpha := 0.0

const INK := Color(0.03, 0.03, 0.03, 0.92)
const GLOW := Color(1.0, 0.16, 0.1, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_style = str(Attach.sight(ch.wpn.weapon()).get("reticle", "duplex"))
	var m := _shade.material as ShaderMaterial
	m.set_shader_parameter("center", _center)
	m.set_shader_parameter("radius", _radius)
	m.set_shader_parameter("alpha", _alpha)
	m.set_shader_parameter("size", vs)
	_marks.queue_redraw()


func _line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var c := Color(col, col.a * _alpha)
	_marks.draw_line(_center + a, _center + b, c, w, true)


func _dot(p: Vector2, r: float, col: Color) -> void:
	_marks.draw_circle(_center + p, r, Color(col, col.a * _alpha))


func _draw_marks() -> void:
	var R := _radius
	var px := maxf(R / 300.0, 1.0)
	match _style:
		"circle_dot":
			_marks.draw_arc(_center, R * 0.12, 0.0, TAU, 64, Color(INK, INK.a * _alpha), 1.6 * px, true)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
				_line(d * R * 0.12, d * R * 0.28, 1.6 * px, INK)
			_dot(Vector2.ZERO, 2.4 * px, GLOW)
		"chevron":
			var w := R * 0.045
			_line(Vector2(-w, w * 1.1), Vector2.ZERO, 2.4 * px, GLOW)
			_line(Vector2(w, w * 1.1), Vector2.ZERO, 2.4 * px, GLOW)
			for d in [Vector2.RIGHT, Vector2.LEFT]:
				_line(d * R * 0.22, d * R, 1.4 * px, INK)
			_line(Vector2(0, R * 0.22), Vector2(0, R), 1.4 * px, INK)
		"acog":
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
			_line(Vector2(-R, 0), Vector2(R, 0), 1.0 * px, INK)
			_line(Vector2(0, -R), Vector2(0, R), 1.0 * px, INK)
			for k in range(1, 6):
				for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
					_dot(d * R * 0.09 * k, 2.2 * px, INK)
			_dot(Vector2.ZERO, 2.0 * px, GLOW)
		_:
			# Duplex: heavy posts outside, fine cross in the middle, lit centre.
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				_line(d * R * 0.32, d * R, 5.0 * px, INK)
				_line(d * R * 0.012, d * R * 0.32, 1.0 * px, INK)
			_dot(Vector2.ZERO, 1.6 * px, GLOW)
