class_name Icons
## Small vector icons drawn into textures once (no icon font needed): navigation, platforms, actions.

static var _cache := {}


static func texture(name: String, size: int = 28, color: Color = Color.WHITE) -> Texture2D:
	var key := "%s|%d|%s" % [name, size, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var s := size * 2   # drawn at twice the size, then halved for smooth edges
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := color
	var u := float(s) / 24.0
	match name:
		"home":
			_poly(img, [Vector2(3, 11), Vector2(12, 3), Vector2(21, 11), Vector2(19, 11), Vector2(19, 21), Vector2(14, 21), Vector2(14, 15), Vector2(10, 15), Vector2(10, 21), Vector2(5, 21), Vector2(5, 11)], u, c)
		"play":
			_poly(img, [Vector2(7, 4), Vector2(20, 12), Vector2(7, 20)], u, c)
		"locker":
			# a T-shirt
			_poly(img, [Vector2(8, 3), Vector2(10, 5), Vector2(14, 5), Vector2(16, 3), Vector2(22, 7), Vector2(19, 11), Vector2(17, 10), Vector2(17, 21), Vector2(7, 21), Vector2(7, 10), Vector2(5, 11), Vector2(2, 7)], u, c)
		"profile":
			_circle(img, Vector2(12, 8), 4.5, u, c)
			_poly(img, [Vector2(4, 21), Vector2(5, 16), Vector2(9, 13.5), Vector2(15, 13.5), Vector2(19, 16), Vector2(20, 21)], u, c)
		"trophy":
			_poly(img, [Vector2(7, 3), Vector2(17, 3), Vector2(17, 9), Vector2(14, 14), Vector2(13, 17), Vector2(16, 18), Vector2(16, 21), Vector2(8, 21), Vector2(8, 18), Vector2(11, 17), Vector2(10, 14), Vector2(7, 9)], u, c)
			_ring(img, Vector2(6, 7), 3, 1.4, u, c)
			_ring(img, Vector2(18, 7), 3, 1.4, u, c)
		"settings":
			_ring(img, Vector2(12, 12), 5.5, 3.0, u, c)
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				var p := Vector2(12, 12) + d * 8.6
				var t := Vector2(-d.y, d.x)
				_poly(img, [p - t * 1.6 - d * 1.6, p + t * 1.6 - d * 1.6, p + t * 1.3 + d * 1.2, p - t * 1.3 + d * 1.2], u, c)
		"globe":
			_ring(img, Vector2(12, 12), 9, 1.6, u, c)
			_ellipse_ring(img, Vector2(12, 12), Vector2(4, 9), 1.5, u, c)
			_poly(img, [Vector2(3, 11.2), Vector2(21, 11.2), Vector2(21, 12.8), Vector2(3, 12.8)], u, c)
		"users":
			_circle(img, Vector2(9, 8), 3.6, u, c)
			_poly(img, [Vector2(2, 20), Vector2(3, 15), Vector2(6, 13), Vector2(12, 13), Vector2(15, 15), Vector2(16, 20)], u, c)
			_circle(img, Vector2(17, 7), 3, u, c * Color(1, 1, 1, 0.7))
			_poly(img, [Vector2(17, 12), Vector2(20, 13), Vector2(22, 17), Vector2(17.5, 17)], u, c * Color(1, 1, 1, 0.7))
		"plus":
			_poly(img, [Vector2(10.5, 4), Vector2(13.5, 4), Vector2(13.5, 10.5), Vector2(20, 10.5), Vector2(20, 13.5), Vector2(13.5, 13.5), Vector2(13.5, 20), Vector2(10.5, 20), Vector2(10.5, 13.5), Vector2(4, 13.5), Vector2(4, 10.5), Vector2(10.5, 10.5)], u, c)
		"refresh":
			_ring(img, Vector2(12, 12), 7.5, 2.2, u, c)
			_poly(img, [Vector2(16, 2), Vector2(22, 6), Vector2(15, 9)], u, c)
		"link":
			_ring(img, Vector2(8.5, 15.5), 4.5, 2, u, c)
			_ring(img, Vector2(15.5, 8.5), 4.5, 2, u, c)
		"phone":
			_poly(img, [Vector2(7, 2), Vector2(17, 2), Vector2(17, 22), Vector2(7, 22)], u, c)
			_poly(img, [Vector2(8.5, 4), Vector2(15.5, 4), Vector2(15.5, 18), Vector2(8.5, 18)], u, Color(0, 0, 0, 0), true)
		"monitor":
			_poly(img, [Vector2(2, 4), Vector2(22, 4), Vector2(22, 16), Vector2(2, 16)], u, c)
			_poly(img, [Vector2(3.5, 5.5), Vector2(20.5, 5.5), Vector2(20.5, 14.5), Vector2(3.5, 14.5)], u, Color(0, 0, 0, 0), true)
			_poly(img, [Vector2(10, 16), Vector2(14, 16), Vector2(15, 20), Vector2(9, 20)], u, c)
		"bot":
			_poly(img, [Vector2(5, 8), Vector2(19, 8), Vector2(19, 20), Vector2(5, 20)], u, c)
			_circle(img, Vector2(9.5, 13), 1.8, u, Color(0, 0, 0, 0), true)
			_circle(img, Vector2(14.5, 13), 1.8, u, Color(0, 0, 0, 0), true)
			_poly(img, [Vector2(11.2, 3), Vector2(12.8, 3), Vector2(12.8, 8), Vector2(11.2, 8)], u, c)
		"star":
			var pts := []
			for i in 10:
				var a2 := -PI / 2 + TAU * i / 10.0
				var r := 9.5 if i % 2 == 0 else 4.2
				pts.append(Vector2(12, 12.5) + Vector2(cos(a2), sin(a2)) * r)
			_poly(img, pts, u, c)
		"check":
			_poly(img, [Vector2(3, 12), Vector2(6, 9), Vector2(10, 13), Vector2(18, 5), Vector2(21, 8), Vector2(10, 19)], u, c)
		"dice":
			_poly(img, [Vector2(3, 3), Vector2(21, 3), Vector2(21, 21), Vector2(3, 21)], u, c)
			for p2 in [Vector2(7.5, 7.5), Vector2(16.5, 16.5), Vector2(12, 12), Vector2(16.5, 7.5), Vector2(7.5, 16.5)]:
				_circle(img, p2, 1.8, u, Color(0, 0, 0, 0), true)
		"none":
			_ring(img, Vector2(12, 12), 8, 2.2, u, c)
			_poly(img, [Vector2(6.2, 7.6), Vector2(7.6, 6.2), Vector2(17.8, 16.4), Vector2(16.4, 17.8)], u, c)
		"back":
			_poly(img, [Vector2(14, 4), Vector2(17, 7), Vector2(12, 12), Vector2(17, 17), Vector2(14, 20), Vector2(6, 12)], u, c)
		"exit":
			_poly(img, [Vector2(3, 3), Vector2(13, 3), Vector2(13, 6), Vector2(6, 6), Vector2(6, 18), Vector2(13, 18), Vector2(13, 21), Vector2(3, 21)], u, c)
			_poly(img, [Vector2(15, 7), Vector2(21, 12), Vector2(15, 17), Vector2(15, 13.5), Vector2(9, 13.5), Vector2(9, 10.5), Vector2(15, 10.5)], u, c)
		_:
			_circle(img, Vector2(12, 12), 6, u, c)
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _inside(p: Vector2, pts: Array) -> bool:
	var c := false
	var j := pts.size() - 1
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			c = not c
		j = i
	return c


static func _poly(img: Image, pts: Array, u: float, c: Color, erase: bool = false) -> void:
	var sp := pts.map(func(p): return p * u)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in sp:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, img.get_height())):
		for x in range(maxi(int(lo.x), 0), mini(int(hi.x) + 1, img.get_width())):
			if _inside(Vector2(x + 0.5, y + 0.5), sp):
				img.set_pixel(x, y, c)


static func _circle(img: Image, ctr: Vector2, r: float, u: float, c: Color, erase: bool = false) -> void:
	var cc := ctr * u
	var rr := r * u
	for y in range(maxi(int(cc.y - rr), 0), mini(int(cc.y + rr) + 1, img.get_height())):
		for x in range(maxi(int(cc.x - rr), 0), mini(int(cc.x + rr) + 1, img.get_width())):
			if Vector2(x + 0.5, y + 0.5).distance_to(cc) <= rr:
				img.set_pixel(x, y, c)


static func _ring(img: Image, ctr: Vector2, r: float, w: float, u: float, c: Color) -> void:
	var cc := ctr * u
	var r0 := (r - w * 0.5) * u
	var r1 := (r + w * 0.5) * u
	for y in range(maxi(int(cc.y - r1), 0), mini(int(cc.y + r1) + 1, img.get_height())):
		for x in range(maxi(int(cc.x - r1), 0), mini(int(cc.x + r1) + 1, img.get_width())):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(cc)
			if d >= r0 and d <= r1:
				img.set_pixel(x, y, c)


static func _ellipse_ring(img: Image, ctr: Vector2, r: Vector2, w: float, u: float, c: Color) -> void:
	var cc := ctr * u
	var rr := r * u
	for y in range(maxi(int(cc.y - rr.y - w * u), 0), mini(int(cc.y + rr.y + w * u) + 1, img.get_height())):
		for x in range(maxi(int(cc.x - rr.x - w * u), 0), mini(int(cc.x + rr.x + w * u) + 1, img.get_width())):
			var q := Vector2((x + 0.5 - cc.x) / rr.x, (y + 0.5 - cc.y) / rr.y)
			if absf(q.length() - 1.0) * minf(rr.x, rr.y) <= w * u * 0.5:
				img.set_pixel(x, y, c)
