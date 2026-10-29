"""r6: SmarTab twice as big on screen (device, screen and so its text), held flat from behind so no fingertip comes
through the screen; the smallest SmarTab text sizes raised; text-size slider up to 2x (asked 2026-10-28)."""
from patchlib import Patch

p = Patch('game/src/player/viewmodel.gd')
p.rep('''var screen_size := Vector2(0.15, 0.15)''', '''var screen_size := Vector2(0.3, 0.3)    # doubled 2026-10-28: the text was too small to read''')
p.rep('''	bm.size = Vector3(0.19, 0.2, 0.022)''', '''	bm.size = Vector3(0.36, 0.38, 0.026)''')
p.rep('''	sm.size = Vector3(0.05, 0.16, 0.012)
	strap.mesh = sm
	strap.material_override = _mat(Color(0.12, 0.13, 0.1), 0.9)
	strap.position = Vector3(0, -0.02, -0.016)''', '''	sm.size = Vector3(0.08, 0.3, 0.012)
	strap.mesh = sm
	strap.material_override = _mat(Color(0.12, 0.13, 0.1), 0.9)
	strap.position = Vector3(0, -0.03, -0.019)''')
p.rep('''	tab_screen.position = Vector3(0, 0.005, 0.0115)''', '''	tab_screen.position = Vector3(0, 0.01, 0.0135)''')
p.rep('''	tab_root.position = Vector3(-0.07, lerpf(-0.42, -0.045, e), lerpf(-0.2, -0.3, e))''',
      '''	tab_root.position = Vector3(lerpf(-0.12, -0.035, e), lerpf(-0.62, -0.035, e), lerpf(-0.2, -0.31, e))''')
p.rep('''		arms.pose("L", tab_root.position + tab_root.basis * Vector3(0.0, -0.035, -0.03), tb2, POLE_L, FpArms.grip("tablet"))''',
      '''		# Flat against the back, low and a little left: the hand is hidden behind the device and its straight fingers
		# cannot curl round through the screen.
		arms.pose("L", tab_root.position + tab_root.basis * Vector3(-0.03, -0.08, -0.016), tb2, POLE_L, FpArms.grip("tablet"))''')
p.save()

p = Patch('game/src/player/fp_arms.gd')
p.rep('''	"tablet": [0.2, 0.35, 0.4, 0.45, 0.5],''', '''	"tablet": [0.12, 0.03, 0.03, 0.04, 0.05],''')
p.save()

p = Patch('game/src/ui/settings_ui.gd')
p.rep('''_slider("accessibility", "smartab_text_scale", 0.8, 1.5, 0.05, "%.2f")''', '''_slider("accessibility", "smartab_text_scale", 0.8, 2.0, 0.05, "%.2f")''')
p.save()

# Smallest text on the device: nothing under 19 px on its 720 px canvas.
p = Patch('game/src/ui/smartab_ui.gd')
p.rep('''func _t(text: String, pos: Vector2, size: int, col: Color = INK, font: Font = null) -> void:
	draw_string(font if font else _font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size * _scale), col)''',
      '''func _t(text: String, pos: Vector2, size: int, col: Color = INK, font: Font = null) -> void:
	draw_string(font if font else _font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxi(size, MIN_TEXT) * _scale), col)''')
p.rep('''const BG := Color(0.03, 0.05, 0.05)
''', '''const BG := Color(0.03, 0.05, 0.05)
const MIN_TEXT := 19   # px on the 720 px canvas: small print stays readable on the held device
''')
p.save()
