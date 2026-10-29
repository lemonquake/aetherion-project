extends Control

const Attach := preload("res://src/weapons/attachments.gd")
## A small, restrained reticle drawn where the weapon actually points (recoil kick and sway included), with
## short ticks that open with the current dispersion. Hidden while aiming through sights with a magnified optic.

var ch = null
var cam: Camera3D = null


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if ch == null or cam == null or not is_instance_valid(ch):
		return
	var off: Vector2 = ch.wpn.aim_offset_deg(Net.tick)
	var b: Basis = cam.global_transform.basis * Basis(Vector3.UP, deg_to_rad(-off.x)) * Basis(Vector3.RIGHT, deg_to_rad(off.y))
	var p := cam.global_position - b.z * 50.0
	if cam.is_position_behind(p):
		return
	var c := cam.unproject_position(p)
	var spread: float = ch.wpn.spread_deg(Vector2(ch.velocity.x, ch.velocity.z).length(), ch.crouching)
	var px_per_deg := get_viewport_rect().size.y / cam.fov
	var gap := maxf(spread * 0.5 * px_per_deg, 3.0)
	var col := Color(0.92, 0.94, 0.9, 0.75)
	var shadow := Color(0, 0, 0, 0.5)
	if ch.wpn.scoped() and ch.wpn.ads > 0.6:
		return  # the scope view draws its own reticle
	var sight: Dictionary = Attach.sight(ch.wpn.weapon())
	if not sight.is_empty() and ch.wpn.ads > 0.6:
		# Red dot or holographic ring projected in the sight window.
		var lit := Color(1.0, 0.15, 0.1, clampf((ch.wpn.ads - 0.6) / 0.3, 0.0, 1.0) * 0.95)
		var k := get_viewport_rect().size.y / 900.0
		if str(sight.get("reticle", "dot")) == "holo":
			draw_arc(c, 17.0 * k, 0.0, TAU, 48, lit, 1.6 * k, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * 17.0 * k, c + d * 21.0 * k, lit, 1.6 * k, true)
		draw_circle(c, 1.9 * k, lit)
		return
	draw_circle(c + Vector2(1, 1), 1.8, shadow)
	draw_circle(c, 1.6, col)
	if ch.wpn.ads < 0.6:
		for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + dir * gap + Vector2(1, 1), c + dir * (gap + 6.0) + Vector2(1, 1), shadow, 2.0)
			draw_line(c + dir * gap, c + dir * (gap + 6.0), col, 1.5)
