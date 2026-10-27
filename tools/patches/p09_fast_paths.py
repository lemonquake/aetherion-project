"""Patch: bot path search on flat arrays (no per-call dictionaries), weighted A* with a partial path to the closest
reachable cell, and a shared budget of path searches per physics tick so many bots cannot stall the server."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


nav = open(G + 'src/ai/nav_grid.gd', encoding='utf-8').read()
start = nav.index('func find_path(')
end = nav.index('func _world(')
nav = nav[:start] + '''func find_path(from: Vector3, to: Vector3, max_expand: int = 9000) -> Array:
	## Weighted A* (w = 1.3) over the grid. Per-cell scratch arrays persist between calls and are invalidated by a
	## generation stamp, so a search allocates nothing proportional to the map. If the goal is not reached within
	## the budget, the path leads to the reached cell closest to it.
	var s := _nearest_walkable(_idx(from))
	var g := _nearest_walkable(_idx(to))
	if s == g:
		return [to]
	if _g.size() != n * n:
		_g.resize(n * n)
		_came.resize(n * n)
		_stamp.resize(n * n)
	_gen += 1
	var si := s.y * n + s.x
	var gi := g.y * n + g.x
	_g[si] = 0.0
	_came[si] = -1
	_stamp[si] = _gen
	var open := []  # binary heap of [f, idx, g]
	_push(open, [_h(s, g) * 1.3, si, 0.0])
	var best_i := si
	var best_h := _h(s, g)
	var expanded := 0
	var found := false
	while not open.is_empty() and expanded < max_expand:
		var cur: Array = _pop(open)
		var ci: int = cur[1]
		var cg: float = cur[2]
		if cg > _g[ci] + 1e-4:
			continue  # stale heap entry
		if ci == gi:
			found = true
			break
		expanded += 1
		var cx := ci % n
		var cz := ci / n
		for k in 8:
			var dx: int = DX[k]
			var dz: int = DZ[k]
			var nx: int = cx + dx
			var nz: int = cz + dz
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				continue
			var ni := nz * n + nx
			if walk[ni] == 0:
				continue
			if dx != 0 and dz != 0 and (walk[cz * n + nx] == 0 or walk[nz * n + cx] == 0):
				continue
			var ng: float = cg + (1.4142 if dx != 0 and dz != 0 else 1.0)
			if _stamp[ni] != _gen or ng < _g[ni]:
				_stamp[ni] = _gen
				_g[ni] = ng
				_came[ni] = ci
				var hh := _h(Vector2i(nx, nz), g)
				if hh < best_h:
					best_h = hh
					best_i = ni
				_push(open, [ng + hh * 1.3, ni, ng])
	var end_i := gi if found else best_i
	if end_i == si:
		return [to]
	var cells := []
	var k2 := end_i
	while k2 != si and k2 >= 0:
		cells.append(k2)
		k2 = _came[k2]
	cells.reverse()
	# Smooth: keep only the cells where straight walking would leave the walkable area.
	var out := []
	var anchor := s
	var prev := s
	for ci in cells:
		var c := Vector2i(ci % n, ci / n)
		if not _clear(anchor, c):
			out.append(_world(prev))
			anchor = prev
		prev = c
	if not found:
		out.append(_world(prev))
	out.append(to)
	return out


''' + nav[end:]
nav = nav.replace('''var walk: PackedByteArray
''', '''var walk: PackedByteArray
var _g := PackedFloat32Array()
var _came := PackedInt32Array()
var _stamp := PackedInt32Array()
var _gen := 0
const DX := [1, -1, 0, 0, 1, 1, -1, -1]
const DZ := [0, 0, 1, -1, 1, -1, 1, -1]
''', 1)
open(G + 'src/ai/nav_grid.gd', 'w', encoding='utf-8').write(nav)
print('rewrote find_path')

patch('src/ai/bot_brain.gd', [
    ('''static var nav = null
''', '''static var nav = null
## Path searches are shared out: at most SEARCHES_PER_TICK per physics tick across all bots; the rest wait a tick
## or two and walk straight toward their goal meanwhile.
const SEARCHES_PER_TICK := 2
static var _budget_tick := -1
static var _budget_used := 0
var _path_pending := false
'''),
    ('''func _set_goal(g: Vector3) -> void:
	goal = g
	path = nav.find_path(ch.global_position, g)
	path_i = 0
	_repath_t = 6.0''', '''func _set_goal(g: Vector3) -> void:
	goal = g
	path = []
	path_i = 0
	_path_pending = true
	_repath_t = 6.0
	_ensure_path()


func _ensure_path() -> void:
	if not _path_pending or goal == Vector3.INF:
		return
	if _budget_tick != Net.tick:
		_budget_tick = Net.tick
		_budget_used = 0
	if _budget_used >= SEARCHES_PER_TICK:
		return
	_budget_used += 1
	_path_pending = false
	path = nav.find_path(ch.global_position, goal)
	path_i = 0'''),
    ('''func _move(cmd: Dictionary, dt: float, slow: bool) -> void:
	if state == "loot" and plan_i < plan.size():''', '''func _move(cmd: Dictionary, dt: float, slow: bool) -> void:
	_ensure_path()
	if state == "loot" and plan_i < plan.size():'''),
])
