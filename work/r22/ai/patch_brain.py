"""r22: move bot_brain.gd's decision code into bot_mind.gd (the LimboAI-style layer); the brain keeps the leaf skills.

    python -I work/r22/ai/patch_brain.py

Edits game/src/ai/bot_brain.gd in place (CRLF kept). Each replacement must match exactly once.
"""
import re
import sys

P = "game/src/ai/bot_brain.gd"
raw = open(P, "rb").read().decode("utf-8")
crlf = "\r\n" in raw
s = raw.replace("\r\n", "\n")


def rep(old, new, cnt=1):
    global s
    n = s.count(old)
    if n != cnt:
        sys.exit("expected %d match(es), found %d for:\n%s" % (cnt, n, old[:300]))
    s = s.replace(old, new)


def cut_func(name, until_marker=None):
    """Remove 'func name(...)' through the line before the next top-level func/var/const/comment block."""
    global s
    m = re.search(r"^func %s\(.*?(?=^(?:func |static func |var |const |# -{10,}))" % re.escape(name), s, re.S | re.M)
    if not m:
        sys.exit("function %s not found" % name)
    s = s[:m.start()] + s[m.end():]


# --- header
rep("""## aim, vision and hold times; pro bots also fight by their gun and the moment (_pro_footwork).
""", """## aim, vision and hold times; pro bots also fight by their gun and the moment (the pro tactics).
##
## (r22) What to do is decided by the bot's mind (bot_mind.gd), built on the LimboAI architecture (src/ai/limbo): a body
## machine every tick (airborne, downed, out of the water, playing), a mind machine four times a second (combat,
## recover, evacuate, directed, ready, objective; one ordered table of guards picks the mode, and each mode is a
## behaviour tree of decisions), and a motor machine every tick running the activity the state label names (move,
## hold, fetch, order, follow, heal, and fight: the combat tree of aim, trigger and footwork). This file keeps the senses
## and the skills those trees call: perception, the walk and paths, doors, unsticking, the house search, holds, aim and
## the trigger. `state` is still the activity label the logs, tests and the motor read.
""")

# --- team intel moves to the team's blackboard (BotTeam.board)
rep("""static var team_intel := {}
""", "")
rep("""	team_targets = {}
	team_intel = {}
""", """	team_targets = {}
""")
rep("""		team_intel["%d:%d" % [Game.match_seed, ch.team]] = {"p": last_seen, "t": Time.get_ticks_msec()}
""", """		BotTeam.board(ch.team).set_var(&"intel", {"p": last_seen, "t": Time.get_ticks_msec()})
""")
rep("""	var it: Dictionary = team_intel.get("%d:%d" % [Game.match_seed, ch.team], {})
""", """	var it: Dictionary = BotTeam.board(ch.team).get_var(&"intel", {})
""")
rep("""		team_intel["%d:%d" % [Game.match_seed, ch.team]] = {"p": h, "t": Time.get_ticks_msec()}
""", """		BotTeam.board(ch.team).set_var(&"intel", {"p": h, "t": Time.get_ticks_msec()})
""")
rep("""## inside the haze line, and loots only when it helps (low on rounds, or a clearly better gun close by).
""", """## inside the haze line, and loots only when it helps (low on rounds, or a clearly better gun close by). (r22) The
## callout is the team's blackboard "intel" (BotTeam.board).
""")

# --- the decision layer's fields
rep("""var _f_o = null                   # fight: the target, its range and the yaw that is on it (set by _fight_aim)
var _f_d := 0.0
var _f_want_yaw := 0.0
""", """var _f_o = null                   # fight: the target, its range and the yaw that is on it (set by _fight_aim)
var _f_d := 0.0
var _f_want_yaw := 0.0
var _f_side := 0.0                # pro: which way it strafes, and the class of the gun in hand (set by _pro_tick)
var _f_cls := ""
""")

# --- think: the mind decides; the per-tick upkeep the mind calls
rep("""func _finish(dt: float) -> void:
	## After the leaves: the light, the field, edges, then the view is kept and the debug traces written.
""", """func _finish(dt: float) -> void:
	## After the activity: the light, the field, edges, then the view is kept and the debug traces written.
""")
rep("""	print("[bot %s] %s step %d/%d %s at %s -> %s (%.1f m) path %d/%d stuck %.1f btn %d%s" % [ch.pname, state, plan_i, plan.size(),""",
    """	if mind != null:
		extra += " | " + str(mind.describe())
	print("[bot %s] %s step %d/%d %s at %s -> %s (%.1f m) path %d/%d stuck %.1f btn %d%s" % [ch.pname, state, plan_i, plan.size(),""")

# --- _choose_state goes (bot_mind.gd: the guard table and the trees)
cut_func("_choose_state")

# --- water: the way out found first (the body's survive guard), then walked
rep("""func _escape_water(cmd: Dictionary, dt: float) -> bool:
	## Wading a moment is fine; after that, climb a ladder if one is close, else walk to the nearest dry ground: into a
	## canal wall the hands catch its coping and the bot climbs out (Parkour.water_grab), up a sloped bank it walks out.
	## (r22) _wet_step decides when (and counts the time wading). False: no dry ground near at all.
	var p: Vector3 = ch.global_position
	var best := {}
	var bd := 12.0
	for ld in world.map.ladders:
		var b: Vector3 = ld.base
		if b.y > p.y + 1.0:
			continue
		var dd := Vector2(b.x - p.x, b.z - p.z).length()
		if dd < bd:
			bd = dd
			best = ld
	cmd.pitch = lerpf(pitch, 0.25, 0.2)
	cmd.my = 1.0
	if not best.is_empty():
		ch.set_meta("ladder_ok", true)
		var n: Vector3 = best.n
		var foot: Vector3 = (best.base as Vector3) + n * 0.3
		var to := Vector2(foot.x - p.x, foot.z - p.z)
		if to.length() > 0.35 and ch.is_on_floor():
			cmd.yaw = lerp_angle(yaw, atan2(-to.x, -to.y), 0.3)
		else:
			cmd.yaw = lerp_angle(yaw, atan2(n.x, n.z), 0.5)
		return true
	# No ladder close: the closest dry point round about.
	ch.set_meta("climb_ok", true)
	_haul = true
	for r in [2.0, 4.0, 7.0, 11.0, 16.0, 22.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var q = Vector2(p.x, p.z) + Vector2(cos(a), sin(a)) * r
			if not world.map.layout.is_water(q.x, q.y):
				var to2 = q - Vector2(p.x, p.z)
				cmd.yaw = lerp_angle(yaw, atan2(-to2.x, -to2.y), 0.3)
				if _stuck_t > 1.0:
					cmd.btn |= Motor.B_JUMP
				var moved := p.distance_to(_last_pos)
				_last_pos = p
				_stuck_t = _stuck_t + dt if moved < 0.4 * dt else 0.0
				return true
	return false
""", """func _water_way() -> Dictionary:
	## The way out of the water: {ladder} when one is close, else {dry: the closest dry point round about}, else {} (no
	## dry ground near at all: carry on as usual). (r22) _wet_step decides when (and counts the time wading).
	var p: Vector3 = ch.global_position
	var best := {}
	var bd := 12.0
	for ld in world.map.ladders:
		var b: Vector3 = ld.base
		if b.y > p.y + 1.0:
			continue
		var dd := Vector2(b.x - p.x, b.z - p.z).length()
		if dd < bd:
			bd = dd
			best = ld
	if not best.is_empty():
		return {"ladder": best}
	for r in [2.0, 4.0, 7.0, 11.0, 16.0, 22.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var q = Vector2(p.x, p.z) + Vector2(cos(a), sin(a)) * r
			if not world.map.layout.is_water(q.x, q.y):
				return {"dry": q}
	return {}


func _escape_water(cmd: Dictionary, dt: float, way: Dictionary) -> void:
	## Wading a moment is fine; after that, climb a ladder if one is close, else walk to the nearest dry ground: into a
	## canal wall the hands catch its coping and the bot climbs out (Parkour.water_grab), up a sloped bank it walks out.
	var p: Vector3 = ch.global_position
	cmd.pitch = lerpf(pitch, 0.25, 0.2)
	cmd.my = 1.0
	if way.has("ladder"):
		var best: Dictionary = way.ladder
		ch.set_meta("ladder_ok", true)
		var n: Vector3 = best.n
		var foot: Vector3 = (best.base as Vector3) + n * 0.3
		var to := Vector2(foot.x - p.x, foot.z - p.z)
		if to.length() > 0.35 and ch.is_on_floor():
			cmd.yaw = lerp_angle(yaw, atan2(-to.x, -to.y), 0.3)
		else:
			cmd.yaw = lerp_angle(yaw, atan2(n.x, n.z), 0.5)
		return
	ch.set_meta("climb_ok", true)
	_haul = true
	var to2: Vector2 = (way.dry as Vector2) - Vector2(p.x, p.z)
	cmd.yaw = lerp_angle(yaw, atan2(-to2.x, -to2.y), 0.3)
	if _stuck_t > 1.0:
		cmd.btn |= Motor.B_JUMP
	var moved := p.distance_to(_last_pos)
	_last_pos = p
	_stuck_t = _stuck_t + dt if moved < 0.4 * dt else 0.0
""")

# --- the fight: leaf skills for the combat tree
rep("""func _fight(cmd: Dictionary, dt: float) -> void:
	var o = world.characters.get(target_eid)
	if o == null:
		target_eid = -1
		return
	var d0: float = o.global_position.distance_to(ch.global_position)""", """# r22: the fight's leaf skills. The combat tree (bot_mind.gd) runs them every tick: _fight_aim, then unarmed
# _fight_flee, else _fight_trigger and the footwork (_pro_* for pro bots, else _fight_temperament).

func _fight_aim(cmd: Dictionary, dt: float) -> bool:
	## On the target (its head at range for pro), off by the skill's aim error as it settles. False: it is gone.
	var o = world.characters.get(target_eid)
	if o == null:
		target_eid = -1
		return false
	var d0: float = o.global_position.distance_to(ch.global_position)""")
rep("""	cmd.yaw = lerp_angle(yaw, want_yaw + deg_to_rad(err.x), minf(dt * _sk_lerp, 1.0))
	cmd.pitch = lerpf(pitch, want_pitch + deg_to_rad(err.y), minf(dt * _sk_lerp, 1.0))
	var d = to.length()
	reaction -= dt
	if ch.wpn.current_id() == "":
		# Unarmed: get away.
		cmd.yaw = want_yaw + PI
		cmd.my = 1.0
		cmd.btn |= Motor.B_SPRINT
		return
	if d < 25.0 or ch.wpn.zoom() > 1.5:
		cmd.btn |= Motor.B_AIM
	if ch.wpn.loaded() == 0:""", """	cmd.yaw = lerp_angle(yaw, want_yaw + deg_to_rad(err.x), minf(dt * _sk_lerp, 1.0))
	cmd.pitch = lerpf(pitch, want_pitch + deg_to_rad(err.y), minf(dt * _sk_lerp, 1.0))
	_f_o = o
	_f_d = to.length()
	_f_want_yaw = want_yaw
	reaction -= dt
	return true


func _fight_flee(cmd: Dictionary) -> void:
	## Unarmed: get away.
	cmd.yaw = _f_want_yaw + PI
	cmd.my = 1.0
	cmd.btn |= Motor.B_SPRINT


func _fight_trigger(cmd: Dictionary, dt: float) -> void:
	## Aim down the sights close or scoped; reload an empty gun; once reacted and on target, fire (bursts with an auto).
	var d := _f_d
	if d < 25.0 or ch.wpn.zoom() > 1.5:
		cmd.btn |= Motor.B_AIM
	if ch.wpn.loaded() == 0:""")
rep("""	elif reaction <= 0.0 and absf(wrapf(want_yaw - yaw, -PI, PI)) < _sk_gate:
		_fire_hold -= dt
		if _fire_hold < 0.0:
			_fire_hold = rng.randf_range(_sk_burst.x, _sk_burst.y)
		if _fire_hold > 0.1 or ch.wpn.fire_mode() != "auto":
			cmd.btn |= Motor.B_FIRE if rng.randf() < _sk_fire else 0
	if _sk_tactics:
		_pro_footwork(cmd, o, d, dt)
		return
	# Footwork by temperament: rushers close in, snipers and campers keep still (crouched at range), the rest strafe.
	match role:""", """	elif reaction <= 0.0 and absf(wrapf(_f_want_yaw - yaw, -PI, PI)) < _sk_gate:
		_fire_hold -= dt
		if _fire_hold < 0.0:
			_fire_hold = rng.randf_range(_sk_burst.x, _sk_burst.y)
		if _fire_hold > 0.1 or ch.wpn.fire_mode() != "auto":
			cmd.btn |= Motor.B_FIRE if rng.randf() < _sk_fire else 0


func _fight_temperament(cmd: Dictionary) -> void:
	## Footwork by temperament: rushers close in, snipers and campers keep still (crouched at range), the rest strafe.
	var d := _f_d
	match role:""")

# --- pro footwork: one leaf per tactic
rep("""func _pro_footwork(cmd: Dictionary, o, d: float, dt: float) -> void:
	## r22 pro: fights by what it holds and what it sees. A marksman or bolt gun stays at range, crouched behind the
	## scope, and backs off (to its handgun) when the enemy closes; out of rounds, or down to a handgun, it rushes; with an
	## smg, rifle, shotgun or lmg it pushes an opening; reloading it gets out of the line of fire.
	_tac_t -= dt
	if _tac_t <= 0.0:
		_tac_t = 0.25
		_pro_read(o, d)
	var side := sin(Time.get_ticks_msec() * 0.003 + ch.eid)
	var cls := str(ch.wpn.def().get("class", ""))
	if ch.wpn.state == WeaponState.RELOAD and not _rush and d < 40.0:
		cmd.my = -0.8
		cmd.mx = 1.0 if side >= 0.0 else -1.0
		cmd.btn = int(cmd.btn) & ~Motor.B_AIM
		return
	if _rush:
		cmd.mx = side
		cmd.my = 1.0 if d > 3.0 else 0.0
		if d > 8.0:
			cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~Motor.B_AIM
		return
	if cls in ["marksman", "precision"]:
		if d > 30.0:
			cmd.mx = 0.0
			cmd.my = 0.0
			cmd.btn = int(cmd.btn) | Motor.B_CROUCH | Motor.B_AIM
		elif d < 20.0:
			cmd.my = -1.0
			cmd.mx = side * 0.7
		else:
			cmd.mx = side * 0.5
			cmd.btn = int(cmd.btn) | Motor.B_AIM
		return
	if _push and d > 4.0 and cls in ["smg", "rifle", "shotgun", "lmg"]:
		cmd.mx = side
		cmd.my = 1.0
		if d > 15.0 and cls != "lmg":
			cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~Motor.B_AIM
		return
	cmd.mx = side * 0.8
	if d > 35.0:
		cmd.my = 0.5
	if ch.health.health < 35.0 and d < 25.0:
		cmd.my = -0.7
""", """# r22 pro: fights by what it holds and what it sees. A marksman or bolt gun stays at range, crouched behind the scope,
# and backs off (to its handgun) when the enemy closes; out of rounds, or down to a handgun, it rushes; with an smg,
# rifle, shotgun or lmg it pushes an opening; reloading it gets out of the line of fire. The combat tree picks the
# first that applies (bot_mind.gd), in that order: reloading, rush, long gun, opening, else strafe.

func _pro_tick(dt: float) -> void:
	## Every tick: the strafe side and the gun's class; four times a second, the read of the fight (_pro_read).
	_tac_t -= dt
	if _tac_t <= 0.0:
		_tac_t = 0.25
		_pro_read(_f_o, _f_d)
	_f_side = sin(Time.get_ticks_msec() * 0.003 + ch.eid)
	_f_cls = str(ch.wpn.def().get("class", ""))


func _pro_reloading_exposed() -> bool:
	return ch.wpn.state == WeaponState.RELOAD and not _rush and _f_d < 40.0


func _pro_back_off(cmd: Dictionary) -> void:
	cmd.my = -0.8
	cmd.mx = 1.0 if _f_side >= 0.0 else -1.0
	cmd.btn = int(cmd.btn) & ~Motor.B_AIM


func _pro_rush(cmd: Dictionary) -> void:
	cmd.mx = _f_side
	cmd.my = 1.0 if _f_d > 3.0 else 0.0
	if _f_d > 8.0:
		cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~Motor.B_AIM


func _pro_range(cmd: Dictionary) -> void:
	if _f_d > 30.0:
		cmd.mx = 0.0
		cmd.my = 0.0
		cmd.btn = int(cmd.btn) | Motor.B_CROUCH | Motor.B_AIM
	elif _f_d < 20.0:
		cmd.my = -1.0
		cmd.mx = _f_side * 0.7
	else:
		cmd.mx = _f_side * 0.5
		cmd.btn = int(cmd.btn) | Motor.B_AIM


func _pro_push(cmd: Dictionary) -> void:
	cmd.mx = _f_side
	cmd.my = 1.0
	if _f_d > 15.0 and _f_cls != "lmg":
		cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~Motor.B_AIM


func _pro_strafe(cmd: Dictionary) -> void:
	cmd.mx = _f_side * 0.8
	if _f_d > 35.0:
		cmd.my = 0.5
	if ch.health.health < 35.0 and _f_d < 25.0:
		cmd.my = -0.7
""")

# --- the role objectives go (bot_mind.gd: the role trees and the endgame tree)
cut_func("_role_objective")
cut_func("_ambush")
cut_func("_endgame_objective")
rep("""	## r22 [botskill] numbers""", """	## r22 [botskill] numbers""")

out = s.replace("\n", "\r\n") if crlf else s
open(P, "wb").write(out.encode("utf-8"))
print("patched", P)
