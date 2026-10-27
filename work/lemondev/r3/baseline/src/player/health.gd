extends RefCounted
## Health, localized injuries, bleeding, armor and treatment for one character (server authoritative).
## The owning client receives a mirror of this state (to_dict) whenever it changes; other clients only see
## the visible consequences (limp, downed, death).

signal changed

const PARTS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]

var ch = null
var health := 100.0
var parts := {}            # part -> hp
var max_parts := {}
var bleeding := {}         # part -> 0 none, 1 light, 2 heavy
var fractured := {}        # part -> bool (limb hp <= 0)
var splinted := {}         # part -> bool
var painkiller_t := 0.0
var downed := false
var bleedout := 0.0
var dead := false
var catastrophic := false
var last_attacker := -1
var last_cause := ""
var revive_progress := 0.0
var treatment := {}        # {item, t, total} while treating
var _dirty_t := 0.0
var dirty := true


func _init(owner = null) -> void:
	ch = owner
	reset()


func reset() -> void:
	var cfg: Dictionary = Defs.health
	health = float(cfg.get("max_health", 100.0))
	for p in PARTS:
		max_parts[p] = float(cfg.get("parts", {}).get(p, 50))
		parts[p] = max_parts[p]
		bleeding[p] = 0
		fractured[p] = false
		splinted[p] = false
	painkiller_t = 0.0
	downed = false
	dead = false
	catastrophic = false
	treatment = {}
	dirty = true


# ------------------------------------------------------------------ derived effects (also used on the owner mirror)

func condition() -> String:
	if dead:
		return "DEAD"
	if downed:
		return "DOWNED"
	var bleed := false
	for p in PARTS:
		if bleeding[p] > 0:
			bleed = true
	if health < 35.0 or bleeding_level() >= 2:
		return "CRITICAL"
	if health < 80.0 or bleed or _any_fracture():
		return "INJURED"
	return "NORMAL"


func bleeding_level() -> int:
	var m := 0
	for p in PARTS:
		m = maxi(m, int(bleeding[p]))
	return m


func _any_fracture() -> bool:
	for p in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		if fractured[p] and not splinted[p]:
			return true
	return false


func _limb_state(p: String) -> float:
	## 0 healthy .. 1 injured .. 2 broken (unsplinted)
	if fractured[p] and not splinted[p]:
		return 2.0
	var frac: float = parts[p] / max_parts[p]
	if fractured[p]:
		return 1.0
	return clampf((1.0 - frac) * 1.6, 0.0, 1.0)


func arm_sway() -> float:
	## Degrees of tremor amplitude from arm injuries (the weapon and crosshair move together).
	var cfg: Dictionary = Defs.health
	var s := maxf(_limb_state("arm_l") * 0.6, _limb_state("arm_r"))
	var deg := 0.0
	if s >= 2.0:
		deg = float(cfg.get("arm_sway_broken_deg", 2.1))
	elif s > 0.15:
		deg = float(cfg.get("arm_sway_deg", 0.9)) * s
	if painkiller_t > 0.0:
		deg *= 0.45
	return deg


func arm_recoil_mult() -> float:
	var s := maxf(_limb_state("arm_l"), _limb_state("arm_r"))
	var m := 1.0 + s * 0.22
	return m * (0.85 if painkiller_t > 0.0 and s > 0.0 else 1.0)


func leg_speed() -> float:
	var cfg: Dictionary = Defs.health
	var s := maxf(_limb_state("leg_l"), _limb_state("leg_r"))
	var m := 1.0
	if s >= 2.0:
		m = float(cfg.get("leg_speed_broken", 0.6))
	elif s > 0.15:
		m = lerpf(1.0, float(cfg.get("leg_speed_injured", 0.82)), s)
	if painkiller_t > 0.0:
		m = lerpf(m, 1.0, 0.4)
	return m


func limp_side() -> float:
	## -1 left leg worse, +1 right leg worse, 0 none. Drives the uneven gait.
	var l := _limb_state("leg_l")
	var r := _limb_state("leg_r")
	if maxf(l, r) < 0.15:
		return 0.0
	return 1.0 if r >= l else -1.0


# ------------------------------------------------------------------ damage

func apply_hit(part: String, energy: float, ammo: Dictionary, e0: float, dir: Vector3, seed: int, attacker: int) -> Dictionary:
	## Returns {damage, absorbed_by, energy_left, killed, downed, armor_broken}
	var out := {"damage": 0.0, "absorbed_by": "", "energy_left": 0.0, "killed": false, "downed": false, "armor_broken": false}
	if dead:
		out.energy_left = energy * 0.8
		return out
	var cfg: Dictionary = Defs.health
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dmg := Ballistics.damage_for(ammo, energy, e0)
	var pen := float(ammo.get("armor_pen", 1.0))
	var p_energy := energy * pen
	var mult := float(cfg.get("part_multiplier", {}).get(part, 1.0))
	var blunt_only := false
	var helmet_saved := false
	# Armor
	var armor_entry = null
	if ch and ch.inv:
		if part == "torso":
			armor_entry = ch.inv.gear.get("vest")
		elif part == "head":
			armor_entry = ch.inv.gear.get("helmet")
	if armor_entry != null and float(armor_entry.get("d", 0.0)) > 0.0:
		var ad := Defs.item(str(armor_entry.id))
		var coverage := float(ad.get("coverage", 1.0))
		if rng.randf() <= coverage:
			var maxd := float(ad.get("durability", 100.0))
			var dur := float(armor_entry.d)
			var prot := float(ad.get("protection", 1000.0)) * (0.4 + 0.6 * dur / maxd)
			if p_energy < prot:
				blunt_only = true
				dmg *= float(ad.get("blunt", 0.3))
				armor_entry.d = maxf(dur - energy / 35.0, 0.0)
				out.absorbed_by = str(armor_entry.id)
			elif part == "head" and bool(ad.get("break_absorbs_lethal", false)) and dur >= maxd * 0.5 and p_energy < prot * 2.0:
				# A qualifying impact: the plate cracks and takes the round, the wearer survives concussed.
				helmet_saved = true
				armor_entry.d = 0.0
				out.armor_broken = true
				out.absorbed_by = str(armor_entry.id)
				dmg *= 0.55
			else:
				dmg *= clampf(1.0 - prot / p_energy * 0.5, 0.5, 1.0)
				armor_entry.d = maxf(dur - energy / 22.0, 0.0)
			if float(armor_entry.d) <= 0.0:
				out.armor_broken = true
			if ch.inv.has_method("mark_dirty"):
				ch.inv.mark_dirty()
	var part_dmg := dmg * mult
	var to_health := part_dmg * float(cfg.get("overflow_to_health", {}).get(part, 1.0))
	if helmet_saved:
		to_health = minf(to_health, maxf(health - 1.0, 0.0))
		part_dmg = minf(part_dmg, parts[part] - 1.0)
	parts[part] = parts[part] - part_dmg
	health -= to_health
	out.damage = to_health
	last_attacker = attacker
	last_cause = "gunshot"
	# Overpenetration: rounds keep energy through limbs, less through the torso.
	if not blunt_only and not helmet_saved:
		var flesh := {"head": 0.35, "torso": 0.15, "arm_l": 0.55, "arm_r": 0.55, "leg_l": 0.45, "leg_r": 0.45}
		out.energy_left = energy * float(flesh.get(part, 0.3)) * clampf(pen / 2.0, 0.2, 1.0)
	# Bleeding
	if not blunt_only:
		var chance := float(cfg.get("bleed_chance", {}).get(part, 0.5))
		if rng.randf() < chance:
			var heavy := part_dmg >= float(cfg.get("heavy_bleed_damage", 28.0))
			bleeding[part] = maxi(int(bleeding[part]), 2 if heavy else 1)
	# Fractures
	if part in ["arm_l", "arm_r", "leg_l", "leg_r"] and parts[part] <= float(cfg.get("fracture_threshold", 0.0)):
		fractured[part] = true
		splinted[part] = false
		parts[part] = 0.0
	if part == "head" and parts.head <= 0.0 and not helmet_saved:
		catastrophic = true
	if part == "torso" and parts.torso < -40.0:
		catastrophic = true
	if downed and to_health > 0.0:
		bleedout -= to_health * 0.6
		if to_health > 40.0:
			catastrophic = true
	_check_state(out)
	dirty = true
	changed.emit()
	return out


func apply_simple(amount: float, cause: String, part: String = "", attacker: int = -1) -> Dictionary:
	## Zone damage, falls, landings.
	var out := {"damage": amount, "killed": false, "downed": false}
	if dead:
		return out
	health -= amount
	last_cause = cause
	if attacker >= 0:
		last_attacker = attacker
	if part != "":
		parts[part] = parts[part] - amount * 1.2
		if part.begins_with("leg") and parts[part] <= 0.0:
			fractured[part] = true
			parts[part] = 0.0
	if downed:
		bleedout -= amount
	_check_state(out)
	dirty = true
	changed.emit()
	return out


func _check_state(out: Dictionary) -> void:
	if catastrophic and not dead:
		_die(out)
		return
	if health <= 0.0 and not dead:
		if not downed and ch and ch.world and ch.world.server_can_be_downed(ch):
			downed = true
			health = 1.0
			bleedout = float(Defs.health.get("downed_bleedout_s", 90.0))
			treatment = {}
			out.downed = true
		elif not downed:
			_die(out)
	if downed and bleedout <= 0.0 and not dead:
		_die(out)


func _die(out: Dictionary) -> void:
	dead = true
	downed = false
	health = 0.0
	out.killed = true


# ------------------------------------------------------------------ over time

func tick(dt: float) -> Dictionary:
	## Returns {killed} when bleeding or bleed-out ends the character.
	var out := {"killed": false, "downed": false}
	if dead:
		return out
	var cfg: Dictionary = Defs.health
	var loss := 0.0
	for p in PARTS:
		match int(bleeding[p]):
			1:
				loss += float(cfg.get("bleed_light_per_s", 0.35))
			2:
				loss += float(cfg.get("bleed_heavy_per_s", 1.05))
	if loss > 0.0:
		health -= loss * dt
		last_cause = "bleeding"
		_dirty_t += dt
	if painkiller_t > 0.0:
		painkiller_t = maxf(painkiller_t - dt, 0.0)
	if downed:
		bleedout -= dt * (0.0 if revive_progress > 0.0 else 1.0)
		_dirty_t += dt
	if _dirty_t > 0.5:
		_dirty_t = 0.0
		dirty = true
	_check_state(out)
	if out.killed:
		dirty = true
	return out


# ------------------------------------------------------------------ treatment

func treatment_need() -> String:
	## The item a quick heal should use next.
	if bleeding_level() > 0:
		return "bandage"
	for p in ["leg_l", "leg_r", "arm_r", "arm_l"]:
		if fractured[p] and not splinted[p]:
			return "splint"
	if health < 75.0:
		return "first_aid"
	if painkiller_t <= 0.0 and (_limb_state("leg_l") > 0.3 or _limb_state("leg_r") > 0.3 or _limb_state("arm_r") > 0.3):
		return "painkillers"
	return ""


func can_use(item_id: String) -> bool:
	match item_id:
		"bandage":
			return bleeding_level() > 0
		"first_aid":
			return health < 99.0 or bleeding_level() > 0
		"splint":
			for p in ["leg_l", "leg_r", "arm_r", "arm_l"]:
				if fractured[p] and not splinted[p]:
					return true
			return false
		"painkillers":
			return true
	return false


func apply_treatment(item_id: String) -> void:
	var d := Defs.item(item_id)
	var stops := int(d.get("stops_bleeding", 0))
	# Worst bleeding first.
	for level in [2, 1]:
		for p in PARTS:
			if stops > 0 and int(bleeding[p]) == level:
				bleeding[p] = 0
				stops -= 1
	if d.has("heal"):
		health = minf(health + float(d.heal), float(Defs.health.get("max_health", 100.0)))
		for p in PARTS:
			if not fractured[p]:
				parts[p] = minf(parts[p] + max_parts[p] * 0.35, max_parts[p])
	if d.get("fixes_fracture", false):
		for p in ["leg_l", "leg_r", "arm_r", "arm_l"]:
			if fractured[p] and not splinted[p]:
				splinted[p] = true
				parts[p] = max_parts[p] * 0.3
				break
	if d.has("pain_relief_s"):
		painkiller_t = float(d.pain_relief_s)
	dirty = true
	changed.emit()


func revive() -> void:
	downed = false
	health = float(Defs.health.get("revive_health", 22.0))
	revive_progress = 0.0
	dirty = true
	changed.emit()


# ------------------------------------------------------------------ replication

func to_dict() -> Dictionary:
	return {"h": health, "p": parts.duplicate(), "b": bleeding.duplicate(), "f": fractured.duplicate(),
		"s": splinted.duplicate(), "pk": painkiller_t, "dn": downed, "bo": bleedout, "dd": dead, "tr": treatment.duplicate()}


func from_dict(d: Dictionary) -> void:
	health = float(d.h)
	parts = d.p
	bleeding = d.b
	fractured = d.f
	splinted = d.s
	painkiller_t = float(d.pk)
	downed = bool(d.dn)
	bleedout = float(d.bo)
	dead = bool(d.dd)
	treatment = d.get("tr", {})
	changed.emit()
