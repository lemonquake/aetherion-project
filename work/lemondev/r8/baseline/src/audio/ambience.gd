extends Node3D
## Night ambience around the listener (client only, cosmetic): insect beds that thin out indoors and fall silent for
## a while after gunfire, a frog chorus from the nearest water, distant dogs that bark more after shots, geckos calling
## from nearby walls, and an owl or a nightjar now and then. Positions are random or tied to the map, never to
## players, so ambience carries no information about anyone.

const BEDS := [["amb_cricket_field", Vector3(26, 2, -20), 0.0], ["amb_cricket_gryllus", Vector3(-30, 2, 10), -2.0],
	["amb_cricket_field", Vector3(6, 2, 32), -5.0]]
const SHOTS := 6

var world = null
var rng := RandomNumberGenerator.new()
var beds: Array = []          # [{player, offset, db}]
var frogs: AudioStreamPlayer3D
var _frog_at := Vector3.INF
var _frog_t := 0.0
var _shots: Array[AudioStreamPlayer3D] = []
var _hush := 0.0              # seconds of quiet left after a loud event
var _level := 1.0             # insect level 0..1
var _indoor := 0.0
var _next := {"dog": 0.0, "gecko": 0.0, "bird": 0.0}
var _alarm := 0.0             # dogs are more excited for a while after shots
var _bgrid := {}              # Vector2i (32 m) -> building origins, for the gecko's perch


func setup(w) -> void:
	world = w
	rng.randomize()
	for b in BEDS:
		var p := _looping(b[0])
		if p:
			beds.append({"player": p, "offset": b[1], "db": b[2]})
	frogs = _looping("amb_frog_chorus" if rng.randf() < 0.5 else "amb_frog_chorus_b")
	_next.dog = rng.randf_range(6.0, 18.0)
	_next.gecko = rng.randf_range(10.0, 35.0)
	_next.bird = rng.randf_range(25.0, 70.0)
	for b in world.map.buildings:
		var o: Vector3 = (b.xf as Transform3D).origin
		var k := Vector2i(floori(o.x / 32.0), floori(o.z / 32.0))
		if not _bgrid.has(k):
			_bgrid[k] = []
		_bgrid[k].append(o)
	for i in SHOTS:
		var q := AudioStreamPlayer3D.new()
		q.bus = "Ambience"
		q.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		q.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(q)
		_shots.append(q)


func _looping(id: String) -> AudioStreamPlayer3D:
	var d: Dictionary = SoundSys.defs.get(id, {})
	var files: Array = d.get("files", [])
	if files.is_empty() or not ResourceLoader.exists("res://" + str(files[0])):
		return null
	var s: AudioStream = (load("res://" + str(files[0])) as AudioStream).duplicate()
	if "loop" in s:
		s.set("loop", true)
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "Ambience"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 16.0
	p.max_distance = 160.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.volume_db = -80.0
	add_child(p)
	p.play(rng.randf() * maxf(s.get_length() - 1.0, 0.0))
	return p


func on_loud(pos: Vector3, radius: float = 160.0) -> void:
	## A gunshot, a burst door, breaking glass: insects nearby stop, dogs start.
	var lp: Vector3 = SoundSys.listener_pos()
	if lp.distance_to(pos) > radius:
		return
	_hush = maxf(_hush, rng.randf_range(7.0, 14.0))
	_alarm = minf(_alarm + 1.0, 3.0)
	_next.dog = minf(_next.dog, rng.randf_range(0.8, 3.5))


func _process(dt: float) -> void:
	var lp: Vector3 = SoundSys.listener_pos()
	var inside: bool = world.map != null and world.map.acoustics.zone_at(lp) != 0
	_indoor = move_toward(_indoor, 1.0 if inside else 0.0, dt * 1.5)
	_hush = maxf(_hush - dt, 0.0)
	_alarm = maxf(_alarm - dt * 0.05, 0.0)
	# Insects drop out quickly after a shot and come back slowly, a few at a time.
	_level = move_toward(_level, 0.0 if _hush > 0.0 else 1.0, dt * (1.6 if _hush > 0.0 else 0.12))
	var base := linear_to_db(maxf(_level, 0.001)) - 9.0 * _indoor
	for b in beds:
		var p: AudioStreamPlayer3D = b.player
		p.global_position = lp + b.offset
		p.volume_db = base + float(b.db) - 4.0
	_frogs(dt, lp, base)
	for k in _next.keys():
		_next[k] -= dt
		if _next[k] <= 0.0:
			_event(k, lp)


func _frogs(dt: float, lp: Vector3, base: float) -> void:
	if frogs == null:
		return
	_frog_t -= dt
	if _frog_t <= 0.0:
		_frog_t = 3.0
		_frog_at = Vector3.INF
		var L = world.map.layout
		for r in [20.0, 45.0, 80.0, 120.0]:
			for i in 12:
				var a := TAU * i / 12.0
				var x: float = lp.x + cos(a) * r
				var z: float = lp.z + sin(a) * r
				if L.is_water(x, z):
					_frog_at = Vector3(x, world.water_height(x, z) + 0.3, z)
					break
			if _frog_at != Vector3.INF:
				break
	if _frog_at == Vector3.INF:
		frogs.volume_db = move_toward(frogs.volume_db, -80.0, dt * 20.0)
		return
	frogs.global_position = frogs.global_position.lerp(_frog_at, clampf(dt * 0.5, 0.0, 1.0)) if frogs.volume_db > -60.0 else _frog_at
	frogs.volume_db = move_toward(frogs.volume_db, base - 2.0, dt * 12.0)


func _event(kind: String, lp: Vector3) -> void:
	match kind:
		"dog":
			var excited := _alarm > 0.3
			_next.dog = rng.randf_range(3.0, 9.0) if excited else rng.randf_range(14.0, 45.0)
			var id := "amb_dog_pack" if excited and rng.randf() < 0.3 else "amb_dog_bark_%s" % "abcde"[rng.randi_range(0, 4)]
			var a := rng.randf() * TAU
			_one_shot(id, lp + Vector3(cos(a), 0, sin(a)) * rng.randf_range(55.0, 180.0), -4.0 if excited else -9.0, 90.0)
		"gecko":
			_next.gecko = rng.randf_range(25.0, 80.0)
			var near = null
			var c := Vector2i(floori(lp.x / 32.0), floori(lp.z / 32.0))
			for dx in [0, -1, 1]:
				for dz in [0, -1, 1]:
					for o in _bgrid.get(c + Vector2i(dx, dz), []):
						if near == null and o.distance_to(lp) < 30.0 and o.distance_to(lp) > 4.0:
							near = o
			if near != null and _level > 0.6:
				_one_shot("amb_gecko_tokay", near + Vector3(0, 2.5, 0), -8.0 - 6.0 * _indoor, 18.0)
		"bird":
			_next.bird = rng.randf_range(40.0, 120.0)
			var a2 := rng.randf() * TAU
			var r2 := rng.randf_range(60.0, 140.0)
			_one_shot("amb_owl_tawny" if rng.randf() < 0.5 else "amb_nightjar", lp + Vector3(cos(a2) * r2, 12.0, sin(a2) * r2), -12.0, 70.0)


func _one_shot(id: String, pos: Vector3, db: float, unit: float) -> void:
	var d: Dictionary = SoundSys.defs.get(id, {})
	var files: Array = d.get("files", [])
	if files.is_empty():
		return
	for q in _shots:
		if not q.playing:
			q.stream = load("res://" + str(files[rng.randi_range(0, files.size() - 1)]))
			q.global_position = pos
			q.unit_size = unit
			q.max_distance = 260.0
			q.volume_db = db + float(d.get("db", 0.0))
			q.pitch_scale = rng.randf_range(0.94, 1.06)
			q.play()
			return
