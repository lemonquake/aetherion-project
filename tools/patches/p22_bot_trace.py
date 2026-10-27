"""Patch: --bottrace=<name part> prints one bot's plan step, position, target and door state every second."""
p = 'A:/Python/aetherion-project/game/src/ai/bot_brain.gd'
s = open(p, encoding='utf-8').read()
old = '''	_lights(cmd)
	yaw = float(cmd.yaw)
	pitch = float(cmd.pitch)
	return cmd'''
new = '''	_lights(cmd)
	yaw = float(cmd.yaw)
	pitch = float(cmd.pitch)
	_trace(cmd, dt)
	return cmd


var _trace_t := 0.0


func _trace(cmd: Dictionary, dt: float) -> void:
	var who = Game.arg("bottrace")
	if who == null or str(who) not in ch.pname:
		return
	_trace_t -= dt
	if _trace_t > 0.0:
		return
	_trace_t = 1.0
	var step: Dictionary = plan[plan_i] if plan_i < plan.size() else {}
	var extra := ""
	if step.has("door"):
		var dn = world.map.dyn.doors[int(step.door)].get("node")
		extra = " door %d target %.2f locked %s" % [int(step.door), dn.target if dn else -1.0, str(dn.locked) if dn else "?"]
	if step.has("search"):
		var c: Dictionary = world.map.dyn.containers[int(step.search)]
		var t: Dictionary = world.interaction.target(ch, cmd)
		extra = " container %d at %s dist %.2f; use ray sees %s" % [int(step.search), str((c.pos as Vector3).snapped(Vector3.ONE * 0.01)),
			ch.eye_position().distance_to(c.pos), str(t.get("kind", "-")) + str(t.get("id", ""))]
	print("[bot %s] %s step %d/%d %s at %s -> %s (%.1f m) path %d/%d stuck %.1f btn %d%s" % [ch.pname, state, plan_i, plan.size(),
		"nav" if step.get("nav", false) else ("search" if step.has("search") else ("door" if step.has("door") else "walk")),
		str(ch.global_position.snapped(Vector3.ONE * 0.1)), str((step.get("p", goal) as Vector3).snapped(Vector3.ONE * 0.1)),
		Vector2(ch.global_position.x - (step.get("p", goal) as Vector3).x, ch.global_position.z - (step.get("p", goal) as Vector3).z).length(),
		path_i, path.size(), _stuck_t, int(cmd.btn), extra])'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
