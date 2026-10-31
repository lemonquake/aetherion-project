extends RefCounted
## Authored outbreak scenes. All cover has matching collision/navigation; small
## litter stays cosmetic. The two lift cabins are open rooms, never fake doors.

var B
var L
var S
var mb
var rng := RandomNumberGenerator.new()
var stats := {"open_lifts": 0, "cover_spots": 0, "breaches": 0, "debris": 0}


func _init(builder) -> void:
	B = builder
	L = B.L
	S = B.S
	mb = B.mb
	rng.seed = 191031


func box(c: Vector3, size: Vector3, mat: String, solid: bool = false, lv: int = 0, rot: Vector3 = Vector3.ZERO) -> void:
	var opt: Dictionary = B.o({"layer": "mid", "collide": solid, "dirt": .7})
	S.box(Transform3D(Basis.from_euler(rot), c), size, mat, opt)
	if solid:
		L.block_rect(lv, Vector2(c.x,c.z), Vector2(size.x,size.z)*.5, -rot.y, .2)


func label_at(text: String, p: Vector3, size: int = 80, color: Color = Color(.76,.8,.73)) -> void:
	if not S.visual:
		return
	var label := Label3D.new()
	label.text = text
	label.position = p
	label.font_size = size
	label.pixel_size = .003
	label.modulate = color
	label.outline_size = 2
	label.outline_modulate = Color(.025,.035,.035)
	label.no_depth_test = false
	label.shaded = true
	label.visibility_range_end = 40.0
	mb.root.add_child(label)


func lifts(unit: Dictionary) -> void:
	var lv := int(unit.level)
	if lv > 0:
		_upper_lobby(lv)
		return
	# North band, Level 1: 13m-wide former unit becomes a damaged lift lobby.
	# Its entrance is an 8m breach. No invisible shopfront or old tenant survives.
	for x in [6.1,18.9]:
		box(Vector3(x,2.1,-40.25),Vector3(.2,4.2,10.5),"mall_paint",true)
	var thresholds: Array = [Rect2(7.25,-40.25,3.5,.4),Rect2(14.25,-40.25,3.5,.4)]
	for piece in B.minus_holes(Rect2(6.2,-45.4,12.6,10.4),thresholds):
		B.hquad(piece,.012,"mall_grey",true,{"collide":true,"layer":"ext"})
	# The suspended ceiling has a real inspection opening, backed by a dark
	# structural soffit. The next tenant's furniture cannot show through it.
	var openings: Array = L.lift_holes() + [Rect2(11,-40,3,3)]
	for panel in B.minus_holes(Rect2(6.2,-45.4,12.6,10.4),openings):
		B.hquad(panel,4.2,"mall_ceiling",false,{"layer":"ext"})
	for soffit in B.minus_holes(Rect2(6.2,-45.4,12.6,10.4),L.lift_holes()):
		B.hquad(soffit,4.65,"concrete",false,{"layer":"ext","tint":Color(.12,.14,.14),"paint":1.0})
	for x in [7.2,17.8]:
		box(Vector3(x,1.45,-35.0),Vector3(2.2,2.9,.32),"concrete_cracked",true)
		for j in 6:
			box(Vector3(x + rng.randf_range(-.8,.8),3.0+rng.randf_range(-.3,.45),-35.02),
				Vector3(.45,.4,.4),"concrete_rebar",false,0,Vector3(0,0,rng.randf_range(-.5,.5)))
	box(Vector3(12.5,3.98,-35.02),Vector3(12.8,.45,.45),"concrete_cracked",true)
	label_at("Elevators  /  Level 1",Vector3(12.5,3.98,-34.76),90)
	B.wall_decal(Vector3(7.2,1.8,-34.81),Vector3.BACK,Vector2(1.7,1.1),"quarantine")
	B.wall_decal(Vector3(17.7,1.5,-34.8),Vector3.BACK,Vector2(1.8,.8),"bloodtext_1")
	for i in 2:
		_cabin(9.0+i*7.0,i)
		_shaft(9.0+i*7.0)
	# Buckled waiting bench, abandoned luggage, overturned trolley, damaged ceiling.
	box(Vector3(6.8,.58,-37.8),Vector3(.55,.16,2.0),"oak",true)
	for z in [-38.5,-37.1]:
		box(Vector3(6.8,.28,z),Vector3(.38,.5,.06),"mall_steel")
	box(Vector3(17.7,.28,-38.0),Vector3(.65,.56,.45),"leather",true,0,Vector3(.15,.3,-.2))
	B.MallWreck.new(B).cart(0,Vector3(14.2,.1,-37.0),.7,true)
	B.floor_decal(Vector3(13,0,-37.5),Vector2(3.0,4.6),.18,"blood_drag_0")
	B.floor_decal(Vector3(9,0,-35.7),Vector2(2.8,4.0),PI,"blood_steps")
	B.hquad(Rect2(6.5,-36.8,1.3,2.0),.02,"rubble",true,{"collide":true,"layer":"mid"})
	_rubble(Vector3(8.4,.05,-34.2),0,30)
	_rubble(Vector3(17.0,.05,-35.3),0,22)
	for j in 6:
		var x := 8.0 + j*1.7
		_wire(Vector3(x,4.15,-38.7),Vector3(x+.28,2.5+rng.randf(),-38.4),"mall_black")
		box(Vector3(x,3.9,-38.8),Vector3(1.1,.03,.6),"mall_ceiling",false,0,Vector3(.24,.1,.3))
	mb.dyn.add_light({"pos":Vector3(12.5,3.6,-36.8),"kind":"down","angle":64.0,
		"color":Color(.56,.79,.74),"energy":2.2,"range":7.0,"fade":40.0,"emitter":true,"fault":"starter"})
	mb.stats["horror_lifts"] = 2
	stats.breaches += 1


func _cabin(x: float, index: int) -> void:
	# Back is north (-z); opening looks south (+z), wide enough for movement.
	for side in [-1,1]:
		box(Vector3(x+side*1.64,1.77,-42.5),Vector3(.18,3.54,3.9),"mall_steel",true)
		# The door leaves are jammed aside in the opening, with visible guide grooves.
		box(Vector3(x+side*1.22,1.5,-40.55),Vector3(.63,3.0,.13),"mall_steel",true)
		box(Vector3(x+side*1.76,1.7,-40.46),Vector3(.18,3.4,.24),"mall_chrome",true)
		box(Vector3(x+side*1.49,1.05,-42.5),Vector3(.05,.05,3.1),"oak")
	box(Vector3(x,1.77,-44.46),Vector3(3.45,3.54,.15),"mall_steel",true)
	box(Vector3(x,3.36,-40.5),Vector3(3.7,.32,.26),"mall_metal_vc",true)
	# The cabin floor is level with the lobby. The threshold has metal collision.
	B.hquad(Rect2(x-1.55,-44.35,3.1,3.9),.035,"mall_tread",true,{"collide":true,"layer":"ext"})
	box(Vector3(x,.025,-40.49),Vector3(2.0,.05,.44),"mall_tread",false)
	S.col_box(Transform3D(Basis(),Vector3(x,-.025,-40.49)),Vector3(2,.1,.44),"steel","elevator_threshold")
	# The cabin roof has torn away: retain its frame and a folded panel, leaving
	# a clear opening into the full-height hoistway above the player's head.
	for side in [-1,1]:
		box(Vector3(x+side*1.37,3.57,-42.5),Vector3(.28,.09,3.8),"mall_steel")
	for z in [-44.15,-40.8]:
		box(Vector3(x,3.57,z),Vector3(2.8,.09,.25),"mall_steel")
	box(Vector3(x-1.1,3.86,-43.5),Vector3(.65,.045,1.45),"mall_ceiling",false,0,Vector3(.25,0,-.65))
	var col := Color(.79,.9,1.0)
	mb.dyn.add_light({"pos":Vector3(x,3.22,-42.1),"kind":"tube","axis":Vector3.RIGHT,
		"color":col,"energy":3.5,"range":7.0,"fade":42.0,
		"emitter":true,"fault":"starter"})
	label_at("Lift A" if index == 0 else "Lift B",Vector3(x,3.38,-40.30),90,Color(.8,.86,.86))
	label_at("01  —",Vector3(x+1.83,2.55,-40.28),60,Color(.75,.25,.12))
	# Buttons, speaker grille and a smashed inspection cover, placed on the back wall.
	box(Vector3(x+1.15,1.48,-44.34),Vector3(.32,1.16,.035),"mall_black")
	for b in 8:
		S.cylinder(Vector3(x+1.08+(b%2)*.13,1.08+(b/2)*.18,-44.30),Vector3.BACK,.012,.035,"mall_chrome",B.o({"sides":8,"layer":"int"}))
	for j in 5:
		box(Vector3(x+1.15,1.9+j*.045,-44.30),Vector3(.18,.012,.01),"mall_steel")
	B.wall_decal(Vector3(x-.55,1.6,-44.35),Vector3.BACK,Vector2(2.5,2.4),"blood_spatter")
	B.wall_decal(Vector3(x+.15,1.2,-44.33),Vector3.BACK,Vector2(.7,.9),"blood_hands_0")
	B.wall_decal(Vector3(x-1.53,1.3,-42.8),Vector3.RIGHT,Vector2(.85,1.2),"blood_hands_1")
	B.floor_decal(Vector3(x,.04,-43),Vector2(2.9,2.8),index*.9,"blood_pool_drag")
	B.floor_decal(Vector3(x,.04,-41),Vector2(2.2,3.6),PI,"blood_drag_1")
	B.floor_decal(Vector3(x,.042,-42.3),Vector2(2.5,2.5),.7,"floor_papers_0")
	# Crumpled stretcher and torn upholstery; the remaining half of each cabin is clear.
	box(Vector3(x-.7,.34,-43.1),Vector3(.65,.18,1.65),"mall_cloth",true,0,Vector3(.16,.2,.1))
	for z in [-43.65,-42.55]:
		box(Vector3(x-.7,.14,z),Vector3(.62,.26,.035),"mall_steel")
	box(Vector3(x+.65,.12,-43.9),Vector3(.7,.12,.6),"mall_ceiling",false,0,Vector3(.1,.4,.2))
	_rubble(Vector3(x,.055,-42.5),0,16)
	stats.open_lifts += 1


func _shaft(x: float) -> void:
	# Continuous 28m hoistway, genuinely absent from every intervening slab.
	# Cabin walls end at 3.5m; structural walls, rails and ropes continue upward.
	for side in [-1,1]:
		box(Vector3(x+side*1.94,14,-42.6),Vector3(.2,28,5.0),"concrete",true)
	box(Vector3(x,14,-45.05),Vector3(4.0,28,.2),"concrete",true)
	box(Vector3(x,27.9,-42.6),Vector3(4.1,.2,5.1),"concrete",true)
	for lv in L.LEVELS:
		for side in [-1,1]:
			L.block_rect(lv,Vector2(x+side*1.94,-42.6),Vector2(.1,2.5),0,.25)
		L.block_rect(lv,Vector2(x,-45.05),Vector2(2,.1),0,.25)
	# T-section guide rails, rail brackets at each landing, and suspension ropes.
	for side in [-1,1]:
		box(Vector3(x+side*1.77,15,-43.3),Vector3(.08,25,.14),"mall_steel")
		box(Vector3(x+side*1.79,15,-43.3),Vector3(.18,25,.04),"mall_chrome")
		for lv in range(1,6):
			box(Vector3(x+side*1.8,lv*5.0,-43.3),Vector3(.25,.13,.5),"mall_metal_vc")
	for dx in [-.48,-.24,0.0,.24,.48]:
		S.cylinder(Vector3(x+dx,3.75,-42.85),Vector3.UP,23.0,.018,"mall_steel",B.o({"sides":6,"layer":"mid"}))
	# Car crosshead, drive sheave, motor and counterweight are visible overhead.
	box(Vector3(x,3.85,-42.8),Vector3(2.5,.18,.35),"mall_metal_vc")
	S.cylinder(Vector3(x-.35,26.5,-42.85),Vector3.RIGHT,.7,.55,"mall_steel",B.o({"sides":20,"layer":"mid"}))
	box(Vector3(x,26.45,-43.65),Vector3(1.3,.7,.75),"mall_metal_vc")
	box(Vector3(x+.75,15.0,-44.83),Vector3(.95,2.3,.17),"mall_steel")
	for j in 8:
		box(Vector3(x+.75,14.05+j*.25,-44.71),Vector3(.9,.05,.05),"mall_black")
	# Real maintenance fittings reveal the shaft structure; no fake haze beams.
	for y in [8.5,18.5,26.9]:
		mb.dyn.add_light({"pos":Vector3(x,y,-44.65),"kind":"lamp","color":Color(.79,.9,1),
			"energy":1.0,"range":7.0,"fade":44.0,"emitter":true,"fault":""})
	mb.stats["lift_shaft_height"] = 28.0


func _upper_lobby(lv: int) -> void:
	var y: float = L.level_y(lv)
	var room := Rect2(6.2,-45.4,12.6,10.4)
	var holes: Array = L.lift_holes()
	for x in [6.1,18.9]:
		box(Vector3(x,y+2.1,-40.25),Vector3(.2,4.2,10.5),"mall_paint",true,lv)
	# Actual walking slabs and their undersides stop at both shaft openings.
	for floor_piece in B.minus_holes(room,holes):
		B.hquad(floor_piece,y,"mall_grey",true,{"collide":true,"layer":"ext"})
		B.hquad(floor_piece,y-.25,"concrete",false,{"layer":"ext"})
	for ceil_piece in B.minus_holes(room,holes):
		B.hquad(ceil_piece,y+4.2,"mall_ceiling",false,{"layer":"ext"})
		B.hquad(ceil_piece,y+4.65,"concrete",false,{"layer":"ext"})
	for x in L.LIFT_CENTRES:
		# Shaft front panels with real landing openings, not a wall behind a door.
		for side in [-1,1]:
			box(Vector3(x+side*1.48,y+1.65,-40.18),Vector3(.85,3.3,.2),"mall_metal_vc",true,lv)
		box(Vector3(x,y+3.75,-40.18),Vector3(3.85,.9,.2),"concrete",true,lv)
		box(Vector3(x,y-.35,-40.18),Vector3(3.85,.7,.2),"concrete",true,lv)
		box(Vector3(x,y+.025,-40.08),Vector3(2.0,.05,.45),"mall_tread")
		var open: bool = lv == 2 and x == 9.0
		if open:
			# Damaged L3 landing: an open view down the shaft, protected by a rail.
			box(Vector3(x-1.0,y+1.55,-40.05),Vector3(.5,3.1,.12),"mall_steel",true,lv)
			box(Vector3(x,y+1.05,-40.0),Vector3(2.2,.08,.08),"mall_steel",true,lv)
			for side in [-1,1]:
				box(Vector3(x+side*.95,y+.52,-40.0),Vector3(.07,1.04,.08),"mall_steel",true,lv)
		else:
			for side in [-1,1]:
				box(Vector3(x+side*.51,y+1.55,-40.05),Vector3(1.0,3.1,.12),"mall_steel",true,lv)
		label_at("Lift A" if x==9.0 else "Lift B",Vector3(x,y+3.6,-39.98),70)
		label_at("%02d"%(lv+1),Vector3(x+1.35,y+2.0,-39.98),60)
	label_at("Elevators  /  Level %d"%(lv+1),Vector3(12.5,y+3.85,-35.0),80)
	mb.dyn.add_light({"pos":Vector3(12.5,y+3.7,-37.7),"kind":"down","angle":68.0,"color":Color(.79,.9,1),
		"energy":3.0,"range":8.0,"fade":38.0,"emitter":true,"fault":"starter"})
	B.floor_decal(Vector3(12.5,y,-38),Vector2(3,3),.2,"floor_papers_1")


func build() -> void:
	stats.open_lifts = int(mb.stats.get("horror_lifts",0))
	stats.breaches = 1
	# Distinct playable gallery positions, two exits around each cover cluster.
	for spec in [[2,Vector2(18,24),-.25],[4,Vector2(-18,-24),.25],
		[1,Vector2(-56,20),.0],[3,Vector2(35,-27),.4]]:
		var lv := int(spec[0])
		var p := Vector3(spec[1].x,L.level_y(lv),spec[1].y)
		_cover(p,lv,float(spec[2]))
	# A battered service partition creates a crouch hiding recess off the north walk.
	for lv in [1,3]:
		var y: float = L.level_y(lv)
		for x in [-33.7,-32.5]:
			box(Vector3(x,y+1.1,25.8),Vector3(.18,2.2,2.8),"mall_metal_vc",true,lv)
		box(Vector3(-33.1,y+1.1,27.1),Vector3(1.4,2.2,.15),"mall_metal_vc",true,lv)
		B.wall_decal(Vector3(-33.1,y+1.45,27.19),Vector3.BACK,Vector2(1.1,.65),"notice_missing")
		stats.cover_spots += 1
	# Chipped column bases, rusted utility runs, grime/blood trails on every floor.
	for lv in L.LEVELS:
		var y: float = L.level_y(lv)
		for x in [-21.0,21.0]:
			for z in [-28.0,28.0]:
				B.floor_decal(Vector3(x,y,z),Vector2(4.1,5.8),rng.randf()*TAU,"floor_grime_1",.85)
				B.floor_decal(Vector3(x+.8,y,z-1),Vector2(1.7,3.6),rng.randf()*TAU,"blood_steps",.8)
				_rubble(Vector3(x,y+.025,z),lv,10)
		for z in [-32.0,32.0]:
			_wire(Vector3(-39,y+3.95,z),Vector3(-23,y+3.95,z),"mall_steel")
			_wire(Vector3(-29,y+3.95,z),Vector3(-28,y+2.5,z+.3),"mall_black")
		# Dead neon over a repair point, small red emergency pool, physically located.
		mb.dyn.add_light({"pos":Vector3(33,y+2.65,31.7),"kind":"lamp","color":Color(1,.08,.025),
			"energy":.8,"range":5.5,"fade":32.0,"emitter":true,"fault":"dying"})
	mb.stats["horror_cover"] = stats.cover_spots
	_wall_scenes()
	for lv in L.LEVELS:
		_floor_design(lv)
	_lobby_finishes()


func _floor_design(lv: int) -> void:
	var y: float = L.level_y(lv)
	# These pieces fill real cutouts in MallBuilder's field. They never sit on
	# another visible floor and share the field's visibility distance.
	for inlay in L.floor_inlays():
		B.hquad(inlay[0],y,inlay[1],true,{"collide":true,"layer":"ext"})
	for repair in L.floor_repairs(lv):
		B.hquad(repair,y,"mall_repair",true,{"collide":true,"layer":"ext","dirt":.3})


func _wall_scenes() -> void:
	# Irregular, individually generated missing plaster and repair shapes. Their
	# placement follows the room, with intact wall between damage patches.
	for room in B.rooms:
		if str(room.kind)=="restroom":
			continue
		var xf: Transform3D = room.xf
		var w := float(room.w)
		var d := float(room.d)
		var y: float = L.level_y(int(room.lv))
		var count := 2 if w>25 else 1
		for j in count:
			var cx := w*(.2+.6*rng.randf())
			var cy := y+rng.randf_range(1.8,2.8)
			var centre := xf*Vector3(cx,cy,d-.16)
			var right := xf.basis.x
			var normal := -xf.basis.z
			var half_w := minf(w*.15,rng.randf_range(.65,1.65))
			var half_h := rng.randf_range(.4,.9)
			var ps: Array[Vector3] = []
			for k in 10:
				var a := TAU*k/10.0
				var r := rng.randf_range(.66,1.0)
				ps.append(centre+right*cos(a)*half_w*r+Vector3.UP*sin(a)*half_h*r)
			var skin := "mall_wall_brick" if rng.randf()<.48 else "mall_repair"
			for k in ps.size():
				S.quad(centre,ps[k],ps[(k+1)%ps.size()],ps[(k+1)%ps.size()],skin,B.o({"facing":normal,"layer":"int","tile":1.4,"dirt":.6}))
			if rng.randf()<.5:
				B.wall_decal(centre+normal*.008+Vector3.UP*.3,normal,Vector2(half_w*2.3,half_h*2.6),"wall_soot",.22)


func _lobby_finishes() -> void:
	# The lift bank has stone thresholds, sage lower walls, ivory upper paint,
	# a repaired back panel and a single exposed-brick break by the bench.
	for x in [6.23,18.77]:
		box(Vector3(x,.6,-38),Vector3(.025,1.2,5.2),"mall_wall_sage")
		box(Vector3(x,1.22,-38),Vector3(.045,.055,5.2),"mall_steel")
	for x in L.LIFT_CENTRES:
		B.hquad(Rect2(x-1.75,-40.25,3.5,.4),.012,"mall_green_stone",true,{"collide":true,"layer":"ext"})
	box(Vector3(12.5,1.9,-45.22),Vector3(2.65,2.8,.04),"mall_wall_buff")
	var n := Vector3.RIGHT
	var c := Vector3(6.26,2.0,-37.7)
	var pts := [c+Vector3(0,-.45,-.85),c+Vector3(0,-.65,.3),c+Vector3(0,-.15,.95),c+Vector3(0,.6,.4),c+Vector3(0,.45,-.65)]
	for i in pts.size():
		S.quad(c,pts[i],pts[(i+1)%pts.size()],pts[(i+1)%pts.size()],"mall_wall_brick",B.o({"facing":n,"layer":"mid","tile":1.4}))


func _cover(p: Vector3, lv: int, yaw: float) -> void:
	box(p+Vector3(0,.49,0),Vector3(3.1,.98,.7),"mall_metal_vc",true,lv,Vector3(0,yaw,0))
	box(p+Vector3(1.35,.72,.9),Vector3(.7,1.44,.7),"plywood",true,lv)
	box(p+Vector3(-1.15,.25,.85),Vector3(.95,.5,.65),"oak",true,lv,Vector3(0,-.3,.1))
	for j in 8:
		box(p+Vector3(-1.4+j*.4,.86,-.37),Vector3(.18,.12,.02),"mall_flat",false,lv,Vector3(0,0,.25))
	B.floor_decal(p,Vector2(4.5,3.8),yaw,"floor_papers_1")
	B.wall_decal(p+Vector3(0,.5,.36),Vector3.BACK,Vector2(2.5,.8),"blood_spatter",.8)
	stats.cover_spots += 1


func _rubble(p: Vector3, _lv: int, count: int) -> void:
	for j in count:
		var o := Vector3(rng.randf_range(-1.35,1.35),rng.randf_range(.015,.07),rng.randf_range(-1.2,1.2))
		box(p+o,Vector3(rng.randf_range(.06,.28),rng.randf_range(.025,.12),rng.randf_range(.06,.24)),
			"concrete_cracked" if j%3 else "mall_ceiling",false,0,Vector3(rng.randf()*.4,rng.randf()*TAU,rng.randf()*.3))
		stats.debris += 1


func _wire(a: Vector3, b: Vector3, mat: String) -> void:
	var axis := (b-a).normalized()
	var up := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > .9 else Vector3.UP
	S.box(Transform3D(Basis.looking_at(axis,up),(a+b)*.5),Vector3(.027,.027,a.distance_to(b)),mat,B.o({"layer":"int"}))
