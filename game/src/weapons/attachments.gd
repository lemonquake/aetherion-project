extends RefCounted
## Weapon attachment rules (data in weapons.json "attachments"): one attachment per slot kind (sight, muzzle, grip,
## mag, stock, light), stat multipliers, magazine capacity, and how good an attachment is for a given weapon (used
## when picking up and by bots). Pure functions of the weapon instance {id, att: [...]}, so the server and the
## owner's prediction agree.

const KINDS: Array[String] = ["sight", "muzzle", "grip", "mag", "stock", "light"]


static func kind(att_id: String) -> String:
	return str(Defs.attachments.get(att_id, {}).get("kind", ""))


static func compatible(weapon_id: String, att_id: String) -> bool:
	return att_id in Defs.weapon(weapon_id).get("attachments", [])


static func sanitize(weapon_id: String, ids: Array) -> Array:
	## (r22) A set of attachments someone asked to fit (Game Setup, the saved profile, a client's loadout request):
	## known ids that fit this weapon, at most one per slot kind (the first one asked for wins), in KINDS order. The
	## same answer on every machine, and sanitize(sanitize(x)) == sanitize(x).
	var by_kind := {}
	for a in ids.slice(0, 24):
		var s := str(a)
		if not Defs.attachments.has(s) or not compatible(weapon_id, s):
			continue
		var k := kind(s)
		if k in KINDS and not by_kind.has(k):
			by_kind[k] = s
	var out := []
	for k in KINDS:
		if by_kind.has(k):
			out.append(by_kind[k])
	return out


static func options(weapon_id: String, k: String) -> Array:
	## (r22) The attachment ids of one slot kind this weapon takes, in the weapon's own order (sights by magnification).
	var out := []
	for a in Defs.weapon(weapon_id).get("attachments", []):
		if Defs.attachments.has(str(a)) and kind(str(a)) == k:
			out.append(str(a))
	if k == "sight":
		out.sort_custom(func(x, y): return float(Defs.attachments[x].get("zoom", 1.0)) < float(Defs.attachments[y].get("zoom", 1.0)))
	return out


static func kinds_for(weapon_id: String) -> Array:
	## (r22) The slot kinds this weapon has at least one attachment for, in KINDS order.
	var out := []
	for k in KINDS:
		if not options(weapon_id, k).is_empty():
			out.append(k)
	return out


static func bot_pick(weapon_id: String, rng: RandomNumberGenerator, chance: float = 0.75) -> Array:
	## (r22) A bot's starting attachments for one gun: each slot the gun takes is filled with `chance`, with the best
	## scoring attachment for it after a little noise (sights by how well their zoom suits the gun).
	var out := []
	for k in KINDS:
		var opts := options(weapon_id, k)
		if opts.is_empty() or rng.randf() >= chance:
			continue
		var best := ""
		var best_s := -INF
		for a in opts:
			var s := score(weapon_id, a) + rng.randf_range(0.0, 0.9)
			if s > best_s:
				best_s = s
				best = a
		if best != "":
			out.append(best)
	return out


static func mult(w: Dictionary, key: String) -> float:
	## Product of `key` over the fitted attachments (1.0 when none sets it).
	var m := 1.0
	for a in w.get("att", []):
		m *= float(Defs.attachments.get(a, {}).get(key, 1.0))
	return m


static func flag(w: Dictionary, key: String) -> bool:
	for a in w.get("att", []):
		if bool(Defs.attachments.get(a, {}).get(key, false)):
			return true
	return false


static func in_slot(w: Dictionary, k: String) -> String:
	for a in w.get("att", []):
		if kind(str(a)) == k:
			return str(a)
	return ""


static func sight(w: Dictionary) -> Dictionary:
	var s := in_slot(w, "sight")
	return Defs.attachments.get(s, {}) if s != "" else {}


static func mag_cap(w: Dictionary) -> int:
	var d := Defs.weapon(str(w.get("id", "")))
	var cap := int(d.get("mag_size", 1))
	if flag(w, "ext"):
		cap = int(d.get("mag_ext", cap))
	var m := mult(w, "cap_mult")   # (r24) drums
	if m > 1.0:
		cap = maxi(cap, int(round(float(d.get("mag_size", 1)) * m)))
	return cap


static func bitmask(w: Dictionary) -> int:
	## Fitted attachments as bits of the sorted attachment id list (replicated for other players' views).
	var ids := ids_sorted()
	var m := 0
	for a in w.get("att", []):
		var i := ids.find(str(a))
		if i >= 0:
			m |= 1 << i
	return m


static func from_bitmask(m: int) -> Array:
	var out := []
	var ids := ids_sorted()
	for i in ids.size():
		if m & (1 << i):
			out.append(ids[i])
	return out


static var _ids: Array = []


static func ids_sorted() -> Array:
	if _ids.size() != Defs.attachments.size():
		_ids = Defs.attachments.keys()
		_ids.sort()
	return _ids


static func preferred_zoom(weapon_id: String) -> float:
	match str(Defs.weapon(weapon_id).get("class", "")):
		"handgun", "shotgun":
			return 1.3
		"smg":
			return 1.6
		"rifle":
			return 3.0
		"marksman":
			return 5.0
		"precision":
			return 6.5
	return 1.3


static func score(weapon_id: String, att_id: String) -> float:
	## How much an attachment is worth on this weapon (0 = incompatible). Sights are scored by how close their
	## magnification is to what the weapon is good for.
	if not compatible(weapon_id, att_id):
		return 0.0
	var a: Dictionary = Defs.attachments.get(att_id, {})
	if kind(att_id) == "sight":
		var z := float(a.get("zoom", 1.3))
		return 3.5 - absf(log(z / preferred_zoom(weapon_id)) / log(2.0)) * 1.2
	return float(a.get("rank", 1.0))


## (r24) What each multiplier means to a player, for the workbench's hover card: [what it changes, whether a smaller
## multiplier is the better one, wording when it improves, wording when it gets worse].
const EFFECT_TEXT := [
	["recoil_up_mult", true, "+%d%% vertical recoil control", "%d%% more vertical recoil"],
	["recoil_side_mult", true, "+%d%% horizontal recoil control", "%d%% more horizontal recoil"],
	["recovery_mult", false, "+%d%% recoil recovery", "%d%% slower recoil recovery"],
	["sway_mult", true, "+%d%% weapon sway resistance", "%d%% more weapon sway"],
	["ads_time_mult", true, "%d%% faster aiming", "%d%% slower aiming"],
	["reload_mult", true, "%d%% faster reload", "%d%% slower reload"],
	["spread_hip_mult", true, "+%d%% hip-fire accuracy", "%d%% wider hip-fire spread"],
	["move_spread_mult", true, "+%d%% accuracy while moving", "%d%% less accurate while moving"],
	["pellet_spread_mult", true, "%d%% tighter pellet spread", "%d%% wider pellet spread"],
	["loudness_mult", true, "%d%% quieter shots", "%d%% louder shots"],
	["flash_mult", true, "%d%% less muzzle flash", "%d%% brighter muzzle flash"],
]


static func effects(att_id: String, weapon_id: String = "") -> Array:
	## (r24) [text, good] lines saying what an attachment does (on this gun, for magazine sizes).
	var a: Dictionary = Defs.attachments.get(att_id, {})
	var out := []
	if a.has("zoom"):
		var z := "%sx magnification" % String.num(float(a.zoom), 1)
		if a.has("zoom_min"):
			z = "%s-%sx variable magnification" % [String.num(float(a.zoom_min), 1), String.num(float(a.zoom), 1)]
		out.append([z, true])
	if weapon_id != "" and (bool(a.get("ext", false)) or float(a.get("cap_mult", 1.0)) > 1.0):
		var base := mag_cap({"id": weapon_id, "att": []})
		var more := mag_cap({"id": weapon_id, "att": [att_id]})
		if more > base:
			out.append(["+%d rounds per magazine (%d -> %d)" % [more - base, base, more], true])
	elif bool(a.get("ext", false)):
		out.append(["More rounds per magazine", true])
	elif float(a.get("cap_mult", 1.0)) > 1.0:
		out.append(["%d%% more rounds per magazine" % roundi((float(a.cap_mult) - 1.0) * 100.0), true])
	for e in EFFECT_TEXT:
		if not a.has(e[0]):
			continue
		var m := float(a[e[0]])
		if absf(m - 1.0) < 0.005:
			continue
		var pct := roundi(absf(m - 1.0) * 100.0)
		var good: bool = (m < 1.0) == bool(e[1])
		out.append([(str(e[2]) if good else str(e[3])) % pct, good])
	if bool(a.get("suppressed", false)):
		out.append(["Suppressed: shots are hard to hear and to trace back", true])
	if bool(a.get("laser", false)):
		out.append(["Laser pointer (V)", true])
	if att_id == "weapon_light":
		out.append(["Flashlight on the gun (F)", true])
	if str(a.get("filter", "")) == "thermal":
		out.append(["Outlines enemies through smoke and darkness", true])
	elif str(a.get("filter", "")) == "night":
		out.append(["Brightens the dark", true])
	if a.has("mass"):
		out.append(["Weight %.2f kg" % float(a.mass), float(a.mass) < 0.3])
	return out


static func best_slot_upgrade(weapons: Array, att_id: String) -> Array:
	## [slot index, gain] of the weapon that gains most from this attachment (gain over what it has in that slot).
	var best := [-1, 0.0]
	for s in weapons.size():
		var w = weapons[s]
		if w == null:
			continue
		var sc := score(str(w.id), att_id)
		if sc <= 0.0:
			continue
		var cur := in_slot(w, kind(att_id))
		var gain := sc - (score(str(w.id), cur) if cur != "" else 0.0)
		if gain > best[1] + 0.01:
			best = [s, gain]
	return best
