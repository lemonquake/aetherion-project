extends RefCounted
## Binary encoding of commands (client -> server) and snapshots (server -> client).


static func encode_cmds(cmds: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(cmds.size())
	for c in cmds:
		b.put_u32(int(c.seq))
		b.put_u32(int(c.get("view_tick", 0)))
		b.put_8(int(round(clampf(float(c.mx), -1.0, 1.0) * 127.0)))
		b.put_8(int(round(clampf(float(c.my), -1.0, 1.0) * 127.0)))
		b.put_float(float(c.yaw))
		b.put_float(float(c.pitch))
		b.put_u32(int(c.btn))
		b.put_u8(int(c.get("slot", 0)))
		b.put_u32(int(c.get("tick", 0)))
	return b.data_array


static func decode_cmds(bytes: PackedByteArray) -> Array:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var out := []
	if bytes.size() < 1:
		return out
	var n := b.get_u8()
	for i in mini(n, 8):
		if b.get_available_bytes() < 27:
			break
		var c := {}
		c.seq = b.get_u32()
		c.view_tick = b.get_u32()
		c.mx = b.get_8() / 127.0
		c.my = b.get_8() / 127.0
		c.yaw = wrapf(b.get_float(), -PI, PI)
		c.pitch = clampf(b.get_float(), -1.5, 1.5)
		c.btn = b.get_u32()
		c.slot = clampi(b.get_u8(), 0, 3)
		c.tick = b.get_u32()
		out.append(c)
	return out


static func encode(tick: int, ack: int, me, others: Array, props: Array, weapon_ids: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_u32(ack)
	if me:
		b.put_u16(me.eid)
		var s: Dictionary = me.get_state()
		_v3(b, s.pos)
		_v3(b, s.vel)
		b.put_u8(int(s.mode))
		b.put_half(float(s.crouch))
		b.put_u8(1 if s.crouching else 0)
		b.put_half(float(s.jcd))
		b.put_half(float(s.ff))
		b.put_half(float(s.ct))
		b.put_float(float(s.cy))
		b.put_half(float(s.fl))
		b.put_u32(int(s.pb))
		b.put_u32(me.compute_flags())
		b.put_half(me.injury_speed)
		b.put_half(me.carry_speed)
		var w: Dictionary = me.wpn.get_state()
		b.put_u8(int(w.cur))
		b.put_u8(int(w.want))
		b.put_u8(int(w.state))
		b.put_half(float(w.timer))
		b.put_u8(int(w.rp))
		b.put_half(float(w.cd))
		b.put_half(float(w.ads))
		b.put_u32(int(w.shots))
		b.put_u16(int(w.burst))
		b.put_half(minf(float(w.since), 60000.0))
		b.put_half((w.kick as Vector2).x)
		b.put_half((w.kick as Vector2).y)
		b.put_u16(int(w.mag))
		b.put_u8((1 if w.chamber else 0) | (2 if w.pf else 0) | (4 if w.pr else 0) | (8 if w.pm else 0))
		b.put_u8(int(w.mode))
		b.put_u8(1 if me.light.on else 0)
		b.put_half(me.light.swap_t)
		b.put_half(maxf(me.light.charge(), -1.0))
	else:
		b.put_u16(0)
	b.put_u8(others.size())
	for ch in others:
		b.put_u16(ch.eid)
		_v3(b, ch.global_position)
		b.put_half(ch.velocity.x)
		b.put_half(ch.velocity.y)
		b.put_half(ch.velocity.z)
		b.put_half(wrapf(ch.yaw, -PI, PI))
		b.put_half(ch.pitch)
		b.put_u8(int(clampf(ch.crouch, 0.0, 2.0) * 127.0))
		b.put_u8(ch.mode)
		b.put_u32(ch.compute_flags())
		var wi := weapon_ids.find(ch.weapon_id)
		b.put_u8(255 if wi < 0 else wi)
		b.put_half(wrapf(ch.chute_yaw, -PI, PI))
	b.put_u16(props.size())
	for p in props:
		b.put_u32(int(p.id))
		_v3(b, p.pos)
		var q: Quaternion = p.rot
		b.put_half(q.x)
		b.put_half(q.y)
		b.put_half(q.z)
		b.put_half(q.w)
	return b.data_array


static func decode(bytes: PackedByteArray, weapon_ids: Array) -> Dictionary:
	if bytes.size() < 11:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var out := {"tick": b.get_u32(), "ack": b.get_u32(), "others": [], "props": []}
	var own_eid := b.get_u16()
	if own_eid != 0:
		var s := {}
		s.eid = own_eid
		s.pos = _gv3(b)
		s.vel = _gv3(b)
		s.mode = b.get_u8()
		s.crouch = b.get_half()
		s.crouching = b.get_u8() == 1
		s.jcd = b.get_half()
		s.ff = b.get_half()
		s.ct = b.get_half()
		s.cy = b.get_float()
		s.fl = b.get_half()
		s.pb = b.get_u32()
		s.flags = b.get_u32()
		s.injury_speed = b.get_half()
		s.carry_speed = b.get_half()
		var w := {}
		w.cur = b.get_u8()
		w.want = b.get_u8()
		w.state = b.get_u8()
		w.timer = b.get_half()
		w.rp = b.get_u8()
		w.cd = b.get_half()
		w.ads = b.get_half()
		w.shots = b.get_u32()
		w.burst = b.get_u16()
		w.since = b.get_half()
		w.kick = Vector2(b.get_half(), b.get_half())
		w.mag = b.get_u16()
		var bits := b.get_u8()
		w.chamber = (bits & 1) != 0
		w.pf = (bits & 2) != 0
		w.pr = (bits & 4) != 0
		w.pm = (bits & 8) != 0
		w.mode = b.get_u8()
		s.wpn = w
		s.light_on = b.get_u8() == 1
		s.light_swap = b.get_half()
		s.light_charge = b.get_half()
		out.own = s
	var n := b.get_u8()
	for i in n:
		var o := {}
		o.eid = b.get_u16()
		o.pos = _gv3(b)
		o.vel = Vector3(b.get_half(), b.get_half(), b.get_half())
		o.yaw = b.get_half()
		o.pitch = b.get_half()
		o.crouch = b.get_u8() / 127.0
		o.mode = b.get_u8()
		o.flags = b.get_u32()
		var wi := b.get_u8()
		o.weapon = "" if wi == 255 or wi >= weapon_ids.size() else weapon_ids[wi]
		o.cy = b.get_half()
		out.others.append(o)
	var np := b.get_u16()
	for i in np:
		var p := {}
		p.id = b.get_u32()
		p.pos = _gv3(b)
		p.rot = Quaternion(b.get_half(), b.get_half(), b.get_half(), b.get_half()).normalized()
		out.props.append(p)
	return out


static func _v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _gv3(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_float(), b.get_float(), b.get_float())
