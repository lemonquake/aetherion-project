extends RefCounted
## Server-side "Use" and inventory logic: doors, shutters, containers, corpses, items on the ground, grabbing,
## dragging and throwing props, reviving teammates, treatment, and every inventory request from the SmarTab.
## Every request is validated against the server's own state: reach, line of sight, ownership and capacity.

const WeaponState := preload("res://src/weapons/weapon_state.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const LootSense := preload("res://src/ai/loot_sense.gd")
const BotBrain := preload("res://src/ai/bot_brain.gd")
const REACH := 2.3
const FORCE_TIME := 2.0

var world = null
var _holds: Dictionary = {}      # eid -> {kind, id, t, ...}
var _held: Dictionary = {}       # eid -> {prop_id, charge, heavy}
var _open: Dictionary = {}       # eid -> {kind: "container"/"corpse", id}


func _init(w) -> void:
	world = w


func holding_heavy(ch) -> bool:
	return _held.has(ch.eid) and bool(_held[ch.eid].heavy)


# ------------------------------------------------------------------ target finding

func target(ch, cmd: Dictionary) -> Dictionary:
	## What the character is pointing at within reach: {kind, id, pos, obj}. Shared by server and client prompts.
	var eye: Vector3 = ch.eye_position()
	var dir: Vector3 = -Basis.from_euler(Vector3(float(cmd.get("pitch", ch.pitch)), float(cmd.get("yaw", ch.yaw)), 0)).z
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * REACH, Defs.SIGHT_MASK | Defs.PHYS_INTERACT | Defs.PHYS_CORPSE | Defs.PHYS_CHAR)
	q.exclude = [ch.get_rid()]
	var r := space.intersect_ray(q)
	var hit_d := REACH
	if not r.is_empty():
		hit_d = eye.distance_to(r.position)
	# Items lying on the ground (no physics bodies): the nearest one along the ray, before anything else.
	var ih: Array = world.map.dyn.item_hit(eye, dir, minf(hit_d + 0.05, REACH))
	if int(ih[0]) >= 0:
		return {"kind": "item", "id": int(ih[0]), "pos": eye + dir * float(ih[1])}
	if not r.is_empty():
		var c = r.collider
		if c:
			if c.has_meta("door_id"):
				return {"kind": "door", "obj": c, "pos": r.position}
			if c.has_meta("shutter_id"):
				return {"kind": "shutter", "obj": c, "pos": r.position}
			if c.has_meta("corpse_id"):
				return {"kind": "corpse", "id": int(c.get_meta("corpse_id")), "pos": r.position}
			if c.has_meta("prop_id"):
				return {"kind": "prop", "id": int(c.get_meta("prop_id")), "pos": r.position}
			if c is Character and c.mode == Motor.DOWNED and c.team == ch.team:
				return {"kind": "revive", "id": c.eid, "pos": r.position}
	# Containers are volumes inside furniture: the nearest one along the ray, before any wall.
	var best := {}
	var best_t := hit_d + 0.35
	for cont in world.map.dyn.containers_near(eye, REACH + 1.0):
		var size: Vector3 = cont.size
		var aabb := AABB((cont.pos as Vector3) - size * 0.5, size).grow(0.12)
		var hit = aabb.intersects_ray(eye, dir)
		if hit != null:
			var t := eye.distance_to(hit)
			if t < best_t:
				best_t = t
				best = {"kind": "container", "id": int(cont.id), "pos": hit}
	return best


# ------------------------------------------------------------------ use (server)

func server_use(ch, cmd: Dictionary) -> void:
	if ch.mode != Motor.GROUND:
		if ch.mode == Motor.DOWNED:
			return
		return
	var t := target(ch, cmd)
	if Game.arg("netdebug") != null and not Net.is_bot(ch.pid):
		print("[netdebug] %s pressed Use at %s yaw %.3f pitch %.3f: %s %s" % [ch.pname, str(ch.global_position.snapped(Vector3.ONE * 0.01)),
			float(cmd.get("yaw", 0.0)), float(cmd.get("pitch", 0.0)), str(t.get("kind", "nothing")), str(t.get("id", ""))])
	if t.is_empty():
		return
	match str(t.kind):
		"door", "shutter":
			var d = t.obj
			var what: String = d.server_use(ch.global_position, -Basis(Vector3.UP, float(cmd.get("yaw", ch.yaw))).z)
			world.map_door_state(d, what)
			if what == "locked":
				_holds[ch.eid] = {"kind": "force", "door": d, "t": 0.0}
		"item":
			_take_item(ch, int(t.id))
		"container":
			_open_container(ch, "container", int(t.id))
		"corpse":
			_open_container(ch, "corpse", int(t.id))
		"revive":
			_holds[ch.eid] = {"kind": "revive", "target": int(t.id), "t": 0.0}
			world.server_sound("revive_start", ch.global_position, 0.0, -1)


func server_use_held(ch, cmd: Dictionary, dt: float) -> void:
	var h: Dictionary = _holds.get(ch.eid, {})
	if h.is_empty():
		return
	match str(h.kind):
		"force":
			h.t += dt
			if fmod(h.t, 0.7) < dt:
				world.server_sound("door_kick", h.door.center(), 0.0, -1)
			if h.t >= FORCE_TIME:
				h.door.server_force(ch.global_position)
				world.map_door_state(h.door, "forced")
				_holds.erase(ch.eid)
		"revive":
			var other = world.characters.get(int(h.target))
			if other == null or other.mode != Motor.DOWNED or other.global_position.distance_to(ch.global_position) > REACH + 0.6:
				_holds.erase(ch.eid)
				return
			h.t += dt
			other.health.revive_progress = h.t
			ch.flags |= Character.F_BUSY
			if h.t >= float(Defs.health.get("revive_time_s", 6.0)):
				other.health.revive()
				world.server_set_mode(other, Motor.GROUND)
				world.server_sound("revive_done", other.global_position, 0.0, -1)
				_holds.erase(ch.eid)
				ch.flags &= ~Character.F_BUSY


func server_use_released(ch) -> void:
	if _holds.has(ch.eid):
		var h: Dictionary = _holds[ch.eid]
		if h.kind == "revive":
			var other = world.characters.get(int(h.target))
			if other:
				other.health.revive_progress = 0.0
			ch.flags &= ~Character.F_BUSY
		_holds.erase(ch.eid)


# ------------------------------------------------------------------ items and containers

func _take_item(ch, id: int) -> void:
	var it: Dictionary = world.map.dyn.items.get(id, {})
	if it.is_empty():
		return
	var e: Dictionary = (it.entry as Dictionary).duplicate(true)
	var left := give(ch, e)
	if Game.arg("netdebug") != null:
		print("[netdebug] %s took item %d (%s), left over: %s" % [ch.pname, id, str(e.id), str(left)])
	if left.is_empty():
		world.map_item_remove(id)
	else:
		it.entry = left
	world.server_sound("pickup", ch.global_position + Vector3.UP, 0.0, -1)


func give(ch, e: Dictionary) -> Dictionary:
	## Puts an entry on a character: weapons into a free slot, better armour on, a flashlight if none, the rest in
	## the bag. Returns whatever did not fit ({} when everything was taken).
	var id := str(e.id)
	if Defs.is_weapon(id):
		var slot: int = ch.wpn.slot_for(id)
		var w: Dictionary = e.get("w", WeaponState.new_instance(id))
		w.id = id
		var old = ch.wpn.slots[slot]
		ch.wpn.slots[slot] = w
		if old != null:
			_drop_entry(ch, {"id": old.id, "n": 1, "w": old})
		fit_from_bag(ch, slot)
		ch.inv.mark_dirty()
		return {}
	var d := Defs.item(id)
	var kind := str(d.get("kind", ""))
	if kind == "attachment" and int(e.get("n", 1)) == 1:
		# Fitted straight onto the gun that gains most from it; whatever it replaces goes in the bag.
		var up: Array = Attach.best_slot_upgrade(ch.wpn.slots, id)
		if int(up[0]) >= 0:
			fit(ch, int(up[0]), id)
			return {}
	if kind in ["armor", "backpack"] or (kind == "flashlight" and ch.inv.gear.flashlight == null):
		var old: Dictionary = ch.inv.equip_gear(e)
		if not old.is_empty():
			var left = ch.inv.add(old)
			if left < int(old.get("n", 1)):
				_drop_entry(ch, old)
		return {}
	var n := int(e.get("n", 1))
	var got: int = ch.inv.add(e)
	if got >= n:
		return {}
	var rest := e.duplicate(true)
	rest.n = n - got
	return rest


func _attach_click(ch) -> void:
	world.server_sound("attach", ch.global_position + Vector3.UP * 1.2, 0.0, -1)


func fit(ch, slot: int, att: String) -> void:
	## Puts an attachment (not taken from the bag) on the weapon in a slot, moving the one in the same mount to the bag.
	var w: Dictionary = ch.wpn.slots[slot]
	var k := Attach.kind(att)
	for a in (w.att as Array).duplicate():
		if Attach.kind(str(a)) == k:
			_unfit(ch, w, str(a))
	w.att.append(att)
	if att == "weapon_light" and not w.has("wl"):
		w.wl = 0.6
	ch.inv.mark_dirty()
	_attach_click(ch)


func _unfit(ch, w: Dictionary, att: String) -> void:
	## Takes an attachment off into the bag (dropped if it does not fit). Rounds beyond the magazine that is left
	## go back into the bag as ammunition.
	w.att.erase(att)
	var cap := Attach.mag_cap(w)
	if int(w.mag) > cap:
		var extra := int(w.mag) - cap
		w.mag = cap
		ch.inv.add({"id": "ammo_" + str(Defs.weapon(str(w.id)).get("ammo", "9x19")), "n": extra}, true)
	if ch.inv.add({"id": att, "n": 1}) == 0:
		_drop_entry(ch, {"id": att, "n": 1})
	ch.inv.mark_dirty()
	_attach_click(ch)


func fit_from_bag(ch, slot: int) -> void:
	## A gun just picked up takes whatever compatible attachments in the bag improve it.
	var w = ch.wpn.slots[slot]
	if w == null:
		return
	for e in ch.inv.bag.duplicate():
		var a := str(e.id)
		if not Defs.is_attachment(a) or not Attach.compatible(str(w.id), a):
			continue
		var cur := Attach.in_slot(w, Attach.kind(a))
		if cur == "" or Attach.score(str(w.id), a) > Attach.score(str(w.id), cur) + 0.01:
			if ch.inv.take(a, 1) == 1:
				fit(ch, slot, a)


func _drop_entry(ch, e: Dictionary) -> void:
	var p: Vector3 = ch.global_position + (-ch.aim_basis().z * Vector3(1, 0, 1)).normalized() * 0.6
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 3.0, Defs.PHYS_WORLD | Defs.PHYS_PROP)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		p = r.position
	world.map_item_spawn_server(e, Transform3D(Basis(Vector3.UP, randf() * TAU), p + Vector3.UP * 0.01))


func _open_container(ch, kind: String, id: int) -> void:
	_open[ch.eid] = {"kind": kind, "id": id}
	var entries := container_entries(kind, id)
	if kind == "container":
		var c: Dictionary = world.map.dyn.containers[id]
		mark_searched(id)
		world.server_sound(str(c.get("sound", "search_drawer")), c.pos, 0.0, -1)
	world.send_container(ch, kind, id, entries)


const TAB_REACH := 2.2


func server_tab_open(ch, cmd: Dictionary) -> void:
	## Raising the SmarTab beside a loot box, any other container or a body shows what is inside straight away:
	## the one pointed at, else the nearest one in reach that the player can see.
	if ch.mode != Motor.GROUND or _held.has(ch.eid):
		return
	var t := target(ch, cmd)
	if str(t.get("kind", "")) in ["container", "corpse"]:
		_open_container(ch, str(t.kind), int(t.id))
		return
	var eye: Vector3 = ch.eye_position()
	var body: Vector3 = ch.global_position + Vector3.UP * 0.9
	var fwd: Vector3 = -Basis(Vector3.UP, float(cmd.get("yaw", ch.yaw))).z
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var best := {}
	var best_score := INF
	var cands := []
	for cont in world.map.dyn.containers_near(body, TAB_REACH + 1.5):
		var aabb := AABB((cont.pos as Vector3) - (cont.size as Vector3) * 0.5, cont.size)
		cands.append(["container", int(cont.id), aabb, cont.has("box")])
	for cid in world.map.dyn.corpses:
		var c = world.map.dyn.corpses[cid]
		var cc: Vector3 = c.center()
		if cc.distance_to(body) < TAB_REACH + 1.0:
			cands.append(["corpse", int(cid), AABB(cc - Vector3(0.5, 0.2, 0.5), Vector3(1.0, 0.4, 1.0)), true])
	for c in cands:
		var aabb: AABB = c[2]
		var near := body.clamp(aabb.position, aabb.end)
		var d := near.distance_to(body)
		if d > TAB_REACH:
			continue
		# Seen from the eyes: a wall between the player and the box hides it (the box itself may stop the ray).
		var q := PhysicsRayQueryParameters3D.create(eye, near, Defs.PHYS_WORLD)
		q.exclude = [ch.get_rid()]
		var r := space.intersect_ray(q)
		if not r.is_empty() and eye.distance_to(r.position) < eye.distance_to(near) - 0.35:
			continue
		var to := near - body
		to.y = 0.0
		var facing := fwd.dot(to.normalized()) if to.length() > 0.05 else 1.0
		# Loot boxes and bodies (what the player sees) before drawers and cupboards hidden in furniture.
		var score := d - 0.6 * facing - (0.8 if c[3] else 0.0)
		if score < best_score:
			best_score = score
			best = {"kind": c[0], "id": c[1]}
	if not best.is_empty():
		_open_container(ch, str(best.kind), int(best.id))


func mark_searched(cid: int) -> void:
	## First search of a container: a loot box opens its lid for everyone.
	var c: Dictionary = world.map.dyn.containers[cid]
	if c.searched:
		return
	c.searched = true
	if c.has("box"):
		world.map_box_opened_server(cid)


func container_entries(kind: String, id: int) -> Array:
	if kind == "container":
		return world.map.dyn.containers[id].entries
	var corpse = world.map.dyn.corpses.get(id)
	return corpse.entries if corpse else []


func container_pos(kind: String, id: int) -> Vector3:
	if kind == "container":
		return world.map.dyn.containers[id].pos
	var corpse = world.map.dyn.corpses.get(id)
	return corpse.center() if corpse else Vector3.INF


func server_inventory_request(ch, req: Dictionary) -> void:
	## SmarTab actions. req.op: take, put, drop, equip, use, unload, attach, detach, drop_weapon, unequip
	var op := str(req.get("op", ""))
	match op:
		"take":
			var o: Dictionary = _open.get(ch.eid, {})
			if o.is_empty() or container_pos(o.kind, o.id).distance_to(ch.global_position) > REACH + 1.2:
				return
			var entries: Array = container_entries(o.kind, o.id)
			var i := int(req.get("index", -1))
			if i < 0 or i >= entries.size():
				return
			var e: Dictionary = entries[i]
			var left := give(ch, e.duplicate(true))
			if left.is_empty():
				entries.remove_at(i)
			else:
				entries[i] = left
			world.server_sound("pickup", ch.global_position + Vector3.UP, -6.0, -1)
			world.send_container(ch, o.kind, o.id, entries)
		"put":
			var o2: Dictionary = _open.get(ch.eid, {})
			if o2.is_empty() or container_pos(o2.kind, o2.id).distance_to(ch.global_position) > REACH + 1.2:
				return
			var e2 := _remove_from_character(ch, req)
			if not e2.is_empty():
				container_entries(o2.kind, o2.id).append(e2)
				world.send_container(ch, o2.kind, o2.id, container_entries(o2.kind, o2.id))
		"drop":
			var e3 := _remove_from_character(ch, req)
			if not e3.is_empty():
				_drop_entry(ch, e3)
		"use":
			var item_id := str(req.get("item", ""))
			start_treatment(ch, item_id)
		"close":
			_open.erase(ch.eid)
		"unload":
			var s := int(req.get("slot", -1))
			if s >= 1 and s <= 3 and ch.wpn.slots[s] != null:
				var w: Dictionary = ch.wpn.slots[s]
				var n := int(w.mag) + (1 if w.chamber else 0)
				w.mag = 0
				w.chamber = false
				if n > 0:
					ch.inv.add({"id": "ammo_" + str(Defs.weapon(str(w.id)).get("ammo", "9x19")), "n": n}, true)
				ch.inv.mark_dirty()
		"attach":
			var s2 := int(req.get("slot", -1))
			var att := str(req.get("att", ""))
			if s2 >= 1 and s2 <= 3 and ch.wpn.slots[s2] != null and ch.inv.count(att) > 0:
				var w2: Dictionary = ch.wpn.slots[s2]
				if Attach.compatible(str(w2.id), att) and ch.inv.take(att, 1) == 1:
					fit(ch, s2, att)
		"detach":
			var s3 := int(req.get("slot", -1))
			var att2 := str(req.get("att", ""))
			if s3 >= 1 and s3 <= 3 and ch.wpn.slots[s3] != null and att2 in ch.wpn.slots[s3].att:
				_unfit(ch, ch.wpn.slots[s3], att2)
		"drop_weapon":
			var s4 := int(req.get("slot", -1))
			if s4 >= 1 and s4 <= 3 and ch.wpn.slots[s4] != null:
				var w3: Dictionary = ch.wpn.slots[s4]
				ch.wpn.slots[s4] = null
				if ch.wpn.cur == s4:
					ch.wpn.cur = WeaponState.HOLSTER
					ch.wpn.want = WeaponState.HOLSTER
				_drop_entry(ch, {"id": w3.id, "n": 1, "w": w3})
				ch.inv.mark_dirty()
		"unequip":
			var slot_name := str(req.get("gear", ""))
			var e4: Dictionary = ch.inv.unequip(slot_name)
			if not e4.is_empty() and ch.inv.add(e4) == 0:
				_drop_entry(ch, e4)


func _remove_from_character(ch, req: Dictionary) -> Dictionary:
	var i := int(req.get("index", -1))
	var n := int(req.get("count", 0))
	if i < 0 or i >= ch.inv.bag.size():
		return {}
	var e: Dictionary = ch.inv.bag[i]
	if n <= 0 or n >= int(e.get("n", 1)):
		ch.inv.bag.remove_at(i)
		ch.inv.mark_dirty()
		return e
	e.n = int(e.n) - n
	ch.inv.mark_dirty()
	var part := e.duplicate(true)
	part.n = n
	return part


# ------------------------------------------------------------------ treatment

func server_quick_heal(ch) -> void:
	if not ch.health.treatment.is_empty():
		ch.health.treatment = {}
		return
	var need: String = ch.health.treatment_need()
	if need == "":
		return
	# Fall back to what is available.
	var order := [need, "bandage", "first_aid", "splint", "painkillers"]
	for it in order:
		if ch.inv.count(it) > 0 and ch.health.can_use(it):
			start_treatment(ch, it)
			return


func start_treatment(ch, item_id: String) -> void:
	if ch.inv.count(item_id) <= 0 or not ch.health.can_use(item_id) or ch.mode != Motor.GROUND:
		return
	var d := Defs.item(item_id)
	ch.health.treatment = {"item": item_id, "t": 0.0, "total": float(d.get("use_time", 3.0))}
	ch.flags |= Character.F_HEAL
	ch.wpn.cancel_reload()
	ch.health.dirty = true
	world.server_sound("treat_" + ("bandage" if item_id in ["bandage", "splint"] else "kit"), ch.global_position + Vector3.UP, 0.0, -1)


func server_treatment_tick(ch, dt: float) -> void:
	var tr: Dictionary = ch.health.treatment
	if tr.is_empty():
		ch.flags &= ~Character.F_HEAL
		return
	# Sprinting, firing or going down interrupts treatment.
	var btn := int(ch.last_cmd.get("btn", 0))
	if ch.sprinting or (btn & Motor.B_FIRE) or ch.mode != Motor.GROUND:
		ch.health.treatment = {}
		ch.flags &= ~Character.F_HEAL
		ch.health.dirty = true
		return
	tr.t += dt
	if tr.t >= tr.total:
		if ch.inv.take(str(tr.item), 1) == 1:
			ch.health.apply_treatment(str(tr.item))
		ch.health.treatment = {}
		ch.flags &= ~Character.F_HEAL


# ------------------------------------------------------------------ grabbing, dragging, throwing

func server_grab(ch, cmd: Dictionary) -> void:
	## T: pick up, drag or carry the object pointed at; T again puts it down. Kept apart from Use (E), which only
	## takes weapons, ammunition and items, so grabbing a bottle never gets in the way of picking up a gun.
	if ch.mode != Motor.GROUND:
		return
	if _held.has(ch.eid):
		server_drop_held(ch, false)
		return
	var t := target(ch, cmd)
	if str(t.get("kind", "")) == "prop":
		_grab(ch, int(t.id))

func _grab(ch, prop_id: int) -> void:
	var dyn = world.map.dyn
	if prop_id < 0 or prop_id >= dyn.props.size() or dyn.props[prop_id].state == "broken":
		return
	var spec: Dictionary = world.map.models.spec(str(dyn.props[prop_id].name))
	var mass := float(spec.get("mass", 5.0))
	if mass > float(Defs.rule("interaction.push_mass_limit", 120.0)):
		return
	var body = dyn.server_activate(prop_id)
	if body == null:
		return
	# Somebody else is already holding it.
	for other in _held:
		if int(_held[other].prop_id) == prop_id:
			return
	var heavy := mass > float(Defs.rule("interaction.carry_mass_limit", 22.0))
	_held[ch.eid] = {"prop_id": prop_id, "charge": 0.0, "heavy": heavy, "body": body, "grip": (body.global_position - ch.global_position)}
	ch.held_prop_id = prop_id
	body.held_by = ch.eid
	body.add_collision_exception_with(ch)
	body.sleeping = false
	world.server_sound("grab", body.global_position, 0.0, -1)


func server_hold_update(ch, cmd: Dictionary, dt: float) -> void:
	var h: Dictionary = _held.get(ch.eid, {})
	if h.is_empty():
		return
	var body = h.body
	if not is_instance_valid(body):
		_release(ch)
		return
	var eye: Vector3 = ch.eye_position()
	var fwd: Vector3 = -Basis.from_euler(Vector3(float(cmd.get("pitch", ch.pitch)), float(cmd.get("yaw", ch.yaw)), 0)).z
	if h.heavy:
		# Drag: the furniture follows the player's feet at walking pace, scraping across the floor.
		var target_pos: Vector3 = ch.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 1.1
		var to: Vector3 = target_pos - body.global_position
		to.y = 0.0
		if to.length() > 2.4:
			_release(ch)
			return
		var v: Vector3 = to * 4.0
		v = v.limit_length(Defs.move("carry_heavy_speed") * 1.2)
		body.linear_velocity = Vector3(v.x, body.linear_velocity.y, v.z)
		body.angular_velocity *= 0.6
		return
	var hold_d := float(Defs.rule("interaction.hold_distance", 1.25))
	var target: Vector3 = eye + fwd * hold_d + Vector3.DOWN * 0.15
	# Never hold an object through a wall.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, target, Defs.PHYS_WORLD | Defs.PHYS_GLASS)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		target = (r.position as Vector3) - fwd * 0.25
	var err: Vector3 = target - body.global_position
	if err.length() > 1.6:
		_release(ch)
		return
	var vmax := float(Defs.rule("interaction.max_held_speed", 7.0))
	body.linear_velocity = (err * 14.0).limit_length(vmax) + ch.velocity * 0.6
	body.angular_velocity = body.angular_velocity * 0.7


func server_throw_charge(ch, dt: float) -> void:
	if _held.has(ch.eid) and not _held[ch.eid].heavy:
		_held[ch.eid].charge = minf(float(_held[ch.eid].charge) + dt / 0.9, 1.0)


func server_drop_held(ch, throw: bool) -> void:
	var h: Dictionary = _held.get(ch.eid, {})
	if h.is_empty():
		return
	var body = h.body
	if throw and is_instance_valid(body) and not h.heavy:
		var mass := float(body.mass)
		if mass <= float(Defs.rule("interaction.throw_mass_limit", 6.0)):
			var fwd: Vector3 = -ch.aim_basis().z
			var speed := lerpf(3.0, float(Defs.rule("interaction.throw_speed_max", 13.0)), float(h.charge)) * clampf(2.5 / maxf(mass, 0.4), 0.35, 1.0)
			body.linear_velocity = fwd * speed + Vector3.UP * 1.2 + ch.velocity * 0.5
			body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
			world.server_sound("throw", ch.eye_position(), 0.0, -1)
	_release(ch)


func _release(ch) -> void:
	var h: Dictionary = _held.get(ch.eid, {})
	_held.erase(ch.eid)
	ch.held_prop_id = -1
	if h.has("body") and is_instance_valid(h.body):
		var b = h.body
		b.held_by = -1
		b.remove_collision_exception_with(ch)
		# Held objects never launch players: clamp whatever velocity was left.
		b.linear_velocity = b.linear_velocity.limit_length(float(Defs.rule("interaction.throw_speed_max", 13.0)))


func bot_take_all(ch, kind: String, id: int) -> void:
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
	BotBrain.counts.items_taken += 1
	if left.is_empty():
		world.map_item_remove(id)
	elif str(left.id) != str(it.entry.id):
		# Swapped guns: the old one is left on the ground where the new one was.
		world.map_item_remove(id)
		world.map_item_spawn_server(left, it.xf)
	else:
		it.entry = left
	return true


func bot_drop_junk(ch, overloaded: bool) -> void:
	## Ammunition for no carried gun is left behind; spare attachments too when overloaded.
	for e in LootSense.junk(ch):
		if Defs.is_attachment(str(e.id)) and (not overloaded or ch.inv.bag_mass() <= ch.inv.capacity()):
			continue
		var idx: int = ch.inv.bag.find(e)
		if idx >= 0:
			var e2 := _remove_from_character(ch, {"index": idx})
			if not e2.is_empty():
				_drop_entry(ch, e2)
