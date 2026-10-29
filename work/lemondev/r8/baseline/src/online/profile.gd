extends Node
## The player's own profile (user://profile.json): an id made once on this device, the outfit, level and XP, career
## stats and the last matches. Matches add XP here at once (offline too); when a stats server is reachable the host
## also reports every match there (Online), and the server's totals win if they are ahead (another device, say).

signal changed

const PATH := "user://profile.json"
## --profile=<name> keeps a separate profile (several game processes on one PC in the tests).
var path := PATH
const MAX_LEVEL := 100

var id := ""
var look: Dictionary = {}
var xp := 0
var stats := {"matches": 0, "wins": 0, "top5": 0, "kills": 0, "deaths": 0, "damage": 0.0, "time_s": 0.0, "best_place": 0}
var history: Array = []   # newest first: {date, place, teams, kills, damage, xp, time_s, won}
## r7: the mode the menu plays ("classic" | "deathmatch") and the Deathmatch guns ({"primary": id, "secondary": id}).
var game_mode := "classic"
var loadout: Dictionary = {}


func _ready() -> void:
	if Game.arg("profile"):
		path = "user://profile_%s.json" % str(Game.arg("profile")).validate_filename()
	load_profile()
	# Tests: --game_mode=classic|deathmatch and --loadout=<primary>,<secondary> override the saved choice for this
	# run only (not written to the profile).
	if Game.arg("game_mode"):
		game_mode = "deathmatch" if str(Game.arg("game_mode")) == "deathmatch" else "classic"
	if Game.arg("loadout"):
		var parts := str(Game.arg("loadout")).split(",")
		loadout = {"primary": parts[0], "secondary": parts[1] if parts.size() > 1 else ""}
		loadout = get_loadout()


static func xp_for_level(level: int) -> int:
	## XP needed to go from `level` to the next: 500 at first, 150 more each level.
	return 500 + 150 * (maxi(level, 1) - 1)


func level() -> int:
	return level_of(xp)


static func level_of(total: int) -> int:
	var lv := 1
	var left := total
	while lv < MAX_LEVEL and left >= xp_for_level(lv):
		left -= xp_for_level(lv)
		lv += 1
	return lv


func progress() -> Array:
	## [XP into the current level, XP that level needs]
	var lv := 1
	var left := xp
	while lv < MAX_LEVEL and left >= xp_for_level(lv):
		left -= xp_for_level(lv)
		lv += 1
	return [left, xp_for_level(lv)]


static func match_xp(r: Dictionary) -> int:
	## Taking part 100, each kill 60, damage dealt 1 per 4 points, time alive 1 per 3 s, and the team's place:
	## 1st 400, top 3 200, top 5 120, top 10 50. A two-team match (Deathmatch) pays the place bonus to the winners only.
	var place := int(r.get("place", 99))
	var bonus := 400 if place == 1 else (200 if place <= 3 else (120 if place <= 5 else (50 if place <= 10 else 0)))
	if int(r.get("teams", 99)) <= 2 and place > 1:
		bonus = 0
	return 100 + int(r.get("kills", 0)) * 60 + int(float(r.get("damage", 0.0)) / 4.0) + int(float(r.get("time", 0)) / 3.0) + bonus


func add_match(r: Dictionary) -> Dictionary:
	## A finished match from the results summary (this player's row). Returns {xp, level_before, level_after}.
	var before := level()
	var gained := int(r.get("xp", match_xp(r)))
	xp += gained
	stats.matches = int(stats.matches) + 1
	var place := int(r.get("place", 99))
	if r.get("winner", false):
		stats.wins = int(stats.wins) + 1
	if place <= 5 and int(r.get("teams", 99)) > 2:
		stats.top5 = int(stats.top5) + 1
	stats.kills = int(stats.kills) + int(r.get("kills", 0))
	stats.deaths = int(stats.deaths) + (0 if r.get("winner", false) else 1)
	stats.damage = float(stats.damage) + float(r.get("damage", 0.0))
	stats.time_s = float(stats.time_s) + float(r.get("time", 0))
	if int(stats.best_place) == 0 or place < int(stats.best_place):
		stats.best_place = place
	history.push_front({"date": Time.get_datetime_string_from_system(false, true), "place": place, "teams": int(r.get("teams", 0)),
		"kills": int(r.get("kills", 0)), "damage": int(float(r.get("damage", 0.0))), "xp": gained, "time_s": int(r.get("time", 0)),
		"won": bool(r.get("winner", false))})
	history = history.slice(0, 20)
	save_profile()
	changed.emit()
	return {"xp": gained, "level_before": before, "level_after": level()}


func merge_server(p: Dictionary) -> void:
	## The stats server's record of this profile: take it when it is ahead of what this device knows.
	if int(p.get("xp", 0)) > xp:
		xp = int(p.xp)
		for k in stats:
			if p.has(k):
				stats[k] = p[k]
		save_profile()
		changed.emit()


func set_look(l: Dictionary) -> void:
	look = l.duplicate()
	save_profile()
	changed.emit()
	if Net.online:
		Net.request_look(look)


static func dm_rules() -> Dictionary:
	return Defs.rules.get("deathmatch", {})


func set_game_mode(m: String) -> void:
	game_mode = "deathmatch" if m == "deathmatch" else "classic"
	save_profile()
	changed.emit()


func get_loadout() -> Dictionary:
	## The saved Deathmatch guns, checked against the rules (anything no longer allowed falls back to the default).
	var dm := dm_rules()
	var prim := str(loadout.get("primary", ""))
	var sec := str(loadout.get("secondary", ""))
	if not prim in dm.get("primary", []):
		prim = str(dm.get("default_primary", "rifle_m416"))
	if not sec in dm.get("secondary", []):
		sec = str(dm.get("default_secondary", "pistol_9"))
	return {"primary": prim, "secondary": sec}


func set_loadout(l: Dictionary) -> void:
	## Game Setup changed the guns: save, and tell the server when in a lobby or match.
	loadout = {"primary": str(l.get("primary", "")), "secondary": str(l.get("secondary", ""))}
	loadout = get_loadout()
	save_profile()
	changed.emit()
	send_loadout()


func send_loadout() -> void:
	if Net.online and (not Net.is_server or Net.players.has(Net.local_pid)):
		Net.request_loadout(get_loadout())
		print("[ui] request_loadout %s" % JSON.stringify(get_loadout()))


func load_profile() -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			id = str(d.get("id", ""))
			look = d.get("look", {})
			xp = int(d.get("xp", 0))
			var s: Dictionary = d.get("stats", {})
			for k in s:
				stats[k] = s[k]
			history = d.get("history", [])
			game_mode = "deathmatch" if str(d.get("game_mode", "classic")) == "deathmatch" else "classic"
			var lo = d.get("loadout", {})
			loadout = lo if lo is Dictionary else {}
	if id == "":
		var c := Crypto.new()
		id = c.generate_random_bytes(8).hex_encode()
		save_profile()
	if look.is_empty():
		look = preload("res://src/player/outfit.gd").default_look()


func save_profile() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"id": id, "look": look, "xp": xp, "stats": stats, "history": history,
			"game_mode": game_mode, "loadout": loadout}, " "))
