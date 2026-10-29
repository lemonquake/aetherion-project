extends RefCounted
## Footsteps for any character, from its actual (interpolated or predicted) movement: stride length and loudness
## follow the gait, the sound follows the surface under the foot, wading splashes, and the injured leg drags.

const STRIDE := {"crouch": 0.55, "walk": 0.72, "run": 0.95, "sprint": 1.25, "crawl": 0.6}
const GAIN := {"crouch": -14.0, "walk": -8.0, "run": -1.0, "sprint": 3.0, "crawl": -10.0}

var world = null
var ch = null
var _acc := 0.0
var _last := Vector3.INF
var _foot := 0


func _init(w, c) -> void:
	world = w
	ch = c


func surface() -> String:
	if ch.water_depth() > 0.12:
		return "water"
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var from: Vector3 = ch.global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.8, Defs.PHYS_WORLD | Defs.PHYS_PROP)
	var r := space.intersect_ray(q)
	if r.is_empty():
		return "dirt"
	var mat := "dirt"
	if r.collider and r.collider.has_meta("mat"):
		mat = str(r.collider.get_meta("mat"))
	match mat:
		"wood", "plywood":
			return "wood"
		"sheet_metal", "steel":
			return "metal"
		"concrete", "hollow_block", "plaster":
			return "concrete"
		"fabric":
			return "carpet"
		"glass":
			return "glass"
	return "dirt"


func update(dt: float) -> void:
	var p: Vector3 = ch.global_position
	if _last == Vector3.INF:
		_last = p
		return
	var moved := Vector2(p.x - _last.x, p.z - _last.z).length()
	_last = p
	if moved > 3.0:  # teleport / correction
		return
	if not ch.is_on_floor() and ch.mode == Motor.GROUND and not ch.is_remote:
		return
	var gait := "run"
	var f: int = ch.flags
	if ch.mode == Motor.DOWNED:
		gait = "crawl"
	elif (f & Character.F_CROUCH) or ch.crouch > 0.5:
		gait = "crouch"
	elif (f & Character.F_SPRINT):
		gait = "sprint"
	elif (f & Character.F_WALK) or Vector2(ch.velocity.x, ch.velocity.z).length() < 2.9:
		gait = "walk"
	_acc += moved
	var stride: float = STRIDE[gait]
	if (f & Character.F_LIMP) and _foot % 2 == 1:
		stride *= 0.75
	if _acc < stride:
		return
	_acc = 0.0
	_foot += 1
	var s := surface()
	var db: float = GAIN[gait]
	if (f & Character.F_LIMP) and _foot % 2 == 0:
		db -= 5.0  # the injured leg lands softly and drags
	var pos: Vector3 = p + Vector3.UP * 0.05
	if ch.is_local:
		SoundSys.play_at("step_" + s, pos, db, {"no_prop": true, "prio": 1})
	else:
		SoundSys.play_at("step_" + s, pos, db, {"prio": 4})
