"""r4: shell casings, suppression from near misses, cached sound paths for bursts of impacts."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))

# ------------------------------------------------------------------ casings (a particle kind of their own)
f = 'src/fx/particles.gd'
patch(f, '''	"blast_debris": {"mesh": "chip",''', '''	"casing": {"mesh": "brass", "amount": 1, "life": 0.75, "vel": [1.6, 2.6], "spread": 22.0, "gravity": -9.8, "damp": 0.2,
		"scale": [0.011, 0.011], "grow": 1.0, "color": Color(0.82, 0.62, 0.28), "pool": 12},
	"blast_debris": {"mesh": "chip",''')
patch(f, '''		var list := []
		for i in POOL:''', '''		var list := []
		for i in int(k.get("pool", POOL)):''')
patch(f, '''		"streak", "sliver":
			m.particle_flag_align_y = true''', '''		"streak", "sliver":
			m.particle_flag_align_y = true
		"brass":
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -900.0
			m.angular_velocity_max = 900.0
			m.particle_flag_rotate_y = true''')
patch(f, '''		_:
			var b3 := BoxMesh.new()
			b3.size = Vector3(1.0, 0.7, 0.85)
			mesh = b3
			mat.roughness = 0.95''', '''		"brass":
			# A spent case: a short brass tube (9 mm about 19 mm long; scale sets the size).
			var cy := CylinderMesh.new()
			cy.top_radius = 0.45
			cy.bottom_radius = 0.5
			cy.height = 2.0
			cy.radial_segments = 6
			cy.rings = 0
			mesh = cy
			mat.metallic = 0.9
			mat.roughness = 0.3
		_:
			var b3 := BoxMesh.new()
			b3.size = Vector3(1.0, 0.7, 0.85)
			mesh = b3
			mat.roughness = 0.95''')

f = 'src/fx/effects.gd'
patch(f, '''	if cam and cam.global_position.distance_to(origin) < 60.0:
		# A wisp of propellant smoke hangs at the muzzle (less from a suppressor).''', '''	if cam and cam.global_position.distance_to(origin) < 25.0 and weapon not in ["revolver_357", "shotgun_double", "sumpak"]:
		# The spent case flies out to the right and tinkles on the ground a moment later.
		var right := dir.cross(Vector3.UP).normalized()
		var eject := (flash_pos - dir * (0.32 if local else 0.42)) + right * 0.04 + Vector3.UP * 0.02
		particles.emit("casing", eject, (right * 1.0 + Vector3.UP * 0.7 - dir * 0.2).normalized())
		var floor_at := eject + Vector3.DOWN * 1.3 + right * 0.6
		get_tree().create_timer(0.42 + _rng.randf() * 0.12).timeout.connect(func(): SoundSys.play_at("casing_drop", floor_at, 0.0, {"prio": 1}))
	if cam and cam.global_position.distance_to(origin) < 60.0:
		# A wisp of propellant smoke hangs at the muzzle (less from a suppressor).''')
patch(f, '''func flyby(pos: Vector3, speed: float, dist: float) -> void:
	SoundSys.play_at("flyby_crack" if speed > 343.0 else "flyby_whiz", pos, -dist * 2.0, {"no_prop": true, "prio": 6})''', '''func flyby(pos: Vector3, speed: float, dist: float) -> void:
	SoundSys.play_at("flyby_crack" if speed > 343.0 else "flyby_whiz", pos, -dist * 2.0, {"no_prop": true, "prio": 6})
	# Suppression: a round cracking past within a couple of metres darkens the edges of the view and jolts it.
	if dist < 2.2 and world.hud and world.hud.has_method("suppress"):
		world.hud.suppress(clampf(1.0 - dist / 2.2, 0.2, 1.0) * (1.0 if speed > 343.0 else 0.6))
		if world.controller and world.controller.has_method("on_suppressed"):
			world.controller.on_suppressed(dist)''')

f = 'src/player/player_controller.gd'
patch(f, '''func on_hit(part: String, dir: Vector3, damage: float, absorbed: String) -> void:''', '''func on_suppressed(dist: float) -> void:
	## A near miss: a small flinch of the view (much less than being hit).
	_hit_shake = minf(_hit_shake + 0.18 * clampf(1.0 - dist / 2.2, 0.2, 1.0), 0.6)


func on_hit(part: String, dir: Vector3, damage: float, absorbed: String) -> void:''')

f = 'src/ui/hud.gd'
patch(f, '''uniform float amount = 0.0;
uniform float low = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.35, 0.85, d);
	COLOR = vec4(mix(vec3(0.0), vec3(0.35, 0.0, 0.0), amount), v * (amount * 0.75 + low * 0.35));
}""''', '''uniform float amount = 0.0;
uniform float low = 0.0;
uniform float supp = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.35, 0.85, d);
	float s = smoothstep(0.18, 0.75, d) * supp;
	vec3 col = mix(vec3(0.0), vec3(0.35, 0.0, 0.0), amount / max(amount + s * 0.6, 0.001));
	COLOR = vec4(col, clamp(v * (amount * 0.75 + low * 0.35) + s * 0.55, 0.0, 0.9));
}""''')
patch(f, '''var pa_banner: Control   # loudspeaker countdown (audio/announcer.gd drives it)''', '''var _supp := 0.0         # near-miss suppression (Effects.flyby)
var pa_banner: Control   # loudspeaker countdown (audio/announcer.gd drives it)''')
patch(f, '''func pa_countdown(n: int, kind: String) -> void:''', '''func suppress(amount: float) -> void:
	_supp = minf(_supp + amount * 0.6, 1.0)


func pa_countdown(n: int, kind: String) -> void:''')
patch(f, '''	(vignette.material as ShaderMaterial).set_shader_parameter("low", low)''', '''	(vignette.material as ShaderMaterial).set_shader_parameter("low", low)
	_supp = move_toward(_supp, 0.0, dt * 0.7)
	(vignette.material as ShaderMaterial).set_shader_parameter("supp", _supp)''')

# ------------------------------------------------------------------ sound paths cached for a moment (bursts of impacts)
f = 'src/audio/sound_system.gd'
patch(f, '''	var prop := {"pos": pos, "gain_db": 0.0, "occ": 0, "reverb": "outdoor", "dist": dist}
	if acoustics and not opts.get("no_prop", false):
		prop = acoustics.propagate(pos, lpos, float(d.get("dist", 40.0)))''', '''	var prop := {"pos": pos, "gain_db": 0.0, "occ": 0, "reverb": "outdoor", "dist": dist}
	if acoustics and not opts.get("no_prop", false):
		prop = _propagate_cached(pos, lpos, float(d.get("dist", 40.0)))''')
patch(f, '''func _grab(prio: int) -> AudioStreamPlayer3D:''', '''var _paths := {}   # "src cell|listener cell" -> [time, source, result]
var _paths_t := 0.0


func _propagate_cached(src: Vector3, lis: Vector3, max_d: float) -> Dictionary:
	## The way a sound reaches the listener (rays and a portal search, about half a millisecond) changes little within
	## a metre and a fraction of a second: a burst of rounds hitting one wall, a stream of footsteps, reuse it.
	var now := Time.get_ticks_msec() / 1000.0
	var key := "%s|%s" % [Vector3i((src / 1.5).floor()), Vector3i((lis / 1.5).floor())]
	var e: Array = _paths.get(key, [])
	if not e.is_empty() and now - float(e[0]) < 0.35:
		var r: Dictionary = (e[2] as Dictionary).duplicate()
		if (r.pos as Vector3).is_equal_approx(e[1]):
			r.pos = src   # heard straight from the source: keep this event's own position
		r.dist = src.distance_to(lis)
		return r
	var res: Dictionary = acoustics.propagate(src, lis, max_d)
	_paths[key] = [now, src, res]
	if now - _paths_t > 2.0:
		_paths_t = now
		for k in _paths.keys():
			if now - float(_paths[k][0]) > 1.0:
				_paths.erase(k)
	return res


func _grab(prio: int) -> AudioStreamPlayer3D:''')
