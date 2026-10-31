extends Control
## r13: what the player sees when they die, over the camera on their body (PlayerController.on_death_report):
## the screen drains to grey with a dark red edge, and a card slams in: who killed them (in their team colour), with
## what, from how far, and where the last hit landed. A headshot gets its own badge: a head with a crosshair on it,
## blood spattered round it and dripping, and "Headshot" in red, with blood thrown across the screen edges.
## Causes with no killer (the field, a fall, bleeding out) get a plain line instead.

const SHOW_S := 6.0

var _t := -1.0
var _info: Dictionary = {}
var _post: ColorRect
var _card: Control
var _badge: Control
var _name: Label
var _by: Label
var _detail: Label
var _hs_label: Label
var _rng := RandomNumberGenerator.new()
var _splats: Array = []   # [pos (unit), radius, drip length] for the badge


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_post = ColorRect.new()
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform float blood = 0.0;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 grey = mix(vec3(g), c, 0.18) * vec3(1.04, 0.96, 0.94);
	vec2 q = UV - 0.5;
	float d = length(q * vec2(1.7, 1.0));
	float vig = smoothstep(0.35, 0.95, d);
	vec3 col = mix(c, grey, amount);
	col = mix(col, col * vec3(0.45, 0.08, 0.06), vig * amount * 0.85);
	// Blood thrown across the edges (headshots): round splats with ragged rims round the border, a drip under the
	// big ones, and fine droplets (aspect-corrected, so they stay round).
	vec2 asp = vec2(1.7778, 1.0);
	float b = 0.0;
	for (int i = 0; i < 26; i++) {
		float fi = float(i) + seed;
		vec2 c = vec2(hash(vec2(fi, 1.0)), hash(vec2(fi, 7.0)));
		if (length((c - 0.5) * vec2(1.7, 1.0)) < 0.52) {
			continue;
		}
		float r = mix(0.02, 0.085, hash(vec2(fi, 13.0)));
		vec2 dv = (UV - c) * asp;
		float ang = atan(dv.y, dv.x);
		float rr = r * (0.86 + 0.08 * sin(ang * 3.0 + fi) + 0.05 * sin(ang * 7.0 + fi * 1.7) + 0.03 * sin(ang * 13.0 + fi * 0.6));
		b = max(b, 1.0 - smoothstep(rr * 0.9, rr, length(dv)));
		if (r > 0.06) {
			float run = r * (2.0 + 3.0 * hash(vec2(fi, 19.0)));
			b = max(b, (1.0 - smoothstep(0.003, 0.006, abs(dv.x - r * 0.3))) * step(0.0, dv.y) * (1.0 - smoothstep(run * 0.8, run, dv.y)));
		}
	}
	for (int j = 0; j < 30; j++) {
		float fj = float(j) + seed * 1.7;
		vec2 c2 = vec2(hash(vec2(fj, 23.0)), hash(vec2(fj, 29.0)));
		if (length((c2 - 0.5) * vec2(1.7, 1.0)) < 0.38) {
			continue;
		}
		float r2 = mix(0.003, 0.011, hash(vec2(fj, 31.0)));
		b = max(b, 1.0 - smoothstep(r2 * 0.8, r2, length((UV - c2) * asp)));
	}
	b *= blood;
	col = mix(col, vec3(0.34, 0.015, 0.012) * (0.85 + 0.3 * hash(floor(UV * 300.0))), b * 0.88);
	COLOR = vec4(col, 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_post.material = mat
	add_child(_post)
	# The card, low in the middle of the screen.
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.size = Vector2(920, 250)
	_card.pivot_offset = Vector2(460, 125)
	add_child(_card)
	_badge = Control.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.position = Vector2(230, -150)
	_badge.size = Vector2(320, 150)
	_badge.draw.connect(_draw_badge)
	_card.add_child(_badge)
	_hs_label = _lbl("Headshot", 64, Color(0.95, 0.12, 0.08), UITheme.font_condensed)
	_hs_label.position = Vector2(400, -112)
	_hs_label.add_theme_constant_override("outline_size", 12)
	_hs_label.add_theme_color_override("font_outline_color", Color(0.08, 0, 0, 0.95))
	_card.add_child(_hs_label)
	_by = _lbl("Killed by", 26, Color(0.85, 0.82, 0.8))
	_by.position = Vector2(0, 0)
	_by.size = Vector2(920, 34)
	_by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_by)
	_name = _lbl("", 72, Color.WHITE, UITheme.font_condensed)
	_name.position = Vector2(0, 30)
	_name.size = Vector2(920, 90)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_constant_override("outline_size", 12)
	_card.add_child(_name)
	_detail = _lbl("", 28, Color(0.92, 0.9, 0.88))
	_detail.position = Vector2(0, 124)
	_detail.size = Vector2(920, 40)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_detail)


func _lbl(text: String, size: int, col: Color, font: Font = null) -> Label:
	var l := UITheme.label(text, size, col, font if font else UITheme.font_semibold)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func show_report(info: Dictionary) -> void:
	_info = info
	_t = 0.0
	visible = true
	_rng.seed = hash(str(info.get("killer", "")) + str(info.get("dist", 0.0)))
	var hs := bool(info.get("headshot", false))
	var killer := str(info.get("killer", ""))
	if killer != "":
		_by.text = "Killed by"
		_name.text = killer
		var team := int(info.get("killer_team", -1))
		_name.add_theme_color_override("font_color", UITheme.TEAM_COLORS[team % UITheme.TEAM_COLORS.size()] if team >= 0 else Color.WHITE)
		var bits := []
		if str(info.get("weapon", "")) != "":
			bits.append(str(info.weapon))
		if float(info.get("dist", 0.0)) > 0.5:
			bits.append("%d m" % int(round(float(info.dist))))
		if str(info.get("part_name", "")) != "":
			bits.append(("shot through %s" if hs else "last hit in %s") % str(info.part_name))
		_detail.text = "  ·  ".join(bits)
	else:
		_by.text = "You died"
		_name.text = {"field": "Crushed by the field", "fall": "The fall killed you", "bleeding": "You bled out",
			"explosion": "Caught in the blast", "drown": "You drowned"}.get(str(info.get("cause", "")), "You died")
		_name.add_theme_color_override("font_color", Color(0.95, 0.9, 0.86))
		_detail.text = ""
	_badge.visible = hs
	_hs_label.visible = hs
	_splats.clear()
	if hs:
		for i in 16:
			var a := _rng.randf_range(-0.9, 0.9) + (0.0 if i % 3 else PI)
			var r := _rng.randf_range(0.25, 1.0)
			_splats.append([Vector2(cos(a), sin(a)) * r * Vector2(1.25, 0.8), _rng.randf_range(2.5, 9.0) * (1.4 - r), _rng.randf_range(0.0, 28.0) if _rng.randf() < 0.35 else 0.0])
	var m := _post.material as ShaderMaterial
	m.set_shader_parameter("seed", _rng.randf_range(0.0, 100.0))
	_badge.queue_redraw()


func hide_report() -> void:
	_t = -1.0
	visible = false


func _process(dt: float) -> void:
	if _t < 0.0:
		return
	_t += dt
	var hs := bool(_info.get("headshot", false))
	var m := _post.material as ShaderMaterial
	var fade_out := 1.0 - smoothstep(SHOW_S - 0.8, SHOW_S, _t)
	m.set_shader_parameter("amount", smoothstep(0.0, 0.6, _t) * fade_out)
	m.set_shader_parameter("blood", (smoothstep(0.05, 0.25, _t) * fade_out) if hs else 0.0)
	# The card slams in (big and fast, a small overshoot), shakes for a moment, then settles.
	var k := clampf((_t - 0.15) / 0.22, 0.0, 1.0)
	var s := lerpf(1.9, 1.0, 1.0 - pow(1.0 - k, 3.0)) - 0.06 * sin(clampf((_t - 0.37) / 0.25, 0.0, 1.0) * PI)
	_card.scale = Vector2.ONE * s
	var shake := maxf(0.0, 1.0 - (_t - 0.37) / 0.35) if _t > 0.37 else 0.0
	_card.position = Vector2(size.x * 0.5 - 460.0, size.y - 330.0) + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 9.0 * shake
	_card.modulate.a = k * fade_out
	_badge.queue_redraw()
	if _t > SHOW_S:
		hide_report()


func _draw_badge() -> void:
	## The headshot badge: a head and shoulders, a crosshair on the head, blood bursting from it and dripping.
	var c := Vector2(80, 78)
	var grow := clampf((_t - 0.3) / 0.25, 0.0, 1.0)
	var dark := Color(0.1, 0.1, 0.11, 0.92)
	var rim := Color(0.95, 0.95, 0.92, 0.95)
	# Shoulders and neck, then the head.
	_badge.draw_rect(Rect2(c + Vector2(-46, 40), Vector2(92, 34)), dark)
	_badge.draw_rect(Rect2(c + Vector2(-11, 22), Vector2(22, 22)), dark)
	_badge.draw_circle(c, 30.0, dark)
	_badge.draw_arc(c, 30.0, 0.0, TAU, 40, rim, 3.0, true)
	_badge.draw_arc(c + Vector2(0, 52), 46.0, PI * 1.08, PI * 1.92, 24, rim, 3.0, true)
	# Blood bursting out of the head.
	var blood := Color(0.78, 0.04, 0.03, 0.95)
	for sp in _splats:
		var p: Vector2 = c + (sp[0] as Vector2) * 58.0 * grow
		_badge.draw_circle(p, float(sp[1]) * grow, blood)
		if float(sp[2]) > 0.0:
			var l: float = float(sp[2]) * clampf((_t - 0.5) / 1.4, 0.0, 1.0)
			_badge.draw_line(p, p + Vector2(0, l), blood, maxf(float(sp[1]) * 0.45, 1.5), true)
			_badge.draw_circle(p + Vector2(0, l), maxf(float(sp[1]) * 0.35, 1.2), blood)
	_badge.draw_circle(c + Vector2(6, -4), 9.0 * grow, Color(0.6, 0.02, 0.02))
	# The crosshair on the head.
	var red := Color(1.0, 0.18, 0.12)
	_badge.draw_arc(c, 40.0, 0.0, TAU, 48, red, 4.0, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_badge.draw_line(c + d * 30.0, c + d * 54.0, red, 4.0, true)
	_badge.draw_circle(c, 4.0, red)
