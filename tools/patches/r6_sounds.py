"""r6: the new sound sets wired in - material-specific bullet impacts, helmet vs vest hits, shotgun shells landing, a
body hitting the ground, and the weapon being drawn."""
from patchlib import Patch

p = Patch('game/src/fx/effects.gd')
p.rep('''## Impact kind (from the ballistics material) -> particle kinds.''', '''## Ballistics material -> its own impact sound where it has one (otherwise "impact_" + the material's impact kind).
const MAT_SOUND := {"sheet_metal": "impact_metal_sheet", "steel": "impact_metal", "tile": "impact_tile"}
## Impact kind (from the ballistics material) -> particle kinds.''')
p.rep('''	SoundSys.play_at("ricochet" if what == "ricochet" else "impact_" + kind, pos, 0.0)''', '''	var snd: String = MAT_SOUND.get(mat, "impact_" + kind)
	if not SoundSys.has_sound(snd):
		snd = "impact_" + kind
	SoundSys.play_at("ricochet" if what == "ricochet" else snd, pos, 0.0)''')
p.rep('''		SoundSys.play_at("impact_armor" if not armor_broken else "armor_break", pos, 0.0)''', '''		SoundSys.play_at(("impact_helmet" if part == "head" else "impact_armor") if not armor_broken else "armor_break", pos, 0.0)''')
p.rep('''		var floor_at := eject + Vector3.DOWN * 1.3 + right * 0.6
		get_tree().create_timer(0.42 + _rng.randf() * 0.12).timeout.connect(func(): SoundSys.play_at("casing_drop", floor_at, 0.0, {"prio": 1}))''', '''		var floor_at := eject + Vector3.DOWN * 1.3 + right * 0.6
		var case_snd := "shell_drop" if str(d.get("class", "")) == "shotgun" else "casing_drop"
		get_tree().create_timer(0.42 + _rng.randf() * 0.12).timeout.connect(func(): SoundSys.play_at(case_snd, floor_at, 0.0, {"prio": 1}))''')
p.rep('''func gun_cues(ch, wid: String, phase: int, empty: bool, dur: float) -> void:''', '''func body_fell(c) -> void:
	## A body going down: the thump when it reaches the ground, about half a second after the ragdoll starts.
	get_tree().create_timer(0.45).timeout.connect(func():
		if is_instance_valid(c):
			SoundSys.play_at("bodyfall", c.center(), 0.0, {"prio": 5}))


func gun_cues(ch, wid: String, phase: int, empty: bool, dur: float) -> void:''')
p.save()

p = Patch('game/src/props/corpse.gd')
p.rep('''func setup_server(w, cid: int, ch, impulse: Vector3) -> void:
	world = w
	id = cid
	server = true
''', '''func setup_server(w, cid: int, ch, impulse: Vector3) -> void:
	world = w
	id = cid
	server = true
	if world.effects:
		world.effects.body_fell(self)
''')
p.rep('''func setup_client(w, cid: int, who: String, t: int, xforms: Array) -> void:
	# The pose stream is interpolated here every frame; engine interpolation on top would step.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world = w
''', '''func setup_client(w, cid: int, who: String, t: int, xforms: Array) -> void:
	# The pose stream is interpolated here every frame; engine interpolation on top would step.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world = w
	if world.effects:
		world.effects.body_fell(self)
''')
p.save()

p = Patch('game/src/player/viewmodel.gd')
p.rep('''	_cur = wid
	_draw = 1.0
''', '''	if wid != "" and wid != _cur and ch and ch.mode == Motor.GROUND:
		SoundSys.play_local("weapon_draw", -6.0)
	_cur = wid
	_draw = 1.0
''')
p.save()
