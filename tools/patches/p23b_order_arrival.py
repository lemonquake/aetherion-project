"""r23: an order counts as reached when the waypoint route ended at the nearest point the roads reach."""
import sys

P = sys.argv[1] if len(sys.argv) > 1 else "game/src/ai/bot_brain.gd"
s = open(P, encoding="utf-8", newline="").read()
CRLF = "\r\n" in s
s = s.replace("\r\n", "\n")


def rep(a, b):
    global s
    if s.count(a) != 1:
        raise SystemExit("patch anchor found %d times: %r" % (s.count(a), a[:80]))
    s = s.replace(a, b)


rep("var _wpdoor_t := 0.0\n", "var _wpdoor_t := 0.0\n"
    "var _ended_short := false         # the last walk ended at the nearest point the roads reach (the goal out of plain sight)\n")
rep("\t_wp_route = false\n\t_wp_prev = -1\n", "\t_wp_route = false\n\t_wp_prev = -1\n\t_ended_short = false\n")
rep("\t\t\tand not nav.line_clear(ch.global_position, goal):\n\t\tgoal = Vector3.INF\n\t\treturn\n",
    "\t\t\tand not nav.line_clear(ch.global_position, goal):\n\t\tgoal = Vector3.INF\n\t\t_ended_short = true\n\t\treturn\n")
old = ("\tvar path_done := path_i >= path.size() and not path.is_empty() and goal != Vector3.INF \t\tand "
       "Vector2(goal.x - ch.global_position.x, goal.z - ch.global_position.z).length() < 1.5\n")
rep(old, "\tvar path_done := (path_i >= path.size() and not path.is_empty() and goal != Vector3.INF \t\tand "
    "Vector2(goal.x - ch.global_position.x, goal.z - ch.global_position.z).length() < 1.5) \\\n"
    "\t\tor (goal == Vector3.INF and _ended_short)   # (r23) the route ended at the waypoint nearest the spot: as near as it gets\n")
if CRLF:
    s = s.replace("\n", "\r\n")
open(P, "w", encoding="utf-8", newline="").write(s)
print("patched", P)
