extends RefCounted
## Firearm handling for one character. Runs on the server (authoritative) and on the owning client (prediction);
## both produce identical shot directions because recoil, sway and spread are deterministic functions of state,
## the server tick and a per-shot seed.

const Attach := preload("res://src/weapons/attachments.gd")
const SELECT_FIRE_MODES := ["auto", "semi", "burst"]

enum { IDLE, DRAW, RELOAD, CYCLE, BUSY }
enum { HOLSTER, PRIMARY, SECONDARY, HANDGUN }

var ch = null
var slots := [null, null, null, null]  # index by HOLSTER..HANDGUN; each {id, mag, chamber, mode, att:[]}
var cur := HOLSTER
var want := HOLSTER
var state := IDLE
var timer := 0.0
var reload_phase := 0     # 0 start, 1 inserting, 2 end (tube/cylinder)
var cooldown := 0.0
var aiming := false
var ads := 0.0            # 0..1 aim-down-sights progress
var shots := 0            # total shots fired (seeds spread)
var burst := 0            # consecutive shots without pause (sustained recoil)
var since_shot := 9.0
var kick := Vector2.ZERO  # weapon-only offset (x = yaw deg, y = pitch deg), recovers
var _reload_queued := false
var climb_pending := 0.0  # view pitch climb the client applies to the camera (deg)
var yaw_pending := 0.0
var reserve_cache := {}   # ammo id -> count (mirror of inventory for prediction)
var blocked := false      # SmarTab raised, swimming, downed, holding an object...
var _prev_fire := false
var _prev_reload := false
var _prev_mode := false
var burst_left := 0       # rounds still due from this trigger press (not the recoil counter above)


func _init(owner = null) -> void:
	ch = owner


# ------------------------------------------------------------------ queries

func weapon() -> Dictionary:
	var w = slots[cur]
	return w if w != null else {}


func def() -> Dictionary:
	var w := weapon()
	return Defs.weapon(str(w.get("id", ""))) if not w.is_empty() else {}


func current_id() -> String:
	return str(weapon().get("id", ""))


func loaded() -> int:
	var w := weapon()
	if w.is_empty():
		return 0
	return int(w.mag) + (1 if w.chamber else 0)


func reloading() -> bool:
	return state == RELOAD


func fired_recently() -> bool:
	return since_shot < 0.12


func can_fire() -> bool:
	# Snapshots store cooldowns as half floats; ignore their sub-millisecond quantization at the boundary.
	return not weapon().is_empty() and state == IDLE and cooldown <= 0.0001 and not blocked


func fire_mode() -> String:
	var modes := available_modes()
	return str(modes[posmod(int(weapon().get("mode", 0)), modes.size())])


static func has_selector(id: String) -> bool:
	return str(Defs.weapon(id).get("class", "")) in ["rifle", "smg"]


func available_modes() -> Array:
	# One consistent selector for every rifle and SMG, regardless of the historical data order.
	if has_selector(current_id()):
		return SELECT_FIRE_MODES
	var modes: Array = def().get("fire_modes", ["semi"])
	return modes if not modes.is_empty() else ["semi"]


func fire_mode_label() -> String:
	match fire_mode():
		"auto": return "Auto"
		"semi": return "Single"
		"burst": return "Burst"
		"pump": return "Pump"
		"bolt": return "Bolt"
	return fire_mode().capitalize()


func cancel_burst() -> void:
	burst_left = 0


func zoom() -> float:
	var z := float(def().get("sight_zoom", 1.1))
	return float(Attach.sight(weapon()).get("zoom", z))


func scoped() -> bool:
	## A magnified optic is fitted: aiming shows the scope view.
	return bool(Attach.sight(weapon()).get("scope", false))


func mag_cap() -> int:
	return Attach.mag_cap(weapon())


func spread_deg(moving: float, crouching: bool) -> float:
	## Current cone (degrees) for the aim state and movement; the reticle draws the same value.
	var d := def()
	var w := weapon()
	var hip := float(d.get("spread_hip", 2.0)) * Attach.mult(w, "spread_hip_mult")
	var spread := lerpf(hip, float(d.get("spread_ads", 0.2)), ads)
	var mv := (float(d.get("move_spread", 1.5)) - 1.0) * Attach.mult(w, "move_spread_mult")
	spread *= 1.0 + clampf(moving / 4.0, 0.0, 1.0) * mv
	if crouching:
		spread *= 0.8
	return spread


func has_attachment(kind: String) -> bool:
	for a in weapon().get("att", []):
		if Defs.attachments.get(a, {}).get("kind", "") == kind:
			return true
	return false


func slot_for(id: String) -> int:
	var d := Defs.weapon(id)
	if d.get("slot", "long") == "handgun":
		return HANDGUN
	if slots[PRIMARY] == null:
		return PRIMARY
	if slots[SECONDARY] == null:
		return SECONDARY
	return PRIMARY if cur != SECONDARY else SECONDARY


static func new_instance(id: String, rng: RandomNumberGenerator = null, loaded_frac: float = -1.0) -> Dictionary:
	var d := Defs.weapon(id)
	var cap := int(d.get("mag_size", 10))
	var n := cap
	if loaded_frac >= 0.0:
		n = int(round(cap * loaded_frac))
	elif rng:
		n = rng.randi_range(int(cap * 0.3), cap)
	# A revolver's next chamber counts as chambered (the trigger turns the cylinder).
	var chamber := (bool(d.get("chamber", true)) or str(d.get("feed", "")) == "cylinder") and n > 0
	if chamber:
		n -= 1
	return {"id": id, "mag": n, "chamber": chamber, "mode": 0, "att": []}


# ------------------------------------------------------------------ simulation

func step(cmd: Dictionary, dt: float, tick: int) -> Array:
	## Returns shots fired this step: [{origin, dir, seed, ammo, pellets}]
	var btn := int(cmd.get("btn", 0))
	var fire := (btn & Motor.B_FIRE) != 0
	var reload := (btn & Motor.B_RELOAD) != 0
	var mode_t := (btn & Motor.B_FIREMODE) != 0
	var out := []
	if not is_finite(dt) or dt <= 0.0:
		return out
	if blocked or (ch != null and ch.mode != Motor.GROUND):
		cancel_burst()
	since_shot += dt
	cooldown = maxf(cooldown - dt, 0.0)
	_recover(dt)
	# Slot changes
	want = int(cmd.get("slot", want))
	if want != cur and (want == HOLSTER or slots[want] != null):
		if state == RELOAD:
			state = IDLE
		cur = want
		if cur != HOLSTER:
			state = DRAW
			timer = float(def().get("draw_time", 0.5))
		else:
			state = IDLE
		ads = 0.0
		burst = 0
		cancel_burst()
		_reload_queued = false
	var d := def()
	var w := weapon()
	# ADS
	aiming = (btn & Motor.B_AIM) != 0 and not w.is_empty() and not blocked and state != DRAW and ch and not ch.sprinting
	var ads_t := float(d.get("ads_time", 0.25)) * _ads_mult()
	ads = move_toward(ads, 1.0 if aiming else 0.0, dt / maxf(ads_t, 0.05))
	match state:
		DRAW:
			timer -= dt
			if timer <= 0.0:
				state = IDLE
		RELOAD:
			_reload_step(dt, fire)
		CYCLE:
			timer -= dt
			if timer <= 0.0:
				_chamber_from_mag(w)
				state = IDLE
		BUSY:
			pass
	if w.is_empty():
		cancel_burst()
		_prev_fire = fire
		_prev_reload = reload
		_prev_mode = mode_t
		return out
	var selector_changed := false
	if mode_t and not _prev_mode and state == IDLE and not blocked:
		var modes := available_modes()
		w.mode = (int(w.get("mode", 0)) + 1) % modes.size()
		cancel_burst()
		selector_changed = true
	_prev_mode = mode_t
	# A reload pressed while a shot is still cycling (pump, bolt, break action) or the gun is coming up is kept and
	# starts as soon as the gun is ready, instead of being lost.
	if reload and not _prev_reload and state in [CYCLE, DRAW]:
		_reload_queued = true
	if ((reload and not _prev_reload) or _reload_queued) and state == IDLE and not blocked:
		_reload_queued = false
		start_reload()
	_prev_reload = reload
	var fm := fire_mode()
	# A burst completes after the finger is lifted, but holding the trigger never starts another burst.
	if state != IDLE or blocked:
		cancel_burst()
	if fm == "burst" and burst_left == 0 and fire and not _prev_fire and not selector_changed and can_fire():
		burst_left = 3
	var trigger := not selector_changed and (burst_left > 0 if fm == "burst" else fire and (fm == "auto" or not _prev_fire))
	if trigger and can_fire() and not w.chamber and str(d.get("feed", "")) == "cylinder":
		_chamber_from_mag(w)  # double action: pulling the trigger brings the next round under the hammer
	if trigger and can_fire():
		if w.chamber:
			out.append(_fire(tick))
			if fm == "burst":
				burst_left = maxi(burst_left - 1, 0)
				if not w.chamber:
					cancel_burst()
		else:
			# Dry fire: empty chamber. An automatic reload starts on the next press if ammo is available.
			cooldown = 0.25
			out.append({"dry": true})
			cancel_burst()
	if not fire:
		if since_shot > 0.25:
			burst = 0
	_prev_fire = fire
	return out


func _ads_mult() -> float:
	return Attach.mult(weapon(), "ads_time_mult")


func _fire(tick: int) -> Dictionary:
	var w := weapon()
	var d := def()
	w.chamber = false
	shots += 1
	burst += 1
	since_shot = 0.0
	cooldown = 60.0 / maxf(float(d.get("rpm", 600)), 1.0)
	var fm := fire_mode()
	if fm == "pump" or fm == "bolt":
		state = CYCLE
		timer = float(d.get("cycle_time", 0.6))
	else:
		_chamber_from_mag(w)
	var seed := hash([ch.eid if ch else 0, shots, tick])
	var dir := shot_direction(tick, seed)
	_apply_recoil(seed)
	var ammo_id: String = w.get("ammo", d.get("ammo", "9x19"))
	return {"origin": muzzle_origin(), "dir": dir, "seed": seed, "ammo": ammo_id, "weapon": w.id,
		"pellets": int(Defs.ammo(ammo_id).get("pellets", 1)), "velocity": float(d.get("muzzle_velocity", 400)),
		"pellet_mult": Attach.mult(w, "pellet_spread_mult")}


func _chamber_from_mag(w: Dictionary) -> void:
	if w.is_empty() or w.chamber:
		return
	if int(w.mag) > 0:
		w.mag = int(w.mag) - 1
		w.chamber = true


func muzzle_origin() -> Vector3:
	## Shots leave from just in front of the eye along the weapon line, so cover between the eye and the muzzle
	## blocks the shot even when the player can see over it.
	if ch == null:
		return Vector3.ZERO
	var b: Basis = ch.aim_basis()
	var eye: Vector3 = ch.eye_position()
	var hip := 1.0 - ads
	var off := Vector3(0.12 * hip + 0.0, -0.09 * hip - 0.035, -0.55)
	if str(def().get("slot", "")) == "handgun":
		off.z = -0.42
	return eye + b * off


func aim_offset_deg(tick: int) -> Vector2:
	## Weapon-only offset from the view centre: recoil kick + sway. The crosshair is drawn here too.
	return kick + sway_deg(tick)


func sway_deg(tick: int) -> Vector2:
	if ch == null:
		return Vector2.ZERO
	var t := float(tick) / Defs.TICK_RATE
	var e := float(ch.eid % 97) * 1.37
	var amp := lerpf(0.55, 0.06, ads) * Attach.mult(weapon(), "sway_mult")  # breathing
	var arm := 0.0
	var h = ch.health
	if h:
		arm = float(h.arm_sway()) if h.has_method("arm_sway") else 0.0
	var moving := Vector2(ch.velocity.x, ch.velocity.z).length()
	amp += minf(moving * 0.05, 0.4) * lerpf(1.0, 0.4, ads)
	if ch.crouching:
		amp *= 0.75
	var breath := Vector2(sin(t * 1.3 + e) * 0.6 + sin(t * 0.7 + e * 2.0) * 0.4, sin(t * 1.9 + e) * 0.5 + cos(t * 0.9 + e) * 0.5) * amp
	# Injured arms: an uneven tremor the player can partly fight, never a HUD-only wobble.
	var tremor := Vector2(sin(t * 5.3 + e) * 0.5 + sin(t * 8.9 + e * 3.0) * 0.3 + sin(t * 2.1) * 0.2,
		sin(t * 6.7 + e * 1.5) * 0.5 + cos(t * 9.7 + e) * 0.3 + sin(t * 1.7 + e) * 0.2) * arm
	return breath + tremor


func shot_direction(tick: int, seed: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var spread := spread_deg(0.0, false)
	if ch:
		spread = spread_deg(Vector2(ch.velocity.x, ch.velocity.z).length(), ch.crouching)
		if not ch.is_on_floor() and ch.mode == Motor.GROUND:
			spread *= 2.5
	var off := aim_offset_deg(tick)
	var ang := rng.randf() * TAU
	var r := sqrt(rng.randf()) * spread * 0.5
	off += Vector2(cos(ang), sin(ang)) * r
	var b: Basis = ch.aim_basis() if ch else Basis()
	b = b * Basis(Vector3.UP, deg_to_rad(-off.x)) * Basis(Vector3.RIGHT, deg_to_rad(off.y))
	return -b.z


func _apply_recoil(seed: int) -> void:
	var r: Dictionary = def().get("recoil", {})
	var pattern: Array = r.get("pattern", [0.0])
	var side := float(pattern[(burst - 1) % pattern.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5bd1e995
	var up := float(r.get("kick_up", 1.5)) * (1.0 + minf(burst * float(r.get("climb", 0.1)), 1.5))
	up *= rng.randf_range(0.85, 1.15)
	var sx := float(r.get("kick_side", 0.5)) * (side + rng.randf_range(-0.35, 0.35))
	up *= Attach.mult(weapon(), "recoil_up_mult")
	sx *= Attach.mult(weapon(), "recoil_side_mult")
	var ads_mult := lerpf(1.0, 0.75, ads)
	if ch and ch.crouching:
		ads_mult *= 0.85
	if ch and ch.health and ch.health.has_method("arm_recoil_mult"):
		ads_mult *= ch.health.arm_recoil_mult()
	up *= ads_mult
	sx *= ads_mult
	var share := float(r.get("camera_share", 0.5))
	climb_pending += up * share
	yaw_pending += sx * share
	kick += Vector2(sx * (1.0 - share), up * (1.0 - share))
	var mx := float(r.get("max_climb", 8.0))
	kick.y = minf(kick.y, mx)


func _recover(dt: float) -> void:
	var rate := float(def().get("recoil", {}).get("recovery", 12.0)) * Attach.mult(weapon(), "recovery_mult")
	kick = kick.move_toward(Vector2.ZERO, rate * dt * (0.4 if since_shot < 0.08 else 1.0))


# ------------------------------------------------------------------ reloading

func reserve(ammo_id: String) -> int:
	if ch and ch.inv and ch.inv.has_method("count"):
		return ch.inv.count("ammo_" + ammo_id)
	return int(reserve_cache.get(ammo_id, 0))


func start_reload() -> void:
	cancel_burst()
	var w := weapon()
	var d := def()
	if w.is_empty():
		return
	var ammo_id := str(w.get("ammo", d.get("ammo", "")))
	var cap := mag_cap()
	var feed := str(d.get("feed", "mag"))
	var full := int(w.mag) + (1 if w.chamber else 0) >= cap if feed == "break" else int(w.mag) >= cap
	if full or reserve(ammo_id) <= 0:
		return
	state = RELOAD
	reload_phase = 0
	var rm := Attach.mult(w, "reload_mult")
	if feed == "mag" or feed == "break":
		timer = float(d.get("reload_empty_time" if not w.chamber else "reload_time", 2.5)) * rm
	else:
		timer = float(d.get("reload_start", 0.5))
	aiming = false


func _reload_step(dt: float, fire: bool) -> void:
	var w := weapon()
	var d := def()
	if w.is_empty():
		state = IDLE
		return
	var ammo_id := str(w.get("ammo", d.get("ammo", "")))
	var cap := mag_cap()
	var feed := str(d.get("feed", "mag"))
	timer -= dt
	if timer > 0.0:
		return
	if feed == "break":
		# Break action: every barrel loaded at once; the round "chambered" is the next barrel to fire.
		var have := int(w.mag) + (1 if w.chamber else 0)
		var total := have + _take_ammo(ammo_id, cap - have)
		w.chamber = total > 0
		w.mag = maxi(total - 1, 0)
		state = IDLE
		return
	if feed == "mag":
		var need := cap - int(w.mag)
		var got := _take_ammo(ammo_id, need)
		w.mag = int(w.mag) + got
		if not w.chamber:
			_chamber_from_mag(w)
		state = IDLE
		return
	# Tube or cylinder: one round at a time, interruptible by the trigger.
	if reload_phase == 0:
		reload_phase = 1
		timer = float(d.get("reload_time", 0.5)) * Attach.mult(w, "reload_mult")
		return
	if reload_phase == 1:
		if _take_ammo(ammo_id, 1) == 1:
			if feed == "cylinder" or w.chamber or not bool(d.get("chamber", true)):
				w.mag = int(w.mag) + 1
			else:
				w.chamber = true
		if int(w.mag) >= cap or reserve(ammo_id) <= 0 or fire:
			reload_phase = 2
			timer = float(d.get("reload_end", 0.4))
			if feed == "cylinder" and not w.chamber:
				_chamber_from_mag(w)
		else:
			timer = float(d.get("reload_time", 0.5)) * Attach.mult(w, "reload_mult")
		return
	if not w.chamber:
		_chamber_from_mag(w)
	state = IDLE


func _take_ammo(ammo_id: String, n: int) -> int:
	if ch and ch.inv and ch.inv.has_method("take"):
		return ch.inv.take("ammo_" + ammo_id, n)
	var have := int(reserve_cache.get(ammo_id, 0))
	var got := mini(have, n)
	reserve_cache[ammo_id] = have - got
	return got


func cancel_reload() -> void:
	cancel_burst()
	if state == RELOAD:
		state = IDLE


# ------------------------------------------------------------------ prediction state

func get_state() -> Dictionary:
	var w := weapon()
	return {"cur": cur, "want": want, "state": state, "timer": timer, "rp": reload_phase, "cd": cooldown, "ads": ads,
		"shots": shots, "burst": burst, "since": since_shot, "kick": kick, "mag": int(w.get("mag", 0)),
		"chamber": bool(w.get("chamber", false)), "mode": int(w.get("mode", 0)), "pf": _prev_fire, "pr": _prev_reload,
		"pm": _prev_mode, "bl": burst_left, "rq": _reload_queued}


func set_state(s: Dictionary) -> void:
	cur = int(s.cur)
	want = int(s.get("want", cur))
	state = int(s.state)
	timer = float(s.timer)
	reload_phase = int(s.rp)
	cooldown = float(s.cd)
	ads = float(s.ads)
	shots = int(s.shots)
	burst = int(s.burst)
	since_shot = float(s.since)
	kick = s.kick
	_prev_fire = bool(s.get("pf", false))
	_prev_reload = bool(s.get("pr", false))
	_prev_mode = bool(s.get("pm", false))
	burst_left = clampi(int(s.get("bl", 0)), 0, 3)
	_reload_queued = bool(s.get("rq", false))
	var w = slots[cur]
	if w != null:
		w.mag = int(s.mag)
		w.chamber = bool(s.chamber)
		w.mode = int(s.mode)
