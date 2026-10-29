extends Control
## Menu backdrop: key art rendered from the game's own map (assets/ui/*_bg.jpg), drifting slowly, darkened toward
## the side the menu sits on, with a vignette and grain.

const SHADE := """
shader_type canvas_item;
uniform float side = 0.0;   // 0: darken the left, 1: the right, 0.5: both evenly
uniform float strength = 0.8;
void fragment() {
	float l = smoothstep(0.62, 0.0, UV.x) * (1.0 - side);
	float r = smoothstep(0.38, 1.0, UV.x) * side;
	float top = smoothstep(0.16, 0.0, UV.y) * 0.55;
	float bot = smoothstep(0.78, 1.0, UV.y) * 0.75;
	float v = distance(UV, vec2(0.55, 0.45));
	float a = clamp(max(max(l, r), max(top, bot)) * strength + smoothstep(0.45, 0.95, v) * 0.5, 0.0, 0.94);
	COLOR = vec4(0.015, 0.018, 0.024, a);
}
"""

var image := "menu_bg"
var side := 0.0
var _art: TextureRect
var _t := 0.0


func _init(img: String = "menu_bg", shade_side: float = 0.0) -> void:
	image = img
	side = shade_side


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var base := ColorRect.new()
	base.color = Color(0.02, 0.022, 0.03)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_art = TextureRect.new()
	var path := "res://assets/ui/%s.jpg" % image
	if ResourceLoader.exists(path):
		_art.texture = load(path)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("side", side)
	shade.material = m
	add_child(shade)
	UITheme.grain(self, 0.045)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	# A little larger than the screen, so it can drift without showing an edge.
	_art.size = size * 1.06
	_art.position = -size * 0.03


func _process(dt: float) -> void:
	_t += dt
	_art.position = -size * 0.03 + Vector2(sin(_t * 0.05) * size.x * 0.018, cos(_t * 0.037) * size.y * 0.012)
