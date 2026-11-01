"""r24: no filters over the scope picture. The thermal 4x showed the lens as flat grey with people as white blobs and the
night vision 3x as green phosphor with grain (the user: "white filters", "annoying filter effects"; enemies hard to
see). Now every scope shows the real picture: thermal keeps a soft warm outline on people (it still finds them in
smoke and darkness, never through walls), night vision brightens the dark in natural colour. The dark rim inside
every lens is thinner."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p24_util import patch

G = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'src')

patch(os.path.join(G, 'ui', 'scope_overlay.gd'), [
    ('''## its own (r14: twelve sights, no two alike). Two scopes also change the picture inside the lens: the night vision
## scope amplifies what little light there is into green phosphor, the thermal scope shows the scene as dull grey
## with people standing out white hot (it sees them through smoke and darkness, not through walls).
''', '''## its own (r14: twelve sights, no two alike). Two scopes also help inside the lens, over the real picture (r24: no
## grey, green or grain filters): the night vision scope brightens the dark in natural colour, the thermal scope
## outlines people with a soft warm glow (it finds them through smoke and darkness, not through walls).
'''),
    ('''	vec3 o = c;
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
	COLOR = vec4(o, inside * alpha);''', '''	vec3 o = c;
	if (mode == 1) {
		// Night vision (r24): the real picture in its own colours, brightened by an automatic gain that settles on
		// the average light in the lens (up to 5x in the dark, none in daylight), soft-clipped so lamps do not glare.
		vec2 cuv = center / size;
		float avg = 0.0;
		for (int i = 0; i < 5; i++) {
			vec2 d = vec2(float(i == 1) - float(i == 2), float(i == 3) - float(i == 4)) * radius * 0.45 / size;
			avg += dot(textureLod(screen_tex, cuv + d, 6.0).rgb, vec3(0.299, 0.587, 0.114));
		}
		avg /= 5.0;
		float gain = clamp(0.3 / max(avg, 0.002), 1.0, 5.0);
		o = vec3(1.0) - exp(-c * gain * 1.15);
	}
	COLOR = vec4(o, inside * alpha * (mode == 1 ? 1.0 : 0.0));'''),
    ('''	float rim = smoothstep(radius * 0.72, radius, d) * 0.6;''', '''	float rim = smoothstep(radius * 0.86, radius, d) * 0.35;'''),
    ('''	_filter.visible = MODES.has(_mode)
''', '''	_filter.visible = _mode == "night"   # (r24) thermal draws its outlines only, over the real picture
'''),
    ('''func _draw_heat() -> void:
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
''', '''const HEAT := Color(1.0, 0.52, 0.16)


func _draw_heat() -> void:
	## (r24) A warm outline round each person in the lens, the person still visible inside it (it was a white blob).
	for hb in _heat:
		var pts: Array = hb[0]
		var r: float = hb[1]
		var w: float = hb[2]
		var head: Vector2 = pts[0]
		var feet: Vector2 = pts[pts.size() - 1]
		var hh := maxf(feet.y - head.y, r * 4.0)
		var box := Rect2(Vector2(minf(head.x, feet.x) - hh * 0.26, head.y - r * 1.4), Vector2(absf(head.x - feet.x) + hh * 0.52, hh + r * 2.0))
		_marks.draw_rect(box.grow(2.0), Color(HEAT, 0.12 * w * _alpha), true)
		_marks.draw_rect(box, Color(HEAT, 0.95 * w * _alpha), false, maxf(1.5, r * 0.18))
		_marks.draw_circle(head, maxf(r * 0.35, 2.0), Color(HEAT, 0.9 * w * _alpha))
'''),
    ('''			_text("WHT  4.0x", Vector2(-R * 0.6, -R * 0.68), int(13 * px), WHITE)''', '''			_text("HEAT  4.0x", Vector2(-R * 0.6, -R * 0.68), int(13 * px), WHITE)'''),
])
