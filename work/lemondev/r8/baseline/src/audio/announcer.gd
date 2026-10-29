extends Node
## The settlement's loudspeakers before every change of the artificial sun: an attention chime and a spoken warning
## 60 s and 30 s ahead, a spoken countdown from ten, and a 7 s siren as the change comes. Every machine runs this
## from the shared match clock (no network traffic). The voice comes from the horns nearest the listener (the next
## horn down the line arrives late and quieter, like a real PA), muffled indoors by the normal sound propagation.

const DayCycle := preload("res://src/world/day_cycle.gd")
## [seconds before the change, cue]
const CUES := [[61.4, "chime"], [60.0, "60"], [31.4, "chime"], [30.0, "30"],
	[10.0, "n10"], [9.0, "n9"], [8.0, "n8"], [7.0, "n7"], [6.0, "n6"], [5.0, "n5"], [4.0, "n4"], [3.0, "n3"],
	[2.0, "n2"], [1.0, "n1"], [0.15, "siren"]]
const WINDOW := 1.2   # a cue missed by more than this (late join, a long frame) is skipped, not played late

var world = null
var fired := {}
## [match time, cue, sound id] of every cue played, for the tests.
var played: Array = []


func setup(w) -> void:
	world = w


func _process(_dt: float) -> void:
	if world == null or world.map == null or world.map.lighting == null or world.match_info.is_empty():
		return
	var t: float = world.map.lighting.match_time()
	if t <= 0.0:
		return
	var nc := DayCycle.next_change(t)
	var at: float = nc[0]
	var kind: String = nc[1]
	var left := at - t
	for i in CUES.size():
		var c: Array = CUES[i]
		var before: float = c[0]
		if left <= before and left > before - WINDOW:
			var key := "%d|%d" % [int(at), i]
			if not fired.has(key):
				fired[key] = true
				_fire(str(c[1]), kind, t)


func _fire(cue: String, kind: String, t: float) -> void:
	var id := ""
	var hud = world.hud
	match cue:
		"chime":
			id = "pa_chime"
		"60", "30":
			id = "pa_%s_%s" % ["ign" if kind == "ignite" else "dusk", cue]
			if hud:
				hud.toast(("Loudspeaker: the artificial sun ignites in %s seconds." if kind == "ignite" else "Loudspeaker: lights out in %s seconds.") % cue)
		"siren":
			id = "pa_siren"
			if hud and hud.has_method("pa_countdown"):
				hud.pa_countdown(0, kind)
		_:
			id = "pa_" + cue
			if hud and hud.has_method("pa_countdown"):
				hud.pa_countdown(int(cue.substr(1)), kind)
	played.append([t, cue, id])
	_play(id)


func _play(id: String) -> void:
	var lp := SoundSys.listener_pos()
	var near := nearest(lp, 2)
	if near.is_empty():
		SoundSys.play_local(id)
		return
	SoundSys.play_at(id, near[0], 0.0, {"prio": 9})
	if near.size() > 1 and lp.distance_to(near[1]) < 260.0:
		SoundSys.play_at(id, near[1], -8.0, {"prio": 8})


func nearest(p: Vector3, n: int) -> Array:
	var best: Array = []   # [[dist, pos]]
	for s in world.map.pa_speakers:
		var q: Vector3 = s.pos
		var d := p.distance_to(q)
		if best.size() < n or d < float(best[-1][0]):
			best.append([d, q])
			best.sort_custom(func(a, b): return a[0] < b[0])
			if best.size() > n:
				best.pop_back()
	return best.map(func(e): return e[1])
