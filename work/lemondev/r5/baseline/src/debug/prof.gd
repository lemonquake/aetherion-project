class_name Prof
## Section timer for the perf autotest: Prof.begin("name") ... Prof.end("name") adds the elapsed microseconds to
## Prof.acc["name"]. Costs one static bool check when off (the default).

static var on := false
static var acc := {}
static var peak := {}
static var _t := {}


static func begin(key: String) -> void:
	if on:
		_t[key] = Time.get_ticks_usec()


static func end(key: String) -> void:
	if on:
		var d := Time.get_ticks_usec() - int(_t.get(key, Time.get_ticks_usec()))
		acc[key] = int(acc.get(key, 0)) + d
		if d > int(peak.get(key, 0)):
			peak[key] = d


static func reset() -> void:
	acc.clear()
	peak.clear()
	_t.clear()
