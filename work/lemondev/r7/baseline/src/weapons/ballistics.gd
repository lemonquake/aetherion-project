class_name Ballistics
## Point-mass projectile flight with gravity and quadratic drag (a = g - k|v|v), integrated in fixed substeps.
## Server projectiles and client tracers call the same function with the same inputs, so a tracer follows the
## simulated path exactly until the server reports where it actually stopped or deflected.


static func integrate(pos: Vector3, vel: Vector3, drag_k: float, dt: float, substeps: int = 2) -> Array:
	## Returns [new_pos, new_vel].
	var g := Vector3(0.0, -float(Defs.ballistics.get("gravity", 9.81)), 0.0)
	var h := dt / float(maxi(substeps, 1))
	for i in substeps:
		# Semi-implicit midpoint: good enough at 120 Hz effective for 1 km flights (error < 1 cm vs RK4).
		var a1 := g - vel * (drag_k * vel.length())
		var mid_v := vel + a1 * (h * 0.5)
		var a2 := g - mid_v * (drag_k * mid_v.length())
		pos += mid_v * h
		vel += a2 * h
	return [pos, vel]


static func energy(mass: float, speed: float) -> float:
	return 0.5 * mass * speed * speed


static func speed_for_energy(mass: float, e: float) -> float:
	return sqrt(maxf(2.0 * e / maxf(mass, 1e-6), 0.0))


static func damage_for(ammo: Dictionary, e: float, e0: float) -> float:
	var exp_ := float(Defs.ballistics.get("damage_energy_exponent", 0.55))
	var frac := clampf(e / maxf(e0, 1.0), 0.0, 1.2)
	return maxf(float(ammo.get("damage", 30)) * pow(frac, exp_), 0.0)


static func flight_table(ammo_id: String, v0: float, distances: Array) -> Array:
	## Diagnostic: time of flight, drop and remaining speed at each distance for a level shot.
	var a := Defs.ammo(ammo_id)
	var pos := Vector3.ZERO
	var vel := Vector3(0, 0, -v0)
	var t := 0.0
	var out := []
	var i := 0
	while i < distances.size() and t < 5.0:
		var r := integrate(pos, vel, float(a.get("drag_k", 0.001)), Defs.TICK_DT, 4)
		var np: Vector3 = r[0]
		if -np.z >= float(distances[i]):
			var f := (float(distances[i]) + pos.z) / (pos.z - np.z)
			var p := pos.lerp(np, f)
			out.append({"distance": distances[i], "time": t + Defs.TICK_DT * f, "drop": -p.y, "speed": (r[1] as Vector3).length()})
			i += 1
			continue
		pos = np
		vel = r[1]
		t += Defs.TICK_DT
	return out
