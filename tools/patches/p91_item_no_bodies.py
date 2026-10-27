"""Ground items without physics bodies: ~15,800 static bodies (every gun, box of rounds and battery on the map)
slowed every character move and every ray. The Use ray now finds items through the item grid with a ray-box test
in each item's own frame, the way containers are found."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

d = Patch('game/src/world/dynamics.gd')
d.rep('''	## Items on the ground have no scene nodes (thousands lie around the map): a static physics body the Use ray can
	## hit, and a render instance with a short draw distance.
	var it: Dictionary = items[id]
	var iid := str(it.entry.id)
	var md: Dictionary = map.item_visual(iid)
	var rest := item_rest(iid)
	var xf: Transform3D = it.xf
	var shape: RID = _item_shapes.get(iid, RID())
	if not shape.is_valid():
		shape = PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, ((rest.size as Vector3).max(Vector3(0.16, 0.06, 0.16))) * 0.5)
		_item_shapes[iid] = shape
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space_rid if space_rid.is_valid() else root.get_world_3d().space)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), Vector3(0, maxf((rest.size as Vector3).y, 0.06) * 0.5, 0)))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_collision_layer(body, Defs.PHYS_INTERACT)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	var ref := Ref.new()
	ref.set_meta("item_id", id)
	PhysicsServer3D.body_attach_object_instance_id(body, ref.get_instance_id())
	it.body = body
	it.ref = ref''', '''	## Items on the ground have no scene nodes and no physics bodies (thousands lie around the map): a pick box in
	## the item's own frame for the Use ray (item_hit) and a render instance with a short draw distance.
	var it: Dictionary = items[id]
	var iid := str(it.entry.id)
	var md: Dictionary = map.item_visual(iid)
	var rest := item_rest(iid)
	var xf: Transform3D = it.xf
	var sz: Vector3 = (rest.size as Vector3).max(Vector3(0.16, 0.06, 0.16))
	it.box = AABB(Vector3(-sz.x * 0.5, 0.0, -sz.z * 0.5), sz)''')
d.rep('''func items_near(p: Vector3, r: float) -> Array:''', '''func item_hit(from: Vector3, dir: Vector3, reach: float) -> Array:
	## The nearest item the ray from `from` along `dir` (normalised) passes through within reach: [id, distance],
	## or [-1, INF].
	var best := -1
	var bt := reach
	for id in items_near(from, reach + 0.6):
		var it: Dictionary = items[id]
		if not it.has("box"):
			continue
		var inv: Transform3D = (it.xf as Transform3D).affine_inverse()
		var hit = (it.box as AABB).grow(0.03).intersects_ray(inv * from, inv.basis * dir)
		if hit != null:
			var t := (inv * from).distance_to(hit)
			if t < bt:
				bt = t
				best = int(id)
	return [best, bt if best >= 0 else INF]


func items_near(p: Vector3, r: float) -> Array:''')
d.save()

i = Patch('game/src/match/interaction.gd')
i.rep('''	var r := space.intersect_ray(q)
	var hit_d := REACH
	if not r.is_empty():
		hit_d = eye.distance_to(r.position)''', '''	var r := space.intersect_ray(q)
	var hit_d := REACH
	if not r.is_empty():
		hit_d = eye.distance_to(r.position)
	# Items lying on the ground (no physics bodies): the nearest one along the ray, before anything else.
	var ih: Array = world.map.dyn.item_hit(eye, dir, minf(hit_d + 0.05, REACH))
	if int(ih[0]) >= 0:
		return {"kind": "item", "id": int(ih[0]), "pos": eye + dir * float(ih[1])}
	if not r.is_empty():''')
i.save()
