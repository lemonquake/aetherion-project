extends Node
## Gameplay audio: bus layout, a pooled set of 3D players, and event playback through Acoustics propagation.
##
## Every audible gameplay event (footstep, door, gunshot, radio click, glass) goes through play_at(). The event is
## heard from where its sound actually reaches the listener: the last opening on the shortest acoustic path, or
## through a wall with the wall's transmission loss and muffling. Distant events arrive late (343 m/s).

const Acoustics := preload("res://src/audio/acoustics.gd")

const SPEED_OF_SOUND := 343.0
const POOL_SIZE := 72
const OCC_CUTOFF := [20500.0, 3800.0, 1500.0, 650.0]
const REVERBS := {
	"none": null,
	"small": {"room_size": 0.25, "damping": 0.7, "wet": 0.16, "spread": 0.6, "predelay": 8.0},
	"medium": {"room_size": 0.45, "damping": 0.55, "wet": 0.2, "spread": 0.8, "predelay": 14.0},
	"large": {"room_size": 0.75, "damping": 0.35, "wet": 0.26, "spread": 1.0, "predelay": 24.0},
	"outdoor": {"room_size": 0.6, "damping": 0.8, "wet": 0.07, "spread": 1.0, "predelay": 45.0},
}

## Sound definitions: id -> {files, db, dist (max audible m), pitch (random +-), cat, prio}
var defs: Dictionary = {}
var acoustics = null
var listener_node: Node3D = null

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _last_variant: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _delayed: Array = []  # [time_left, callable]
var _loops: Dictionary = {}  # key -> {player, id, pos, refresh}
var _root: Node3D
var trace: Array = []     # tests: [msec, id, "local"/"world"] of every sound started, while trace_on
var trace_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build_buses()
	_root = Node3D.new()
	_root.name = "SoundPool"
	add_child(_root)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 4.0
		p.max_db = 6.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.attenuation_filter_cutoff_hz = 20500.0
		p.attenuation_filter_db = 0.0
		p.set_meta("prio", 0)
		_root.add_child(p)
		_pool.append(p)
	for i in 8:
		var q := AudioStreamPlayer.new()
		q.bus = "UI"
		add_child(q)
		_pool_2d.append(q)
	_load_defs()
	Settings.changed.connect(_on_setting)
	_apply_output()


func _build_buses() -> void:
	var ab := AudioServer
	if ab.get_bus_index("Effects") >= 0:
		return
	var master := 0
	var comp := AudioEffectCompressor.new()
	comp.threshold = -22.0
	comp.ratio = 5.0
	comp.attack_us = 2000.0
	comp.release_ms = 220.0
	comp.gain = 7.0
	ab.add_bus_effect(master, comp)
	ab.set_bus_effect_enabled(master, 0, false)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.6
	ab.add_bus_effect(master, lim)
	for name in ["Effects", "Ambience", "Voice", "UI"]:
		_add_bus(name, "Master")
	var duck := AudioEffectCompressor.new()
	duck.threshold = -28.0
	duck.ratio = 6.0
	duck.release_ms = 900.0
	duck.sidechain = &"Effects"
	ab.add_bus_effect(ab.get_bus_index("Ambience"), duck)
	# Speech through a handheld radio: narrow band, a little grit. Sends into Voice, so the voice volume applies.
	var radio := _add_bus("Radio", "Voice")
	var bp := AudioEffectBandPassFilter.new()
	bp.cutoff_hz = 1600.0
	bp.resonance = 0.62
	ab.add_bus_effect(radio, bp)
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 380.0
	ab.add_bus_effect(radio, hp)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_CLIP
	dist.pre_gain = 6.0
	dist.drive = 0.25
	dist.post_gain = -5.0
	ab.add_bus_effect(radio, dist)
	var mic := _add_bus("Mic", "Master")
	ab.set_bus_mute(mic, true)
	ab.add_bus_effect(mic, AudioEffectCapture.new())
	for rv in REVERBS:
		for occ in OCC_CUTOFF.size():
			var idx := _add_bus("SFX_%s_%d" % [rv, occ], "Effects")
			if occ > 0:
				var lp := AudioEffectLowPassFilter.new()
				lp.cutoff_hz = OCC_CUTOFF[occ]
				lp.resonance = 0.5
				ab.add_bus_effect(idx, lp)
			if REVERBS[rv] != null:
				var r := AudioEffectReverb.new()
				var cfg: Dictionary = REVERBS[rv]
				r.room_size = cfg.room_size
				r.damping = cfg.damping
				r.wet = cfg.wet
				r.dry = 1.0
				r.spread = cfg.spread
				r.predelay_msec = cfg.predelay
				r.hipass = 0.15
				ab.add_bus_effect(idx, r)


func _add_bus(name: String, send: String) -> int:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, send)
	return idx


func _on_setting(section: String, key: String) -> void:
	if section == "audio" and key == "output":
		_apply_output()


func _apply_output() -> void:
	var strength := 1.0 if str(Settings.get_value("audio", "output")) == "headphones" else 0.55
	for p in _pool:
		p.panning_strength = strength


# ------------------------------------------------------------------ definitions

func _load_defs() -> void:
	var f := FileAccess.open("res://data/sounds.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			defs = d.get("sounds", {})


func warm() -> void:
	## Loads every sound while the map is being built, so none is read from disk the first time it plays.
	for id in defs:
		for f in defs[id].get("files", []):
			_stream("res://" + str(f))


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_streams[path] = s
	return s


func _pick(id: String) -> AudioStream:
	var d: Dictionary = defs.get(id, {})
	var files: Array = d.get("files", [])
	if files.is_empty():
		return null
	var i := _rng.randi_range(0, files.size() - 1)
	if files.size() > 2 and _last_variant.get(id, -1) == i:
		i = (i + 1) % files.size()
	_last_variant[id] = i
	var path := "res://" + str(files[i])
	if d.get("loop", false):
		return _looping(path)
	return _stream(path)


func _looping(path: String) -> AudioStream:
	## A copy of the stream set to loop over its whole length (sounds.json marks hums, static and engines).
	var key := path + "#loop"
	if _streams.has(key):
		return _streams[key]
	var s := _stream(path)
	if s != null:
		s = s.duplicate()
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif "loop" in s:
			s.set("loop", true)
	_streams[key] = s
	return s


func has_sound(id: String) -> bool:
	return defs.has(id)


# ------------------------------------------------------------------ playback

func clear() -> void:
	for p in _pool:
		p.stop()
	_delayed.clear()
	for k in _loops.keys():
		stop_loop(k)
	acoustics = null
	listener_node = null


func set_acoustics(a) -> void:
	acoustics = a


func listener_pos() -> Vector3:
	if listener_node and is_instance_valid(listener_node):
		return listener_node.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


func play_ui(id: String, db: float = 0.0) -> void:
	var s := _pick(id)
	if s == null:
		return
	for q in _pool_2d:
		if not q.playing:
			q.stream = s
			q.volume_db = float(defs[id].get("db", 0.0)) + db
			q.play()
			return


func play_local(id: String, db: float = 0.0, pitch: float = 1.0) -> void:
	## Non-positional sound heard only by the local player (own breathing, SmarTab handling).
	var s := _pick(id)
	if s == null:
		return
	if trace_on:
		trace.append([Time.get_ticks_msec(), id, "local"])
	for q in _pool_2d:
		if not q.playing:
			q.stream = s
			q.bus = "Effects"
			q.volume_db = float(defs[id].get("db", 0.0)) + db
			q.pitch_scale = pitch * (1.0 + _rng.randf_range(-1.0, 1.0) * float(defs[id].get("pitch", 0.0)))
			q.play()
			return


func play_at(id: String, pos: Vector3, db: float = 0.0, opts: Dictionary = {}) -> void:
	## Plays a world sound as the local listener hears it. opts: pitch, delay (bool, default true for loud),
	## source_zone (int), prio (int), no_prop (bool, skip propagation for the local player's own sounds).
	if DisplayServer.get_name() == "headless" or not defs.has(id):
		return
	var d: Dictionary = defs[id]
	var lpos := listener_pos()
	var dist := lpos.distance_to(pos)
	var max_d := float(d.get("dist", 40.0)) * float(opts.get("dist_mult", 1.0))
	if dist > max_d:
		return
	if trace_on:
		trace.append([Time.get_ticks_msec(), id, "world"])
	var delay := 0.0
	if opts.get("delay", float(d.get("dist", 40.0)) > 120.0) and dist > 25.0:
		delay = dist / SPEED_OF_SOUND
	if delay > 0.02:
		_delayed.append([delay, func(): _play_now(id, pos, db, opts)])
	else:
		_play_now(id, pos, db, opts)


func _play_now(id: String, pos: Vector3, db: float, opts: Dictionary) -> AudioStreamPlayer3D:
	var d: Dictionary = defs.get(id, {})
	var lpos := listener_pos()
	var dist := lpos.distance_to(pos)
	var stream_id := id
	if d.has("far") and dist > float(d.get("far_from", 120.0)):
		stream_id = str(d.far)
	var s := _pick(stream_id)
	if s == null:
		s = _pick(id)
	if s == null:
		return null
	var prop := {"pos": pos, "gain_db": 0.0, "occ": 0, "reverb": "outdoor", "dist": dist}
	if acoustics and not opts.get("no_prop", false):
		prop = _propagate_cached(pos, lpos, float(d.get("dist", 40.0)))
	elif acoustics:
		prop.reverb = acoustics.reverb_at(lpos)
	var gain := float(d.get("db", 0.0)) + db + float(prop.gain_db)
	if gain < -60.0:
		return null
	var p := _grab(int(opts.get("prio", d.get("prio", 1))))
	if p == null:
		return null
	p.stream = s
	p.global_position = prop.pos
	p.max_distance = float(d.get("dist", 40.0)) * 1.2
	p.unit_size = float(d.get("unit", 4.0))
	p.volume_db = gain
	p.bus = "SFX_%s_%d" % [prop.reverb, clampi(int(prop.occ), 0, 3)]
	var pv := float(d.get("pitch", 0.05))
	p.pitch_scale = float(opts.get("pitch", 1.0)) * (1.0 + _rng.randf_range(-pv, pv))
	p.set_meta("prio", int(opts.get("prio", d.get("prio", 1))))
	p.play()
	return p


var _paths := {}   # "src cell|listener cell" -> [time, source, result]
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


func _grab(prio: int) -> AudioStreamPlayer3D:
	var lowest: AudioStreamPlayer3D = null
	for p in _pool:
		if not p.playing:
			return p
		if lowest == null or int(p.get_meta("prio")) < int(lowest.get_meta("prio")):
			lowest = p
	if lowest and int(lowest.get_meta("prio")) <= prio:
		lowest.stop()
		return lowest
	return null


# ------------------------------------------------------------------ loops (radio static, scraping, hums)

func start_loop(key: String, id: String, pos: Vector3, db: float = 0.0) -> void:
	if _loops.has(key):
		update_loop(key, pos, db)
		return
	var p := _play_now(id, pos, db, {"prio": 3})
	if p == null:
		return
	_loops[key] = {"player": p, "id": id, "pos": pos, "db": db, "t": 0.0}


func update_loop(key: String, pos: Vector3, db: float = 0.0) -> void:
	if not _loops.has(key):
		return
	_loops[key].pos = pos
	_loops[key].db = db


func stop_loop(key: String) -> void:
	if not _loops.has(key):
		return
	var p: AudioStreamPlayer3D = _loops[key].player
	if is_instance_valid(p):
		p.stop()
	_loops.erase(key)


func _process(delta: float) -> void:
	for i in range(_delayed.size() - 1, -1, -1):
		_delayed[i][0] -= delta
		if _delayed[i][0] <= 0.0:
			var cb: Callable = _delayed[i][1]
			_delayed.remove_at(i)
			cb.call()
	for key in _loops.keys():
		var L: Dictionary = _loops[key]
		var p: AudioStreamPlayer3D = L.player
		if not is_instance_valid(p) or not p.playing:
			_loops.erase(key)
			continue
		L.t -= delta
		if L.t <= 0.0:
			L.t = 0.2
			var d: Dictionary = defs.get(L.id, {})
			var prop := {"pos": L.pos, "gain_db": 0.0, "occ": 0, "reverb": "outdoor"}
			if acoustics:
				prop = acoustics.propagate(L.pos, listener_pos(), float(d.get("dist", 40.0)))
			p.global_position = prop.pos
			p.volume_db = float(d.get("db", 0.0)) + float(L.db) + float(prop.gain_db)
			p.bus = "SFX_%s_%d" % [prop.reverb, clampi(int(prop.occ), 0, 3)]
