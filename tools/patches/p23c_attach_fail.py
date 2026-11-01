"""r23: a bot's own position is checked with a cylinder thinner than its body; route failures are counted."""
W = "game/src/ai/waypoints.gd"
N = "game/src/debug/nav_watch.gd"
s = open(W, encoding="utf-8", newline="").read()


def rep(a, b):
    global s
    if s.count(a) != 1:
        raise SystemExit("anchor found %d times: %r" % (s.count(a), a[:80]))
    s = s.replace(a, b)


rep("const R_TIGHT := 0.31\n", "const R_TIGHT := 0.31\n"
    "const R_FROM := 0.26          # from where a bot stands: thinner than the body (it may stand against a wall already)\n")
rep("\t\tif tested > 8:\n\t\t\tbreak\n\t\tif clear(p, q):\n\t\t\treturn i\n\treturn -1",
    "\t\tif tested > 8:\n\t\t\tbreak\n\t\tif clear(p, q, R_FROM):\n\t\t\treturn i\n\treturn -1")
rep("static func clear(a: Vector3, b: Vector3) -> bool:", "static func clear(a: Vector3, b: Vector3, r: float = R_TIGHT) -> bool:")
rep("\t\treturn sweep(a, Vector3(b.x, a.y, b.z), R_TIGHT)", "\t\treturn sweep(a, Vector3(b.x, a.y, b.z), r)")
rep("\treturn sweep(Vector3(a.x, a.y + lift, a.z), Vector3(b.x, b.y + maxf(a.y - b.y, 0.0), b.z), R_TIGHT)",
    "\treturn sweep(Vector3(a.x, a.y + lift, a.z), Vector3(b.x, b.y + maxf(a.y - b.y, 0.0), b.z), r)")
rep("\tvar gs := _goal_nodes(to)\n\tif gs.is_empty():\n\t\treturn {}",
    "\tvar gs := _goal_nodes(to)\n\tif gs.is_empty():\n\t\t_fail(\"no_goal_node\", to)\n\t\treturn {}")
rep("\t\tlead = _nearest_main(from)\n\t\tif lead < 0:\n\t\t\treturn {}",
    "\t\tlead = _nearest_main(from)\n\t\tif lead < 0:\n\t\t\t_fail(\"no_start_node\", from)\n\t\t\treturn {}")
rep("\tif best.is_empty():\n\t\treturn {}\n\tvar pts := []", "\tif best.is_empty():\n\t\t_fail(\"no_path\", to)\n\t\treturn {}\n\tvar pts := []")
rep("static func attach(p: Vector3, _start: bool) -> int:", '''static func _fail(why_s: String, p: Vector3) -> void:
	var f: Dictionary = stats.get("route_fail", {})
	f[why_s] = int(f.get(why_s, 0)) + 1
	stats.route_fail = f
	if int(f[why_s]) <= 5 and (Game.arg("navwatch") != null or Game.arg("bottrace") != null):
		print("[waypoints] no route (%s) at %s" % [why_s, str(p.snapped(Vector3.ONE * 0.1))])


static func attach(p: Vector3, _start: bool) -> int:''')
open(W, "w", encoding="utf-8", newline="").write(s)

t = open(N, encoding="utf-8", newline="").read()
a = '\ttotals["waypoints"]["edge_reports"] = int(W.stats.get("stuck_reports", 0))\n'
assert t.count(a) == 1
t = t.replace(a, a + '\ttotals["waypoints"]["route_fail"] = W.stats.get("route_fail", {})\n')
open(N, "w", encoding="utf-8", newline="").write(t)
print("patched")
