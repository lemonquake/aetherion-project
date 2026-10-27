extends RefCounted
## The artificial sun over Sitio Kalinaw. Every match starts at night; after night_s the sun ignites and holds full
## daylight for day_s, then goes dark again, and the cycle repeats. Pure functions of match time (seconds since the
## aircraft set off, from the server's tick), so every machine sees the same sky at the same moment.

const NIGHT_S := 300.0
const DAY_S := 300.0
const IGNITE_S := 9.0    # night -> day: a fast, slightly uneven ignition
const DUSK_S := 24.0     # day -> night: a slower fade at the end of the day


static func night_s() -> float:
	return float(Defs.rule("day_cycle.night_s", NIGHT_S))


static func day_s() -> float:
	return float(Defs.rule("day_cycle.day_s", DAY_S))


static func daylight(t: float) -> float:
	## 0 at night, 1 in full daylight.
	if t < 0.0:
		return 0.0
	var n := night_s()
	var d := day_s()
	var c := fmod(t, n + d)
	if c < n:
		return 0.0
	var u := c - n
	if u < IGNITE_S:
		# The sun strikes, stutters once and comes up to full.
		var k := u / IGNITE_S
		var s := smoothstep(0.0, 1.0, k)
		if k > 0.18 and k < 0.3:
			s *= 0.35
		return s
	if u > d - DUSK_S:
		return smoothstep(0.0, 1.0, (d - u) / DUSK_S)
	return 1.0


static func until_change(t: float) -> float:
	## Seconds until the next ignition (at night) or the next dusk (by day).
	var n := night_s()
	var d := day_s()
	var c := fmod(maxf(t, 0.0), n + d)
	return n - c if c < n else n + d - c


static func is_day(t: float) -> bool:
	return daylight(t) > 0.5
