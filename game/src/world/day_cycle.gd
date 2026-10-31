extends RefCounted
## The artificial sun over Sitio Kalinaw. Every match starts at night; after night_s the sun ignites and holds full
## daylight for day_s, then goes dark again, and the cycle repeats. Pure functions of match time (seconds since the
## aircraft set off, from the server's tick), so every machine sees the same sky at the same moment. A Deathmatch
## round has no aircraft: its clock starts with the round (Lighting.match_time).
## (r17) Every match on every map starts at night. The lobby's host picks how long each night and each day lasts
## (Net.config.day_len: 2, 5 or 10 minutes), and an indoor map (Malasugue Mall, layout.night_only) has no sun at all.

const NIGHT_S := 300.0
const DAY_S := 300.0
const IGNITE_S := 9.0    # night -> day: a fast, slightly uneven ignition
const DUSK_S := 24.0     # day -> night: a slower fade at the end of the day
const LENGTHS := [120, 300, 600]   # the host's choices for day_len (seconds)

## Set for the match being played (configure): the length of one night and of one day (<= 0: rules.json day_cycle),
## and whether the map stays dark the whole match.
static var phase_len := -1.0
static var night_only := false


static func configure(day_len: float, always_night: bool) -> void:
	phase_len = day_len if day_len >= 60.0 else -1.0
	night_only = always_night


static func night_s() -> float:
	if phase_len > 0.0:
		return phase_len
	return float(Defs.rule("day_cycle.night_s", NIGHT_S))


static func day_s() -> float:
	if phase_len > 0.0:
		return phase_len
	return float(Defs.rule("day_cycle.day_s", DAY_S))


static func daylight(t: float) -> float:
	## 0 at night, 1 in full daylight.
	if t < 0.0 or night_only:
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
	if night_only:
		return INF
	var n := night_s()
	var d := day_s()
	var c := fmod(maxf(t, 0.0), n + d)
	return n - c if c < n else n + d - c


static func is_day(t: float) -> bool:
	return daylight(t) > 0.5


static func next_change(t: float) -> Array:
	## [match time of the next change, "ignite" | "dusk"]: the moment the sun strikes, or the moment it starts to die
	## (the start of the dusk fade). The loudspeakers count down to these. A night-only map: never.
	if night_only:
		return [INF, "ignite"]
	var n := night_s()
	var d := day_s()
	var cyc := n + d
	var t0 := maxf(t, 0.0)
	var k := floorf(t0 / cyc)
	var c := t0 - k * cyc
	if c < n:
		return [k * cyc + n, "ignite"]
	if c < n + d - DUSK_S:
		return [k * cyc + n + d - DUSK_S, "dusk"]
	return [(k + 1.0) * cyc + n, "ignite"]
