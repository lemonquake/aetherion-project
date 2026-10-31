extends Node
## The settlement's loudspeakers before every change of the artificial sun: an attention chime and a spoken warning
## 60 s and 30 s ahead, a spoken countdown from ten, and a 7 s siren as the change comes. Every machine runs this
## from the shared match clock (no network traffic). The voice comes from the horns nearest the listener (the next
## horn down the line arrives late and quieter, like a real PA), muffled indoors by the normal sound propagation.
##
## r11, Lawless Sub's cage: the speaker stacks on the cage wall (map.pa_speakers kind "cage"/"tower") carry the
## cage announcer (pa_cage_*: a radio-linked voice in a steel arena). Besides the day/night cues it announces the
## start of the trial, each closing of the containment, the final phase, every team eliminated and the end, and
## between those an ambient line about every 100 s (picked from the match clock, so every player hears the same
## line at the same moment). Three stacks speak at once; SoundSys delays each by its distance, so the far ones
## arrive as echoes across the arena.

const DayCycle := preload("res://src/world/day_cycle.gd")
## [seconds before the change, cue]
const CUES := [[61.4, "chime"], [60.0, "60"], [31.4, "chime"], [30.0, "30"],
	[10.0, "n10"], [9.0, "n9"], [8.0, "n8"], [7.0, "n7"], [6.0, "n6"], [5.0, "n5"], [4.0, "n4"], [3.0, "n3"],
	[2.0, "n2"], [1.0, "n1"], [0.15, "siren"]]
const WINDOW := 1.2   # a cue missed by more than this (late join, a long frame) is skipped, not played late
const AMBIENT_EVERY := 101.0
const AMBIENT_LINES := 6
const CAGE_TEXT := {
	"pa_cage_start": "Attention, subjects. The trial has begun. Only one team will leave this enclosure.",
	"pa_cage_zone": "Containment is closing. Move inside the marked area.",
	"pa_cage_zone_final": "Final containment phase. Remain inside the line.",
	"pa_cage_team_out": "A team has been eliminated.",
	"pa_cage_end": "The trial is over. Survivors, remain where you are.",
	"pa_cage_amb_1": "Remain calm. You are being observed.",
	"pa_cage_amb_2": "Do not approach the perimeter wall.",
	"pa_cage_amb_3": "Reminder: teams that work together survive longer.",
	"pa_cage_amb_4": "Food and water are not provided. Please do not ask.",
	"pa_cage_amb_5": "This enclosure is for your protection.",
	"pa_cage_amb_6": "Subjects found at the wall will be... discouraged.",
}

var world = null
var fired := {}
## [match time, cue, sound id] of every cue played, for the tests.
var played: Array = []
var _busy_until := 0.0     # match time the last spoken line ends (ambient lines wait for it)
var _last_zone := ""
var _last_alive := {}
var _last_phase := ""


func setup(w) -> void:
	world = w


func is_cage() -> bool:
	if world == null or world.map == null or world.map.pa_speakers.is_empty():
		return false
	return str(world.map.pa_speakers[0].get("kind", "")) in ["cage", "tower"]


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
	if is_cage():
		_cage_events(t, left)


func _cage_events(t: float, left: float) -> void:
	## Match events read from the replicated match state, the same on every machine. t is the clock of the day
	## cycle (a round may start at a seeded time of day); el is the time since the round started.
	var info: Dictionary = world.match_info
	var phase := str(info.get("phase", ""))
	var el := float(Net.tick - int(info.get("t0", Net.tick))) / float(Defs.TICK_RATE)
	if phase != _last_phase:
		if phase == "playing" and _last_phase in ["", "plane", "lobby", "loading"] and el < 40.0:
			_say("pa_cage_start", t, 1.2)
		elif phase == "ended" and _last_phase == "playing":
			_say("pa_cage_end", t, 0.0)
		_last_phase = phase
	var zone: Dictionary = info.get("zone", {})
	var zkey := "%d|%s" % [int(zone.get("i", -1)), str(zone.get("state", ""))]
	if zkey != _last_zone:
		if str(zone.get("state", "")) == "shrink" and _last_zone != "":
			var phases: Array = Defs.rule("deathmatch.zone.phases", [])
			_say("pa_cage_zone_final" if int(zone.get("i", 0)) >= phases.size() - 1 else "pa_cage_zone", t, 0.0)
		_last_zone = zkey
	var alive: Dictionary = info.get("alive", {})
	for k in alive:
		var n := int(alive[k])
		if _last_alive.has(k) and int(_last_alive[k]) > 0 and n == 0 and phase == "playing":
			_say("pa_cage_team_out", t, 0.6)
	_last_alive = alive.duplicate()
	# Ambient lines between the others, never over the day/night warnings.
	if phase == "playing" and el > 30.0 and t > _busy_until + 4.0 and (left > 75.0 or left < -3.0):
		var slot := int(floor(el / AMBIENT_EVERY))
		var key := "amb|%d" % slot
		if not fired.has(key) and fmod(el, AMBIENT_EVERY) > 40.0:
			fired[key] = true
			var pick := (slot * 7 + int(Game.match_seed)) % AMBIENT_LINES + 1
			_say("pa_cage_amb_%d" % pick, t, 0.0)


func _say(id: String, t: float, delay: float) -> void:
	## A cage line (and its subtitle): after an optional short delay, from the stacks nearest the listener.
	played.append([t, id, id])
	_busy_until = maxf(_busy_until, t + delay + 7.0)
	var hud = world.hud
	if hud and CAGE_TEXT.has(id):
		hud.toast("Loudspeaker: " + str(CAGE_TEXT[id]))
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): _play(id))
	else:
		_play(id)


func _fire(cue: String, kind: String, t: float) -> void:
	var id := ""
	var hud = world.hud
	var cage := is_cage()
	var pre := "pa_cage_" if cage else "pa_"
	match cue:
		"chime":
			id = pre + "chime"
		"60", "30":
			id = (pre + "%s_%s") % ["ign" if kind == "ignite" else "dusk", cue]
			if hud:
				if cage:
					hud.toast(("Loudspeaker: the daylight phase begins in %s seconds." if kind == "ignite" else "Loudspeaker: the night phase begins in %s seconds.") % cue)
				else:
					hud.toast(("Loudspeaker: the artificial sun ignites in %s seconds." if kind == "ignite" else "Loudspeaker: lights out in %s seconds.") % cue)
		"siren":
			id = pre + "siren"
			if hud and hud.has_method("pa_countdown"):
				hud.pa_countdown(0, kind)
		_:
			id = pre + cue
			if hud and hud.has_method("pa_countdown"):
				hud.pa_countdown(int(cue.substr(1)), kind)
	played.append([t, cue, id])
	if cue in ["60", "30"]:
		_busy_until = maxf(_busy_until, t + 12.0)
	_play(id)


func _play(id: String) -> void:
	var lp = SoundSys.listener_pos()
	var cage := is_cage()
	var near := nearest(lp, 3 if cage else 2)
	if near.is_empty():
		SoundSys.play_local(id)
		return
	SoundSys.play_at(id, near[0], 0.0, {"prio": 9})
	if cage:
		# The next stacks along the cage: later (SoundSys adds the distance delay) and quieter, so the line rolls
		# across the arena off the steel.
		for k in range(1, near.size()):
			if lp.distance_to(near[k]) < 420.0:
				SoundSys.play_at(id, near[k], -4.0 - 3.0 * k, {"prio": 8})
	elif near.size() > 1 and lp.distance_to(near[1]) < 260.0:
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
