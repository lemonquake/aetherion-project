extends RefCounted
## Carried items for one character (server authoritative; the owner holds a read-only mirror).
##
## Entries are dictionaries {id, n, ...}: batteries carry `c` (charge 0..1, one battery per entry), armor carries
## `d` (durability), a flashlight carries `c` (its battery charge, -1 when empty), weapons carry their instance in
## `w`. Weapons in hand live in WeaponState.slots; worn gear lives in `gear`.

signal changed

var ch = null
var bag: Array = []
var gear := {"helmet": null, "vest": null, "backpack": null, "flashlight": null}
var dirty := true


func _init(owner = null) -> void:
	ch = owner


func mark_dirty() -> void:
	dirty = true
	changed.emit()


# ------------------------------------------------------------------ weight

func capacity() -> float:
	var cap := float(Defs.carry.get("base_capacity", 7.0))
	if gear.backpack != null:
		cap += float(Defs.item(str(gear.backpack.id)).get("capacity", 0.0))
	return cap


static func entry_mass(e: Dictionary) -> float:
	return float(Defs.item(str(e.id)).get("mass", 0.1)) * int(e.get("n", 1))


func bag_mass() -> float:
	var m := 0.0
	for e in bag:
		m += entry_mass(e)
	return m


func total_mass() -> float:
	var m := bag_mass()
	for k in gear:
		if gear[k] != null:
			m += entry_mass(gear[k])
	if ch and ch.wpn:
		for w in ch.wpn.slots:
			if w != null:
				m += float(Defs.weapon(str(w.id)).get("mass", 3.0))
	return m


func speed_mult() -> float:
	var over := maxf(bag_mass() - capacity(), 0.0)
	return clampf(1.0 - over * float(Defs.carry.get("overweight_slow_per_kg", 0.04)), 0.55, 1.0)


# ------------------------------------------------------------------ queries

func count(id: String) -> int:
	var n := 0
	for e in bag:
		if e.id == id:
			n += int(e.get("n", 1))
	return n


func batteries() -> Array:
	var out := []
	for e in bag:
		if e.id == "battery":
			out.append(e)
	return out


func best_battery() -> Dictionary:
	var best := {}
	for e in bag:
		if e.id == "battery" and (best.is_empty() or float(e.c) > float(best.c)):
			best = e
	return best


# ------------------------------------------------------------------ mutation (server)

func take(id: String, n: int) -> int:
	var got := 0
	for i in range(bag.size() - 1, -1, -1):
		var e: Dictionary = bag[i]
		if e.id != id:
			continue
		var k := mini(int(e.get("n", 1)), n - got)
		e.n = int(e.get("n", 1)) - k
		got += k
		if e.n <= 0:
			bag.remove_at(i)
		if got >= n:
			break
	if got > 0:
		mark_dirty()
	return got


func remove_entry(e: Dictionary) -> void:
	bag.erase(e)
	mark_dirty()


func add(e: Dictionary, force: bool = false) -> int:
	## Adds an entry to the bag (stacking where possible). Returns how many units were accepted.
	var d := Defs.item(str(e.id))
	if d.is_empty():
		return 0
	var unit := float(d.get("mass", 0.1))
	var room := capacity() - bag_mass()
	var n := int(e.get("n", 1))
	var fit := n if force or unit <= 0.0 else mini(n, int(floor((room + 0.0001) / unit)))
	if fit <= 0:
		return 0
	var stack := int(d.get("stack", 1))
	if stack > 1:
		var left := fit
		for x in bag:
			if x.id == e.id and int(x.n) < stack:
				var k := mini(stack - int(x.n), left)
				x.n = int(x.n) + k
				left -= k
				if left <= 0:
					break
		while left > 0:
			var k := mini(stack, left)
			bag.append({"id": e.id, "n": k})
			left -= k
	else:
		for i in fit:
			var c := e.duplicate(true)
			c.n = 1
			bag.append(c)
	mark_dirty()
	return fit


func equip_gear(e: Dictionary) -> Dictionary:
	## Wears armor/backpack/flashlight. Returns the entry it replaced (or {}).
	var d := Defs.item(str(e.id))
	var slot := str(d.get("slot", ""))
	if d.get("kind", "") == "flashlight":
		slot = "flashlight"
	if slot == "" or not gear.has(slot):
		return {}
	var old = gear[slot]
	gear[slot] = e
	mark_dirty()
	return old if old != null else {}


func unequip(slot: String) -> Dictionary:
	var old = gear.get(slot)
	if old == null:
		return {}
	gear[slot] = null
	mark_dirty()
	return old


func all_entries() -> Array:
	## Everything carried, for dropping into a corpse.
	var out := []
	for k in gear:
		if gear[k] != null:
			out.append(gear[k])
	for e in bag:
		out.append(e)
	if ch and ch.wpn:
		for w in ch.wpn.slots:
			if w != null:
				out.append({"id": w.id, "n": 1, "w": w})
	return out


func clear() -> void:
	bag.clear()
	for k in gear:
		gear[k] = null
	mark_dirty()


# ------------------------------------------------------------------ replication

func to_dict() -> Dictionary:
	var w := []
	if ch and ch.wpn:
		for s in ch.wpn.slots:
			w.append(s)
	return {"bag": bag.duplicate(true), "gear": gear.duplicate(true), "w": w}


func from_dict(d: Dictionary) -> void:
	bag = d.bag
	gear = d.gear
	if ch and ch.wpn and d.has("w"):
		var arr: Array = d.w
		for i in mini(arr.size(), 4):
			var incoming = arr[i]
			var cur = ch.wpn.slots[i]
			# Keep the predicted magazine of the weapon in hand; snapshots correct it every tick.
			if incoming != null and cur != null and incoming.id == cur.id and i == ch.wpn.cur:
				incoming.mag = cur.mag
				incoming.chamber = cur.chamber
				incoming.mode = cur.get("mode", 0)  # snapshots reconcile the selector with the predicted magazine
			ch.wpn.slots[i] = incoming
	changed.emit()
