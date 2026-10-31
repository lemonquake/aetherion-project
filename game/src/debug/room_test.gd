extends Node
## r15 lobby host check (`--room_test=alpha|bravo|solo`, with --join to a dedicated server): the first player in an
## official lobby is its host. alpha (joins first): is the host, cannot start while bravo is not Ready, starts once
## bravo is. bravo (joins second): is not the host, its own start is refused. solo: alone, starts at once (bots fill
## the seats). Prints [roomtest] PASS/FAIL lines and quits.

var role := ""
var fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = str(Game.arg("room_test", ""))
	Net.connected_to_server.connect(func(): _run.call_deferred())


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("[roomtest] %s %s %s: %s" % [role, "PASS" if ok else "FAIL", name, detail])


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	await _wait(1.5)
	match role:
		"solo":
			_check("host", Net.is_room_host(), "room host %d, me %d" % [Net.room_host(), Net.local_pid])
			Net.request_start()
			# (r17) A live official lobby counts down before it loads; then this client builds the map and gets a body.
			var t0 := 0.0
			while Game.state == "lobby" and t0 < 30.0:
				await _wait(0.5)
				t0 += 0.5
			_check("starts_alone", Game.state in ["loading", "match"], "state %s after %.1f s" % [Game.state, t0])
			var t1 := 0.0
			while (Game.world == null or Game.world.local_char == null) and t1 < 90.0:
				await _wait(0.5)
				t1 += 0.5
			var w = Game.world
			_check("in_the_match", w != null and w.local_char != null, "state %s, map %s, my character %s, %d characters, match phase %s" % [Game.state,
				str(Net.config.get("map", "")), str(w.local_char.global_position.round()) if w and w.local_char else "-", w.characters.size() if w else 0,
				str(w.match_info.get("phase", "-")) if w else "-"])
		"alpha":
			_check("host", Net.is_room_host(), "room host %d, me %d" % [Net.room_host(), Net.local_pid])
			# wait for bravo
			var t := 0.0
			while Net.humans() < 2 and t < 20.0:
				await _wait(0.5)
				t += 0.5
			_check("bravo_joined", Net.humans() >= 2, "%d humans" % Net.humans())
			_check("waits_for_ready", not Net.not_ready().is_empty(), "not ready: %s" % ", ".join(Net.not_ready()))
			Net.request_start()
			await _wait(2.0)
			_check("start_refused", Game.state == "lobby", "state %s after Start with %s not ready" % [Game.state, ", ".join(Net.not_ready())])
			t = 0.0
			while not Net.not_ready().is_empty() and t < 20.0:
				await _wait(0.5)
				t += 0.5
			Net.request_start()
			t = 0.0
			while Game.state == "lobby" and t < 10.0:
				await _wait(0.5)
				t += 0.5
			_check("starts_when_ready", Game.state in ["loading", "match"], "state %s" % Game.state)
		"bravo":
			_check("not_host", not Net.is_room_host() and Net.room_host() != 0, "room host %d, me %d" % [Net.room_host(), Net.local_pid])
			Net.request_start()
			await _wait(2.0)
			_check("own_start_refused", Game.state == "lobby", "state %s" % Game.state)
			await _wait(2.0)
			Net.request_set_ready(true)
			var t2 := 0.0
			while Game.state == "lobby" and t2 < 15.0:
				await _wait(0.5)
				t2 += 0.5
			_check("match_started", Game.state in ["loading", "match"], "state %s" % Game.state)
	print("[roomtest] %s done: %d failed" % [role, fails])
	await _wait(1.0)
	get_tree().quit(1 if fails else 0)
