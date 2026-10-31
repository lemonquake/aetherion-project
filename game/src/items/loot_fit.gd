extends RefCounted
## r14: how an item suits a character's kit, for the SmarTab (useless items in the bag are red, suitable ones nearby
## green) and for the outline drawn round suitable loot on the ground. Pure functions of what the character carries.
##
## Suitable: ammunition one of the carried guns fires, an attachment that improves a carried gun (better than what is
## on it in that mount), armour or a backpack better than what is worn.
## Useless: ammunition no carried gun fires, an attachment no carried gun takes, batteries with nothing to power.

const Attach := preload("res://src/weapons/attachments.gd")


static func guns(ch) -> Array:
	var out := []
	if ch == null or ch.wpn == null:
		return out
	for s in [1, 2, 3]:
		if ch.wpn.slots[s] != null:
			out.append(ch.wpn.slots[s])
	return out


static func ammo_wanted(ch) -> Dictionary:
	var out := {}
	for w in guns(ch):
		out["ammo_" + str(Defs.weapon(str(w.id)).get("ammo", ""))] = true
	return out


static func suitable(ch, e: Dictionary) -> bool:
	var id := str(e.get("id", ""))
	if id.begins_with("ammo_"):
		return ammo_wanted(ch).has(id)
	if Defs.is_attachment(id):
		return float(Attach.best_slot_upgrade(ch.wpn.slots, id)[1]) > 0.05
	var d := Defs.item(id)
	match str(d.get("kind", "")):
		"armor":
			var slot := str(d.get("slot", "vest"))
			var worn = ch.inv.gear.get(slot) if ch.inv else null
			if worn == null:
				return true
			var wd := Defs.item(str(worn.id))
			# Heavier armour is the stronger one (its durability); a broken piece is beaten by anything.
			var cur_left := float(worn.get("d", 0.0))
			return float(d.get("durability", 0)) > float(wd.get("durability", 0)) or (cur_left <= 0.0) \
				or float(e.get("d", d.get("durability", 0))) > cur_left + 25.0 and str(e.get("id", "")) == str(worn.id)
		"backpack":
			var bp = ch.inv.gear.get("backpack") if ch.inv else null
			return bp == null or float(d.get("capacity", 0.0)) > float(Defs.item(str(bp.id)).get("capacity", 0.0))
	return false


static func useless(ch, e: Dictionary) -> bool:
	var id := str(e.get("id", ""))
	if id.begins_with("ammo_"):
		return not ammo_wanted(ch).has(id)
	if Defs.is_attachment(id):
		for w in guns(ch):
			if Attach.compatible(str(w.id), id):
				return false
		return true
	if id == "battery":
		if ch.inv and ch.inv.gear.get("flashlight") != null:
			return false
		for w in guns(ch):
			if "weapon_light" in w.get("att", []):
				return false
		return true
	return false


static func why_useless(ch, e: Dictionary) -> String:
	var id := str(e.get("id", ""))
	if id.begins_with("ammo_"):
		return "No gun you carry fires this"
	if Defs.is_attachment(id):
		return "Fits none of your guns"
	if id == "battery":
		return "Nothing to power"
	return ""


static func guns_for_ammo(ammo_id: String) -> Array:
	## Names of every gun that fires this ammunition (for the item's description).
	var out := []
	var cal := ammo_id.trim_prefix("ammo_")
	for wid in Defs.weapons:
		if str(Defs.weapons[wid].get("ammo", "")) == cal:
			out.append(str(Defs.weapons[wid].get("name", wid)))
	return out


static func effects(att_id: String) -> Array:
	## What an attachment does, as short lines ("Vertical recoil -26%").
	var a: Dictionary = Defs.attachments.get(att_id, {})
	var out := []
	var names := {"recoil_up_mult": "Vertical recoil", "recoil_side_mult": "Horizontal recoil", "sway_mult": "Sway",
		"ads_time_mult": "Aim time", "recovery_mult": "Recoil recovery", "reload_mult": "Reload time", "loudness_mult": "Loudness",
		"flash_mult": "Muzzle flash", "spread_hip_mult": "Hip-fire spread", "pellet_spread_mult": "Pellet spread",
		"move_spread_mult": "Spread on the move"}
	for k in names:
		if a.has(k):
			var pct := int(round((float(a[k]) - 1.0) * 100.0))
			out.append("%s %s%d%%" % [names[k], "+" if pct > 0 else "", pct])
	if a.has("zoom"):
		out.push_front(("%.0f-%.0fx magnification" % [float(a.zoom_min), float(a.zoom)]) if a.has("zoom_min") else ("%sx magnification" % str(snappedf(float(a.zoom), 0.05))))
	if bool(a.get("ext", false)):
		out.append("Larger magazine")
	if bool(a.get("suppressed", false)):
		out.append("Suppressed")
	if str(a.get("filter", "")) == "night":
		out.append("Night vision")
	if str(a.get("filter", "")) == "thermal":
		out.append("Thermal: people show white hot")
	if bool(a.get("laser", false)):
		out.append("Laser")
	return out
