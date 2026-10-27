extends RefCounted
## What a bot wants from loot. A gun comes first, then ammunition that fits the guns it carries, attachments that
## improve them, armour, a bigger bag, medicine and batteries. Ammunition for nothing it carries is worth nothing,
## so bots do not fill their bags with rounds they cannot fire.
##
## value() is how much the bot gains from taking an entry now (0 = leave it); take_count() how many units of a stack
## it takes. Both look at what the bot already carries, so taking a gun makes its ammunition wanted next.

const Attach := preload("res://src/weapons/attachments.gd")

## Rounds a bot likes to carry per weapon class (beyond what is loaded).
const AMMO_WANT := {"handgun": 30, "smg": 90, "rifle": 120, "marksman": 50, "precision": 25, "shotgun": 24}
const MED_WANT := {"bandage": 4, "first_aid": 2, "splint": 1, "painkillers": 2}


static func weapon_score(ch, id: String, w = null) -> float:
	## A gun's worth to this bot: its class value, more if it can be fed.
	var d := Defs.weapon(id)
	var v := float(d.get("value", 1.0))
	var rounds = ch.inv.count(Defs.ammo_item(id))
	if w != null:
		rounds += int(w.get("mag", 0)) + (1 if w.get("chamber", false) else 0)
		v += float((w.get("att", []) as Array).size()) * 0.25
	if rounds <= 0:
		v -= 1.5
	return v


static func long_slot(ch, id: String, w = null) -> Array:
	## [slot, gain] for a long gun: an empty long slot, or the weaker of the two if this one beats it.
	var best := [-1, 0.0]
	var sc := weapon_score(ch, id, w)
	for s in [1, 2]:
		var cur = ch.wpn.slots[s]
		var have := weapon_score(ch, str(cur.id), cur) if cur != null else 0.0
		if sc - have > best[1] + 0.01:
			best = [s, sc - have]
	return best


static func ammo_need(ch, cal: String) -> int:
	var want := 0
	for s in [1, 2, 3]:
		var w = ch.wpn.slots[s]
		if w != null and str(Defs.weapon(str(w.id)).get("ammo", "")) == cal:
			want = maxi(want, int(AMMO_WANT.get(str(Defs.weapon(str(w.id)).get("class", "")), 30)))
	return maxi(want - ch.inv.count("ammo_" + cal), 0)


static func value(ch, e: Dictionary) -> float:
	var id := str(e.get("id", ""))
	if Defs.is_weapon(id):
		var w = e.get("w")
		if str(Defs.weapon(id).get("slot", "long")) == "handgun":
			var cur = ch.wpn.slots[3]
			var have := weapon_score(ch, str(cur.id), cur) if cur != null else 0.0
			return maxf(weapon_score(ch, id, w) - have, 0.0) * (1.0 if cur != null else 1.5)
		return float(long_slot(ch, id, w)[1]) * 1.5
	var d := Defs.item(id)
	match str(d.get("kind", "")):
		"ammo":
			var need := ammo_need(ch, str(d.get("ammo", "")))
			return 0.0 if need <= 0 else 3.0 + minf(float(need) / 30.0, 2.0)
		"attachment":
			return float(Attach.best_slot_upgrade(ch.wpn.slots, id)[1])
		"armor":
			var g = ch.inv.gear.get(str(d.get("slot", "")))
			var mine := 0.0
			if g != null:
				var gd := Defs.item(str(g.id))
				mine = float(gd.get("protection", 0)) * float(g.get("d", 0.0)) / maxf(float(gd.get("durability", 100)), 1.0)
			var theirs := float(d.get("protection", 0)) * float(e.get("d", d.get("durability", 100))) / maxf(float(d.get("durability", 100)), 1.0)
			return 3.0 if theirs > mine * 1.15 + 50.0 else 0.0
		"backpack":
			var bp = ch.inv.gear.backpack
			var cap := float(Defs.item(str(bp.id)).get("capacity", 0.0)) if bp != null else 0.0
			return 2.5 if float(d.get("capacity", 0.0)) > cap else 0.0
		"medical":
			return 2.0 if ch.inv.count(id) < int(MED_WANT.get(id, 1)) else 0.0
		"battery":
			return 1.5 if ch.inv.count("battery") < 3 else 0.0
		"flashlight":
			return 2.0 if ch.inv.gear.flashlight == null else 0.0
	return 0.0


static func take_count(ch, e: Dictionary) -> int:
	var id := str(e.get("id", ""))
	var n := int(e.get("n", 1))
	var d := Defs.item(id)
	match str(d.get("kind", "")):
		"ammo":
			return mini(n, ammo_need(ch, str(d.get("ammo", ""))) + 10)
		"medical":
			return mini(n, maxi(int(MED_WANT.get(id, 1)) - ch.inv.count(id), 1))
	return n


static func junk(ch) -> Array:
	## Bag entries to drop when overloaded: ammunition for no carried gun first, then spare attachments.
	var out := []
	for e in ch.inv.bag:
		var d := Defs.item(str(e.id))
		if str(d.get("kind", "")) == "ammo" and ammo_need(ch, str(d.get("ammo", ""))) <= 0:
			var used := false
			for s in [1, 2, 3]:
				var w = ch.wpn.slots[s]
				if w != null and Defs.ammo_item(str(w.id)) == str(e.id):
					used = true
			if not used:
				out.append(e)
	for e in ch.inv.bag:
		if Defs.is_attachment(str(e.id)) and not out.has(e):
			out.append(e)
	return out


static func armed_ok(ch) -> bool:
	## Carries a gun with at least a magazine's worth of rounds for it.
	for s in [1, 2, 3]:
		var w = ch.wpn.slots[s]
		if w == null:
			continue
		var rounds = int(w.mag) + (1 if w.chamber else 0) + ch.inv.count(Defs.ammo_item(str(w.id)))
		if rounds >= mini(int(Defs.weapon(str(w.id)).get("mag_size", 10)), 12):
			return true
	return false
