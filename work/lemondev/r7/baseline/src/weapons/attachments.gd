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
