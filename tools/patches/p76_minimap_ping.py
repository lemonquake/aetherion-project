"""Lite minimap (top-left) and team pings on V with a radio click everyone nearby hears."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

h = Patch('game/src/ui/hud.gd')
h.rep('''var _prompt_t := 0.0
''', '''var _prompt_t := 0.0
var minimap: Control
''')
h.rep('''	_build_loading()
	Net.lobby_changed.connect(func(): pass)''', '''	minimap = preload("res://src/ui/minimap.gd").new()
	minimap.position = Vector2(150, 20) if Settings.touch_active() else Vector2(20, 20)
	minimap.size = Vector2(230, 230)
	root.add_child(minimap)
	minimap.setup(world)
	_build_loading()
	Net.lobby_changed.connect(func(): pass)''')
h.rep('''func toast(text: String) -> void:''', '''func add_ping(eid: int, pos: Vector3) -> void:
	minimap.add_ping(eid, pos, ch != null and is_instance_valid(ch) and ch.eid == eid)


func toast(text: String) -> void:''')
# The "hold Tab" hint is for a box opened with Use; not when Tab itself opened it.
h.rep('''	if not tab_held:
		toast("Hold TAB to see what's inside.")''', '''	if not tab_held and not Input.is_action_pressed("smartab"):
		toast("Hold TAB to see what's inside.")''')
h.save()

w = Patch('game/src/match/world.gd')
w.rep('''func server_sound(id: String, pos: Vector3, db: float = 0.0, except_eid: int = -1) -> void:''', '''var _ping_t: Dictionary = {}     # eid -> time of the last ping (s)


func server_ping(ch: Character) -> void:
	## V: a click on the team radio and this player's position blinking on every teammate's minimap for 5 s. The
	## click comes out of the radio itself, so anyone close enough hears it, enemies included (bots turn to look).
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_ping_t.get(ch.eid, -10.0)) < 1.0 or ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
		return
	_ping_t[ch.eid] = now
	var pos := ch.global_position
	server_sound("radio_click", pos + Vector3.UP * 1.3, 0.0, -1)
	for pid in Net.human_peers():
		if int(Net.players[pid].get("team", -1)) == ch.team:
			_ev_ping.rpc_id(pid, ch.eid, pos)
	if not is_server_dedicated() and int(Net.players.get(Net.local_pid, {}).get("team", -1)) == ch.team:
		_ev_ping(ch.eid, pos)
	var heard := float(SoundSys.defs.get("radio_click", {}).get("dist", 18.0))
	for eid in bots:
		var b = bots[eid]
		if b.ch.team != ch.team and b.ch.global_position.distance_to(pos) < heard:
			b.hear(pos, heard)


@rpc("authority", "call_remote", "reliable")
func _ev_ping(eid: int, pos: Vector3) -> void:
	if hud:
		hud.add_ping(eid, pos)


func server_sound(id: String, pos: Vector3, db: float = 0.0, except_eid: int = -1) -> void:''')
w.save()
