"""Loot run (2026-10-26): picking up attachments fits them, a new gun takes compatible attachments from the bag,
extended magazines give rounds back when removed, loot boxes open for everyone, late joiners get only the floor-item
changes, and the HUD names what you are about to take or search.

    python -I tools/patches/p47_loot_interaction.py
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


# ------------------------------------------------------------------ interaction
i = Patch('game/src/match/interaction.gd')
i.rep('''const WeaponState := preload("res://src/weapons/weapon_state.gd")''', '''const WeaponState := preload("res://src/weapons/weapon_state.gd")
const Attach := preload("res://src/weapons/attachments.gd")''')
i.rep('''	var id := str(e.id)
	if Defs.is_weapon(id):
		var slot: int = ch.wpn.slot_for(id)
		var w: Dictionary = e.get("w", WeaponState.new_instance(id))
		w.id = id
		var old = ch.wpn.slots[slot]
		ch.wpn.slots[slot] = w
		if old != null:
			_drop_entry(ch, {"id": old.id, "n": 1, "w": old})
		ch.inv.mark_dirty()
		return {}
	var d := Defs.item(id)
	var kind := str(d.get("kind", ""))''', '''	var id := str(e.id)
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
			return {}''')
i.rep('''func _drop_entry(ch, e: Dictionary) -> void:''', '''func fit(ch, slot: int, att: String) -> void:
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


func _drop_entry(ch, e: Dictionary) -> void:''')
i.rep('''	if kind == "container":
		var c: Dictionary = world.map.dyn.containers[id]
		if not c.searched:
			c.searched = true
		world.server_sound(str(c.get("sound", "search_drawer")), c.pos, 0.0, -1)''', '''	if kind == "container":
		var c: Dictionary = world.map.dyn.containers[id]
		mark_searched(id)
		world.server_sound(str(c.get("sound", "search_drawer")), c.pos, 0.0, -1)''')
i.rep('''func container_entries(kind: String, id: int) -> Array:''', '''func mark_searched(cid: int) -> void:
	## First search of a container: a loot box opens its lid for everyone.
	var c: Dictionary = world.map.dyn.containers[cid]
	if c.searched:
		return
	c.searched = true
	if c.has("box"):
		world.map_box_opened_server(cid)


func container_entries(kind: String, id: int) -> Array:''')
i.rep('''			if s2 >= 1 and s2 <= 3 and ch.wpn.slots[s2] != null and ch.inv.count(att) > 0:
				var w2: Dictionary = ch.wpn.slots[s2]
				if att in Defs.weapon(str(w2.id)).get("attachments", []):
					var kind := str(Defs.attachments.get(att, {}).get("kind", ""))
					for a in (w2.att as Array).duplicate():
						if Defs.attachments.get(a, {}).get("kind", "") == kind:
							w2.att.erase(a)
							ch.inv.add({"id": a, "n": 1}, true)
					ch.inv.take(att, 1)
					w2.att.append(att)
					if att == "weapon_light" and not w2.has("wl"):
						w2.wl = 0.6
					ch.inv.mark_dirty()''', '''			if s2 >= 1 and s2 <= 3 and ch.wpn.slots[s2] != null and ch.inv.count(att) > 0:
				var w2: Dictionary = ch.wpn.slots[s2]
				if Attach.compatible(str(w2.id), att) and ch.inv.take(att, 1) == 1:
					fit(ch, s2, att)''')
i.rep('''			if s3 >= 1 and s3 <= 3 and ch.wpn.slots[s3] != null and att2 in ch.wpn.slots[s3].att:
				ch.wpn.slots[s3].att.erase(att2)
				ch.inv.add({"id": att2, "n": 1}, true)
				ch.inv.mark_dirty()''', '''			if s3 >= 1 and s3 <= 3 and ch.wpn.slots[s3] != null and att2 in ch.wpn.slots[s3].att:
				_unfit(ch, ch.wpn.slots[s3], att2)''')
i.rep('''	if kind == "container":
		world.map.dyn.containers[id].searched = true''', '''	if kind == "container":
		mark_searched(id)''')
i.save()

# ------------------------------------------------------------------ world: box events, late joiners
w = Patch('game/src/match/world.gd')
w.rep('''func server_send_items(pid: int) -> void:
	## Floor loot rolled on the server during the build, in one message.
	var ids := PackedInt32Array()
	var entries := []
	var xfs := []
	for id in map.dyn.items:
		ids.append(id)
		entries.append(map.dyn.items[id].entry)
		xfs.append(map.dyn.items[id].xf)
	_items_bulk.rpc_id(pid, ids, entries, xfs)
	print("[net] sent %d floor items to %d" % [ids.size(), pid])


@rpc("authority", "call_remote", "reliable")
func _items_bulk(ids: PackedInt32Array, entries: Array, xfs: Array) -> void:
	## Authoritative list of the items on the ground (late joiners): drop what is gone, add what is new.
	if map == null:
		return
	var keep := {}
	for i in ids.size():
		keep[ids[i]] = true
	for id in map.dyn.items.keys():
		if not keep.has(id):
			map.dyn.remove_item(id)
	for i in ids.size():
		if not map.dyn.items.has(ids[i]):
			map.dyn.client_spawn_item(ids[i], entries[i], xfs[i])''', '''func server_send_items(pid: int) -> void:
	## Late joiners built the same floor loot from the match seed (ids 1..floor_count): send only what changed since,
	## the items taken and the items dropped.
	var gone := PackedInt32Array()
	var ids := PackedInt32Array()
	var entries := []
	var xfs := []
	for id in range(1, map.dyn.floor_count + 1):
		if not map.dyn.items.has(id):
			gone.append(id)
	for id in map.dyn.items:
		if id > map.dyn.floor_count:
			ids.append(id)
			entries.append(map.dyn.items[id].entry)
			xfs.append(map.dyn.items[id].xf)
	_items_delta.rpc_id(pid, map.dyn.floor_count, gone, ids, entries, xfs)
	print("[net] floor items to %d: %d taken, %d dropped" % [pid, gone.size(), ids.size()])


@rpc("authority", "call_remote", "reliable")
func _items_delta(floor_count: int, gone: PackedInt32Array, ids: PackedInt32Array, entries: Array, xfs: Array) -> void:
	## Items on the ground for a late joiner: remove the taken ones, add the dropped ones.
	if map == null:
		return
	if floor_count != map.dyn.floor_count:
		push_warning("[net] floor loot differs from the server's (%d vs %d items)" % [map.dyn.floor_count, floor_count])
	for id in gone:
		map.dyn.remove_item(id)
	for i in ids.size():
		if not map.dyn.items.has(ids[i]):
			map.dyn.client_spawn_item(ids[i], entries[i], xfs[i])


func map_box_opened_server(cid: int) -> void:
	map.dyn.set_box_open(cid, true)
	_box_opened.rpc(PackedInt32Array([cid]))


@rpc("authority", "call_remote", "reliable")
func _box_opened(cids: PackedInt32Array) -> void:
	if map == null:
		return
	for cid in cids:
		map.dyn.set_box_open(cid, true)''')
w.save()

# floor_count in dynamics
dy = Patch('game/src/world/dynamics.gd')
dy.rep('''var _next_item := 1''', '''var _next_item := 1
var floor_count := 0           # items 1..floor_count were rolled from the match seed on every machine''')
dy.rep('''	for sp in spawn:
		server_spawn_item(sp[0], sp[1], false)''', '''	for sp in spawn:
		server_spawn_item(sp[0], sp[1], false)
	floor_count = _next_item - 1''')
dy.save()

mb = Patch('game/src/world/map_builder.gd')
mb.rep('''	world.server_send_items(pid)''', '''	world.server_send_items(pid)
	var opened := dyn.opened_boxes()
	if not opened.is_empty():
		world._box_opened.rpc_id(pid, opened)''')
mb.save()

# ------------------------------------------------------------------ HUD prompt
h = Patch('game/src/ui/hud.gd')
h.rep('''			var it: Dictionary = world.map.dyn.items.get(int(t.id), {})
			if it.is_empty():
				return ""
			return "%s  Take %s" % [key, Defs.item_name(str(it.entry.id))]
		"container":
			return "%s  Search" % key''', '''			var it: Dictionary = world.map.dyn.items.get(int(t.id), {})
			if it.is_empty():
				return ""
			var iid := str(it.entry.id)
			var label := Defs.item_name(iid)
			if int(it.entry.get("n", 1)) > 1:
				label += " (%d)" % int(it.entry.n)
			if Defs.is_attachment(iid):
				var up: Array = Attach.best_slot_upgrade(ch.wpn.slots, iid)
				if int(up[0]) >= 0:
					label += ", fits your " + Defs.item_name(str(ch.wpn.slots[int(up[0])].id))
			elif iid.begins_with("ammo_"):
				for s in [1, 2, 3]:
					var wv = ch.wpn.slots[s]
					if wv != null and Defs.ammo_item(str(wv.id)) == iid:
						label += ", for your " + Defs.item_name(str(wv.id))
						break
			return "%s  Take %s" % [key, label]
		"container":
			var c: Dictionary = world.map.dyn.containers[int(t.id)]
			if c.has("box"):
				var b: Dictionary = world.map.dyn.loot_boxes[int(c.box)]
				return "%s  Search the %s%s" % [key, BOX_NAMES.get(str(b.name), "box"), " (opened)" if b.open else ""]
			return "%s  Search" % key''')
h.rep('''func _prompt_text() -> String:''', '''const Attach := preload("res://src/weapons/attachments.gd")
const BOX_NAMES := {"lootbox_balikbayan": "balikbayan box", "lootbox_bin": "storage bin", "lootbox_ammocan": "ammo can",
	"lootbox_footlocker": "footlocker", "lootbox_toolbox": "toolbox", "lootbox_medcase": "first aid case", "lootbox_riflecase": "rifle case",
	"lootbox_cooler": "icebox"}


func _prompt_text() -> String:''')
h.save()
print('ok')
