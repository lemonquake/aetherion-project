"""Vaulting wired into movement, character state, prediction, the owner snapshot, the viewmodel and firing."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

m = Patch('game/src/player/motor.gd')
m.rep('''static func _ground(ch, cmd: Dictionary, dt: float, downed: bool) -> void:
	var btn := int(cmd.get("btn", 0))
''', '''static func _ground(ch, cmd: Dictionary, dt: float, downed: bool) -> void:
	var btn := int(cmd.get("btn", 0))
	if ch.vault_t >= 0.0:
		Vault.step(ch, dt)
		return
''')
m.rep('''		if (btn & B_JUMP) != 0 and (ch.prev_buttons & B_JUMP) == 0 and not ch.crouching and not downed \\
				and ch.jump_cooldown <= 0.0 and water < 0.6:
			v.y = Defs.move("jump_velocity")
			ch.jump_cooldown = 0.45
			ch.emit_motion_event("jump", 0.0)''', '''		var jump_press: bool = (btn & B_JUMP) != 0 and (ch.prev_buttons & B_JUMP) == 0 and not downed \\
				and ch.jump_cooldown <= 0.0 and water < 0.6
		var vault := Vault.find(ch) if jump_press and ch.held_prop_id < 0 else {}
		if not vault.is_empty():
			# Close to something low enough to get over or through: vault instead of jumping.
			Vault.start(ch, vault)
			ch.jump_cooldown = 0.3
			return
		if jump_press and not ch.crouching:
			v.y = Defs.move("jump_velocity")
			ch.jump_cooldown = 0.45
			ch.emit_motion_event("jump", 0.0)''')
m.save()

c = Patch('game/src/player/character.gd')
c.rep('''var chute_separation := Vector3.ZERO
''', '''var chute_separation := Vector3.ZERO
var vault_t := -1.0         # time into a vault, -1 when not vaulting (Vault)
var vault_d := 0.5          # its duration
var vault_a := Vector3.ZERO # start, over-the-top point, landing
var vault_m := Vector3.ZERO
var vault_b := Vector3.ZERO
var vault_h := 1.78         # body height while going over (fits a window opening)
''')
c.rep('''func height() -> float:
	if mode == Motor.DOWNED:
		return Defs.move("downed_height")
	return lerpf(Defs.move("stand_height"), Defs.move("crouch_height"), clampf(crouch, 0.0, 1.0))''', '''func height() -> float:
	if mode == Motor.DOWNED:
		return Defs.move("downed_height")
	var h := lerpf(Defs.move("stand_height"), Defs.move("crouch_height"), clampf(crouch, 0.0, 1.0))
	if vault_t >= 0.0:
		h = minf(h, vault_h)
	return h''')
c.rep('''		"jcd": jump_cooldown, "ff": freefall_t, "ct": chute_t, "cy": chute_yaw, "fl": flare_t, "pb": prev_buttons}''',
      '''		"jcd": jump_cooldown, "ff": freefall_t, "ct": chute_t, "cy": chute_yaw, "fl": flare_t, "pb": prev_buttons,
		"vt": vault_t, "vd": vault_d, "va": vault_a, "vm": vault_m, "vb": vault_b, "vh": vault_h}''')
c.rep('''	prev_buttons = s.get("pb", prev_buttons)
	apply_height()''', '''	prev_buttons = s.get("pb", prev_buttons)
	vault_t = s.get("vt", -1.0)
	vault_d = s.get("vd", vault_d)
	vault_a = s.get("va", vault_a)
	vault_m = s.get("vm", vault_m)
	vault_b = s.get("vb", vault_b)
	vault_h = s.get("vh", vault_h)
	apply_height()''')
c.save()

s = Patch('game/src/net/snapshot.gd')
s.rep('''		b.put_u32(int(s.pb))
		b.put_u32(me.compute_flags())''', '''		b.put_u32(int(s.pb))
		b.put_half(float(s.vt))
		if float(s.vt) >= 0.0:
			b.put_half(float(s.vd))
			_v3(b, s.va)
			_v3(b, s.vm)
			_v3(b, s.vb)
			b.put_half(float(s.vh))
		b.put_u32(me.compute_flags())''')
s.rep('''		s.pb = b.get_u32()
		s.flags = b.get_u32()''', '''		s.pb = b.get_u32()
		s.vt = b.get_half()
		if s.vt >= 0.0:
			s.vd = b.get_half()
			s.va = _gv3(b)
			s.vm = _gv3(b)
			s.vb = _gv3(b)
			s.vh = b.get_half()
		s.flags = b.get_u32()''')
s.save()

pc = Patch('game/src/player/player_controller.gd')
pc.rep('''		"jcd": float(own.jcd), "ff": float(own.ff), "ct": float(own.ct), "cy": float(own.cy), "fl": float(own.fl), "pb": int(own.pb)})''',
       '''		"jcd": float(own.jcd), "ff": float(own.ff), "ct": float(own.ct), "cy": float(own.cy), "fl": float(own.fl), "pb": int(own.pb),
		"vt": float(own.get("vt", -1.0)), "vd": float(own.get("vd", 0.5)), "va": own.get("va", Vector3.ZERO), "vm": own.get("vm", Vector3.ZERO),
		"vb": own.get("vb", Vector3.ZERO), "vh": float(own.get("vh", 1.78))})''')
pc.rep('''		or ch.held_prop_id >= 0 or ch.light.swapping() or (ch.flags & Character.F_BUSY) != 0''',
       '''		or ch.held_prop_id >= 0 or ch.light.swapping() or (ch.flags & Character.F_BUSY) != 0 or ch.vault_t >= 0.0''')
pc.save()

w = Patch('game/src/match/world.gd')
w.rep('''	ch.wpn.blocked = tab or ch.mode != Motor.GROUND or ch.water_depth() > 1.15 or ch.held_prop_id >= 0 \\
		or ch.light.swapping() or not ch.health.treatment.is_empty()''', '''	ch.wpn.blocked = tab or ch.mode != Motor.GROUND or ch.water_depth() > 1.15 or ch.held_prop_id >= 0 \\
		or ch.light.swapping() or not ch.health.treatment.is_empty() or ch.vault_t >= 0.0''')
w.save()

v = Patch('game/src/player/viewmodel.gd')
v.rep('''	_lower = move_toward(_lower, 1.0 if (_tab > 0.0 or busy or ch.held_prop_id >= 0 or ch.sprinting) else 0.0, dt / 0.25)''',
      '''	# Vaulting: the gun drops out of sight fast and comes back up after (only if it was out: the drawn weapon is
	# unchanged, this is just the hands being busy).
	var vaulting: bool = ch.vault_t >= 0.0
	_lower = move_toward(_lower, 1.0 if (_tab > 0.0 or busy or ch.held_prop_id >= 0 or ch.sprinting or vaulting) else 0.0, dt / (0.1 if vaulting else 0.25))''')
v.save()
