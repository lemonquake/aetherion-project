"""r6: reload and action sounds as timed cues of the r5 hand animations (weapon_anims.cues), played by the local
viewmodel and, for everyone else's guns, scheduled on each client from one event per reload step or action cycle."""
from patchlib import Patch

# ------------------------------------------------------------------ weapon_anims.gd: the cue table
p = Patch('game/src/player/weapon_anims.gd')
if 'const CUES' not in p.s:
  p.rep('''const POUCH := Vector3(-0.3, -0.62, -0.2)   # view space, below the screen: where spare magazines and shells come from
''', '''const POUCH := Vector3(-0.3, -0.62, -0.2)   # view space, below the screen: where spare magazines and shells come from

## Every sound a clip can ask for (sounds.json ids; tools/build_r6_sounds.py makes them).
const CUES := ["mag_out", "mag_in", "mag_out_pistol", "mag_in_pistol", "mag_pouch", "charge_back", "charge_release",
	"slide_back", "slide_release", "bolt_up", "bolt_back", "bolt_fwd", "bolt_down", "clip_in", "pump_back", "pump_fwd",
	"shell_insert", "cylinder_open", "cylinder_close", "round_insert", "cylinder_click", "break_open", "break_close",
	"shell_eject", "pipe_slide", "weapon_draw"]
''')
  p.rep('''# ------------------------------------------------------------------ evaluation
''', '''static func cues(kind: String, empty: bool, wid: String = "") -> Array:
	## The sounds of a clip as [normalised time, sound id], timed to the keys of clip() above (the hand reaches the
	## part, the part moves): played over the same length of time as the clip, they land on the motion.
	match kind:
		"mag_rifle":
			if empty:
				return [[0.17, "mag_out"], [0.33, "mag_pouch"], [0.555, "mag_in"], [0.72, "charge_back"], [0.775, "charge_release"]]
			return [[0.2, "mag_out"], [0.41, "mag_pouch"], [0.665, "mag_in"]]
		"mag_pistol":
			var out := [[0.11, "mag_out_pistol"], [0.34, "mag_pouch"], [0.6, "mag_in_pistol"]]
			if empty:
				out.append_array([[0.745, "slide_back"], [0.78, "slide_release"]])
			return out
		"mag_bolt":
			var out := [[0.16, "mag_out"], [0.36, "mag_pouch"], [0.585, "mag_in"]]
			if empty:
				out.append_array(_bolt_cues(0.64, 0.96))
			return out
		"clip_bolt":
			return [[0.14, "bolt_up"], [0.21, "bolt_back"], [0.36, "mag_pouch"], [0.6, "clip_in"], [0.67, "round_insert"],
				[0.8, "bolt_fwd"], [0.85, "bolt_down"]]
		"clip_semi":
			return [[0.19, "charge_back"], [0.36, "mag_pouch"], [0.6, "clip_in"], [0.67, "round_insert"], [0.775, "charge_release"]]
		"tube_start":
			return [[0.92, "mag_pouch"]]
		"tube_insert":
			return [[0.67, "shell_insert"]]
		"tube_end":
			return [[0.6, "pump_back"], [0.77, "pump_fwd"]] if empty else []
		"gate_start":
			return [[0.5, "cylinder_open"], [0.92, "mag_pouch"]]
		"gate_insert":
			return [[0.72, "round_insert"], [0.97, "cylinder_click"]]
		"gate_end":
			return [[0.25, "cylinder_close"]]
		"break":
			return [[0.21, "break_open"], [0.28, "shell_eject"], [0.44, "mag_pouch"], [0.7, "shell_insert"], [0.83, "break_close"]]
		"pipe":
			return [[0.22, "pipe_slide"], [0.27, "shell_eject"], [0.42, "mag_pouch"], [0.66, "shell_insert"], [0.85, "pipe_slide"]]
		"cycle_pump":
			return [[0.36, "pump_back"], [0.78, "pump_fwd"]]
		"cycle_bolt":
			return _bolt_cues(0.02, 0.96)
	return []


static func _bolt_cues(t0: float, t1: float) -> Array:
	## The bolt worked by hand (see _bolt_cycle): lifted, drawn back (the case flies), run home, turned down.
	var s := func(f: float) -> float: return t0 + (t1 - t0) * f
	return [[s.call(0.27), "bolt_up"], [s.call(0.42), "bolt_back"], [s.call(0.58), "bolt_fwd"], [s.call(0.69), "bolt_down"]]


static func clip_name(wid: String, phase: int, has: Dictionary) -> String:
	## The clip for reload phase `phase` (tube and gate loads step through start, one insert per round, end), or for the
	## action worked between shots when phase < 0.
	if phase < 0:
		return "cycle_pump" if "pump" in Defs.weapon(wid).get("fire_modes", []) else "cycle_bolt"
	var kind := reload_kind(wid, has)
	if kind in ["tube", "gate"]:
		return kind + ["_start", "_insert", "_end"][clampi(phase, 0, 2)]
	return kind


# ------------------------------------------------------------------ evaluation
''')
  p.save()

# ------------------------------------------------------------------ viewmodel.gd: the player's own gun
p = Patch('game/src/player/viewmodel.gd')
p.rep('''var _clip_t := 0.0
''', '''var _clip_t := 0.0
var _cues: Array = []            # [t, sound id] of the playing clip still to come
''')
p.rep('''		if stepped:
			var name := _kind
			if _kind in ["tube", "gate"]:
				name = _kind + ["_start", "_insert", "_end"][clampi(phase, 0, 2)]
			_play(name, maxf(float(wpn.timer), 0.05))''', '''		if stepped:
			_play(Anims.clip_name(_cur, phase, _parts), maxf(float(wpn.timer), 0.05))''')
p.rep('''	if _clip_name != "":
		_clip_t = clampf(1.0 - float(wpn.timer) / _clip_total, 0.0, 1.0)
''', '''	if _clip_name != "":
		_clip_t = clampf(1.0 - float(wpn.timer) / _clip_total, 0.0, 1.0)
		while not _cues.is_empty() and float(_cues[0][0]) <= _clip_t:
			SoundSys.play_local(str(_cues[0][1]), -2.0)
			_cues.pop_front()
''')
p.rep('''	_clip_name = name
	_clip = Anims.filled(Anims.clip(name, _empty, _cur))
	_clip_total = total
	_clip_t = 0.0
''', '''	_clip_name = name
	_clip = Anims.filled(Anims.clip(name, _empty, _cur))
	_clip_total = total
	_clip_t = 0.0
	_cues = Anims.cues(name, _empty, _cur)
''')
p.rep('''		_clip = []
		_clip_name = ""
		_mag_mode = "gun"''', '''		_clip = []
		_clip_name = ""
		_cues = []
		_mag_mode = "gun"''')
p.save()

# ------------------------------------------------------------------ world.gd: everyone else's guns
p = Patch('game/src/match/world.gd')
p.rep('''		var st0: int = ch.wpn.state
		var rounds0: int = int(ch.wpn.weapon().get("mag", 0))
		var shots: Array = ch.wpn.step(cmd, dt, tick)
		_reload_sounds(ch, st0, rounds0)''', '''		var st0: int = ch.wpn.state
		var ph0: int = ch.wpn.reload_phase
		var tm0: float = ch.wpn.timer
		var shots: Array = ch.wpn.step(cmd, dt, tick)
		_reload_sounds(ch, st0, ph0, tm0)''')
p.rep('''func _reload_sounds(ch: Character, st0: int, rounds0: int) -> void:
	var feed := str(ch.wpn.def().get("feed", "mag"))
	var rounds := int(ch.wpn.weapon().get("mag", 0))
	var at: Vector3 = ch.global_position + Vector3.UP * 1.1
	if st0 != WeaponState.RELOAD and ch.wpn.state == WeaponState.RELOAD:
		# Magazine guns: the reload sequence of their class; tubes, cylinders and break actions: open up.
		var cls := str(ch.wpn.def().get("class", "rifle"))
		var seq := {"handgun": "reload_pistol", "smg": "reload_smg", "precision": "reload_sniper", "marksman": "reload_sniper"}.get(cls, "reload_rifle")
		server_sound(seq if feed == "mag" else "switch_click", at, 0.0, -1)
	elif ch.wpn.state == WeaponState.RELOAD and rounds > rounds0 and feed != "mag":
		server_sound("mag_in", at, -6.0, -1)
	elif st0 == WeaponState.RELOAD and ch.wpn.state != WeaponState.RELOAD and feed == "mag" and rounds > rounds0:
		server_sound("reload_finish", at, 0.0, -1)
''', '''func _reload_sounds(ch: Character, st0: int, ph0: int, tm0: float) -> void:
	## Each reload step, and the pump or bolt worked between shots, goes to the players near enough to hear it as one
	## event: their clients play that step's sounds (WeaponAnims.cues) over its length, on the motion of the hands.
	## The shooter's own client plays them from its viewmodel instead.
	var w = ch.wpn
	var phase := -2
	if w.state == WeaponState.RELOAD:
		if st0 != WeaponState.RELOAD:
			ch.set_meta("reload_empty", not bool(w.weapon().get("chamber", true)) or str(w.def().get("feed", "")) == "break")
			phase = w.reload_phase
		elif w.reload_phase != ph0 or float(w.timer) > tm0 + 1e-4:
			phase = w.reload_phase
	elif w.state == WeaponState.CYCLE and st0 != WeaponState.CYCLE:
		phase = -1
	if phase == -2:
		return
	var wid := str(w.weapon().get("id", ""))
	if wid == "":
		return
	var empty := bool(ch.get_meta("reload_empty", false)) if phase >= 0 else false
	var dur := maxf(float(w.timer), 0.05)
	for pid in Net.human_peers():
		if pid == ch.pid:
			continue
		var o := char_by_pid(pid)
		if o and o.global_position.distance_to(ch.global_position) > 40.0:
			continue
		_ev_clip.rpc_id(pid, ch.eid, wid, phase, empty, dur)
	if not is_server_dedicated() and not (local_char and local_char.eid == ch.eid):
		_ev_clip(ch.eid, wid, phase, empty, dur)


@rpc("authority", "call_remote", "reliable")
func _ev_clip(eid: int, wid: String, phase: int, empty: bool, dur: float) -> void:
	if effects and characters.has(eid):
		effects.gun_cues(characters[eid], wid, phase, empty, dur)
''')
p.save()

# ------------------------------------------------------------------ effects.gd: scheduling them
p = Patch('game/src/fx/effects.gd')
p.rep('''const Blood := preload("res://src/fx/blood.gd")
''', '''const Blood := preload("res://src/fx/blood.gd")
const Anims := preload("res://src/player/weapon_anims.gd")
const GunModel := preload("res://src/weapons/gun_model.gd")
''')
p.rep('''	if weapon in ["shotgun_pump", "bolt_308"]:
		var cyc := "pump_cycle" if weapon == "shotgun_pump" else "bolt_cycle"
		get_tree().create_timer(0.2).timeout.connect(func(): SoundSys.play_at(cyc, origin, 0.0, {"no_prop": local}))
''', '')
p.rep('''func flyby(pos: Vector3, speed: float, dist: float) -> void:''', '''func gun_cues(ch, wid: String, phase: int, empty: bool, dur: float) -> void:
	## Another character's reload step or worked action (World._reload_sounds): its sounds at the times the hands
	## would make them, from wherever the character is by then.
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(ch.global_position) > 45.0:
		return
	var name := Anims.clip_name(wid, phase, GunModel.parts(wid))
	for c in Anims.cues(name, empty, wid):
		var id := str(c[1])
		get_tree().create_timer(float(c[0]) * dur).timeout.connect(func():
			if is_instance_valid(ch) and ch.mode in [Motor.GROUND, Motor.DOWNED]:
				SoundSys.play_at(id, ch.global_position + Vector3.UP * 1.15, 0.0, {"prio": 4}))


func flyby(pos: Vector3, speed: float, dist: float) -> void:''')
p.save()
