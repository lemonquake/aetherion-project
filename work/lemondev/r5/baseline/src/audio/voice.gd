extends Node
## Team voice over handheld radios. Push-to-talk (or voice activation) captures the microphone, encodes 40 ms frames
## and sends them to the server. Teammates hear it on their own radios (band-limited, a little static) with the
## key click when it starts and the squelch tail when it ends. Radios are loud enough to overhear, as in life:
## anyone within ~12 m of a teammate's radio hears the speech coming out of it, and anyone within ~9 m of the speaker
## hears their voice directly; nobody farther away gets anything (the server decides who receives what).
##
## Codec: Opus through the TwoVoIP extension when it is installed; otherwise 8 kHz mu-law (64 kbps), which is
## plenty on a LAN. Third-party voice apps cannot trigger the in-world radio cue; that limitation is documented.

const FRAME_S := 0.04
const RATE := 8000

var world = null
var mic_player: AudioStreamPlayer
var capture: AudioEffectCapture
var talking := false
var _buf := PackedFloat32Array()
var _send_t := 0.0
var _players: Dictionary = {}  # "pid:kind" -> {player, pb, src}
var _mix_rate := 48000.0
var _level := 0.0
var _hold_open := 0.0


func setup(w) -> void:
	world = w
	_mix_rate = AudioServer.get_mix_rate()
	var idx := AudioServer.get_bus_index("Mic")
	if idx >= 0:
		for i in AudioServer.get_bus_effect_count(idx):
			var e := AudioServer.get_bus_effect(idx, i)
			if e is AudioEffectCapture:
				capture = e
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Mic"
	add_child(mic_player)
	if str(Settings.get_value("audio", "voice_mode")) != "off" and DisplayServer.get_name() != "headless":
		if OS.get_name() == "Android" and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
			# Android asks the player first; without it the radio still receives.
			get_tree().on_request_permissions_result.connect(func(perm: String, granted: bool):
				if granted and perm.ends_with("RECORD_AUDIO") and is_instance_valid(mic_player):
					mic_player.play())
			OS.request_permission("android.permission.RECORD_AUDIO")
		else:
			mic_player.play()
	Net.voice_received.connect(_on_voice)


func _process(dt: float) -> void:
	for k in _players:
		if int(_players[k].kind) != 0:
			_place(_players[k])
	if capture == null:
		return
	var mode := str(Settings.get_value("audio", "voice_mode"))
	var frames := capture.get_frames_available()
	var data := capture.get_buffer(frames) if frames > 0 else PackedVector2Array()
	var gain := float(Settings.get_value("audio", "mic_gain"))
	var peak := 0.0
	var mono := PackedFloat32Array()
	mono.resize(data.size())
	for i in data.size():
		var s := (data[i].x + data[i].y) * 0.5 * gain
		mono[i] = s
		peak = maxf(peak, absf(s))
	_level = lerpf(_level, peak, 0.3)
	var want := false
	if mode == "push":
		want = Input.is_action_pressed("push_to_talk")
	elif mode == "open":
		if _level > float(Settings.get_value("audio", "voice_threshold")):
			_hold_open = 0.4
		_hold_open -= dt
		want = _hold_open > 0.0
	var ch = world.local_char
	if ch == null or ch.mode == Motor.DEAD:
		want = want and mode == "push"
	if want != talking:
		talking = want
		SoundSys.play_local("radio_key" if talking else "radio_off", -8.0)
	if not talking:
		_buf.clear()
		return
	# Downsample to 8 kHz by averaging.
	var step := _mix_rate / RATE
	var acc := 0.0
	var cnt := 0.0
	var pos := 0.0
	for i in mono.size():
		acc += mono[i]
		cnt += 1.0
		pos += 1.0
		if pos >= step:
			pos -= step
			_buf.append(acc / cnt)
			acc = 0.0
			cnt = 0.0
	var frame_len := int(RATE * FRAME_S)
	while _buf.size() >= frame_len:
		var frame := _buf.slice(0, frame_len)
		_buf = _buf.slice(frame_len)
		Net.send_voice(_encode(frame))


static func _ulaw(x: float) -> int:
	var s := clampf(x, -1.0, 1.0)
	var mag := log(1.0 + 255.0 * absf(s)) / log(256.0)
	var v := int(round(mag * 127.0))
	return (v | 128) if s < 0.0 else v


static func _unulaw(b: int) -> float:
	var neg := (b & 128) != 0
	var mag := float(b & 127) / 127.0
	var s := (pow(256.0, mag) - 1.0) / 255.0
	return -s if neg else s


func _encode(frame: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(frame.size())
	for i in frame.size():
		out[i] = _ulaw(frame[i])
	return out


func _on_voice(from_pid: int, bytes: PackedByteArray, src_eid: int = -1, kind: int = 0) -> void:
	var key := "%d:%d" % [from_pid, kind]
	if not _players.has(key):
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.5
		var p: Node
		if kind == 0:
			var p2 := AudioStreamPlayer.new()
			p2.bus = "Radio"
			p2.stream = gen
			p = p2
		else:
			# Overheard: positional, from the radio (or the mouth) it comes out of; dull and quiet at the edge.
			var p3 := AudioStreamPlayer3D.new()
			p3.bus = "Radio" if kind == 1 else "Voice"
			p3.stream = gen
			p3.unit_size = 2.2 if kind == 1 else 3.0
			p3.max_distance = float(Defs.rule("radio.eavesdrop_radius", 12.0)) + 4.0 if kind == 1 else float(Defs.rule("radio.voice_radius", 9.0)) + 3.0
			p3.attenuation_filter_cutoff_hz = 3500.0
			p3.attenuation_filter_db = -14.0
			p3.volume_db = -3.0 if kind == 1 else 0.0
			p3.top_level = true
			p = p3
		add_child(p)
		p.call("play")
		_players[key] = {"player": p, "pb": p.call("get_stream_playback"), "src": src_eid, "kind": kind}
	var rec: Dictionary = _players[key]
	rec.src = src_eid
	var pb: AudioStreamGeneratorPlayback = rec.pb
	var radio := kind != 2
	var frames := PackedVector2Array()
	frames.resize(bytes.size())
	for i in bytes.size():
		var s := _unulaw(bytes[i])
		if radio:
			s += randf_range(-0.01, 0.01)   # the carrier's hiss under the speech
		frames[i] = Vector2(s, s)
	if pb.can_push_buffer(frames.size()):
		pb.push_buffer(frames)
	if kind != 0:
		_place(rec)


func _place(rec: Dictionary) -> void:
	var c = world.characters.get(int(rec.src)) if world else null
	if c and is_instance_valid(c):
		(rec.player as Node3D).global_position = c.global_position + Vector3.UP * (1.35 if int(rec.kind) == 1 else 1.55)


func overheard_players() -> int:
	## Positional voice streams that have received something (tests).
	var n := 0
	for k in _players:
		if int(_players[k].kind) != 0:
			n += 1
	return n


func level() -> float:
	return _level
