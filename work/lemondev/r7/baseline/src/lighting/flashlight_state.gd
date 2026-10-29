extends RefCounted
## Flashlight logic for one character (server authoritative; the owner predicts the switch).
##
## Handling rules:
##  - With a long gun that has a weapon light, the weapon light is the active light and points where the barrel
##    points (including recoil and sway).
##  - Otherwise the handheld flashlight is used: in the left hand with a handgun or with no weapon (it follows the
##    view), or clipped to the shoulder strap with a long gun (it follows the body and only roughly the view).
## Tap the light key to switch on/off; hold it to change the battery (hands busy, light off, ~2.6 s).

var ch = null
var on := false
var swap_t := 0.0
var _held_t := 0.0
var _prev := false
var _swapped_this_hold := false
var weapon_mounted := false


func _init(owner = null) -> void:
	ch = owner


func source() -> Dictionary:
	## The entry whose battery powers the active light: the weapon instance (weapon light) or the flashlight gear.
	weapon_mounted = false
	if ch and ch.wpn:
		var w: Dictionary = ch.wpn.weapon()
		if not w.is_empty() and "weapon_light" in w.get("att", []):
			weapon_mounted = true
			if not w.has("wl"):
				w.wl = 0.8
			return w
	if ch and ch.inv and ch.inv.gear.get("flashlight") != null:
		return ch.inv.gear.flashlight
	return {}


func charge() -> float:
	var s := source()
	if s.is_empty():
		return -1.0
	return float(s.get("wl" if weapon_mounted else "c", -1.0))


func _set_charge(v: float) -> void:
	var s := source()
	if s.is_empty():
		return
	s["wl" if weapon_mounted else "c"] = v


func low() -> bool:
	var c := charge()
	return c >= 0.0 and c < float(Defs.flashlight.get("low_charge", 0.15))


func swapping() -> bool:
	return swap_t > 0.0


func step(cmd: Dictionary, dt: float, authoritative: bool) -> Array:
	## Returns events: "on", "off", "swap_start", "swap_done", "dead".
	var ev := []
	var held := (int(cmd.get("btn", 0)) & Motor.B_LIGHT) != 0
	if held:
		_held_t += dt
	if held and _held_t >= 0.45 and not _swapped_this_hold and swap_t <= 0.0:
		_swapped_this_hold = true
		if _can_swap():
			swap_t = float(Defs.flashlight.get("swap_time", 2.6))
			if on:
				on = false
				ev.append("off")
			ev.append("swap_start")
	if not held and _prev:
		if not _swapped_this_hold and _held_t < 0.45 and swap_t <= 0.0:
			var c := charge()
			if on:
				on = false
				ev.append("off")
			elif c > 0.0:
				on = true
				ev.append("on")
			else:
				ev.append("click_dead")
		_held_t = 0.0
		_swapped_this_hold = false
	_prev = held
	if swap_t > 0.0:
		swap_t -= dt
		if swap_t <= 0.0:
			swap_t = 0.0
			if authoritative:
				_do_swap()
			ev.append("swap_done")
	if on:
		var life := float(Defs.flashlight.get("weapon_light_battery_life_s" if weapon_mounted else "battery_life_s", 540.0))
		var c := charge()
		if authoritative and c >= 0.0:
			c = maxf(c - dt / life, 0.0)
			_set_charge(c)
			if ch and ch.inv:
				ch.inv.dirty = true
		if c <= 0.0:
			on = false
			ev.append("dead")
	return ev


func _can_swap() -> bool:
	if source().is_empty() or ch == null or ch.inv == null:
		return false
	return not ch.inv.best_battery().is_empty()


func _do_swap() -> void:
	var s := source()
	if s.is_empty() or ch.inv == null:
		return
	var best: Dictionary = ch.inv.best_battery()
	if best.is_empty():
		return
	var old := float(s.get("wl" if weapon_mounted else "c", -1.0))
	ch.inv.remove_entry(best)
	_set_charge(float(best.c))
	if old > 0.02:
		ch.inv.add({"id": "battery", "n": 1, "c": old}, true)
	ch.inv.mark_dirty()


func flicker(t: float, eid: int) -> float:
	## Intensity multiplier with restrained low-battery instability. Deterministic so every client agrees.
	var c := charge()
	if c < 0.0:
		return 0.0
	var base := clampf(0.55 + c * 3.0, 0.55, 1.0)
	if not low():
		return base
	var x := t * float(Defs.flashlight.get("low_flicker_rate", 0.9)) + float(eid) * 3.17
	var n := sin(x * 7.1) * 0.5 + sin(x * 13.3 + 1.7) * 0.3 + sin(x * 2.3) * 0.2
	var dip := 1.0 if n > 0.82 else 0.0
	return base * (0.75 + 0.2 * sin(x * 3.0)) * (1.0 - dip * 0.8)
