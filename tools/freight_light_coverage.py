"""Freight Delight light coverage (r22): where can a player not see where they are going?

Builds the map in memory with tools/make_freight_map.py (nothing is written to the .map), records every brush, finds
the walkable floor cells on a 1 m grid - the ground (tops near y = 0: the yard, shack and container floors) and the
second floor (tops near L1 = 3.2 m reachable from the three stairs) - and estimates the light at each cell 1 m above
its floor from every light entity, the way the game lights them (src/world/lighting.gd via map_builder): an omni's
energy * (1 - (d/range)^4)^2 * d^-1.4, a flood's spot cone (45 deg, aimed by angle/pitch, spot attenuation 0.9) on
top; a light is blocked when the line from it to the cell passes through a solid (0.5 m voxels of every drawn brush).
Values are weighted by the light colour's luminance.

    python -I tools/freight_light_coverage.py [--tag=before] [--without-r22] [--dark=0.04]

Writes work/r22/lights/coverage_<tag>.png (top-down heat maps, ground and second floor), coverage_<tag>.json and
coverage_<tag>.md (share of walkable cells below the darkness threshold, the darkest 20 cells, the dark clusters).
--without-r22 leaves the r22 lights group out (the "before" picture from the current generator).
"""
import json
import math
import os
import sys
from collections import deque

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_freight_map as fm   # noqa: E402

ROOT = fm.ROOT
OUT_DIR = ROOT / "work" / "r22" / "lights"
X0, X1, Z0, Z1 = -62.0, 62.0, -42.0, 41.75     # the play area (clip bounds)
CELL = 1.0
VOX = 0.5
VY0, VY1 = -1.0, 15.0
CLEAR = 1.7       # head room needed over a floor
STEP = 0.45       # walkable height change between neighbouring cells (steps, pallet steps, the r21 tread plate)
EYE = 1.0         # light is sampled this far above the floor

_rec = []         # brush -> dict
_stairs = []      # (x, z) of each flight's top


def _hull_wrap(orig):
    def hull_brush(verts_m, tex, face_tex=None, uv=None, fit_faces=(), vfit=None, key=""):
        b = orig(verts_m, tex, face_tex, uv, fit_faces, vfit, key)
        xs = [p[0] for p in verts_m]
        ys = [p[1] for p in verts_m]
        zs = [p[2] for p in verts_m]
        corners = {(round(x, 3), round(y, 3), round(z, 3)) for x in (min(xs), max(xs)) for y in (min(ys), max(ys)) for z in (min(zs), max(zs))}
        exact = {(round(p[0], 3), round(p[1], 3), round(p[2], 3)) for p in verts_m} == corners
        b._aabb = (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs))
        b._exact = exact
        b._p1z = b.faces[0][0][2]
        return b
    return hull_brush


def _stairs_wrap(orig):
    def stairs(x0, x1, z0, z1, rise_dir, y0, y1, tex, side_tex=None, solid=True, name="Stair", ramp_tex="freight/clip_concrete"):
        n = max(1, int(round((y1 - y0) / fm.STEP_RISE)))
        span = (n - 1) * fm.STEP_RUN
        top = {"n": ((x0 + x1) / 2, z1 - span - 0.4), "s": ((x0 + x1) / 2, z0 + span + 0.4),
               "w": (x1 - span - 0.4, (z0 + z1) / 2), "e": (x0 + span + 0.4, (z0 + z1) / 2)}[rise_dir]
        _stairs.append((top[0], top[1], y1, name))
        return orig(x0, x1, z0, z1, rise_dir, y0, y1, tex, side_tex, solid, name, ramp_tex)
    return stairs


def build(without_r22):
    fm.hull_brush = _hull_wrap(fm.hull_brush)
    fm.stairs = _stairs_wrap(fm.stairs)
    if without_r22 and hasattr(fm, "r22_lights"):
        fm.r22_lights = lambda: None
    fm.build()
    solids = []      # (aabb, collide, visible, exact)
    for e in [fm.WORLD] + list(fm.LAYERS.values()) + fm.GROUPS + fm.ENTITIES:
        cls = e.props.get("classname")
        for b in e.brushes:
            if not hasattr(b, "_aabb"):
                continue
            dy = (b.faces[0][0][2] - b._p1z) / fm.U       # raised by lift() after it was made
            x0, y0, z0, x1, y1, z1 = b._aabb
            texs = {f[3] for f in b.faces}
            clip = all(t.startswith("freight/clip") or t == "freight/skip" for t in texs)
            collide = cls not in ("func_illusionary", "func_stairs")
            visible = cls != "func_illusionary" and not clip
            solids.append(((x0, y0 + dy, z0, x1, y1 + dy, z1), collide, visible, b._exact, b))
    lights = []
    r22_gid = None
    for g in fm.GROUPS:
        if g.props.get("_tb_name") == "r22 lights":
            r22_gid = g.props["_tb_id"]
    for e in fm.ENTITIES:
        if e.props.get("classname") != "light":
            continue
        qx, qy, qz = [float(t) for t in e.props["origin"].split()]
        c = [float(t) for t in e.props["_color"].split()]
        lights.append({"pos": (qx / fm.U, qz / fm.U, -qy / fm.U), "kind": e.props["kind"], "energy": float(e.props["energy"]),
                       "range": float(e.props["range"]), "lum": (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255.0,
                       "angle": float(e.props.get("angle", 0)), "pitch": float(e.props.get("pitch", 90)),
                       "cone": float(e.props.get("cone", 45)), "fault": e.props.get("fault", ""),
                       "new": r22_gid is not None and e.props.get("_tb_group") == r22_gid})
    spawns = []
    for e in fm.ENTITIES:
        if e.props.get("classname") == "info_team_spawn":
            qx, qy, qz = [float(t) for t in e.props["origin"].split()]
            spawns.append((qx / fm.U, -qy / fm.U))
    return solids, lights, spawns


def voxels(solids):
    nx = int(round((X1 - X0 + 2) / VOX))
    nz = int(round((Z1 - Z0 + 4) / VOX))
    ny = int(round((VY1 - VY0) / VOX))
    occ = np.zeros((nx, ny, nz), dtype=bool)
    ox, oz = X0 - 1, Z0 - 2
    for (a, collide, visible, exact, b) in solids:
        if not visible:
            continue
        x0, y0, z0, x1, y1, z1 = a
        i0, i1 = int(math.floor((x0 - ox) / VOX + 1e-4)), int(math.ceil((x1 - ox) / VOX - 1e-4))
        j0, j1 = int(math.floor((y0 - VY0) / VOX + 1e-4)), int(math.ceil((y1 - VY0) / VOX - 1e-4))
        k0, k1 = int(math.floor((z0 - oz) / VOX + 1e-4)), int(math.ceil((z1 - oz) / VOX - 1e-4))
        i0, j0, k0 = max(i0, 0), max(j0, 0), max(k0, 0)
        i1, j1, k1 = min(i1, nx), min(j1, ny), min(k1, nz)
        if i1 <= i0 or j1 <= j0 or k1 <= k0:
            continue
        if exact:
            occ[i0:i1, j0:j1, k0:k1] = True
            continue
        # a slope / prism (a roof, a ramp, a drum): the voxels whose centres lie within 0.3 m inside all its planes
        gi, gj, gk = np.meshgrid(np.arange(i0, i1), np.arange(j0, j1), np.arange(k0, k1), indexing="ij")
        c = np.stack([ox + (gi + 0.5) * VOX, VY0 + (gj + 0.5) * VOX, oz + (gk + 0.5) * VOX], -1).reshape(-1, 3)
        inside = np.ones(len(c), dtype=bool)
        for f in b.faces:
            p1, p2, p3 = [np.array((q[0] / fm.U, q[2] / fm.U, -q[1] / fm.U)) for q in f[:3]]
            n = np.cross(p3 - p1, p2 - p1)
            n = n / (np.linalg.norm(n) or 1.0)
            inside &= (c - p1) @ n <= 0.3
        occ[gi.reshape(-1)[inside], gj.reshape(-1)[inside], gk.reshape(-1)[inside]] = True
    return occ, (ox, oz)


def surfaces(solids):
    """Per 1 m cell: the walkable floor tops (with head room)."""
    nx = int(round((X1 - X0) / CELL))
    nz = int(math.ceil((Z1 - Z0) / CELL))
    cols = [[[] for _ in range(nz)] for _ in range(nx)]
    for (a, collide, visible, exact, _b) in solids:
        if not collide:
            continue
        x0, y0, z0, x1, y1, z1 = a
        i0 = max(int(math.ceil((x0 - X0) / CELL - 0.5)), 0)
        i1 = min(int(math.floor((x1 - X0) / CELL - 0.5)), nx - 1)
        k0 = max(int(math.ceil((z0 - Z0) / CELL - 0.5)), 0)
        k1 = min(int(math.floor((z1 - Z0) / CELL - 0.5)), nz - 1)
        for i in range(i0, i1 + 1):
            for k in range(k0, k1 + 1):
                cols[i][k].append((y0, y1, exact))
    tops = {}
    for i in range(nx):
        for k in range(nz):
            iv = cols[i][k]
            cand = [y1 for (y0, y1, ex) in iv if ex]
            out = []
            for t in sorted(set(round(c, 3) for c in cand)):
                if t < -0.2 or t > 4.0:
                    continue
                if any(y0 < t + CLEAR and y1 > t + 0.05 for (y0, y1, ex) in iv):
                    continue
                out.append(t)
            if out:
                tops[(i, k)] = out
    return tops, nx, nz


def reach(tops, nx, nz, seeds, lo, hi):
    """Floor nodes (cell, top) with lo <= top <= hi reachable from the seeds by STEP-high moves."""
    seen = set()
    q = deque()
    for (i, k) in seeds:
        for t in tops.get((i, k), []):
            if lo <= t <= hi and ((i, k), t) not in seen:
                seen.add(((i, k), t))
                q.append(((i, k), t))
    while q:
        (i, k), t = q.popleft()
        for (di, dk) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c = (i + di, k + dk)
            for t2 in tops.get(c, []):
                if lo <= t2 <= hi and abs(t2 - t) <= STEP and (c, t2) not in seen:
                    seen.add((c, t2))
                    q.append((c, t2))
    return seen


def cell_of(x, z):
    return (int(math.floor((x - X0) / CELL)), int(math.floor((z - Z0) / CELL)))


def centre(i, k):
    return (X0 + (i + 0.5) * CELL, Z0 + (k + 0.5) * CELL)


def light_at(points, lights, occ, origin):
    """points: (N, 3) array; returns the summed light per point."""
    total = np.zeros(len(points), dtype=np.float64)
    for L in lights:
        idx, val = contrib(L, points, occ, origin)
        total[idx] += val
    return total


def contrib(L, points, occ, origin):
    """One light's share at the points: (indices, values). L["normal"] (a wall lamp's face): only the half in front."""
    ox, oz = origin
    nxv, nyv, nzv = occ.shape
    p = np.array(L["pos"])
    rel = points - p
    d = np.sqrt((rel ** 2).sum(1))
    m = d < L["range"]
    if "normal" in L:
        m &= (rel @ np.array(L["normal"])) > 0.0
    if not m.any():
        return np.zeros(0, dtype=int), np.zeros(0)
    idx = np.where(m)[0]
    dd = np.maximum(d[idx], 0.75)
    att = np.maximum(1.0 - (dd / L["range"]) ** 4, 0.0) ** 2 * dd ** -1.4
    if L["kind"] in ("flood", "street", "down", "shaft"):
        a = math.radians(L["angle"])
        pi = math.radians(L["pitch"])
        aim = np.array([math.cos(a) * math.cos(pi), -math.sin(pi), -math.sin(a) * math.cos(pi)])
        cosang = (rel[idx] @ aim) / np.maximum(d[idx], 1e-6)
        cut = math.cos(math.radians(L["cone"]))
        rim = np.clip((1.0 - np.maximum(cosang, cut)) / (1.0 - cut), 1e-4, 1.0)
        att = att * (1.0 - rim ** 0.9) * (cosang > cut)
    # line of sight through the voxels (skip 0.6 m at the lamp: its own wall / fitting, 0.4 m at the floor cell)
    dmax = float(d[idx].max())
    ns = max(int(dmax / 0.3), 2)
    s = np.linspace(0.0, 1.0, ns)[None, :]
    segs = p[None, None, :] + rel[idx][:, None, :] * s[:, :, None]
    along = d[idx][:, None] * s
    keep = (along > 0.6) & (along < d[idx][:, None] - 0.4)
    vi = ((segs[..., 0] - ox) / VOX).astype(int)
    vj = ((segs[..., 1] - VY0) / VOX).astype(int)
    vk = ((segs[..., 2] - oz) / VOX).astype(int)
    inside = (vi >= 0) & (vi < nxv) & (vj >= 0) & (vj < nyv) & (vk >= 0) & (vk < nzv)
    hit = np.zeros(vi.shape, dtype=bool)
    ok = inside & keep
    hit[ok] = occ[vi[ok], vj[ok], vk[ok]]
    blocked = hit.any(1)
    val = L["energy"] * att * L["lum"] * (~blocked)
    return idx, val


def mounts(solids, x, z, floor_y, upper):
    """Where a fitting could go near the cell centre (x, z): on a wall face at mount height, or hanging under
    something overhead. Returns [(kind, pos, normal or None, what)]."""
    hm = floor_y + (2.2 if upper else 2.5)
    out = []
    best = None
    for (a, collide, visible, exact, _b) in solids:
        if not (collide and visible and exact):
            continue
        x0, y0, z0, x1, y1, z1 = a
        if y0 > hm - 0.3 or y1 < hm + 0.1:
            continue
        px, pz = min(max(x, x0), x1), min(max(z, z0), z1)
        dd = math.hypot(px - x, pz - z)
        if dd > 0.95 or dd < 1e-3:
            continue
        if abs(px - x) >= abs(pz - z):      # an x face (normal along x)
            if z1 - z0 < 0.8:
                continue
            nrm = (1.0 if x > px else -1.0, 0.0, 0.0)
            pos = (px + 0.12 * nrm[0], hm, min(max(z, z0 + 0.25), z1 - 0.25))
        else:
            if x1 - x0 < 0.8:
                continue
            nrm = (0.0, 0.0, 1.0 if z > pz else -1.0)
            pos = (min(max(x, x0 + 0.25), x1 - 0.25), hm, pz + 0.12 * nrm[2])
        if best is None or dd < best[0]:
            best = (dd, ("wall", pos, nrm, "%.2f..%.2f" % (y0, y1)))
    if best:
        out.append(best[1])
    low = floor_y + 2.95
    over = None
    for (a, collide, visible, exact, _b) in solids:
        if not (visible and exact):
            continue
        x0, y0, z0, x1, y1, z1 = a
        if x0 <= x <= x1 and z0 <= z <= z1 and low <= y0 <= floor_y + 4.2:
            if over is None or y0 < over:
                over = y0
    if over is not None:
        out.append(("hang", (x, over - 0.72, z), None, "under %.2f" % over))
    return out


def suggest(solids, cells_pts, vals, occ, origin, thr, n_pick, path):
    """Greedy: the mountable fittings that take away the most darkness (sum of min(light, thr) gained)."""
    pts = np.array([p for (_c, p, _u) in cells_pts])
    base = np.array(vals)
    cand = []
    seen = set()
    for i, (c, p, upper) in enumerate(cells_pts):
        if base[i] > thr * 1.5:
            continue
        for (kind, pos, nrm, what) in mounts(solids, p[0], p[2], p[1] - EYE, upper):
            key = (kind, round(pos[0] * 2), round(pos[1] * 2), round(pos[2] * 2))
            if key in seen:
                continue
            seen.add(key)
            L = {"pos": pos, "kind": "lamp" if kind == "wall" else "bulb", "energy": 1.0 * fm.LAMP_K, "range": 8.0,
                 "lum": 0.74, "mount": kind, "what": what, "upper": upper}
            if nrm:
                L["normal"] = nrm
            idx, val = contrib(L, pts, occ, origin)
            if len(idx):
                cand.append((L, idx, val))
    cur = base.copy()
    picks = []
    for _ in range(n_pick):
        best = None
        for j, (L, idx, val) in enumerate(cand):
            g = float((np.minimum(cur[idx] + val, thr) - np.minimum(cur[idx], thr)).sum())
            if best is None or g > best[0]:
                best = (g, j)
        if best is None or best[0] <= 0.0:
            break
        L, idx, val = cand.pop(best[1])
        cur[idx] += val
        picks.append((best[0], L))
    nl = chr(10)
    with open(path, "w", encoding="utf-8", newline=nl) as f:
        f.write("# Suggested fittings (greedy, %d candidates)" % len(seen) + nl + nl
                + "| # | gain | mount | x | y | z | normal | on |" + nl + "|---|---|---|---|---|---|---|---|" + nl)
        for k, (g, L) in enumerate(picks):
            f.write("| %d | %.2f | %s%s | %.2f | %.2f | %.2f | %s | %s |" % (k, g, L["mount"], " (L1)" if L["upper"] else "", L["pos"][0], L["pos"][1],
                                                                     L["pos"][2], L.get("normal", ""), L["what"]) + nl)
    for k, (g, L) in enumerate(picks):
        print("%2d gain %6.2f %-5s %s (%.2f, %.2f, %.2f) n=%s %s" % (k, g, L["mount"], "L1" if L["upper"] else "  ", L["pos"][0], L["pos"][1], L["pos"][2], L.get("normal", ""), L["what"]))
    dark_after = int((cur < thr).sum())
    print("suggested %d: dark cells %d -> %d of %d" % (len(picks), int((base < thr).sum()), dark_after, len(base)))


def clusters(cells, dark):
    """8-connected clusters of dark cells: [(size, cx, cz, x0, z0, x1, z1, mean light)]."""
    dset = {c for c in cells if dark[c]}
    out = []
    seen = set()
    for c in dset:
        if c in seen:
            continue
        comp = []
        q = deque([c])
        seen.add(c)
        while q:
            a = q.popleft()
            comp.append(a)
            for di in (-1, 0, 1):
                for dk in (-1, 0, 1):
                    b = (a[0] + di, a[1] + dk)
                    if b in dset and b not in seen:
                        seen.add(b)
                        q.append(b)
        xs = [centre(*a)[0] for a in comp]
        zs = [centre(*a)[1] for a in comp]
        out.append((len(comp), sum(xs) / len(xs), sum(zs) / len(zs), min(xs), min(zs), max(xs), max(zs), comp))
    out.sort(key=lambda r: -r[0])
    return out


def heatmap(path, nx, nz, floors, solids_top, lights, dark_thr, title):
    from PIL import Image, ImageDraw
    px = 7
    pad = 24
    W = nx * px
    H = nz * px
    img = Image.new("RGB", (W + 2 * pad, 2 * (H + pad) + pad + 30), (10, 10, 14))
    d = ImageDraw.Draw(img)
    d.text((pad, 6), title, fill=(235, 235, 235))
    stops = np.array([[8, 8, 40], [40, 20, 110], [140, 30, 120], [220, 80, 50], [250, 170, 40], [255, 245, 170]], dtype=np.float32)
    for fi, (name, vals) in enumerate(floors):
        oy = 30 + fi * (H + pad)
        arr = np.zeros((nz, nx, 3), dtype=np.uint8)
        arr[:, :] = (28, 28, 32)
        for (i, k), top in solids_top.items():
            if fi == 0 and top > 0.6:
                arr[k, i] = (58, 58, 64) if top < 4.0 else (78, 78, 86)
            if fi == 1 and top > 3.6:
                arr[k, i] = (78, 78, 86)
        for (i, k), v in vals.items():
            t = math.log10(max(v, 1e-3) / 1e-3) / 3.3       # 0.001 .. 2: log scale
            t = min(max(t, 0.0), 1.0) * (len(stops) - 1)
            a = min(int(t), len(stops) - 2)
            col = stops[a] + (stops[a + 1] - stops[a]) * (t - a)
            arr[k, i] = col.astype(np.uint8)
            if v < dark_thr:
                arr[k, i] = (arr[k, i] * 0.6 + np.array([0, 90, 160]) * 0.4).astype(np.uint8)
        im = Image.fromarray(arr).resize((W, H), Image.NEAREST)
        img.paste(im, (pad, oy))
        d.text((pad + 4, oy + 4), name, fill=(255, 255, 255))
        for L in lights:
            x, y, z = L["pos"]
            if (fi == 0 and y > fm.L1 + 0.5) or (fi == 1 and y < fm.L1 + 0.5 and L["kind"] != "flood"):
                continue
            cx = pad + (x - X0) / CELL * px
            cy = oy + (z - Z0) / CELL * px
            r = 4 if L["kind"] == "flood" else 2
            col = (80, 255, 120) if L.get("new") else (255, 255, 255)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, fill=col if L.get("new") else None)
    d.text((pad, img.size[1] - 18), "log light 0.001..2 (navy..yellow); blue tint = below %.3f; dark grey = solid; white rings = lights, green = r22" % dark_thr,
           fill=(200, 200, 200))
    img.save(path)


def main():
    tag = "now"
    dark_thr = 0.04
    without = "--without-r22" in sys.argv
    for a in sys.argv[1:]:
        if a.startswith("--tag="):
            tag = a.split("=", 1)[1]
        elif a.startswith("--dark="):
            dark_thr = float(a.split("=", 1)[1])
    solids, lights, spawns = build(without)
    occ, origin = voxels(solids)
    tops, nx, nz = surfaces(solids)
    ground = reach(tops, nx, nz, [cell_of(x, z) for (x, z) in spawns], -0.2, 1.3)
    seeds = []
    for (sx, sz, sy, nm) in _stairs:
        ci, ck = cell_of(sx, sz)
        for di in range(-2, 3):
            for dk in range(-2, 3):
                seeds.append((ci + di, ck + dk))
    upper = reach(tops, nx, nz, seeds, fm.L1 - 0.45, fm.L1 + 0.45)
    floors = []
    all_pts = []
    all_vals = []
    report = {"tag": tag, "dark_threshold": dark_thr, "lights": len(lights), "lights_r22": sum(1 for L in lights if L["new"]),
              "floors": {}}
    md = ["# Freight Delight light coverage: %s\n" % tag,
          "tools/freight_light_coverage.py%s. %d lights (%d in r22 lights). Light 1 m above the floor; dark = below %.3f "
          "(about a 1.4-energy bulb seen from 7 m)." % (" --without-r22" if without else "", len(lights), report["lights_r22"], dark_thr), ""]
    top_solid = {}
    for (i, k), ts in tops.items():
        top_solid[(i, k)] = max(ts)
    for name, nodes in (("ground", ground), ("second floor (L1)", upper)):
        best = {}
        for (c, t) in nodes:
            if c not in best or abs(t - (0 if name == "ground" else fm.L1)) < abs(best[c] - (0 if name == "ground" else fm.L1)):
                best[c] = t
        cells = sorted(best)
        pts = np.array([(centre(*c)[0], best[c] + EYE, centre(*c)[1]) for c in cells])
        val = light_at(pts, lights, occ, origin) if len(cells) else np.zeros(0)
        for L in lights:
            if L["new"] and len(cells):
                idx, cv = contrib(L, pts, occ, origin)
                only = int(((val[idx] >= dark_thr) & (val[idx] - cv < dark_thr)).sum())
                L.setdefault("only", {})[name] = only
        vals = {c: float(v) for c, v in zip(cells, val)}
        dark = {c: vals[c] < dark_thr for c in cells}
        n = len(cells)
        nd = sum(dark.values())
        q = np.percentile(val, [10, 50, 90]) if n else [0, 0, 0]
        cl = clusters(cells, dark)
        darkest = sorted(cells, key=lambda c: vals[c])[:20]
        report["floors"][name] = {"cells": n, "dark": nd, "dark_share": round(nd / max(n, 1), 4),
                                  "p10": round(float(q[0]), 4), "median": round(float(q[1]), 4), "p90": round(float(q[2]), 4),
                                  "darkest": [[round(centre(*c)[0], 1), round(best[c], 2), round(centre(*c)[1], 1), round(vals[c], 4)] for c in darkest],
                                  "clusters": [[r[0], round(r[1], 1), round(r[2], 1), round(r[3], 1), round(r[4], 1), round(r[5], 1), round(r[6], 1),
                                                round(float(np.mean([vals[c] for c in r[7]])), 4)] for r in cl[:40]]}
        md += ["## %s" % name, "",
               "Walkable cells %d, dark %d (%.1f%%). Light p10 %.3f, median %.3f, p90 %.3f." % (n, nd, 100.0 * nd / max(n, 1), q[0], q[1], q[2]), "",
               "Darkest 20 cells (x, floor y, z: light): " + "; ".join("(%.1f, %.1f, %.1f): %.4f" % (centre(*c)[0], best[c], centre(*c)[1], vals[c]) for c in darkest), "",
               "| dark cluster cells | centre x | centre z | x range | z range | mean light |", "|---|---|---|---|---|---|"]
        for r in cl[:25]:
            md.append("| %d | %.1f | %.1f | %.1f..%.1f | %.1f..%.1f | %.4f |" % (r[0], r[1], r[2], r[3], r[5], r[4], r[6], float(np.mean([vals[c] for c in r[7]]))))
        md.append("")
        floors.append((name, vals))
        for c, pt in zip(cells, pts):
            all_pts.append((c, tuple(pt), name != "ground"))
            all_vals.append(vals[c])
        print("%-18s cells %5d  dark %5d (%.1f%%)  median %.3f" % (name, n, nd, 100.0 * nd / max(n, 1), q[1]))
        for r in cl[:12]:
            print("   cluster %3d cells  centre (%.1f, %.1f)  x %.1f..%.1f  z %.1f..%.1f" % (r[0], r[1], r[2], r[3], r[5], r[4], r[6]))
    os.makedirs(OUT_DIR, exist_ok=True)
    heatmap(OUT_DIR / ("coverage_%s.png" % tag), nx, nz, floors, top_solid, lights, dark_thr,
            "Freight Delight light coverage (%s): %d lights, ground dark %.1f%%, second floor dark %.1f%%" % (
                tag, len(lights), 100 * report["floors"]["ground"]["dark_share"], 100 * report["floors"]["second floor (L1)"]["dark_share"]))
    with open(OUT_DIR / ("coverage_%s.json" % tag), "w", encoding="utf-8", newline="\n") as f:
        json.dump(report, f, indent=1)
    with open(OUT_DIR / ("coverage_%s.md" % tag), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(md) + "\n")
    print("lights %d (r22 %d); wrote %s" % (len(lights), report["lights_r22"], OUT_DIR / ("coverage_%s.png" % tag)))
    new = [L for L in lights if L["new"]]
    if new:
        rows = ["| kind | x | y | z | fault | cells lit only by it (ground / L1) |", "|---|---|---|---|---|---|"]
        for L in new:
            o = L.get("only", {})
            rows.append("| %s | %.2f | %.2f | %.2f | %s | %d / %d |" % (L["kind"], L["pos"][0], L["pos"][1], L["pos"][2], L["fault"],
                                                                  o.get("ground", 0), o.get("second floor (L1)", 0)))
            print("  r22 %-6s (%6.2f, %5.2f, %6.2f) %-8s only-lit %4d / %3d" % (L["kind"], L["pos"][0], L["pos"][1], L["pos"][2], L["fault"],
                                                                         o.get("ground", 0), o.get("second floor (L1)", 0)))
        with open(OUT_DIR / ("coverage_%s.md" % tag), "a", encoding="utf-8", newline=chr(10)) as f:
            f.write(chr(10).join(["## r22 fittings", ""] + rows) + chr(10))
    for a in sys.argv[1:]:
        if a.startswith("--suggest="):
            suggest(solids, all_pts, all_vals, occ, origin, dark_thr, int(a.split("=", 1)[1]), OUT_DIR / ("suggest_%s.md" % tag))


if __name__ == "__main__":
    sys.exit(main())
