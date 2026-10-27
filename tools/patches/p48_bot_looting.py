"""Loot run (2026-10-26): bots loot what they need (a gun, ammunition for it, attachments that improve it, armour,
medicine), walk to loose items they see, search loot boxes at sites, drop ammunition they cannot use when
overloaded, reload between fights and pick the right gun for the range. Plus an item grid for nearby-item queries
and a [lootstats] line in the match log.

    python -I tools/patches/p48_bot_looting.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class Patch:
    def __init__(self, rel):
        self.p = os.path.join(ROOT, rel)
        raw = open(self.p, 'rb').read().decode()
        self.crlf = '\r\n' in raw
        self.s = raw.replace('\r\n', '\n')

    def rep(self, a, b, cnt=1):
        assert self.s.count(a) == cnt, (self.p, a[:90], self.s.count(a))
        self.s = self.s.replace(a, b)

    def save(self):
        open(self.p, 'wb').write((self.s.replace('\n', '\r\n') if self.crlf else self.s).encode())


# ------------------------------------------------------------------ dynamics: item grid
d = Patch('game/src/world/dynamics.gd')
d.rep('''var _next_item := 1
''', '''var _next_item := 1
var _igrid: Dictionary = {}    # Vector2i (8 m cell) -> [item id]
''')
d.rep('''func client_spawn_item(id: int, entry: Dictionary, xf: Transform3D) -> void:
	items[id] = {"entry": entry, "xf": xf}''', '''func client_spawn_item(id: int, entry: Dictionary, xf: Transform3D) -> void:
	items[id] = {"entry": entry, "xf": xf}
	_igrid_add(id, xf.origin)''')
d.rep('''	var id := _next_item
	_next_item += 1
	items[id] = {"entry": entry, "xf": xf}''', '''	var id := _next_item
	_next_item += 1
	items[id] = {"entry": entry, "xf": xf}
	_igrid_add(id, xf.origin)''')
d.rep('''	if it.get("inst", RID()).is_valid():
		RenderingServer.free_rid(it.inst)
	items.erase(id)''', '''	if it.get("inst", RID()).is_valid():
		RenderingServer.free_rid(it.inst)
	var k := Vector2i(floori((it.xf as Transform3D).origin.x / 8.0), floori((it.xf as Transform3D).origin.z / 8.0))
	if _igrid.has(k):
		(_igrid[k] as Array).erase(id)
	items.erase(id)


func _igrid_add(id: int, p: Vector3) -> void:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not _igrid.has(k):
		_igrid[k] = []
	_igrid[k].append(id)


func items_near(p: Vector3, r: float) -> Array:
	## Ids of items on the ground within r (r up to 8 m checks the 3x3 cells around p; more scans wider).
	var out := []
	var span := int(ceil(r / 8.0))
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for id in _igrid.get(k + Vector2i(dx, dz), []):
				if ((items[id].xf as Transform3D).origin).distance_to(p) <= r:
					out.append(id)
	return out''')
d.save()

# ------------------------------------------------------------------ interaction: wanted-only bot taking
i = Patch('game/src/match/interaction.gd')
i.rep('''const Attach := preload("res://src/weapons/attachments.gd")''', '''const Attach := preload("res://src/weapons/attachments.gd")
const LootSense := preload("res://src/ai/loot_sense.gd")''')
old = i.s[i.s.index('func bot_take_all(ch, kind: String, id: int) -> void:'):]
i.s = i.s.replace(old, '''func bot_take_all(ch, kind: String, id: int) -> void:
	## Bots do not use the SmarTab: from what they just opened they take what they need, best first (a gun, then
	## its ammunition, then attachments that improve it...), and leave the rest.
	if id < 0:
		return
	if kind == "container" and (id >= world.map.dyn.containers.size()):
		return
	var entries: Array = container_entries(kind, id)
	for guard in 24:
		var bi := -1
		var bv := 0.0
		for k in entries.size():
			var v := LootSense.value(ch, entries[k])
			if v > bv:
				bv = v
				bi = k
		if bi < 0:
			break
		var left := bot_take_entry(ch, entries[bi])
		if left.is_empty():
			entries.remove_at(bi)
		else:
			entries[bi] = left
			if guard > 20:
				break
	if kind == "container":
		mark_searched(id)


func bot_take_entry(ch, e: Dictionary) -> Dictionary:
	## Takes one wanted entry. Returns what is left of it ({} when all of it was taken). A gun goes into an empty
	## slot or replaces the weaker gun, which is left in its place.
	var id := str(e.id)
	if Defs.is_weapon(id):
		var slot := 3
		if str(Defs.weapon(id).get("slot", "long")) != "handgun":
			slot = int(LootSense.long_slot(ch, id, e.get("w"))[0])
		if slot < 0:
			return e
		var w: Dictionary = e.get("w", WeaponState.new_instance(id))
		w.id = id
		var old = ch.wpn.slots[slot]
		ch.wpn.slots[slot] = w
		fit_from_bag(ch, slot)
		ch.inv.mark_dirty()
		return {"id": old.id, "n": 1, "w": old} if old != null else {}
	var n := int(e.get("n", 1))
	var want := LootSense.take_count(ch, e)
	if want < n:
		var part := e.duplicate(true)
		part.n = want
		var rest := give(ch, part)
		var back := e.duplicate(true)
		back.n = n - want + int(rest.get("n", 0))
		return back
	return give(ch, e.duplicate(true))


func bot_take_item(ch, id: int) -> bool:
	## A bot picks up an item it is standing next to (same reach rule as Use).
	var it: Dictionary = world.map.dyn.items.get(id, {})
	if it.is_empty() or (it.xf as Transform3D).origin.distance_to(ch.global_position) > REACH + 0.4:
		return false
	if LootSense.value(ch, it.entry) <= 0.0:
		return false
	var left := bot_take_entry(ch, (it.entry as Dictionary).duplicate(true))
	world.server_sound("pickup", ch.global_position + Vector3.UP, 0.0, -1)
	if left.is_empty():
		world.map_item_remove(id)
	elif str(left.id) != str(it.entry.id):
		# Swapped guns: the old one is left on the ground where the new one was.
		world.map_item_remove(id)
		world.map_item_spawn_server(left, it.xf)
	else:
		it.entry = left
	return true


func bot_drop_junk(ch) -> void:
	## Overloaded: drop ammunition for no carried gun, then spare attachments.
	for e in LootSense.junk(ch):
		if ch.inv.bag_mass() <= ch.inv.capacity():
			return
		var idx: int = ch.inv.bag.find(e)
		if idx >= 0:
			var e2 := _remove_from_character(ch, {"index": idx})
			if not e2.is_empty():
				_drop_entry(ch, e2)
''')
i.save()

# ------------------------------------------------------------------ bot brain
b = Patch('game/src/ai/bot_brain.gd')
b.rep('''const NavGrid := preload("res://src/ai/nav_grid.gd")''', '''const NavGrid := preload("res://src/ai/nav_grid.gd")
const LootSense := preload("res://src/ai/loot_sense.gd")''')
b.rep('''var _no_progress := 0.0
static var nav = null''', '''var _no_progress := 0.0
## Loose loot: an item the bot is walking to (detour from a house search), a fetch target outside, and what it gave
## up on.
var _detour := -1
var _detour_t := 0.0
var _fetch := {}          # {kind: "item"/"container", id, p}
var _skip := {}           # "item:12" / "container:40" -> true
var _scan_t := 0.0
var _junk_t := 0.0
var _slot_hold := 0.0
static var site_boxes := []   # containers outside houses (bid -1)
static var nav = null''')
b.rep('''	for c in world.map.dyn.containers:
		if int(c.bid) < 0:
			continue''', '''	site_boxes = []
	for c in world.map.dyn.containers:
		if int(c.bid) < 0:
			site_boxes.append(c)
			continue''')
# think: fetch state
b.rep('''	match state:
		"fight":
			_fight(cmd, dt)
		"heal":
			cmd.btn |= Motor.B_HEAL if ch.health.treatment.is_empty() and rng.randf() < 0.2 else 0
			_move(cmd, dt, true)
		_:
			_move(cmd, dt, false)
			_loot_actions(cmd, dt)''', '''	match state:
		"fight":
			_fight(cmd, dt)
		"heal":
			cmd.btn |= Motor.B_HEAL if ch.health.treatment.is_empty() and rng.randf() < 0.2 else 0
			_move(cmd, dt, true)
		"fetch":
			_fetch_step(cmd, dt)
		_:
			if _detour >= 0:
				_detour_step(cmd, dt)
			else:
				_move(cmd, dt, false)
			_loot_actions(cmd, dt)''')
# choose state: fetch loose loot / site boxes before roaming
b.rep('''	if state == "loot" and plan_i < plan.size():
		return
	if state == "roam" and goal != Vector3.INF and path_i < path.size():
		return
	_pick_loot_goal()''', '''	if state == "fetch" and not _fetch.is_empty():
		return
	if state == "loot" and plan_i < plan.size():
		return
	if _pick_fetch():
		return
	if state == "roam" and goal != Vector3.INF and path_i < path.size():
		return
	_pick_loot_goal()''')
# loot actions: take wanted items directly, detours, junk, idle reload
b.rep('''	match str(t.kind):
		"item", "container", "corpse":
			cmd.btn |= Motor.B_USE
			if str(t.kind) != "item":
				world.interaction.bot_take_all(ch, str(t.kind), int(t.get("id", -1)))
		"door":
			if absf(t.obj.target) < 0.05:
				cmd.btn |= Motor.B_USE
	_equip_best(cmd)''', '''	match str(t.kind):
		"item":
			if not world.interaction.bot_take_item(ch, int(t.id)):
				_skip["item:%d" % int(t.id)] = true
		"container", "corpse":
			cmd.btn |= Motor.B_USE
			world.interaction.bot_take_all(ch, str(t.kind), int(t.get("id", -1)))
		"door":
			if absf(t.obj.target) < 0.05:
				cmd.btn |= Motor.B_USE
	_equip_best(cmd)


func _upkeep(cmd: Dictionary, dt: float) -> void:
	## Between fights: reload a half-empty gun, drop what the bot cannot use when overloaded, and look for loose loot
	## close by in the same room (or the same stretch of street).
	if ch.wpn.current_id() != "" and ch.wpn.state == 0 and ch.wpn.loaded() < int(ch.wpn.mag_cap() * 0.5) \\
			and ch.wpn.reserve(str(ch.wpn.def().get("ammo", ""))) > 0 and rng.randf() < 0.3:
		cmd.btn |= Motor.B_RELOAD
	_junk_t -= dt
	if _junk_t <= 0.0:
		_junk_t = 4.0
		if ch.inv.bag_mass() > ch.inv.capacity():
			world.interaction.bot_drop_junk(ch)
	_scan_t -= dt
	if _scan_t > 0.0 or _detour >= 0:
		return
	_scan_t = 0.8
	var eye: Vector3 = ch.eye_position()
	var zone: int = world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5)
	var best := -1
	var bv := 0.6
	for id in world.map.dyn.items_near(ch.global_position, 7.0):
		if _skip.has("item:%d" % id):
			continue
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		if absf(p.y - ch.global_position.y) > 1.5 or world.map.acoustics.zone_at(p + Vector3.UP * 0.3) != zone:
			continue
		var v := LootSense.value(ch, it.entry) - ch.global_position.distance_to(p) * 0.05
		if v > bv:
			bv = v
			best = id
	if best >= 0:
		var p2: Vector3 = (world.map.dyn.items[best].xf as Transform3D).origin
		var q := PhysicsRayQueryParameters3D.create(eye, p2 + Vector3.UP * 0.15, Defs.SIGHT_MASK)
		if world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_detour = best
			_detour_t = 0.0
		else:
			_skip["item:%d" % best] = true


func _detour_step(cmd: Dictionary, dt: float) -> void:
	## Walk straight to a loose item in sight, pick it up, then carry on with whatever the bot was doing.
	var it: Dictionary = world.map.dyn.items.get(_detour, {})
	_detour_t += dt
	if it.is_empty() or _detour_t > 7.0:
		if not it.is_empty():
			_skip["item:%d" % _detour] = true
		_detour = -1
		return
	var p: Vector3 = (it.xf as Transform3D).origin
	var to := p - ch.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 1.3:
		if not world.interaction.bot_take_item(ch, _detour):
			_skip["item:%d" % _detour] = true
		_detour = -1
		_equip_best(cmd)
		return
	cmd.yaw = lerp_angle(yaw, atan2(-flat.x, -flat.y), 0.3)
	cmd.pitch = lerpf(pitch, -0.5, 0.1)
	cmd.my = 1.0
	cmd.btn |= Motor.B_WALK
	var moved = ch.global_position.distance_to(_last_pos)
	_last_pos = ch.global_position
	if moved < 0.3 * dt and _detour_t > 1.5:
		cmd.btn |= Motor.B_JUMP if rng.randf() < 0.1 else 0


func _pick_fetch() -> bool:
	## Outside a house plan: a wanted item lying in the open or an unsearched loot box at a site, within a short
	## walk. Bots without a usable gun look further.
	var need := not LootSense.armed_ok(ch)
	var reach := 45.0 if need else 25.0
	var best := {}
	var bd := INF
	var here: Vector3 = ch.global_position
	for id in world.map.dyn.items_near(here, reach):
		if _skip.has("item:%d" % id):
			continue
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		if world.map.acoustics.zone_at(p + Vector3.UP * 0.3) != 0:
			continue  # indoors: found by house searches
		var v := LootSense.value(ch, it.entry)
		if v < (0.6 if need else 1.2):
			continue
		var dd := p.distance_to(here) / v
		if dd < bd:
			bd = dd
			best = {"kind": "item", "id": id, "p": p}
	for c in site_boxes:
		if c.searched or _skip.has("container:%d" % int(c.id)):
			continue
		var p2: Vector3 = c.pos
		var dist := p2.distance_to(here)
		if dist > reach:
			continue
		var dd2 := dist / 1.5
		if dd2 < bd:
			bd = dd2
			best = {"kind": "container", "id": int(c.id), "p": p2}
	if best.is_empty():
		return false
	_fetch = best
	_fetch.t = 0.0
	state = "fetch"
	plan = []
	_set_goal(best.p)
	return true


func _fetch_step(cmd: Dictionary, dt: float) -> void:
	_fetch.t = float(_fetch.t) + dt
	var p: Vector3 = _fetch.p
	var key := "%s:%d" % [_fetch.kind, int(_fetch.id)]
	var gone: bool = (_fetch.kind == "item" and not world.map.dyn.items.has(int(_fetch.id))) \\
		or (_fetch.kind == "container" and world.map.dyn.containers[int(_fetch.id)].searched)
	if gone or float(_fetch.t) > 40.0:
		_skip[key] = true
		_fetch = {}
		state = "roam"
		goal = Vector3.INF
		return
	var flat := Vector2(p.x - ch.global_position.x, p.z - ch.global_position.z)
	if flat.length() < 1.4:
		if _fetch.kind == "item":
			world.interaction.bot_take_item(ch, int(_fetch.id))
		else:
			var tv: Vector3 = p - ch.eye_position()
			cmd.yaw = atan2(-tv.x, -tv.z)
			cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
			cmd.btn |= Motor.B_USE
			world.interaction.bot_take_all(ch, "container", int(_fetch.id))
		_skip[key] = true
		_fetch = {}
		state = "roam"
		goal = Vector3.INF
		_equip_best(cmd)
		return
	_move(cmd, dt, false)
	if goal == Vector3.INF:
		# Path ran out short of the target: the last stretch in a straight line.
		cmd.yaw = lerp_angle(yaw, atan2(-flat.x, -flat.y), 0.3)
		cmd.my = 1.0''')
b.rep('''func _loot_actions(cmd: Dictionary, dt: float) -> void:
	_use_t -= dt''', '''func _loot_actions(cmd: Dictionary, dt: float) -> void:
	_upkeep(cmd, dt)
	_use_t -= dt''')
b.rep('''func _equip_best(cmd: Dictionary) -> void:
	for s in [1, 2, 3]:
		if ch.wpn.slots[s] != null:
			cmd.slot = s
			return''', '''func _equip_best(cmd: Dictionary, dist: float = 20.0) -> void:
	## The gun for the range among those with rounds for them; holds a choice for a moment so a bot does not keep
	## swapping (each draw takes time).
	var best := -1
	var bs := -INF
	for s in [1, 2, 3]:
		var w = ch.wpn.slots[s]
		if w == null:
			continue
		var d := Defs.weapon(str(w.id))
		var rounds := int(w.mag) + (1 if w.chamber else 0) + ch.inv.count(Defs.ammo_item(str(w.id)))
		var v := float(d.get("value", 1.0)) if rounds > 0 else -10.0
		var cls := str(d.get("class", ""))
		if dist < 12.0 and cls in ["shotgun", "smg"]:
			v += 2.5
		elif dist > 45.0 and cls in ["rifle", "marksman", "precision"]:
			v += 2.0
		elif dist > 45.0 and cls in ["shotgun", "handgun"]:
			v -= 3.0
		if s == ch.wpn.cur:
			v += 0.8
		if v > bs:
			bs = v
			best = s
	if best >= 0:
		cmd.slot = best''')
b.rep('''	var o = world.characters.get(target_eid)
	if o == null:
		target_eid = -1
		return
	_equip_best(cmd)
	var aim_pt: Vector3 = o.global_position + Vector3.UP * (1.25 if o.mode != Motor.DOWNED else 0.25)''', '''	var o = world.characters.get(target_eid)
	if o == null:
		target_eid = -1
		return
	_equip_best(cmd, o.global_position.distance_to(ch.global_position))
	var aim_pt: Vector3 = o.global_position + Vector3.UP * (1.25 if o.mode != Motor.DOWNED else 0.25)''')
b.rep('''	if d < 25.0:
		cmd.btn |= Motor.B_AIM''', '''	if d < 25.0 or ch.wpn.zoom() > 1.5:
		cmd.btn |= Motor.B_AIM''')
b.save()

# ------------------------------------------------------------------ match log: loot stats
m = Patch('game/src/match/match_server.gd')
m.rep('''		log_event("bots: %s; containers searched by bots %d (all players %d); plan steps done %d; guns carried %d" % [str(states), searched, opened, steps, guns])''',
      '''		log_event("bots: %s; containers searched by bots %d (all players %d); plan steps done %d; guns carried %d" % [str(states), searched, opened, steps, guns])
		_log_loot()


func _log_loot() -> void:
	## Evidence for bot looting: of the bots on the ground, how many carry a gun, how many of those carry ammunition
	## for it, how many attachments are fitted, and how much ammunition for no carried gun they hold.
	var LootSense := preload("res://src/ai/loot_sense.gd")
	var alive := 0
	var armed := 0
	var fed := 0
	var atts := 0
	var junk := 0
	var long_guns := 0
	for b in world.bots.values():
		var c = b.ch
		if c.mode != Motor.GROUND:
			continue
		alive += 1
		var has_gun := false
		var has_ammo := false
		for s in [1, 2, 3]:
			var w = c.wpn.slots[s]
			if w == null:
				continue
			has_gun = true
			if s < 3:
				long_guns += 1
			atts += (w.get("att", []) as Array).size()
			if int(w.mag) + (1 if w.chamber else 0) + c.inv.count(Defs.ammo_item(str(w.id))) > 0:
				has_ammo = true
		if has_gun:
			armed += 1
			if has_ammo:
				fed += 1
		for e in LootSense.junk(c):
			if str(Defs.item(str(e.id)).get("kind", "")) == "ammo":
				junk += int(e.get("n", 1))
	log_event("[lootstats] bots on the ground %d; armed %d; armed with ammo for a gun %d; long guns %d; attachments fitted %d; rounds of unusable ammo carried %d; items on the ground %d"
		% [alive, armed, fed, long_guns, atts, junk, world.map.dyn.items.size()])''')
m.save()
print('ok')
