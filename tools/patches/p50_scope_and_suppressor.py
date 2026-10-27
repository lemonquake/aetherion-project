"""Loot run (2026-10-26): scope view in the HUD, red-dot and holographic reticles while aiming through 1x sights,
suppressed and flash-hidden shots (sound, muzzle flash, how far the ambience reacts).

    python -I tools/patches/p50_scope_and_suppressor.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class Patch:
    def __init__(self, rel):
        self.p = os.path.join(ROOT, rel)
        raw = open(self.p, 'rb').read().decode()
        self.crlf = '\r\n' in raw
        self.s = raw.replace('\r\n', '\n')

    def rep(self, a, b, cnt=1):
        assert self.s.count(a) == cnt, (self.p, a[:90], self.s.count(a))
        self.s = self.s.replace(a, b)

    def save(self):
        open(self.p, 'wb').write((self.s.replace('\n', '\r\n') if self.crlf else self.s).encode())


h = Patch('game/src/ui/hud.gd')
h.rep('''var reticle: Control
''', '''var reticle: Control
var scope: Control
''')
h.rep('''	reticle = preload("res://src/ui/reticle.gd").new()
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)''', '''	scope = preload("res://src/ui/scope_overlay.gd").new()
	scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope.visible = false
	root.add_child(scope)
	reticle = preload("res://src/ui/reticle.gd").new()
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)''')
h.rep('''	reticle.set("ch", ch)
	reticle.set("cam", world.controller.cam if world.controller else null)''', '''	reticle.set("ch", ch)
	reticle.set("cam", world.controller.cam if world.controller else null)
	scope.set("ch", ch if not tab_held else null)
	scope.set("cam", world.controller.cam if world.controller else null)''')
h.save()

r = Patch('game/src/ui/reticle.gd')
r.rep('''extends Control''', '''extends Control

const Attach := preload("res://src/weapons/attachments.gd")''')
r.rep('''	if ch.wpn.ads > 0.7 and ch.wpn.zoom() > 2.0:
		# Magnified optic: a fine cross like the scope reticle, no ticks.
		draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), col, 1.0)
		draw_line(c + Vector2(0, -14), c + Vector2(0, 14), col, 1.0)
		return''', '''	if ch.wpn.scoped() and ch.wpn.ads > 0.6:
		return  # the scope view draws its own reticle
	var sight: Dictionary = Attach.sight(ch.wpn.weapon())
	if not sight.is_empty() and ch.wpn.ads > 0.6:
		# Red dot or holographic ring projected in the sight window.
		var lit := Color(1.0, 0.15, 0.1, clampf((ch.wpn.ads - 0.6) / 0.3, 0.0, 1.0) * 0.95)
		var k := get_viewport_rect().size.y / 900.0
		if str(sight.get("reticle", "dot")) == "holo":
			draw_arc(c, 17.0 * k, 0.0, TAU, 48, lit, 1.6 * k, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * 17.0 * k, c + d * 21.0 * k, lit, 1.6 * k, true)
		draw_circle(c, 1.9 * k, lit)
		return''')
r.save()

e = Patch('game/src/fx/effects.gd')
e.rep('''func shot(ch, origin: Vector3, dir: Vector3, velocity: float, ammo: String, weapon: String, seed: int, local: bool = false) -> void:
	var d := Defs.weapon(weapon)
	var a := Defs.ammo(ammo)
	var flash_pos := origin
	if local and world.controller and world.controller.vm:
		flash_pos = world.controller.vm.muzzle_position()
	_flash(flash_pos)
	if world.ambience:
		world.ambience.on_loud(origin, float(d.get("loudness", 600)) * 0.25)
	var snd := "shot_" + str(d.get("sound", "pistol_9"))''', '''func shot(ch, origin: Vector3, dir: Vector3, velocity: float, ammo: String, weapon: String, seed: int, local: bool = false) -> void:
	var d := Defs.weapon(weapon)
	var a := Defs.ammo(ammo)
	# Muzzle devices on the shooter's gun (own gun: from the inventory; others: the replicated mask).
	var w: Dictionary = {}
	if ch != null and is_instance_valid(ch):
		w = ch.wpn.weapon() if local or ch.is_local else {"att": Attach.from_bitmask(ch.weapon_att)}
	var flash_pos := origin
	if local and world.controller and world.controller.vm:
		flash_pos = world.controller.vm.muzzle_position()
	_flash(flash_pos, Attach.mult(w, "flash_mult"))
	if world.ambience:
		world.ambience.on_loud(origin, float(d.get("loudness", 600)) * 0.25 * Attach.mult(w, "loudness_mult"))
	var snd := "shot_" + str(d.get("sound", "pistol_9"))
	if Attach.flag(w, "suppressed") and SoundSys.defs.has(snd + "_sup"):
		snd += "_sup"''')
e.rep('''func _flash(p: Vector3) -> void:
	var reduce := bool(Settings.get_value("accessibility", "reduce_flashes"))
	for f in _flash_pool:
		if f.t <= 0.0:
			var l: OmniLight3D = f.light
			l.global_position = p
			l.light_energy = 2.2 if reduce else 5.0''', '''func _flash(p: Vector3, mult: float = 1.0) -> void:
	if mult < 0.15:
		return  # suppressed: no flash worth lighting a room with
	var reduce := bool(Settings.get_value("accessibility", "reduce_flashes"))
	for f in _flash_pool:
		if f.t <= 0.0:
			var l: OmniLight3D = f.light
			l.global_position = p
			l.light_energy = (2.2 if reduce else 5.0) * minf(mult, 1.3)''')
if 'const Attach := preload' not in e.s:
    e.rep('''extends Node''', '''extends Node

const Attach := preload("res://src/weapons/attachments.gd")''')
e.save()
print('ok')
