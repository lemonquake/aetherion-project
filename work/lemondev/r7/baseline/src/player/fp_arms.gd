extends Node3D
## First-person arms: a skinned human arm pair (assets/models/fp_arms, tools/blender/make_fp_arms.py) dressed like
## the player's outfit (skin tone, T-shirt / long sleeve / jacket sleeves, gloves) and posed every frame from one hand
## target per side.
##
## A hand target is where the palm touches (in this node's space) and the hand's orientation as a basis whose -Z
## runs along the fingers and whose +Y points out of the palm; the same basis means the same physical hand pose for
## either hand. Shoulder, elbow and wrist come from two-bone IK (the elbow bends toward a pole direction); the forearm
## takes half of the wrist's twist so the skin does not wrap. Fingers curl from 0 (open) to 1 (fist) per finger:
## [thumb, index, middle, ring, pinky].

const SCENE := "res://assets/models/fp_arms/fp_arms.glb"
const Outfit := preload("res://src/player/outfit.gd")
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]
## Bend of each finger joint at full curl (degrees): knuckle, middle, tip. Thumb: base, middle, tip.
const CURL_DEG := [[30.0, 35.0, 50.0], [80.0, 100.0, 65.0], [85.0, 100.0, 65.0], [85.0, 100.0, 65.0], [85.0, 100.0, 65.0]]
const GRIPS := {
	"open": [0.1, 0.08, 0.08, 0.1, 0.12],
	"relaxed": [0.25, 0.3, 0.35, 0.4, 0.45],
	"pistol": [0.6, 0.18, 0.85, 0.9, 0.92],
	"fist": [0.75, 0.9, 0.95, 0.95, 0.95],
	"fore": [0.35, 0.6, 0.66, 0.7, 0.74],
	"cup": [0.25, 0.5, 0.55, 0.6, 0.65],
	"mag": [0.55, 0.55, 0.62, 0.7, 0.75],
	"pinch": [0.75, 0.7, 0.85, 0.9, 0.92],
	"shell": [0.7, 0.62, 0.55, 0.75, 0.85],
	"tablet": [0.12, 0.03, 0.03, 0.04, 0.05],
	"torch": [0.6, 0.8, 0.85, 0.88, 0.9],
}

var root: Node3D
var skel: Skeleton3D
var pieces := {}           # piece name -> MeshInstance3D
var sides := {}            # "R" / "L" -> rig data (see _rig_side)
var _to_skel := Transform3D()
var _look_key := ""
var ok := false
var shoulder := {"R": Vector3.ZERO, "L": Vector3.ZERO}   # stance offset of each shoulder joint (parent space)


func setup(layer: int) -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ps: PackedScene = load(SCENE)
	root = ps.instantiate()
	add_child(root)
	skel = _find_skel(root)
	if skel == null:
		return
	for c in _all_meshes(root):
		pieces[str(c.name)] = c
		c.layers = layer
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The arms are posed far from the bind pose; the imported bounds would cull them at the screen edge.
		c.extra_cull_margin = 2.0
	skel.reset_bone_poses()
	var xf := Transform3D()
	var n: Node = skel
	while n != self and n != null:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	_to_skel = xf.affine_inverse()
	for s in ["R", "L"]:
		var d := _rig_side(s)
		if d.is_empty():
			return
		sides[s] = d
	ok = true


static func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null


static func _all_meshes(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out


func _bone(contains: String, not_contains: String = "") -> int:
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		if nm.contains(contains) and (not_contains == "" or not nm.contains(not_contains)):
			return i
	return -1


func _rig_side(s: String) -> Dictionary:
	var side := "Right" if s == "R" else "Left"
	var d := {}
	d.upper = _bone(side + "Arm_", "Fore")
	d.fore = _bone(side + "ForeArm")
	d.hand = _bone(side + "Hand_")
	if d.upper < 0 or d.fore < 0 or d.hand < 0:
		push_warning("fp_arms: %s arm bones not found" % side)
		return {}
	var fingers := []
	for f in FINGERS:
		var chain := []
		for j in [1, 2, 3, 4]:
			chain.append(_bone(side + "Hand" + f + str(j)))
		fingers.append(chain)
	d.fingers = fingers
	var g := func(b: int) -> Transform3D: return skel.get_bone_global_rest(b)
	var S0: Vector3 = g.call(d.upper).origin
	var E0: Vector3 = g.call(d.fore).origin
	var W0: Vector3 = g.call(d.hand).origin
	d.l1 = S0.distance_to(E0)
	d.l2 = E0.distance_to(W0)
	d.e0 = E0 - S0
	d.w0 = W0 - E0
	d.n0 = (E0 - S0).cross(W0 - E0).normalized()
	d.ru0 = (g.call(d.upper) as Transform3D).basis.orthonormalized()
	d.rf0 = (g.call(d.fore) as Transform3D).basis.orthonormalized()
	d.rh0 = (g.call(d.hand) as Transform3D).basis.orthonormalized()
	# Canonical hand frame at rest: -Z along the fingers, +Y out of the palm.
	var mid: Vector3 = g.call(fingers[2][0]).origin
	var idx: Vector3 = g.call(fingers[1][0]).origin
	var pky: Vector3 = g.call(fingers[4][0]).origin
	var f := (mid - W0).normalized()
	var a := (idx - pky) if s == "R" else (pky - idx)
	var z := -f
	var x := (a - z * a.dot(z)).normalized()
	var y := z.cross(x).normalized()
	x = y.cross(z).normalized()
	var F0 := Basis(x, y, z)
	d.f0 = F0
	d.hand_map = F0.inverse() * d.rh0          # hand bone basis = target basis * hand_map
	# Palm contact point (centre of the palm surface) relative to the wrist, in the canonical frame.
	d.palm = F0.inverse() * ((W0 + mid) * 0.5 - W0 + y * 0.016)
	# Finger curl axes in each bone's own rest frame: rotating about them bends the finger toward the palm.
	var axes := []
	for fi in fingers.size():
		var chain: Array = fingers[fi]
		var ax := []
		for j in 3:
			var b: int = chain[j]
			var nb: int = chain[j + 1]
			if b < 0 or nb < 0:
				ax.append(Vector3.ZERO)
				continue
			var dir: Vector3 = (g.call(nb).origin - g.call(b).origin).normalized()
			var axis := dir.cross(y).normalized()
			if fi == 0:
				# The thumb folds across the palm toward the little finger.
				axis = dir.cross(y + x * 0.6 * (1.0 if s == "R" else 1.0)).normalized()
			ax.append((g.call(b) as Transform3D).basis.orthonormalized().inverse() * axis)
		axes.append(ax)
	d.axes = axes
	d.curl = [0.3, 0.3, 0.3, 0.3, 0.3]
	return d


# ------------------------------------------------------------------ dressing

func dress(look: Dictionary) -> void:
	## Sleeves, gloves and skin tone for an outfit look (same rules as the third-person body).
	if not ok:
		return
	look = Outfit.normalized(look)
	var key := Outfit.key(look)
	if key == _look_key:
		return
	_look_key = key
	var jacket := str(look.get("jacket", "none"))
	var shirt := str(look.get("shirt", "none"))
	var gloves := str(look.get("gloves", "none"))
	var sleeve := ""
	var cloth := Color(0.2, 0.2, 0.22)
	if jacket != "none":
		sleeve = "sleeve_jacket"
		cloth = _colour("jacket", jacket, int(look.get("jacket_c", 0)))
	elif shirt == "longsleeve":
		sleeve = "sleeve_long"
		cloth = _colour("shirt", shirt, int(look.get("shirt_c", 0)))
	elif shirt in ["tee", "jersey", "polo"]:
		sleeve = "sleeve_short"
		cloth = _colour("shirt", shirt, int(look.get("shirt_c", 0)))
	var glove := ""
	var glove_c := Color(0.1, 0.1, 0.1)
	if gloves == "fingerless":
		glove = "glove_fingerless"
	elif gloves != "none":
		glove = "glove"
	if glove != "":
		glove_c = _colour("gloves", gloves, int(look.get("gloves_c", 0)))
	var long := sleeve in ["sleeve_long", "sleeve_jacket"]
	_show("skin_upper", sleeve == "")
	_show("skin_arm", not long)
	_show("skin_hand", glove != "glove")
	for p in ["sleeve_short", "sleeve_long", "sleeve_jacket"]:
		_show(p, p == sleeve)
	for p in ["glove", "glove_fingerless"]:
		_show(p, p == glove)
	var tone := Outfit.tone(look)
	for p in ["skin_upper", "skin_arm", "skin_hand"]:
		var mi: MeshInstance3D = pieces.get(p)
		if mi and mi.mesh:
			var m = mi.mesh.surface_get_material(0)
			if m is StandardMaterial3D:
				var mm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				mm.albedo_color = tone
				mi.material_override = mm
	if sleeve != "":
		(pieces[sleeve] as MeshInstance3D).material_override = _cloth_mat(cloth, jacket == "puffer" or jacket == "bomber")
	if glove != "":
		(pieces[glove] as MeshInstance3D).material_override = _glove_mat(glove_c, gloves)


func _show(p: String, on: bool) -> void:
	var mi: MeshInstance3D = pieces.get(p)
	if mi:
		mi.visible = on


static func _colour(slot: String, id: String, ci: int) -> Color:
	var cols: Array = Outfit.item(slot, id).get("colors", [])
	if cols.is_empty():
		return Color(0.3, 0.3, 0.3)
	# White means "the texture's own colours" on the body; the plain cloth here takes a neutral grey-beige.
	var c := Color.html(str(cols[clampi(ci, 0, cols.size() - 1)]))
	if c.is_equal_approx(Color.WHITE):
		c = Color(0.62, 0.6, 0.55)
	return c


static func _cloth_mat(c: Color, shiny: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/models/fp_arms/fabric.png")
	m.albedo_color = c
	m.normal_enabled = true
	m.normal_texture = load("res://assets/models/fp_arms/fabric_n.png")
	m.normal_scale = 0.6
	m.roughness = 0.6 if shiny else 0.93
	m.uv1_scale = Vector3(6, 6, 6)
	return m


static func _glove_mat(c: Color, kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var cloth := kind == "wraps"
	m.albedo_texture = load("res://assets/models/fp_arms/fabric.png" if cloth else "res://assets/models/fp_arms/leather.png")
	m.albedo_color = c
	m.normal_enabled = true
	m.normal_texture = load("res://assets/models/fp_arms/fabric_n.png" if cloth else "res://assets/models/fp_arms/leather_n.png")
	m.roughness = 0.9 if cloth else 0.55
	m.uv1_scale = Vector3(5, 5, 5)
	return m


# ------------------------------------------------------------------ posing

static func hand_basis(fingers: Vector3, palm: Vector3) -> Basis:
	## A hand orientation from where the fingers point and where the palm faces (any space).
	var z := -fingers.normalized()
	var y := (palm - z * palm.dot(z)).normalized()
	return Basis(y.cross(z), y, z)


func show_side(s: String, on: bool) -> void:
	## Hides an arm (no target this frame): its meshes stay, the arm is folded down out of view.
	if not ok:
		return
	var d: Dictionary = sides[s]
	if not on:
		pose(s, Vector3(0.35 if s == "R" else -0.35, -0.9, 0.1), hand_basis(Vector3.DOWN, Vector3.LEFT if s == "R" else Vector3.RIGHT), Vector3.DOWN, GRIPS.relaxed)
	d.hidden = not on


func pose(s: String, palm_at: Vector3, b: Basis, pole: Vector3, curl: Array) -> void:
	## Puts side s's palm at palm_at with orientation b (this node's space); the elbow bends toward pole.
	if not ok:
		return
	var d: Dictionary = sides[s]
	# Targets arrive in the parent's space (the viewmodel); this node may sit offset in it.
	var into := _to_skel * transform.affine_inverse()
	var B := into.basis.orthonormalized() * b
	var P := into * palm_at
	var pole_s := (into.basis * pole).normalized()
	var Hd: Basis = (B * d.hand_map).orthonormalized()
	var W: Vector3 = P - B * (d.palm as Vector3)
	# Shoulder joint where the (unposed) clavicle holds it, moved by the stance (a shouldered rifle turns the torso
	# and brings the left shoulder forward).
	# The collarbone carries the move, so the shoulder's own skin goes with it instead of stretching.
	var up_parent := skel.get_bone_parent(d.upper)
	var sh: Vector3 = shoulder.get(s, Vector3.ZERO)
	if up_parent >= 0:
		var cp := skel.get_bone_parent(up_parent)
		var cg := skel.get_bone_global_pose(cp) if cp >= 0 else Transform3D()
		skel.set_bone_pose_position(up_parent, skel.get_bone_rest(up_parent).origin + cg.basis.inverse() * (into.basis * sh))
	var pg := skel.get_bone_global_pose(up_parent) if up_parent >= 0 else Transform3D()
	var S: Vector3 = pg * skel.get_bone_pose_position(d.upper)
	var l1: float = d.l1
	var l2: float = d.l2
	var to := W - S
	var dist := clampf(to.length(), 0.05, l1 + l2 - 0.002)
	var dir := to.normalized()
	W = S + dir * dist
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var bend := pole_s - dir * pole_s.dot(dir)
	if bend.length_squared() < 1e-6:
		bend = Vector3.DOWN - dir * dir.y
	bend = bend.normalized()
	var E := S + dir * (l1 * ca) + bend * (l1 * sqrt(1.0 - ca * ca))
	var n1 := (E - S).cross(W - E).normalized()
	var Ru := _align(d.ru0, d.e0, E - S, d.n0, n1)
	var Rf := _align(d.rf0, d.w0, W - E, d.n0, n1)
	# Half the wrist's twist about the forearm goes into the forearm.
	var fa := (W - E).normalized()
	var tw := _twist_angle(Rf * (d.rf0 as Basis).inverse() * (d.rh0 as Basis), Hd, fa)
	Rf = Basis(fa, tw * 0.5) * Rf
	skel.set_bone_pose_rotation(d.upper, (pg.basis.orthonormalized().inverse() * Ru).get_rotation_quaternion())
	skel.set_bone_pose_rotation(d.fore, (Ru.inverse() * Rf).get_rotation_quaternion())
	skel.set_bone_pose_rotation(d.hand, (Rf.inverse() * Hd).get_rotation_quaternion())
	_curl(d, curl)
	d.want = [_to_skel * transform.affine_inverse() * palm_at, B]


func pose_error(s: String) -> Vector2:
	## (metres, degrees) between the last requested palm and where the posed skeleton put it (for tests).
	var d: Dictionary = sides[s]
	if not d.has("want"):
		return Vector2.ZERO
	var hg := skel.get_bone_global_pose(d.hand)
	var got_b: Basis = hg.basis.orthonormalized() * (d.hand_map as Basis).inverse()
	var got_p: Vector3 = hg.origin + got_b * (d.palm as Vector3)
	var want_b: Basis = d.want[1]
	var q := (got_b * want_b.inverse()).get_rotation_quaternion()
	return Vector2(got_p.distance_to(d.want[0]), rad_to_deg(q.get_angle()))


static func _align(r0: Basis, v0: Vector3, v1: Vector3, n0: Vector3, n1: Vector3) -> Basis:
	## Rest basis r0 turned so its segment v0 lies along v1 and its bend normal n0 matches n1.
	var a := v0.normalized()
	var b := v1.normalized()
	var q := Quaternion(a, b) if a.dot(b) > -0.9999 else Quaternion(a.cross(Vector3.UP).normalized(), PI)
	var r := Basis(q) * r0
	var m := Basis(q) * n0
	m = (m - b * m.dot(b)).normalized()
	var t := (n1 - b * n1.dot(b)).normalized()
	var ang := atan2(b.dot(m.cross(t)), m.dot(t))
	return (Basis(b, ang) * r).orthonormalized()


static func _twist_angle(from: Basis, to: Basis, axis: Vector3) -> float:
	## Rotation about axis that takes from's frame toward to's (the twist part of the difference).
	var dq := (to * from.inverse()).get_rotation_quaternion()
	var v := Vector3(dq.x, dq.y, dq.z)
	var p := axis * v.dot(axis)
	var tq := Quaternion(p.x, p.y, p.z, dq.w).normalized()
	var ang := 2.0 * acos(clampf(tq.w, -1.0, 1.0))
	if Vector3(tq.x, tq.y, tq.z).dot(axis) < 0.0:
		ang = -ang
	return wrapf(ang, -PI, PI)


func _curl(d: Dictionary, curl: Array) -> void:
	var fingers: Array = d.fingers
	var axes: Array = d.axes
	for fi in fingers.size():
		var c := clampf(float(curl[fi]) if fi < curl.size() else 0.3, -0.2, 1.1)
		for j in 3:
			var b: int = fingers[fi][j]
			var ax: Vector3 = axes[fi][j]
			if b < 0 or ax == Vector3.ZERO:
				continue
			var rest := skel.get_bone_rest(b).basis.get_rotation_quaternion()
			skel.set_bone_pose_rotation(b, rest * Quaternion(ax, deg_to_rad(float(CURL_DEG[fi][j]) * c)))


static func grip(name: String) -> Array:
	return GRIPS.get(name, GRIPS.relaxed)


static func mix_curl(a: Array, b: Array, t: float) -> Array:
	var out := []
	for i in 5:
		out.append(lerpf(float(a[i]), float(b[i]), t))
	return out
