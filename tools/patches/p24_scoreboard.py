"""r24: scoreboard stats on the server (K/D/A, damage dealt and received, headshot and grenade kills/deaths), the
board sent to clients on request, and the same numbers in the end-of-match summary."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p24_util import patch

G = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'src')

patch(os.path.join(G, 'match', 'match_server.gd'), [
    ('''		stats[ch.eid] = {"pid": pid, "name": p.name, "team": p.team, "kills": 0, "damage": 0.0, "downs": 0, "alive_t": 0.0, "placed": 0, "bot": p.bot}
''', '''		stats[ch.eid] = new_stats(pid, p, int(p.team))
'''),
    ('''		stats[ch.eid] = {"pid": pid, "name": p.name, "team": team, "kills": 0, "damage": 0.0, "downs": 0, "alive_t": 0.0, "placed": 0, "bot": p.bot}
''', '''		stats[ch.eid] = new_stats(pid, p, team)
'''),
    ('''		_pid_stats[pid] = {"pid": pid, "name": p.name, "team": team, "kills": 0, "damage": 0.0, "downs": 0, "alive_t": 0.0, "placed": 0, "bot": p.bot}
''', '''		_pid_stats[pid] = new_stats(pid, p, team)
'''),
    ('''var _field_enabled := true
''', '''var _field_enabled := true
var _hurt_by := {}            # (r24) victim eid -> {attacker pid: true}: who earns an assist when it dies


static func new_stats(pid: int, p: Dictionary, team: int) -> Dictionary:
	## One player's numbers for the match (r24: the scoreboard's deaths, assists, damage received, headshot and grenade
	## kills and deaths too).
	return {"pid": pid, "name": p.name, "team": team, "kills": 0, "damage": 0.0, "downs": 0, "alive_t": 0.0, "placed": 0, "bot": p.bot,
		"deaths": 0, "assists": 0, "taken": 0.0, "hs_kills": 0, "hs_deaths": 0, "nade_kills": 0, "nade_deaths": 0}
'''),
    ('''func on_killed(ch: Character, attacker: int) -> void:
	if stats.has(attacker) and attacker != ch.eid and world.team_of(attacker) != ch.team:
		stats[attacker].kills += 1
''', '''func on_damage(ch: Character, attacker: int, dmg: float) -> void:
	## (r24) Damage received, and who hurt this life (an assist when someone else finishes it).
	if stats.has(ch.eid):
		stats[ch.eid].taken = float(stats[ch.eid].get("taken", 0.0)) + dmg
	if stats.has(attacker) and attacker != ch.eid and world.team_of(attacker) != ch.team:
		if not _hurt_by.has(ch.eid):
			_hurt_by[ch.eid] = {}
		_hurt_by[ch.eid][int(stats[attacker].pid)] = true


func _stats_of_pid(pid: int):
	if _pid_stats.has(pid):
		return _pid_stats[pid]
	for s in stats.values():
		if int(s.pid) == pid:
			return s
	return null


func _score_death(ch: Character, attacker: int) -> void:
	## (r24) Deaths, assists, headshot and grenade kills and deaths for the scoreboard.
	var cause := str(ch.health.last_cause)
	var hit: Array = ch.get_meta("killing_hit", [""]) if ch.has_meta("killing_hit") else [""]
	var head := cause == "gunshot" and str(hit[0]) == "head"
	var grenade := cause == "explosion"
	var vs = stats.get(ch.eid)
	if vs:
		vs.deaths = int(vs.get("deaths", 0)) + 1
		vs.hs_deaths = int(vs.get("hs_deaths", 0)) + (1 if head else 0)
		vs.nade_deaths = int(vs.get("nade_deaths", 0)) + (1 if grenade else 0)
	var killer_pid := -1
	if stats.has(attacker) and attacker != ch.eid and world.team_of(attacker) != ch.team:
		var ks = stats[attacker]
		killer_pid = int(ks.pid)
		ks.hs_kills = int(ks.get("hs_kills", 0)) + (1 if head else 0)
		ks.nade_kills = int(ks.get("nade_kills", 0)) + (1 if grenade else 0)
	for pid in _hurt_by.get(ch.eid, {}):
		if int(pid) == killer_pid:
			continue
		var s = _stats_of_pid(int(pid))
		if s:
			s.assists = int(s.get("assists", 0)) + 1
	_hurt_by.erase(ch.eid)


func board() -> Array:
	## (r24) The scoreboard: one row per player with every number it shows, and whether they are standing now.
	var standing := {}
	for c in world.characters.values():
		if c.mode in [Motor.GROUND, Motor.FREEFALL, Motor.CHUTE, Motor.PLANE, Motor.DOWNED]:
			standing[c.pid] = true
	var rows := []
	var seen := {}
	for s in (_pid_stats.values() if dm else stats.values()):
		if seen.has(int(s.pid)):
			continue
		seen[int(s.pid)] = true
		rows.append(_board_row(s, standing.has(int(s.pid))))
	return rows


static func _board_row(s: Dictionary, alive: bool) -> Dictionary:
	return {"pid": int(s.pid), "name": str(s.name), "team": int(s.team), "bot": bool(s.bot), "alive": alive,
		"kills": int(s.kills), "deaths": int(s.get("deaths", 0)), "assists": int(s.get("assists", 0)),
		"damage": int(float(s.damage)), "taken": int(float(s.get("taken", 0.0))), "hs_kills": int(s.get("hs_kills", 0)),
		"hs_deaths": int(s.get("hs_deaths", 0)), "nade_kills": int(s.get("nade_kills", 0)), "nade_deaths": int(s.get("nade_deaths", 0))}


func on_killed(ch: Character, attacker: int) -> void:
	if stats.has(attacker) and attacker != ch.eid and world.team_of(attacker) != ch.team:
		stats[attacker].kills += 1
	_score_death(ch, attacker)
'''),
    ('''		rows.append({"pid": int(s.pid), "name": s.name, "team": s.team, "kills": s.kills, "downs": s.downs, "time": int(s.alive_t), "winner": int(s.team) == winner,
			"bot": s.bot, "damage": int(float(s.damage)), "place": place})
''', '''		var row := _board_row(s, false)
		row.merge({"downs": s.downs, "time": int(s.alive_t), "winner": int(s.team) == winner, "place": place}, true)
		rows.append(row)
'''),
])

patch(os.path.join(G, 'match', 'world.gd'), [
    ('''func _count_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	## Damage dealt to the other teams, for XP and the stats.
	if match_server and match_server.stats.has(attacker) and attacker != ch.eid and team_of(attacker) != ch.team:
		match_server.stats[attacker].damage = float(match_server.stats[attacker].damage) + float(res.get("damage", 0.0))
''', '''func _count_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	## Damage dealt to the other teams, for XP and the stats; (r24) damage received and assists for the scoreboard.
	if match_server == null:
		return
	if match_server.stats.has(attacker) and attacker != ch.eid and team_of(attacker) != ch.team:
		match_server.stats[attacker].damage = float(match_server.stats[attacker].damage) + float(res.get("damage", 0.0))
	if float(res.get("damage", 0.0)) > 0.0:
		match_server.on_damage(ch, attacker, float(res.get("damage", 0.0)))


# ------------------------------------------------------------------ r24: the scoreboard (held ~)

var board_rows: Array = []        # the latest scoreboard rows (clients: as the server last sent them)
var board_at := 0                 # msec when they arrived


func request_board() -> void:
	if is_server:
		if match_server:
			board_rows = match_server.board()
			board_at = Time.get_ticks_msec()
	else:
		_req_board.rpc_id(1)


@rpc("any_peer", "reliable")
func _req_board() -> void:
	if is_server and match_server:
		_board.rpc_id(multiplayer.get_remote_sender_id(), match_server.board())


@rpc("authority", "call_remote", "reliable")
func _board(rows: Array) -> void:
	board_rows = rows
	board_at = Time.get_ticks_msec()
'''),
])
