extends RefCounted
## GPU integration checks: walk both cabins, inspect physical surfaces, verify
## fog stays off, and measure real world illumination from pooled muzzle lights.
const Footsteps := preload("res://src/audio/footsteps.gd")
var t
var world
var mall

func _init(test) -> void:
	t = test
	world = t.world
	mall = preload("res://src/debug/autotest_mall.gd").new(t)

func run() -> void:
	await t._until(func(): return t.ch.mode == Motor.GROUND,60.0)
	mall._freeze_zone()
	mall._freeze_bots(true)
	t.ch.health.test_invulnerable = true
	if t.ch.light.on:
		await t._tap("flashlight")
	if str(Game.arg("horror_only","")) == "flash":
		await _flash()
		return
	var l = world.map.lighting
	var fog_ok := true
	for tm in [30.0,450.0,900.0]:
		l.forced_time = tm
		l.set_daylight(1.0)
		fog_ok = fog_ok and not l.env.fog_enabled and not l.env.volumetric_fog_enabled
	t._check("horror_no_fog",fog_ok,"depth fog and volumetric fog remain disabled through daylight/settings updates")
	t._check("horror_profile",world.map.mats.mall_horror and world.map.stats.get("horror_lifts",0)==2,
		"mall material profile and exactly two open lift cabins")
	await _cabins()
	await _shafts()
	await _surfaces()
	await _flash()
	await _cover()
	# The escalator movement checks exercise both original banks after new collision.
	await mall._ride_up()
	await mall._ride_down()
	await mall._glass()

func _cabins() -> void:
	for x in [9.0,16.0]:
		t._teleport(Vector3(x,.08,-38.6),0.0)
		await t._wait(.35)
		t._act("move_forward",true)
		var entered: bool = await t._until(func(): return t.ch.global_position.z < -42.1,3.5)
		t._act("move_forward",false)
		t._check("lift_%d_walk_in"%int(x),entered,"walked through threshold to %s"%str(t.ch.global_position))
		t._look_at(Vector3(x,1.5,-44.3))
		await t._wait(.5)
		await t._shot("elevator_%d"%int(x))
		t._act("move_back",true)
		var exited: bool = await t._until(func(): return t.ch.global_position.z > -39.3,3.5)
		t._act("move_back",false)
		t._check("lift_%d_walk_out"%int(x),exited,"returned to lobby without jumping")

func _surfaces() -> void:
	var fs := Footsteps.new(world,t.ch)
	var samples := [[Vector3(-18,.06,28),"tile"],[Vector3(12.5,.07,-42),"tile"],
		[Vector3(9.65,.09,-41.3),"metal"],[Vector3(7.1,.07,-35.8),"dirt"]]
	var e: Dictionary = world.map.layout.escalators[0]
	var a: Vector3 = e.a
	var b: Vector3 = e.b
	samples.append([(a+b)*.5+Vector3.UP*.07,"escalator"])
	for sample in samples:
		t._teleport(sample[0],0.0)
		await t._wait(.12)
		var found := fs.surface()
		t._check("surface_"+str(sample[1]),found==str(sample[1]),"expected %s, got %s at %s"%[sample[1],found,str(t.ch.global_position)])
	for name in ["tile","rubber","escalator"]:
		var files: Array = SoundSys.defs.get("step_"+name,{}).get("files",[])
		t._check("recorded_steps_"+name,files.size()>=5 and files.all(func(p):return ResourceLoader.exists("res://"+p)),"%d imported recorded variants"%files.size())

func _shafts() -> void:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for x in [9.0,16.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x+.65,4.8,-41.7),Vector3(x+.65,29,-41.7),Defs.PHYS_WORLD)
		var hit := space.intersect_ray(q)
		var height: float = float(hit.position.y) if not hit.is_empty() else 0.0
		t._check("lift_shaft_%d_clear"%int(x),height>27.0,"ray passes through four upper slabs and hits machinery roof at y=%.2f"%height)
		t._teleport(Vector3(x+.3,.08,-41.4),0.0)
		t._look_at(Vector3(x,20,-42.8))
		await t._wait(.35)
		await t._shot("lift_%d_shaft_up"%int(x))
	for lv in range(1,5):
		var cell: Vector2i = world.map.layout.nav_cell(Vector2(9,-42))
		var open: int = world.map.layout.nav_open[lv][cell.y*world.map.layout.nav_nx+cell.x]
		t._check("shaft_void_nav_%d"%lv,open==0,"upper-floor navigation excludes the empty hoistway")
	t._teleport(Vector3(12.5,10.08,-36),0.0)
	await t._wait(.2)
	t._act("move_forward",true)
	var reached: bool = await t._until(func():return t.ch.global_position.z < -38.3,2.5)
	t._act("move_forward",false)
	t._check("upper_lift_lobby_access",reached and absf(t.ch.global_position.y-10.0)<.15,"walked from Level 3 concourse into real upper landing lobby")

func _flash() -> void:
	# Real first-person firing for screenshot evidence, plus a static view for a
	# precise luminance comparison free from recoil and muzzle sprite brightness.
	t._teleport(Vector3(12.5,.08,-38.3),0.0)
	t._look_at(Vector3(13,1.5,-44.3))
	await t._wait(.7)
	var dark: float = await t._view_luma()
	await t._shot("dark_lobby")
	world.effects._flash(Vector3(12.5,1.4,-40.6),1.0,1.4)
	# Hold the light for this comparison only, so a low framerate cannot miss it.
	var live: Dictionary = {}
	for f in world.effects._flash_pool:
		if f.t > 0:
			live = f
			f.t = .7
			f.duration = .7
			(f.light as OmniLight3D).light_energy = f.base
			break
	await RenderingServer.frame_post_draw
	var lit: float = await t._view_luma()
	await t._shot("muzzle_lights_room")
	t._check("muzzle_world_light",lit > dark*1.08,"view luminance %.2f -> %.2f; world surfaces receive warm light"%[dark,lit])
	if not live.is_empty():
		live.t = .095
		live.duration = .095
	await t._wait(.3)
	t._check("muzzle_pool_decay",world.effects._flash_pool.all(func(f):return f.t<=0 and not f.light.visible),"all pooled flashes extinguish after the shot")
	# Exercise the real firing input and event path too.
	t._act("fire",true)
	await t._wait(.3)
	t._act("fire",false)

func _cover() -> void:
	t._check("gallery_cover",int(world.map.stats.get("horror_cover",0))>=6,"six authored cover/recess positions on four upper floors")
	for spec in [[2,Vector3(18,10.06,22.4)],[4,Vector3(-18,20.06,-22.4)]]:
		t._teleport(spec[1],0.0)
		await t._wait(.25)
		t._look_at(Vector3(0,8.0,0))
		await t._shot("gallery_level_%d"%(spec[0]+1))
		t._check("gallery_floor_%d"%spec[0],absf(t.ch.global_position.y-float(spec[0])*5)<.25,"gallery stance rests on existing walkable floor")
