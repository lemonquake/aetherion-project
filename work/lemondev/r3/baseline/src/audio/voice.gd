extends Node
## Team voice. Push-to-talk (or voice activation) captures the microphone, encodes 40 ms frames and sends them to
## the server, which relays them to teammates only. The server also plays a short radio click and faint static
## from the speaker's body for anyone within ~14 m (enemies hear that a radio keyed, not what was said).
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
var _players: Dictionary = {}  # pid -> {player, playback}
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
		SoundSys.play_local("radio_on" if talking else "radio_off", -10.0)
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


func _on_voice(from_pid: int, bytes: PackedByteArray) -> void:
	if not _players.has(from_pid):
		var p := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.5
		p.stream = gen
		p.bus = "Voice"
		add_child(p)
		p.play()
		_players[from_pid] = {"player": p, "pb": p.get_stream_playback()}
	var pb: AudioStreamGeneratorPlayback = _players[from_pid].pb
	var frames := PackedVector2Array()
	frames.resize(bytes.size())
	for i in bytes.size():
		var s := _unulaw(bytes[i])
		frames[i] = Vector2(s, s)
	if pb.can_push_buffer(frames.size()):
		pb.push_buffer(frames)


func level() -> float:
	return _level
