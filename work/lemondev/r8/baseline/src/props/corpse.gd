extends Node3D
## A dead player: a 13-part ragdoll that moves the character's own skinned, dressed body, and the inventory they
## carried.
##
## The server simulates the ragdoll (jointed rigid bodies) with the momentum of the fall and the killing shot,
## streams the part transforms to clients until the body comes to rest, then sends the final pose reliably. Clients
## pose the same parts kinematically, so every machine sees the body lying in the same place and the loot is always
## where the body is. Corpses stay until the match resets.
##
## The parts are laid along the character rig's bones and start from the pose the living body was in when it died
## (standing, walking, running, crouched or lying downed: the same clips character_visual plays), fitted clear of
## walls, floors, other bodies and stair treads before the first physics step. Knees and elbows are hinges that bend
## one way; hips, shoulders, spine, neck and ankles are cone-twist joints whose cones are centred on a natural
## mid-range. Every machine with a screen poses the skeleton of the dressed body from the parts; plain shapes are
## drawn only if the body model is missing, and headless servers draw nothing.

const BODY := "res://assets/models/sleep/characters/stranger.glb"
const Outfit := preload("res://src/player/outfit.gd")
## Only ragdolls collide with this layer: solid stair treads over flights whose collision is a ramp under the drawn
## steps (Dynamics.corpse_steps_near), so a body on a stair lies on the steps the player sees.
const PHYS_CORPSE_STEPS := 1 << 19
const MASK := Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS | Defs.PHYS_CORPSE | PHYS_CORPSE_STEPS

## name: [bone it moves, parent part, shape, a, b, size, mass]. Rig rest pose (T-pose), skeleton space: the
## character faces +Z, its left is +X, feet at 0. Boxes: centre a, size b. Capsules: from a (the joint end) to b
## (end caps included), radius in size. Sized to the dressed body (41 outfits measured, rest pose): 90% of its
## vertices lie within 2 cm of these shapes, 99% within 3-5 cm (puffer jackets, cap brims); then 1 cm larger all
## round, because resting contacts sink by Jolt's penetration slop (1 cm in project.godot). Each body then grows
## them for what it wears (_outfit_extra: brims, hoods, boots, puffer jackets, backpacks).
const PARTS := {
	"pelvis": ["hips", "", "box", Vector3(0, 1.01, 0.03), Vector3(0.3, 0.24, 0.31), 0.0, 11.0],
	"chest": ["chest", "pelvis", "box", Vector3(0, 1.285, 0.035), Vector3(0.38, 0.45, 0.35), 0.0, 17.0],
	"head": ["head", "chest", "capsule", Vector3(0, 1.46, 0.035), Vector3(0, 1.835, 0.035), 0.122, 5.0],
	"uarm_l": ["upper_arm.L", "chest", "capsule", Vector3(0.16, 1.45, 0), Vector3(0.51, 1.45, 0), 0.095, 2.2],
	"larm_l": ["forearm.L", "uarm_l", "capsule", Vector3(0.43, 1.45, -0.01), Vector3(0.87, 1.43, 0), 0.078, 1.7],
	"uarm_r": ["upper_arm.R", "chest", "capsule", Vector3(-0.16, 1.45, 0), Vector3(-0.51, 1.45, 0), 0.095, 2.2],
	"larm_r": ["forearm.R", "uarm_r", "capsule", Vector3(-0.43, 1.45, -0.01), Vector3(-0.87, 1.43, 0), 0.078, 1.7],
	"uleg_l": ["thigh.L", "pelvis", "capsule", Vector3(0.11, 1.11, 0.02), Vector3(0.11, 0.49, 0.02), 0.115, 8.0],
	"lleg_l": ["shin.L", "uleg_l", "capsule", Vector3(0.1, 0.57, -0.01), Vector3(0.1, -0.03, -0.01), 0.09, 4.0],
	"foot_l": ["foot.L", "lleg_l", "box", Vector3(0.145, 0.055, 0.07), Vector3(0.18, 0.15, 0.29), 0.0, 1.1],
	"uleg_r": ["thigh.R", "pelvis", "capsule", Vector3(-0.11, 1.11, 0.02), Vector3(-0.11, 0.49, 0.02), 0.115, 8.0],
	"lleg_r": ["shin.R", "uleg_r", "capsule", Vector3(-0.1, 0.57, -0.01), Vector3(-0.1, -0.03, -0.01), 0.09, 4.0],
	"foot_r": ["foot.R", "lleg_r", "box", Vector3(-0.145, 0.055, 0.07), Vector3(0.18, 0.15, 0.29), 0.0, 1.1],
}
## A backpack, on the chest part when the outfit has one (centre and size, rest pose).
const PACK := [Vector3(0, 1.27, -0.2), Vector3(0.32, 0.38, 0.16)]
## Which part each bone's vertices ride on.
const BONE_PART := {"root": "pelvis", "hips": "pelvis", "spine": "chest", "chest": "chest", "neck": "head", "head": "head",
	"shoulder.L": "chest", "upper_arm.L": "uarm_l", "forearm.L": "larm_l", "hand.L": "larm_l", "weapon.L": "larm_l",
	"thigh.L": "uleg_l", "shin.L": "lleg_l", "foot.L": "foot_l", "toe.L": "foot_l",
	"shoulder.R": "chest", "upper_arm.R": "uarm_r", "forearm.R": "larm_r", "hand.R": "larm_r", "weapon.R": "larm_r",
	"thigh.R": "uleg_r", "shin.R": "lleg_r", "foot.R": "foot_r", "toe.R": "foot_r"}
## Most a piece of clothing may grow a part (a cap's brim would otherwise make the head a ball).
const EXTRA_MAX := 0.05
const ORDER := ["pelvis", "chest", "head", "uarm_l", "larm_l", "uarm_r", "larm_r", "uleg_l", "lleg_l", "foot_l", "uleg_r", "lleg_r", "foot_r"]
## child part: [joint, anchor (rest pose, skeleton space), swing or lower limit, twist or upper limit]. Hinges bend
## the child toward FLEX (skeleton space) for positive angles; cones are centred on the neutral pose (see rig()).
const JOINTS := {
	"chest": ["cone", Vector3(0, 1.08, 0), 0.7, 0.35],
	"head": ["cone", Vector3(0, 1.5, 0), 0.65, 0.55],
	"uarm_l": ["cone", Vector3(0.19, 1.44, 0), 1.4, 0.6],
	"uarm_r": ["cone", Vector3(-0.19, 1.44, 0), 1.4, 0.6],
	"larm_l": ["hinge", Vector3(0.47, 1.44, 0), -0.25, 2.5],
	"larm_r": ["hinge", Vector3(-0.47, 1.44, 0), -0.25, 2.5],
	"uleg_l": ["cone", Vector3(0.1, 0.94, 0), 1.15, 0.35],
	"uleg_r": ["cone", Vector3(-0.1, 0.94, 0), 1.15, 0.35],
	"lleg_l": ["hinge", Vector3(0.1, 0.51, 0), -0.1, 2.6],
	"lleg_r": ["hinge", Vector3(-0.1, 0.51, 0), -0.1, 2.6],
	"foot_l": ["cone", Vector3(0.1, 0.08, 0), 0.5, 0.15],
	"foot_r": ["cone", Vector3(-0.1, 0.08, 0), 0.5, 0.15],
}
## Elbows fold forward, knees backward (skeleton space: forward is +Z).
const FLEX := {"larm_l": Vector3(0, 0, 1), "larm_r": Vector3(0, 0, 1), "lleg_l": Vector3(0, 0, -1), "lleg_r": Vector3(0, 0, -1)}
## Where the killing shot lands, by hit zone.
const HIT_PART := {"head": "head", "torso": "chest", "arm_l": "uarm_l", "arm_r": "uarm_r", "leg_l": "uleg_l", "leg_r": "uleg_r"}

var id := -1
var server := false
var entries: Array = []
var pname := ""
var team := 0
var outfit := 0
var look: Dictionary = {}
var eid := 0
var bodies: Dictionary = {}     # server: name -> RigidBody3D
var visuals: Dictionary = {}    # client: name -> StaticBody3D
var skel: Skeleton3D = null     # the dressed body, on machines with a screen
var settled := false
var _pooled := false
var fit_note := ""              # how the start pose was fitted clear of the world (for logs and tests)
var rescues := 0                # times the body was pulled back up after falling through the ground
var _links: Array = []          # [parent body, child body, anchor in parent, anchor in child]
var _sync_t := 0.0
var _rest_t := 0.0
var _age := 0.0
var _still_t := 0.0
var _pose_tail := 0.0
var _last_good: Array = []
var _good_t := 0.0
var _snaps: Array = []
var _final_got := false
var _extra: Dictionary = {}     # part (or "pack") -> metres its shape grows for this outfit
var world = null

static var _rig: Dictionary = {}
static var _body_scene: PackedScene = null
static var _piece_extras: Dictionary = {}
static var _bind_parts: Array = []


# ------------------------------------------------------------------ the rig (shared, built once)

static func rig() -> Dictionary:
	## Bones, rest pose and clips of the character model, the parts' frames on their bones, and the poses the ragdoll
	## starts from. Works headless (nothing is added to the tree).
	if not _rig.is_empty():
		return _rig
	var R := {"ok": false, "skel_in_char": Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), "poses": {}, "anims": {}}
	_rig = R
	var prest := {}
	for part in ORDER:
		var spec: Array = PARTS[part]
		if spec[2] == "box":
			prest[part] = Transform3D(Basis(), spec[3])
		else:
			prest[part] = _segment_frame(spec[3], spec[4], Vector3.RIGHT)
	R.prest = prest
	var pinv := {}
	var near := {}
	for part in ORDER:
		pinv[part] = (prest[part] as Transform3D).affine_inverse()
		# A vertex counts as covered by its own part, the part above it or a part below it.
		var nb := [part]
		if str(PARTS[part][1]) != "":
			nb.append(str(PARTS[part][1]))
		for other in ORDER:
			if str(PARTS[other][1]) == part:
				nb.append(other)
		near[part] = nb
	R.prest_inv = pinv
	R.near = near
	if ResourceLoader.exists(BODY):
		_body_scene = load(BODY)
	if _body_scene == null:
		return R
	var m: Node = _body_scene.instantiate()
	var sk: Skeleton3D = _find(m, "Skeleton3D")
	var ap: AnimationPlayer = _find(m, "AnimationPlayer")
	if sk == null:
		m.free()
		return R
	# The skeleton's place in the model, then the model's half turn (the clips face +Z, characters face -Z).
	var chain := Transform3D()
	var n: Node = sk
	while n != m and n is Node3D:
		chain = (n as Node3D).transform * chain
		n = n.get_parent()
	R.skel_in_char = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * chain
	var names := []
	var parents := []
	var local := []
	var rest := []
	var index := {}
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
		parents.append(sk.get_bone_parent(i))
		local.append(sk.get_bone_rest(i))
		rest.append(sk.get_bone_global_rest(i))
		index[sk.get_bone_name(i)] = i
	R.names = names
	R.parents = parents
	R.local = local
	R.rest = rest
	R.index = index
	if ap:
		for a in ["idle", "walk", "run", "crouch_walk", "knockdown", "knockback"]:
			if ap.has_animation(a):
				R.anims[a] = ap.get_animation(a)
	m.free()
	for part in ORDER:
		if not index.has(PARTS[part][0]):
			return R
	# Each part's frame relative to its bone (constant), and how every bone is driven from the parts: by its part,
	# half way between two parts (spine, neck), rigidly with a part (root, shoulders) or by its parent (hands, toes).
	var boff := {}
	var drive := []
	drive.resize(names.size())
	for part in ORDER:
		var b: int = index[PARTS[part][0]]
		boff[part] = (rest[b] as Transform3D).affine_inverse() * prest[part]
		drive[b] = [0, part, (boff[part] as Transform3D).affine_inverse()]
	for pair in [["root", "pelvis"], ["shoulder.L", "chest"], ["shoulder.R", "chest"]]:
		if index.has(pair[0]):
			var b: int = index[pair[0]]
			drive[b] = [0, pair[1], (prest[pair[1]] as Transform3D).affine_inverse() * rest[b]]
	for tri in [["spine", "pelvis", "chest"], ["neck", "chest", "head"]]:
		if index.has(tri[0]):
			var b: int = index[tri[0]]
			drive[b] = [1, tri[1], (prest[tri[1]] as Transform3D).affine_inverse() * rest[b], tri[2], (prest[tri[2]] as Transform3D).affine_inverse() * rest[b]]
	R.boff = boff
	R.drive = drive
	# Neutral pose: the middle of the joints' ranges (arms 45 degrees down and a little forward, thighs 45 degrees
	# forward); the joints are made in this pose so their cones are centred on it.
	var g: Array = rest.duplicate()
	_turn(R, g, index["upper_arm.L"], Vector3.BACK, -0.8)
	_turn(R, g, index["upper_arm.L"], Vector3.UP, -0.45)
	_turn(R, g, index["upper_arm.R"], Vector3.BACK, 0.8)
	_turn(R, g, index["upper_arm.R"], Vector3.UP, 0.45)
	_turn(R, g, index["thigh.L"], Vector3.RIGHT, -0.78)
	_turn(R, g, index["thigh.R"], Vector3.RIGHT, -0.78)
	R.neutral = g
	R.ok = true
	return R


static func _segment_frame(a: Vector3, b: Vector3, hint: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var x := hint - y * hint.dot(y)
	if x.length() < 0.1:
		x = Vector3.BACK - y * Vector3.BACK.dot(y)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)


static func _turn(R: Dictionary, g: Array, bone: int, axis: Vector3, ang: float) -> void:
	## Rotates a bone and everything below it about the bone's origin (skeleton space).
	var b := Basis(axis.normalized(), ang)
	var pivot: Vector3 = (g[bone] as Transform3D).origin
	var rot := Transform3D(b, pivot - b * pivot)
	for i in g.size():
		var p := i
		while p >= 0 and p != bone:
			p = R.parents[p]
		if p == bone:
			g[i] = rot * g[i]


static func _anim_pose(R: Dictionary, clip: String, at_end: bool) -> Array:
	## Bone globals (skeleton space) of a clip's first or last frame, sampled from the tracks.
	var key := clip + ("@end" if at_end else "")
	if R.poses.has(key):
		return R.poses[key]
	var a: Animation = R.anims.get(clip)
	if a == null:
		return R.neutral
	var t := a.length if at_end else 0.0
	var loc: Array = R.local.duplicate()
	for i in a.get_track_count():
		var b: int = R.index.get(str(a.track_get_path(i).get_concatenated_subnames()), -1)
		if b < 0:
			continue
		var cur: Transform3D = loc[b]
		match a.track_get_type(i):
			Animation.TYPE_POSITION_3D:
				loc[b] = Transform3D(cur.basis, a.position_track_interpolate(i, t))
			Animation.TYPE_ROTATION_3D:
				loc[b] = Transform3D(Basis(a.rotation_track_interpolate(i, t)), cur.origin)
	var g := []
	for i in loc.size():
		var p: int = R.parents[i]
		g.append(loc[i] if p < 0 else (g[p] as Transform3D) * loc[i])
	R.poses[key] = g
	return g


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


static func _shape(part: String, shrink: float = 0.0, extra: float = 0.0) -> Shape3D:
	var spec: Array = PARTS[part]
	var grow := extra - shrink
	if spec[2] == "box":
		var b := BoxShape3D.new()
		b.size = (spec[4] as Vector3) + Vector3.ONE * grow * 2.0
		return b
	var c := CapsuleShape3D.new()
	c.radius = float(spec[5]) + grow
	c.height = maxf((spec[4] as Vector3).distance_to(spec[3]) + grow * 2.0, c.radius * 2.0 + 0.01)
	return c


static func _sdf(part: String, p: Vector3) -> float:
	## Signed distance from a rest-pose point to a part's bare shape ("pack": the backpack box).
	var R := rig()
	if part == "pack":
		var qp: Vector3 = (p - (PACK[0] as Vector3)).abs() - (PACK[1] as Vector3) * 0.5
		return Vector3(maxf(qp.x, 0.0), maxf(qp.y, 0.0), maxf(qp.z, 0.0)).length() + minf(maxf(qp.x, maxf(qp.y, qp.z)), 0.0)
	var spec: Array = PARTS[part]
	var l: Vector3 = (R.prest_inv[part] as Transform3D) * p
	if spec[2] == "box":
		var q: Vector3 = l.abs() - (spec[4] as Vector3) * 0.5
		return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
	var r := float(spec[5])
	var h := (spec[4] as Vector3).distance_to(spec[3]) * 0.5 - r
	return Vector3(l.x, maxf(absf(l.y) - h, 0.0), l.z).length() - r


static func _piece_extra(piece: String) -> Dictionary:
	## How far one outfit piece sticks out of the bare shapes (98th percentile of its vertices, rest pose: the
	## pieces are modelled on the rig in its rest pose), per part it rides on. Measured once per piece.
	if _piece_extras.has(piece):
		return _piece_extras[piece]
	var out := {}
	_piece_extras[piece] = out
	var R := rig()
	var arr: Array = Outfit.pieces.get(piece, [])
	if not R.ok or arr.is_empty() or Outfit.skin == null:
		return out
	if _bind_parts.is_empty():
		var sk: Skin = Outfit.skin
		for b in sk.get_bind_count():
			var bone := sk.get_bind_bone(b)
			var bn: String = sk.get_bind_name(b) if bone < 0 or bone >= (R.names as Array).size() else R.names[bone]
			_bind_parts.append(str(BONE_PART.get(bn, "")))
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	if v.is_empty() or bo.size() < v.size():
		return out
	var nw := bo.size() / v.size()
	var pack := piece.begins_with("pack")
	var dists := {}
	for i in range(0, v.size(), 3):
		var top := 0
		var tw := -1.0
		for k in nw:
			if w[i * nw + k] > tw:
				tw = w[i * nw + k]
				top = bo[i * nw + k]
		var part: String = _bind_parts[top] if top < _bind_parts.size() else ""
		if part == "":
			continue
		var d := 9.0
		for q in R.near[part]:
			d = minf(d, _sdf(q, v[i]))
		var key := part
		if pack and part == "chest":
			var dp := _sdf("pack", v[i])
			if dp < d:
				d = dp
				key = "pack"
		if not dists.has(key):
			dists[key] = []
		dists[key].append(d)
	for key in dists:
		var a: Array = dists[key]
		a.sort()
		var e := clampf(float(a[int(a.size() * 0.98)]), 0.0, EXTRA_MAX)
		if e > 0.003:
			out[key] = e
	return out


func _outfit_extra() -> void:
	## Grow the parts for the outfit worn: the largest growth any worn piece needs on each part.
	_extra = {}
	if look.is_empty() or not Outfit.ensure():
		return
	for p in Outfit.pieces_for(look):
		var ex := _piece_extra(str(p[0]))
		for k in ex:
			_extra[k] = maxf(float(_extra.get(k, 0.0)), float(ex[k]))


func _shapes(part: String, shrink: float = 0.0) -> Array:
	## [[shape, transform in the part's frame]] of a part: its own shape, and the backpack on the chest if worn.
	var out := [[_shape(part, shrink, float(_extra.get(part, 0.0))), Transform3D()]]
	if part == "chest" and _wears_pack():
		var b := BoxShape3D.new()
		b.size = (PACK[1] as Vector3) + Vector3.ONE * (float(_extra.get("pack", 0.0)) - shrink) * 2.0
		out.append([b, (rig().prest.chest as Transform3D).affine_inverse() * Transform3D(Basis(), PACK[0])])
	return out


func _wears_pack() -> bool:
	return not look.is_empty() and str(look.get("pack", "none")) != "none"


func _add_shapes(body: CollisionObject3D, part: String) -> void:
	for s in _shapes(part):
		var cs := CollisionShape3D.new()
		cs.shape = s[0]
		cs.transform = s[1]
		body.add_child(cs)


static func part_xforms(char_xf: Transform3D, g) -> Dictionary:
	## World transforms of the parts for a character frame (feet at the origin, facing -Z) and a rig pose.
	var R := rig()
	var base: Transform3D = char_xf * R.skel_in_char
	var out := {}
	for part in ORDER:
		if g == null or not R.ok:
			out[part] = base * R.prest[part]
		else:
			out[part] = base * (g[R.index[PARTS[part][0]]] as Transform3D) * R.boff[part]
	return out


# ------------------------------------------------------------------ server

func setup_server(w, cid: int, ch, impulse: Vector3) -> void:
	world = w
	id = cid
	server = true
	if world.effects:
		world.effects.body_fell(self)
	pname = ch.pname
	team = ch.team
	eid = ch.eid
	# The outfit they wore (character_visual._dress picks the same): its backpack is part of the body's shape.
	look = Net.players.get(ch.pid, {}).get("look", {})
	look = Outfit.normalized(look) if not look.is_empty() else Outfit.random_look(ch.eid * 7919 + 17)
	var t_out := Time.get_ticks_usec()
	_outfit_extra()
	t_out = Time.get_ticks_usec() - t_out
	name = "Corpse%d" % id
	var R := rig()
	var origin: Vector3 = ch.global_position
	global_position = origin
	var fit := _fit(R, ch, _start_pose(R, ch))
	fit_note += "; outfit shapes %.1f ms %s" % [t_out / 1000.0, str(_extra)]
	var start_g = fit.g
	var char_xf: Transform3D = fit.xf
	var start := part_xforms(char_xf, start_g)
	var neutral := part_xforms(char_xf, R.neutral if R.ok else null)
	for part in ORDER:
		var spec: Array = PARTS[part]
		var rb := RigidBody3D.new()
		rb.name = part
		rb.mass = float(spec[6])
		rb.collision_layer = Defs.PHYS_CORPSE
		rb.collision_mask = MASK
		rb.set_meta("corpse_id", id)
		rb.set_meta("mat", "flesh")
		# A dead body has no muscle tone: little to hold its limbs but the joints' limits.
		rb.linear_damp = 0.1
		rb.angular_damp = 0.8
		rb.continuous_cd = true
		var pm := PhysicsMaterial.new()
		pm.friction = 0.85
		pm.bounce = 0.0
		rb.physics_material_override = pm
		_add_shapes(rb, part)
		add_child(rb)
		rb.global_transform = neutral[part]
		bodies[part] = rb
	# Joints are made in the neutral pose (their limits are relative to the pose they are made in), then the parts
	# move to the pose the body died in.
	var fwd: Vector3 = (char_xf.basis * R.skel_in_char.basis * Vector3.BACK).normalized()
	for part in ORDER:
		var parent := str(PARTS[part][1])
		if parent != "":
			_joint(bodies[parent], bodies[part], part, neutral, fwd)
	for part in ORDER:
		var rb: RigidBody3D = bodies[part]
		rb.global_transform = start[part]
		rb.reset_physics_interpolation()
		rb.linear_velocity = ch.velocity
	_no_self_overlap(start)
	_apply_hit(ch, impulse)
	_last_good = _xforms()
	if DisplayServer.get_name() != "headless":
		_build_body()


func _start_pose(R: Dictionary, ch):
	## The clip the living body was showing (character_visual._animate), first frame; downed bodies lie as the
	## knockdown clip ends.
	if not R.ok:
		return null
	var v: Vector3 = ch.velocity
	var speed := Vector2(v.x, v.z).length()
	if ch.mode == Motor.DOWNED:
		return _anim_pose(R, "knockdown", true)
	if ch.crouch > 0.5:
		return _anim_pose(R, "crouch_walk", false)
	if v.y < -4.0:
		return _anim_pose(R, "knockback", false)
	if speed > 5.0:
		return _anim_pose(R, "run", false)
	if speed > 0.4:
		return _anim_pose(R, "walk", false)
	return _anim_pose(R, "idle", false)


func _fit(R: Dictionary, ch, g) -> Dictionary:
	## The character frame and pose the ragdoll starts in: where the body was, in the pose it died in, turned, moved
	## and lifted as little as possible so no part starts inside a wall, floor, stair tread or another body (the
	## solver would push it out through the thin side, or pin it there). A body lying downed is first tilted to the
	## walkable surface under it. Where nothing fits (a cramped corner) the body starts standing and collapses.
	var t0 := Time.get_ticks_usec()
	var space := get_world_3d().direct_space_state
	var origin: Vector3 = ch.global_position
	var basis := Basis(Vector3.UP, ch.yaw)
	if ch.mode == Motor.DOWNED:
		var q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.4, origin + Vector3.DOWN * 0.6, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var r := space.intersect_ray(q)
		if not r.is_empty() and (r.normal as Vector3).y > 0.6:
			basis = Basis(Quaternion(Vector3.UP, (r.normal as Vector3).normalized())) * basis
	var shapes := {}
	for part in ORDER:
		shapes[part] = _shapes(part, 0.012)
	var cands := []
	for lift in [0.0, 0.03, 0.07, 0.12, 0.2, 0.3]:
		cands.append([0.0, Vector3.ZERO, lift])
	for yaw in [0.5, -0.5, 1.1, -1.1, 1.6, -1.6, 2.2, -2.2, 2.7, -2.7, PI]:
		for lift in [0.0, 0.05, 0.12, 0.25]:
			cands.append([yaw, Vector3.ZERO, lift])
	for d in [0.15, 0.3, 0.45, 0.6]:
		for k in 8:
			var a := TAU * k / 8.0
			for yaw in [0.0, 1.6]:
				for lift in [0.0, 0.1]:
					cands.append([yaw, Vector3(cos(a), 0, sin(a)) * d, lift])
	for lift in [0.45, 0.6]:
		cands.append([0.0, Vector3.ZERO, lift])
	var poses := [[g, "as it died"]]
	if R.ok:
		poses.append([_anim_pose(R, "idle", false), "standing"])
	var best := {}
	var best_n := 99
	var tries := 0
	for pz in poses:
		var pb := Basis(Vector3.UP, ch.yaw) if pz[1] == "standing" else basis
		for c in cands:
			tries += 1
			var xf := Transform3D(Basis(Vector3.UP, float(c[0])) * pb, origin + (c[1] as Vector3) + Vector3.UP * float(c[2]))
			var px := part_xforms(xf, pz[0])
			var n := 0
			var touching := []
			for part in ORDER:
				for s in shapes[part]:
					var q := PhysicsShapeQueryParameters3D.new()
					q.shape = s[0]
					q.transform = (px[part] as Transform3D) * (s[1] as Transform3D)
					q.collision_mask = MASK
					var hit := space.intersect_shape(q, 1)
					if not hit.is_empty():
						n += 1
						touching.append("%s:%s" % [part, str(hit[0].collider.name) if hit[0].collider is Node else "geometry"])
						break
				if n >= best_n:
					break
			if n < best_n:
				best_n = n
				best = {"xf": xf, "c": c, "touching": touching, "g": pz[0], "pose": pz[1]}
			if n == 0:
				break
		if best_n == 0:
			break
	fit_note = "%s, %d tries in %.1f ms, turn %.1f, shift %.2f m, lift %.2f m, %d parts still touching %s" % [best.pose, tries,
		(Time.get_ticks_usec() - t0) / 1000.0, float(best.c[0]), (best.c[1] as Vector3).length(), float(best.c[2]), best_n, ", ".join(best.touching)]
	return best


func _joint(a: RigidBody3D, b: RigidBody3D, part: String, px: Dictionary, fwd: Vector3) -> void:
	var spec: Array = JOINTS[part]
	var R := rig()
	var anchor: Vector3 = (px[part] as Transform3D) * ((R.prest[part] as Transform3D).affine_inverse() * (spec[1] as Vector3))
	var d: Vector3 = (px[part] as Transform3D).basis.y.normalized()
	var j: Joint3D
	var basis: Basis
	if spec[0] == "hinge":
		# The hinge turns the child toward FLEX for positive angles; Jolt's hinge measures them about -Z.
		var flex: Vector3 = (fwd if (FLEX[part] as Vector3).z > 0.0 else -fwd)
		var axis := d.cross(flex - d * flex.dot(d)).normalized()
		var z := -axis
		basis = Basis(d, z.cross(d), z)
		var h := HingeJoint3D.new()
		h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, float(spec[2]))
		h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, float(spec[3]))
		j = h
	else:
		# The cone's axis (X) runs along the child part, so the swing limit is centred on the neutral pose.
		var y := (px[part] as Transform3D).basis.z
		y = (y - d * y.dot(d)).normalized()
		basis = Basis(d, y, d.cross(y))
		var c := ConeTwistJoint3D.new()
		c.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, float(spec[2]))
		c.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, float(spec[3]))
		# No softness: Jolt ignores it and logged a warning with a backtrace per joint (a hitch on every death).
		c.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
		j = c
	add_child(j)
	j.global_transform = Transform3D(basis.orthonormalized(), anchor)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	_links.append([a, b, a.global_transform.affine_inverse() * anchor, b.global_transform.affine_inverse() * anchor])


func _no_self_overlap(px: Dictionary) -> void:
	## Parts that start inside one another (a hand on a thigh when crouched, an arm across the chest when downed) would
	## be shoved apart on the first step: those pairs ignore each other. Jointed pairs never collide anyway.
	var seg := {}
	for part in ORDER:
		var spec: Array = PARTS[part]
		var xf: Transform3D = px[part]
		if spec[2] == "box":
			var s: Vector3 = spec[4]
			var dims := [[s.x, Vector3.RIGHT], [s.y, Vector3.UP], [s.z, Vector3.BACK]]
			dims.sort_custom(func(p, q): return p[0] > q[0])
			var r: float = float(dims[1][0]) * 0.5 + float(_extra.get(part, 0.0))
			var half: float = maxf(float(dims[0][0]) * 0.5 - r, 0.0)
			seg[part] = [xf * ((dims[0][1] as Vector3) * half), xf * ((dims[0][1] as Vector3) * -half), r]
		else:
			var h: float = (spec[4] as Vector3).distance_to(spec[3]) * 0.5 - float(spec[5])
			seg[part] = [xf * Vector3(0, h, 0), xf * Vector3(0, -h, 0), float(spec[5]) + float(_extra.get(part, 0.0))]
	for i in ORDER.size():
		for k in range(i + 1, ORDER.size()):
			var a: String = ORDER[i]
			var b: String = ORDER[k]
			if PARTS[a][1] == b or PARTS[b][1] == a:
				continue
			var pts := Geometry3D.get_closest_points_between_segments(seg[a][0], seg[a][1], seg[b][0], seg[b][1])
			if (pts[0] as Vector3).distance_to(pts[1]) < float(seg[a][2]) + float(seg[b][2]) - 0.005:
				(bodies[a] as RigidBody3D).add_collision_exception_with(bodies[b])


func _apply_hit(ch, impulse: Vector3) -> void:
	## The killing shot: most of it where it hit (off-centre, so the body turns), the rest into chest and pelvis.
	if impulse == Vector3.ZERO:
		return
	var hit: Array = ch.get_meta("killing_hit", [])
	var part := "chest"
	var at := Vector3.INF
	if hit.size() >= 2:
		part = str(HIT_PART.get(str(hit[0]), "chest"))
		at = hit[1]
	var rb: RigidBody3D = bodies[part]
	var off := Vector3.ZERO if at == Vector3.INF else (at - rb.global_position).limit_length(0.25)
	rb.apply_impulse(impulse * 5.0, off)
	(bodies.chest as RigidBody3D).apply_central_impulse(impulse * 4.0)
	(bodies.pelvis as RigidBody3D).apply_central_impulse(impulse * 2.5)


func pose() -> Array:
	## What a client needs to make this body: the part transforms, then who it was (for the outfit).
	var out := _xforms()
	out.append({"look": look, "eid": eid})
	return out


func _xforms() -> Array:
	var out := []
	for part in ORDER:
		out.append((bodies[part] if server else visuals[part]).global_transform)
	return out


func joint_gaps() -> Array:
	## How far apart each joint's two halves are (a few mm while it holds).
	var out := []
	for l in _links:
		out.append(((l[0] as Node3D).global_transform * (l[2] as Vector3)).distance_to((l[1] as Node3D).global_transform * (l[3] as Vector3)))
	return out


func _physics_process(dt: float) -> void:
	if not server or settled:
		return
	_age += dt
	_sync_t -= dt
	var vmax := 0.0
	var wmax := 0.0
	for part in ORDER:
		var rb: RigidBody3D = bodies[part]
		vmax = maxf(vmax, rb.linear_velocity.length())
		wmax = maxf(wmax, rb.angular_velocity.length())
	_guard(dt)
	# Once the body has slumped to a near stop it bleeds off what is left of its motion instead of creeping and
	# twitching (a body still sliding or folding keeps moving freely).
	if _age > 1.0 and vmax < 0.5:
		_still_t += dt
		var k := clampf(_still_t / 0.8, 0.0, 1.0)
		for part in ORDER:
			var rb: RigidBody3D = bodies[part]
			rb.linear_damp = lerpf(0.1, 2.5, k)
			rb.angular_damp = lerpf(0.8, 7.0, k)
	if vmax < 0.08 and wmax < 0.5:
		_rest_t += dt
	else:
		_rest_t = 0.0
	if _sync_t <= 0.0:
		_sync_t = 1.0 / float(Defs.rule("corpse_ragdoll_sync_hz", 12))
		world.corpse_pose(id, _xforms(), false)
	# At rest for a quarter second, or barely creeping after 4 s (still sliding or falling: keep simulating).
	if (_rest_t > 0.25 and _age > 0.7) or (_age > 4.0 and vmax < 0.5) or _age > 12.0 or get_tree() == null:
		settled = true
		_pose_tail = 0.4
		# Settled bodies stop simulating but keep their collision so bullets and loot rays still find them.
		for part in ORDER:
			var rb: RigidBody3D = bodies[part]
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.freeze = true
		world.corpse_pose(id, _xforms(), true)
		_bleed_out()


func _guard(dt: float) -> void:
	## A body that falls through the ground (a part tunnelling through a seam) is put back where it last lay whole.
	var pel: Vector3 = (bodies.pelvis as Node3D).global_position
	if world and world.map and pel.y < world.map.ground_height(pel.x, pel.z) - 1.0:
		rescues += 1
		push_warning("corpse %d fell through the ground at %s; restored" % [id, str(pel)])
		for i in ORDER.size():
			var rb: RigidBody3D = bodies[ORDER[i]]
			rb.global_transform = _last_good[i]
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
		return
	_good_t -= dt
	if _good_t <= 0.0:
		_good_t = 0.25
		_last_good = _xforms()


func _bleed_out() -> void:
	## Where the body comes to rest, blood pools under the chest and spreads (cosmetic; anyone drawing the world).
	var fx = world.effects if world else null
	if fx == null or fx.blood == null or _pooled:
		return
	_pooled = true
	var parts: Dictionary = bodies if server else visuals
	var ex := []
	for part in parts:
		ex.append((parts[part] as CollisionObject3D).get_rid())
	# Under the trunk, between hips and chest: where the blood runs to whether the body lies flat or sits slumped.
	var trunk: Vector3 = ((parts.pelvis as Node3D).global_position + (parts.chest as Node3D).global_position) * 0.5
	fx.blood.pool_under(trunk, randf_range(1.3, 1.8), randf_range(18.0, 26.0), ex)
	if parts.has("head"):
		fx.blood.pool_under((parts.head as Node3D).global_position, randf_range(0.45, 0.7), randf_range(14.0, 20.0), ex)


# ------------------------------------------------------------------ clients

func setup_client(w, cid: int, who: String, t: int, xforms: Array) -> void:
	# The pose stream is interpolated here every frame; engine interpolation on top would step.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world = w
	if world.effects:
		world.effects.body_fell(self)
	id = cid
	pname = who
	team = t
	name = "Corpse%d" % id
	if xforms.size() > ORDER.size() and xforms[ORDER.size()] is Dictionary:
		look = xforms[ORDER.size()].get("look", {})
		eid = int(xforms[ORDER.size()].get("eid", 0))
	_outfit_extra()
	if not xforms.is_empty() and xforms[0] is Transform3D:
		global_position = (xforms[0] as Transform3D).origin
	for i in ORDER.size():
		var part: String = ORDER[i]
		var sb := StaticBody3D.new()
		sb.name = part
		sb.collision_layer = Defs.PHYS_CORPSE
		sb.collision_mask = 0
		sb.set_meta("corpse_id", id)
		sb.set_meta("mat", "flesh")
		_add_shapes(sb, part)
		add_child(sb)
		visuals[part] = sb
		if i < xforms.size() and xforms[i] is Transform3D:
			sb.global_transform = xforms[i]
	if DisplayServer.get_name() != "headless":
		_build_body()


func client_pose(xforms: Array, final: bool) -> void:
	if _final_got:
		return   # the resting pose came on the reliable channel; anything after it is a stale stream packet
	_snaps.append([Time.get_ticks_msec() / 1000.0, xforms])
	if final:
		_final_got = true


func _process(dt: float) -> void:
	if server:
		if skel and (not settled or _pose_tail > 0.0):
			if settled:
				_pose_tail -= dt
			var px := {}
			for part in ORDER:
				px[part] = (bodies[part] as Node3D).get_global_transform_interpolated()
			_pose_skeleton(px)
		return
	if _snaps.is_empty():
		return
	# Play the stream back ~120 ms late, interpolating between received poses; stop on the resting pose.
	var now := Time.get_ticks_msec() / 1000.0 - 0.12
	if _final_got and now >= float(_snaps[-1][0]):
		_apply(_snaps[-1][1])
		_snaps.clear()
		settled = true
		_bleed_out()
		return
	var a: Array = _snaps[0]
	var b: Array = _snaps[0]
	for i in range(_snaps.size() - 1, -1, -1):
		if float(_snaps[i][0]) <= now:
			a = _snaps[i]
			b = _snaps[mini(i + 1, _snaps.size() - 1)]
			break
	var span := float(b[0]) - float(a[0])
	var f := 0.0 if span <= 0.0 else clampf((now - float(a[0])) / span, 0.0, 1.0)
	var out := []
	for i in mini(mini((a[1] as Array).size(), (b[1] as Array).size()), ORDER.size()):
		var ta: Transform3D = a[1][i]
		var tb: Transform3D = b[1][i]
		out.append(ta.interpolate_with(tb, f))
	_apply(out)
	while _snaps.size() > 2 and float(_snaps[1][0]) < now:
		_snaps.pop_front()


func _apply(xforms: Array) -> void:
	var px := {}
	for i in mini(xforms.size(), ORDER.size()):
		if not xforms[i] is Transform3D:
			continue
		(visuals[ORDER[i]] as Node3D).global_transform = xforms[i]
		px[ORDER[i]] = xforms[i]
	if skel and px.size() == ORDER.size():
		_pose_skeleton(px)


# ------------------------------------------------------------------ the body you see

func _build_body() -> void:
	## The character's own model, dressed in the outfit they wore (Outfit, as character_visual._dress), its clips
	## removed: the ragdoll poses its skeleton. Plain shapes on the parts if the model is missing.
	var R := rig()
	if not R.ok or _body_scene == null:
		_fallback_meshes()
		return
	var model: Node3D = _body_scene.instantiate()
	add_child(model)
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	skel = _find(model, "Skeleton3D")
	var ap := _find(model, "AnimationPlayer")
	if ap:
		ap.get_parent().remove_child(ap)
		ap.free()
	if skel == null or skel.get_bone_count() != (R.names as Array).size():
		model.queue_free()
		skel = null
		_fallback_meshes()
		return
	for c in skel.get_children():
		if c is BoneAttachment3D:
			skel.remove_child(c)
			c.free()
	var lk := look
	if lk.is_empty():
		lk = Outfit.random_look(eid * 7919 + 17)
	if Outfit.ensure():
		for c in skel.get_children():
			if c is MeshInstance3D:
				skel.remove_child(c)
				c.free()
		Outfit.dress(skel, lk, Defs.RENDER_CHARACTERS, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for c in skel.get_children():
		if c is MeshInstance3D:
			c.layers = Defs.RENDER_CHARACTERS
			# The skeleton moves the whole body away from the model's origin as it falls.
			c.extra_cull_margin = 2.5
	var px := {}
	for part in ORDER:
		px[part] = (bodies[part] if server else visuals[part]).global_transform
	_pose_skeleton(px)


func _pose_skeleton(px: Dictionary) -> void:
	## Every bone from the parts: a part's bone takes its frame, spine and neck sit half way between their two parts,
	## and hands, toes and the rest keep their rest pose under their parent.
	var R := rig()
	var inv := skel.global_transform.affine_inverse()
	var n: int = (R.names as Array).size()
	var g := []
	g.resize(n)
	for i in n:
		var d = R.drive[i]
		var p: int = R.parents[i]
		if d == null:
			g[i] = (g[p] as Transform3D) * R.local[i] if p >= 0 else R.local[i]
		elif int(d[0]) == 0:
			g[i] = inv * (px[d[1]] as Transform3D) * (d[2] as Transform3D)
		else:
			var a: Transform3D = inv * (px[d[1]] as Transform3D) * (d[2] as Transform3D)
			var b: Transform3D = inv * (px[d[3]] as Transform3D) * (d[4] as Transform3D)
			g[i] = a.interpolate_with(b, 0.5)
	for i in n:
		var p: int = R.parents[i]
		var l: Transform3D = g[i] if p < 0 else (g[p] as Transform3D).affine_inverse() * g[i]
		skel.set_bone_pose_position(i, l.origin)
		skel.set_bone_pose_rotation(i, l.basis.orthonormalized().get_rotation_quaternion())
		skel.set_bone_pose_scale(i, Vector3.ONE)


func _fallback_meshes() -> void:
	for part in ORDER:
		var body: Node3D = bodies[part] if server else visuals[part]
		body.add_child(_part_mesh(part))


func _part_mesh(part: String) -> MeshInstance3D:
	## Plain clothed segments (dark hoodie, jeans, skin at head and hands) when the body model is missing.
	var mi := MeshInstance3D.new()
	var spec: Array = PARTS[part]
	if spec[2] == "box":
		var bm := BoxMesh.new()
		bm.size = spec[4]
		mi.mesh = bm
	else:
		var sh := _shape(part) as CapsuleShape3D
		var cm := CapsuleMesh.new()
		cm.radius = sh.radius
		cm.height = sh.height
		mi.mesh = cm
	var m := StandardMaterial3D.new()
	if part in ["chest", "uarm_l", "uarm_r", "pelvis"]:
		m.albedo_color = Color(0.07, 0.07, 0.08)
	elif part.begins_with("uleg") or part.begins_with("lleg") or part.begins_with("foot"):
		m.albedo_color = Color(0.12, 0.14, 0.2)
	else:
		m.albedo_color = Color(0.4, 0.28, 0.22)
	m.roughness = 0.9
	mi.material_override = m
	mi.layers = Defs.RENDER_CHARACTERS
	return mi


func center() -> Vector3:
	if server:
		return (bodies.pelvis as Node3D).global_position
	return (visuals.pelvis as Node3D).global_position
