"""Freight Delight: the first version of the map, written as a TrenchBroom map (Valve 220 format).

The .map is the map's source from here on: open it in TrenchBroom (game config in tools/trenchbroom/Aetherion) and
edit it there; Godot re-imports it on save (addons/aetherion_map) and the game loads the scene that holds it
(game/assets/maps/freight_delight.tscn). This script only lays out the first version, so it refuses to overwrite
a map that has been edited since it last wrote it (use --force to start over from this layout).

    python -I tools/make_freight_map.py [--force] [--out=<path>]

Coordinates below are Godot metres: x east, y up, z south (z < 0 is north). Written to the .map as Quake units
(32 per metre): qx = x * 32, qy = -z * 32, qz = y * 32.

The plan: a squatter settlement that grew inside an old container yard by the port.
    West Team starts on the fish pier (Pantalan 3), East Team at the truck gate, ~110 m apart.
    North lane: the Container Canyon between the yard's perimeter stack and the inner row.
    Middle lane: the Bodega (warehouse) - the plaza under the old gantry crane - the Talyer (repair shop).
    South lane: the Eskinita, a maze of shanties with a courtyard, behind them the estero.
    2nd floor (y = 3.2 m): the inner container row's roof deck, the bridges over the plaza and the crane platform,
    the Bodega mezzanine and the Taas (the two-storey row house over the plaza). Three stairs reach it: Stair A in
    the Bodega (west), Stair B up the container stack north of the Talyer (east), Stair C in the Eskinita (south).
"""
import hashlib
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "maps" / "freight_delight.map"
U = 32.0            # Quake units per metre
L1 = 3.2            # the second floor
STEP_RISE = 0.2
STEP_RUN = 0.28
LAMP_K = 1.3        # every small lamp's energy (bulbs, tubes, lamps): the yard is dark, its lamps carry the light
CW = 2.44           # container width
CH = 2.9            # container height (high cube)
C20 = 6.06
C40 = 12.19

TEX_SIZE = {}       # material -> (metres per repeat, px w, px h, fit)


def load_surfaces():
    import json
    p = ROOT / "game" / "assets" / "maps" / "surfaces.json"
    for k, v in json.loads(p.read_text()).items():
        TEX_SIZE[k] = (float(v.get("size", 2.0)), int(v["px"][0]), int(v["px"][1]), bool(v.get("fit", False)))


# ------------------------------------------------------------------ map model

class Brush:
    def __init__(self, faces):
        self.faces = faces   # [(p1, p2, p3, tex, uaxis, uoff, vaxis, voff, sx, sy)]


class Entity:
    def __init__(self, classname, props=None):
        self.props = {"classname": classname}
        if props:
            self.props.update({k: str(v) for k, v in props.items()})
        self.brushes = []


ENTITIES = []
WORLD = Entity("worldspawn", {"mapversion": 220, "message": "Freight Delight", "map_id": "freight_delight", "night_only": 1,
                              "levels": 2, "level_height": L1, "_tb_textures": "textures/freight"})
LAYERS = {}         # name -> Entity (func_group _tb_layer)
GROUPS = []
_cur = {"layer": None, "group": None, "ent": None}
_ids = [1]


def layer(name):
    if name not in LAYERS:
        _ids[0] += 1
        e = Entity("func_group", {"_tb_type": "_tb_layer", "_tb_name": name, "_tb_id": _ids[0], "_tb_layer_sort_index": len(LAYERS)})
        LAYERS[name] = e
    _cur["layer"] = LAYERS[name]
    _cur["group"] = None


def group(name):
    """A TrenchBroom group (select the whole building with one click) in the current layer."""
    _ids[0] += 1
    e = Entity("func_group", {"_tb_type": "_tb_group", "_tb_name": name, "_tb_id": _ids[0]})
    if _cur["layer"] is not None:
        e.props["_tb_layer"] = _cur["layer"].props["_tb_id"]
    GROUPS.append(e)
    _cur["group"] = e
    return e


def end_group():
    _cur["group"] = None


def _target(ent):
    if ent is not None:
        return ent
    if _cur["ent"] is not None:
        return _cur["ent"]
    if _cur["group"] is not None:
        return _cur["group"]
    if _cur["layer"] is not None:
        return _cur["layer"]
    return WORLD


def entity(classname, props=None):
    """A brush entity (func_illusionary, func_stairs...) in the current layer / group: brushes go to it until end()."""
    e = Entity(classname, props)
    if _cur["layer"] is not None:
        e.props["_tb_layer"] = _cur["layer"].props["_tb_id"]
    if _cur["group"] is not None:
        e.props["_tb_group"] = _cur["group"].props["_tb_id"]
    ENTITIES.append(e)
    _cur["ent"] = e
    return e


def end():
    _cur["ent"] = None


def point(classname, pos, **props):
    e = Entity(classname, props)
    x, y, z = pos
    e.props["origin"] = "%g %g %g" % (round(x * U, 2), round(-z * U, 2), round(y * U, 2))
    if _cur["layer"] is not None:
        e.props["_tb_layer"] = _cur["layer"].props["_tb_id"]
    if _cur["group"] is not None:
        e.props["_tb_group"] = _cur["group"].props["_tb_id"]
    ENTITIES.append(e)
    return e


# ------------------------------------------------------------------ geometry helpers (Quake space inside)

def q(p):
    """Godot metres -> Quake units (rounded to whole units: the map stays on TrenchBroom's grid)."""
    return (round(p[0] * U), round(-p[2] * U), round(p[1] * U))


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(a):
    ln = math.sqrt(dot(a, a))
    return (a[0] / ln, a[1] / ln, a[2] / ln) if ln > 1e-9 else (0.0, 0.0, 0.0)


def _rand(key, n):
    h = hashlib.md5(key.encode()).digest()
    return [h[i] / 255.0 for i in range(n)]


def uv_axes(n):
    """Valve 220 texture axes for a face with outward normal n (Quake space): floors world-aligned, walls with u to
    the viewer's right and v down (so text and signs read the right way round from outside), slopes along the fall."""
    if abs(n[2]) > 0.94:
        return (1.0, 0.0, 0.0), (0.0, -1.0, 0.0)
    hz = norm((n[0], n[1], 0.0))
    right = norm(cross((-hz[0], -hz[1], 0.0), (0.0, 0.0, 1.0)))
    v = norm(cross(n, right))
    if v[2] > 0:
        v = (-v[0], -v[1], -v[2])
    return right, v


def make_face(pts_on_face, outward, tex, all_pts, uv=None, fit=False, vfit=None, rot_key=""):
    """pts_on_face: the face's polygon corners (Quake units); returns the face tuple with three plane points wound
    so (p3 - p1) x (p2 - p1) points outward (TrenchBroom's convention)."""
    p1 = pts_on_face[0]
    best = None
    for i in range(1, len(pts_on_face)):
        for j in range(1, len(pts_on_face)):
            if i == j:
                continue
            a = sub(pts_on_face[j], p1)
            b = sub(pts_on_face[i], p1)
            c = cross(a, b)
            if dot(c, outward) > 0 and (best is None or dot(c, c) > best[0]):
                best = (dot(c, c), pts_on_face[i], pts_on_face[j])
    _, p2, p3 = best
    n = norm(outward)
    u, v = uv if uv else uv_axes(n)
    size_m, pw, ph, tfit = TEX_SIZE.get(tex, (2.0, 512, 512, False))
    sx = sy = size_m * U / max(pw, 1)
    sy = size_m * U / max(pw, 1)
    r = _rand(tex + rot_key, 2)
    uo = round(r[0] * pw)
    vo = round(r[1] * ph)
    if fit or tfit:
        us = [dot(p, u) for p in pts_on_face]
        vs = [dot(p, v) for p in pts_on_face]
        sx = (max(us) - min(us)) / pw
        sy = (max(vs) - min(vs)) / ph
        uo = -min(us) / sx
        vo = -min(vs) / sy
    elif vfit is not None:
        # the texture's height spans the face from vfit[0] (top, Quake z) to vfit[1] (bottom)
        top, bot = vfit
        sy = (top - bot) / ph
        sx = sy
        vo = top / sy if v[2] < 0 else 0.0
    return (p1, p2, p3, tex, u, uo, v, vo, sx, sy)


def hull_brush(verts_m, tex, face_tex=None, uv=None, fit_faces=(), vfit=None, key=""):
    """A convex brush from its corner points (Godot metres). face_tex(n_godot) -> texture name or None for tex."""
    V = list({q(p) for p in verts_m})
    faces = []
    planes = []
    cen = tuple(sum(p[i] for p in V) / len(V) for i in range(3))
    n = len(V)
    for i in range(n):
        for j in range(i + 1, n):
            for k in range(j + 1, n):
                c = cross(sub(V[j], V[i]), sub(V[k], V[i]))
                if dot(c, c) < 1e-6:
                    continue
                nn = norm(c)
                d = dot(nn, V[i])
                if dot(nn, cen) > d:
                    nn = (-nn[0], -nn[1], -nn[2])
                    d = -d
                side = [dot(nn, p) - d for p in V]
                if max(side) > 0.01:
                    continue
                if any(abs(dot(nn, pn) - 1) < 1e-6 and abs(d - pd) < 0.01 for pn, pd in planes):
                    continue
                planes.append((nn, d))
                on = [p for p, s in zip(V, side) if abs(s) <= 0.01]
                gn = (nn[0], nn[2], -nn[1])            # back to Godot axes for the caller's choice
                t = face_tex(gn) if face_tex else None
                faces.append(make_face(on, nn, t or tex, V, uv=uv, fit=(t in fit_faces), vfit=vfit, rot_key=key))
    return Brush(faces)


def add(brush, ent=None):
    _target(ent).brushes.append(brush)
    return brush


def _snap(a, b):
    """Both ends on the 1-unit grid, at least one unit apart (a 3 cm rail must not round away to nothing)."""
    qa, qb = round(min(a, b) * U), round(max(a, b) * U)
    if qb <= qa:
        qb = qa + 1
    return qa / U, qb / U


def box(x0, y0, z0, x1, y1, z1, tex, top=None, bottom=None, sides=None, n=None, s=None, e=None, w=None, ent=None,
        fit=False, vfit=False, key=""):
    """Axis-aligned box (Godot metres). Per face: top, bottom, sides (all four), or n / s / e / w (the face looking
    north, south, east, west). The bottom resting on the ground (y0 <= 0) is skipped (never seen)."""
    x0, x1 = _snap(x0, x1)
    y0, y1 = _snap(y0, y1)
    z0, z1 = _snap(z0, z1)
    if bottom is None and y0 <= 0.001:
        bottom = "freight/skip"

    def ft(g):
        if g[1] > 0.9:
            return top
        if g[1] < -0.9:
            return bottom
        if g[2] < -0.9:
            return n or sides
        if g[2] > 0.9:
            return s or sides
        if g[0] > 0.9:
            return e or sides
        if g[0] < -0.9:
            return w or sides
        return None
    verts = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    fitset = set()
    if fit:
        fitset = {t for t in (top, bottom, sides, n, s, e, w, tex) if t}
    vf = (round(y1 * U), round(y0 * U)) if vfit else None
    b = hull_brush(verts, tex, ft, fit_faces=fitset, vfit=vf, key=key or "%g%g%g" % (x0, y0, z0))
    return add(b, ent)


def slab(p0, p1, p2, p3, thick, tex, under=None, edge=None, ent=None, key=""):
    """A thin sheet through the four corners (a roof, a tarp, a ramp), thick along its normal, downward."""
    a = [p0, p1, p2, p3]
    u = sub(p1, p0)
    v = sub(p3, p0)
    nn = norm(cross(v, u))
    if nn[1] < 0:
        nn = (-nn[0], -nn[1], -nn[2])
    b = [(p[0] - nn[0] * thick, p[1] - nn[1] * thick, p[2] - nn[2] * thick) for p in a]

    def ft(g):
        if dot(g, nn) > 0.9:
            return None
        if dot(g, nn) < -0.9:
            return under
        return edge
    return add(hull_brush(a + b, tex, ft, key=key or str(p0)), ent)


def prism(poly_xz, y0, y1, tex, top=None, bottom=None, sides=None, ent=None, key=""):
    """A vertical prism over a convex polygon (Godot x, z)."""
    if bottom is None and y0 <= 0.001:
        bottom = "freight/skip"
    verts = [(x, y, z) for (x, z) in poly_xz for y in (y0, y1)]

    def ft(g):
        if g[1] > 0.9:
            return top
        if g[1] < -0.9:
            return bottom
        return sides
    return add(hull_brush(verts, tex, ft, key=key or str(poly_xz[0])), ent)


def octagon(cx, cz, r):
    return [(cx + r * math.cos(math.pi / 8 + k * math.pi / 4), cz + r * math.sin(math.pi / 8 + k * math.pi / 4)) for k in range(8)]


def cyl(cx, cz, r, y0, y1, tex, top=None, sides=None, ent=None):
    return prism(octagon(cx, cz, r), y0, y1, tex, top=top, sides=sides, ent=ent)


# ------------------------------------------------------------------ building pieces

def wall(axis, at, a0, a1, y0, y1, t, tex, holes=(), ent=None, **faces):
    """A straight wall. axis "x": runs along x from a0 to a1, from z = at to at + t; axis "z": along z, from x = at to
    at + t. holes: [(c, w, h0, h1)] openings (doors from the floor, windows above it); no two may overlap along the
    wall. faces: n / s / e / w textures for the wall's two sides (the room side usually differs)."""
    cuts = sorted([(c - w / 2, c + w / 2, h0, h1) for (c, w, h0, h1) in holes])
    t0, t1 = at, at + t

    def piece(b0, b1, c0, c1):
        if b1 - b0 < 0.01 or c1 - c0 < 0.01:
            return
        if axis == "x":
            box(b0, c0, t0, b1, c1, t1, tex, ent=ent, **faces)
        else:
            box(t0, c0, b0, t1, c1, b1, tex, ent=ent, **faces)
    x = a0
    for (c0, c1, h0, h1) in cuts:
        piece(x, c0, y0, y1)
        piece(c0, c1, y0, h0)
        piece(c0, c1, h1, y1)
        x = c1
    piece(x, a1, y0, y1)


def roof(x0, z0, x1, z1, y_lo, y_hi, tex, fall="s", over=0.25, thick=0.06, under=None, ent=None):
    """A mono-pitch sheet roof over the rectangle, falling toward fall (n/s/e/w), overhanging by over."""
    x0 -= over
    x1 += over
    z0 -= over
    z1 += over
    if fall == "s":
        pts = [(x0, y_hi, z0), (x1, y_hi, z0), (x1, y_lo, z1), (x0, y_lo, z1)]
    elif fall == "n":
        pts = [(x0, y_lo, z0), (x1, y_lo, z0), (x1, y_hi, z1), (x0, y_hi, z1)]
    elif fall == "e":
        pts = [(x0, y_hi, z0), (x1, y_lo, z0), (x1, y_lo, z1), (x0, y_hi, z1)]
    else:
        pts = [(x0, y_lo, z0), (x1, y_hi, z0), (x1, y_hi, z1), (x0, y_lo, z1)]
    return slab(pts[0], pts[1], pts[2], pts[3], thick, tex, under=under or tex, ent=ent)


def railing(x0, z0, x1, z1, y, tex="freight/steel_rust", h=1.0, posts=1.6):
    """Posts, a top rail and a mid rail from (x0, z0) to (x1, z1) on a floor at y (axis-aligned runs)."""
    along_x = abs(x1 - x0) >= abs(z1 - z0)
    ln = abs(x1 - x0) if along_x else abs(z1 - z0)
    n = max(1, int(round(ln / posts)))
    for k in range(n + 1):
        t = k / n
        x = x0 + (x1 - x0) * t
        z = z0 + (z1 - z0) * t
        box(x - 0.03, y, z - 0.03, x + 0.03, y + h, z + 0.03, tex)
    for hh in (h - 0.04, h * 0.5):
        if along_x:
            box(min(x0, x1), y + hh - 0.02, z0 - 0.025, max(x0, x1), y + hh + 0.02, z0 + 0.025, tex)
        else:
            box(x0 - 0.025, y + hh - 0.02, min(z0, z1), x0 + 0.025, y + hh + 0.02, max(z0, z1), tex)


def parapet(x0, z0, x1, z1, y, tex, h=1.05, t=0.04):
    """A low sheet wall on a deck edge (plywood or yero nailed to the rail): waist-high cover."""
    if abs(x1 - x0) >= abs(z1 - z0):
        box(min(x0, x1), y, z0 - t / 2, max(x0, x1), y + h, z0 + t / 2, tex)
    else:
        box(x0 - t / 2, y, min(z0, z1), x0 + t / 2, y + h, max(z0, z1), tex)


def container(x0, z0, along, length, colour, y0=0.0, hollow=False, open_ends=(), cut=None, key=""):
    """A shipping container (2.44 wide x 2.9 high) with its corner at (x0, z0), running along "x" or "z".
    hollow: walls, floor and roof only (a home); open_ends: "a" / "b" ends left open (doors swung away);
    cut: [(side "n"/"s"/"e"/"w", centre, width)] torch-cut openings in the long sides (doorways)."""
    side = "freight/container_" + colour
    door = "freight/container_door_" + colour
    rf = "freight/container_roof"
    if along == "x":
        x1, z1 = x0 + length, z0 + CW
    else:
        x1, z1 = x0 + CW, z0 + length
    y1 = y0 + CH
    key = key or "c%g%g" % (x0, z0)
    if not hollow:
        if along == "x":
            box(x0, y0, z0, x1, y1, z1, side, top=rf, e=door, w=door, vfit=True, key=key)
        else:
            box(x0, y0, z0, x1, y1, z1, side, top=rf, n=door, s=door, vfit=True, key=key)
        return
    t = 0.05
    fl = "freight/plywood"
    box(x0, y0, z0, x1, y0 + 0.12, z1, side, top=fl)                     # floor
    if y0 > 0.1:
        # raised on footings: a pallet step outside each doorway (the floor is higher than a stride)
        for (s_, c, w) in (cut or []):
            hs = (y0 + 0.12) * 0.5
            if s_ == "n":
                box(c - 0.6, 0, z0 - 0.55, c + 0.6, hs, z0, "freight/pallet", top="freight/pallet")
            elif s_ == "s":
                box(c - 0.6, 0, z1, c + 0.6, hs, z1 + 0.55, "freight/pallet", top="freight/pallet")
            elif s_ == "w":
                box(x0 - 0.55, 0, c - 0.6, x0, hs, c + 0.6, "freight/pallet", top="freight/pallet")
            else:
                box(x1, 0, c - 0.6, x1 + 0.55, hs, c + 0.6, "freight/pallet", top="freight/pallet")
    box(x0, y1 - t, z0, x1, y1, z1, side, top=rf, bottom=side)          # roof
    cuts = cut or []
    if along == "x":
        for zz, sd, out in ((z0, "n", "n"), (z1 - t, "s", "s")):
            holes = [(c, w, y0 + 0.12, y0 + 2.2) for (s_, c, w) in cuts if s_ == sd]
            wall("x", zz, x0, x1, y0 + 0.12, y1 - t, t, side, holes=holes)
        for xx, end_ in ((x0, "a"), (x1 - t, "b")):
            if end_ in open_ends:
                continue
            box(xx, y0 + 0.12, z0 + t, xx + t, y1 - t, z1 - t, door, fit=True)
    else:
        for xx, sd in ((x0, "w"), (x1 - t, "e")):
            holes = [(c, w, y0 + 0.12, y0 + 2.2) for (s_, c, w) in cuts if s_ == sd]
            wall("z", xx, z0, z1, y0 + 0.12, y1 - t, t, side, holes=holes)
        for zz, end_ in ((z0, "a"), (z1 - t, "b")):
            if end_ in open_ends:
                continue
            box(x0 + t, y0 + 0.12, zz, x1 - t, y1 - t, zz + t, door, fit=True)


def rack(x0, z0, x1, z1, h=2.6, key=""):
    """Pallet racking along z: uprights every ~1.9 m, four shelves, sacks and boxes on them (gaps to shoot through)."""
    n = max(1, int(round((z1 - z0) / 1.9)))
    for k in range(n + 1):
        z = z0 + (z1 - z0) * k / n
        for x in (x0, x1 - 0.08):
            box(x, 0, min(z, z1 - 0.08), x + 0.08, h, min(z, z1 - 0.08) + 0.08, "freight/steel_blue")
    r = _rand("rack" + key, 16)
    for j, y in enumerate((0.12, 0.95, 1.75, 2.5)):
        box(x0, y - 0.05, z0, x1, y, z1, "freight/steel_blue", top="freight/plywood")
        if y > 2.4:
            continue
        z = z0 + 0.15
        i = 0
        while z < z1 - 0.7:
            w = 0.5 + r[(j * 4 + i) % 16] * 0.6
            if r[(j * 3 + i * 5) % 16] < 0.7:
                tex = "freight/sack" if r[(i + j) % 16] < 0.5 else "freight/plywood"
                box(x0 + 0.08, y, z, x1 - 0.08, y + 0.35 + r[(i * 7 + j) % 16] * 0.3, min(z + w, z1 - 0.1), tex)
            z += w + 0.12
            i += 1


def footings(x0, z0, along, length, h=0.3):
    """Concrete blocks under a raised container (its corners and middle)."""
    xs = [x0 + 0.1, x0 + length / 2 - 0.25, x0 + length - 0.6] if along == "x" else [x0 + 0.1, x0 + CW - 0.6]
    zs = [z0 + 0.1, z0 + CW - 0.6] if along == "x" else [z0 + 0.1, z0 + length / 2 - 0.25, z0 + length - 0.6]
    for x in xs:
        for z in zs:
            box(x, 0, z, x + 0.5, h, z + 0.5, "freight/concrete_rough")


def stairs(x0, x1, z0, z1, rise_dir, y0, y1, tex, side_tex=None, solid=True, name="Stair", ramp_tex="freight/clip_concrete"):
    """A straight flight inside the rectangle, rising toward rise_dir (n/s/e/w) from y0 to y1 in 0.2 m risers.
    solid: each step a block down to y0 (masonry / boxed timber); otherwise 6 cm treads on two stringers.
    Wrapped in a func_stairs entity so the game knows its foot and top (bots, the level map)."""
    n = max(1, int(round((y1 - y0) / STEP_RISE)))
    rise = (y1 - y0) / n
    e = entity("func_stairs", {"targetname": name})
    for k in range(n - 1):     # the last riser lands on the floor above
        top = y0 + (k + 1) * rise
        bot = y0 if solid else top - 0.06
        if rise_dir == "n":
            a, b = z1 - (k + 1) * STEP_RUN, z1 - k * STEP_RUN
            box(x0, bot, a, x1, top, b, tex, sides=side_tex, ent=e)
        elif rise_dir == "s":
            a, b = z0 + k * STEP_RUN, z0 + (k + 1) * STEP_RUN
            box(x0, bot, a, x1, top, b, tex, sides=side_tex, ent=e)
        elif rise_dir == "w":
            a, b = x1 - (k + 1) * STEP_RUN, x1 - k * STEP_RUN
            box(a, bot, z0, b, top, z1, tex, sides=side_tex, ent=e)
        else:
            a, b = x0 + k * STEP_RUN, x0 + (k + 1) * STEP_RUN
            box(a, bot, z0, b, top, z1, tex, sides=side_tex, ent=e)
    end()
    # The flight's collision: an invisible ramp over the step nosings (the steps themselves are drawn only, as in the
    # game's own stairs). Bodies walk up it in one slope; its clip_<surface> texture makes footsteps and rounds match the
    # steps. It stays out of the func_stairs, so the flight's foot and top are the steps'.
    span = (n - 1) * STEP_RUN
    if rise_dir == "n":
        a0, a1 = z1 + STEP_RUN, z1 - span
        ramp = [(x0, y0, a0), (x1, y0, a0), (x1, y1, a1), (x0, y1, a1)]
    elif rise_dir == "s":
        a0, a1 = z0 - STEP_RUN, z0 + span
        ramp = [(x0, y0, a0), (x1, y0, a0), (x1, y1, a1), (x0, y1, a1)]
    elif rise_dir == "w":
        a0, a1 = x1 + STEP_RUN, x1 - span
        ramp = [(a0, y0, z0), (a0, y0, z1), (a1, y1, z1), (a1, y1, z0)]
    else:
        a0, a1 = x0 - STEP_RUN, x0 + span
        ramp = [(a0, y0, z0), (a0, y0, z1), (a1, y1, z1), (a1, y1, z0)]
    if solid:
        # a boxed-in flight: the ramp is a wedge down to the floor, so nobody walks into the steps from the side
        add(hull_brush(ramp + [(p[0], y0, p[2]) for p in ramp[2:]], ramp_tex, key=name))
    else:
        slab(ramp[0], ramp[1], ramp[2], ramp[3], 0.25, ramp_tex)
    if not solid:
        # stringers: two sloped steel beams along the flight
        run = (n - 1) * STEP_RUN
        for s in (0, 1):
            if rise_dir in ("n", "s"):
                xx = x0 if s == 0 else x1 - 0.08
                za, zb = (z1, z1 - run) if rise_dir == "n" else (z0, z0 + run)
                slab((xx, y0 + 0.25, za), (xx + 0.08, y0 + 0.25, za), (xx + 0.08, y1 - rise + 0.2, zb), (xx, y1 - rise + 0.2, zb), 0.25, side_tex or tex)
            else:
                zz = z0 if s == 0 else z1 - 0.08
                xa, xb = (x1, x1 - run) if rise_dir == "w" else (x0, x0 + run)
                slab((xa, y0 + 0.25, zz), (xa, y0 + 0.25, zz + 0.08), (xb, y1 - rise + 0.2, zz + 0.08), (xb, y1 - rise + 0.2, zz), 0.25, side_tex or tex)


def light(pos, kind="bulb", colour=(255, 186, 120), energy=1.2, rng=9.0, fault="", angle=None, pitch=None, **extra):
    if kind not in ("flood", "street", "candle"):
        energy = round(energy * LAMP_K, 2)
    props = {"kind": kind, "_color": "%d %d %d" % colour, "energy": energy, "range": rng}
    if fault:
        props["fault"] = fault
    if angle is not None:
        props["angle"] = angle
    if pitch is not None:
        props["pitch"] = pitch
    props.update(extra)
    point("light", pos, **props)


def bulb_on_wire(pos, fault="", energy=1.1, rng=8.5, colour=(255, 178, 104)):
    """A bare bulb hanging from a wire: the wire is drawn, the bulb itself is the game's emitter."""
    x, y, z = pos
    box(x - 0.006, y + 0.06, z - 0.006, x + 0.006, y + 0.7, z + 0.006, "freight/rubber", ent=_illus())
    light(pos, "bulb", colour, energy, rng, fault)


_ILL = {}


def _illus():
    """The current layer's func_illusionary (drawn, no collision): wires, laundry, hanging tarps."""
    lay = _cur["layer"]
    k = lay.props["_tb_id"] if lay is not None else "w"
    if k not in _ILL:
        e = Entity("func_illusionary", {})
        if lay is not None:
            e.props["_tb_layer"] = k
        ENTITIES.append(e)
        _ILL[k] = e
    return _ILL[k]


def laundry_line(x0, z0, x1, z1, y):
    ill = _illus()
    if abs(x1 - x0) >= abs(z1 - z0):
        box(min(x0, x1), y - 0.01, z0 - 0.005, max(x0, x1), y, z0 + 0.005, "freight/rubber", ent=ill)
        x = min(x0, x1) + 0.4
        k = 0
        while x < max(x0, x1) - 0.6:
            w = 0.45 + (k * 0.37 % 0.5)
            hgt = 0.5 + (k * 0.53 % 0.45)
            box(x, y - hgt, z0 - 0.01, x + w, y - 0.01, z0 + 0.01, "freight/laundry", ent=ill)
            x += w + 0.15 + (k * 0.29 % 0.4)
            k += 1
    else:
        box(x0 - 0.005, y - 0.01, min(z0, z1), x0 + 0.005, y, max(z0, z1), "freight/rubber", ent=ill)
        z = min(z0, z1) + 0.4
        k = 0
        while z < max(z0, z1) - 0.6:
            w = 0.45 + (k * 0.37 % 0.5)
            hgt = 0.5 + (k * 0.53 % 0.45)
            box(x0 - 0.01, y - hgt, z, x0 + 0.01, y - 0.01, z + w, "freight/laundry", ent=ill)
            z += w + 0.15 + (k * 0.29 % 0.4)
            k += 1


def crate_stack(x, z, n=2, tex="freight/plastic_blue"):
    for k in range(n):
        box(x, k * 0.32, z, x + 0.6, k * 0.32 + 0.3, z + 0.42, tex)


def icebox(x, z, rot=False):
    w, d = (1.1, 0.75) if not rot else (0.75, 1.1)
    box(x, 0, z, x + w, 0.72, z + d, "freight/plastic_white", top="freight/plastic_blue")


def sacks(x0, z0, x1, z1, h=1.0):
    """A wall of sandbags / rice sacks."""
    box(x0, 0, z0, x1, h * 0.5, z1, "freight/sack")
    box(x0 + 0.08, h * 0.5, z0 + 0.06, x1 - 0.08, h, z1 - 0.06, "freight/sack")


def drum(x, z, tex="freight/plastic_blue", h=0.9):
    cyl(x, z, 0.3, 0, h, tex)


def pallet_stack(x, z, n=4, rot=False):
    w, d = (1.2, 1.0) if not rot else (1.0, 1.2)
    box(x, 0, z, x + w, n * 0.15, z + d, "freight/pallet", top="freight/pallet")


def tire_stack(x, z, n=4):
    cyl(x, z, 0.36, 0, n * 0.22, "freight/tire", top="freight/rubber")


def post(x, z, y0, y1, tex="freight/timber", w=0.16):
    box(x - w / 2, y0, z - w / 2, x + w / 2, y1, z + w / 2, tex)


def shack(x0, z0, x1, z1, h, wall_tex, roof_tex, doors=(), windows=(), fall="s", floor_tex="freight/planks_dark",
          t=0.1, roof_hi=None, inner_tex=None, name=None):
    """A one-room shack: four walls (doors / windows: [(side, centre, width)]), a wooden floor and a sheet roof.
    Sides: n (z0), s (z1), w (x0), e (x1)."""
    if name:
        group(name)
    wt = wall_tex if isinstance(wall_tex, dict) else {s: wall_tex for s in "nswe"}
    hd = {s: [] for s in "nswe"}
    for (s, c, w) in doors:
        hd[s].append((c, w, 0.0, 2.15))
    for (s, c, w) in windows:
        hd[s].append((c, w, 1.0, 1.9))
    wall("x", z0, x0, x1, 0, h, t, wt["n"], holes=hd["n"], s=inner_tex)
    wall("x", z1 - t, x0, x1, 0, h, t, wt["s"], holes=hd["s"], n=inner_tex)
    wall("z", x0, z0 + t, z1 - t, 0, h, t, wt["w"], holes=hd["w"], e=inner_tex)
    wall("z", x1 - t, z0 + t, z1 - t, 0, h, t, wt["e"], holes=hd["e"], w=inner_tex)
    box(x0 + t, 0, z0 + t, x1 - t, 0.08, z1 - t, floor_tex, top=floor_tex)
    hi = roof_hi if roof_hi is not None else h + 0.35
    roof(x0, z0, x1, z1, h, hi, roof_tex, fall={"s": "s", "n": "n", "e": "e", "w": "w"}[fall])
    if name:
        end_group()


# ------------------------------------------------------------------ the map

def ground():
    layer("Ground")
    group("Ground slabs")
    box(-62, -0.5, -42, -44, 0, 42, "freight/concrete_wet", top="freight/concrete_wet", sides="freight/concrete_rough")
    box(-44, -0.5, -42, 44, 0, 14, "freight/concrete_wet", top="freight/concrete_wet", sides="freight/concrete_rough")
    box(-44, -0.5, 14, 44, 0, 42, "freight/mud", top="freight/mud", sides="freight/concrete_rough")
    box(44, -0.5, -42, 62, 0, 42, "freight/asphalt", top="freight/asphalt", sides="freight/concrete_rough")
    end_group()
    group("Beyond the yard (not reachable)")
    ill = entity("func_illusionary", {})
    # the harbour west of the pier, the quay wall, the far bank of the estero, the road east of the gate
    box(-120, -2.4, -90, -62, -2.2, 90, "freight/water", ent=ill)
    box(-62.4, -3.0, -60, -62, 0, 60, "freight/concrete_rough", ent=ill)
    box(-62, -0.5, 42, 62, -0.2, 43, "freight/concrete_rough", ent=ill)
    box(-90, -1.6, 43, 90, -1.4, 50, "freight/water", ent=ill)
    box(-90, -1.6, 50, 90, 0.4, 56, "freight/mud", top="freight/mud", ent=ill)
    box(62, -0.5, -90, 110, 0, 90, "freight/asphalt", top="freight/asphalt", ent=ill)
    box(-62, -0.5, -90, 62, 0, -44.5, "freight/concrete_wet", top="freight/concrete_wet", ent=ill)
    end()
    end_group()


def perimeter():
    layer("Perimeter")
    cols = ["red", "blue", "green", "orange", "grey", "yellow"]
    # North: the yard's stack, three high, behind the canyon.
    group("North stack")
    x = -62.0
    k = 0
    while x < 62:
        ln = min(C40, 62 - x)
        for tier in range(3):
            if tier == 2 and k % 4 == 3:
                continue
            off = (0.0, 0.3, -0.4)[tier]
            container(x + (0.0 if tier == 0 else off), -44.44, "x", ln if tier == 0 else min(ln, 62 - x - off), cols[(k * 7 + tier * 3) % 6], y0=tier * CH, key="n%d%d" % (k, tier))
        x += ln
        k += 1
    end_group()
    group("South wall and fence")
    box(-62, 0, 41.75, 62, 1.1, 42.0, "freight/chb_raw", top="freight/concrete_rough")
    entity("func_illusionary", {})
    for xx in range(-62, 63, 3):
        box(xx - 0.03, 1.1, 41.85, xx + 0.03, 2.7, 41.91, "freight/steel_rust")
    box(-62, 1.1, 41.86, 62, 2.6, 41.9, "freight/chain_link")
    end()
    end_group()
    group("East wall and gate")
    box(62, 0, -42, 62.3, 3.2, -6, "freight/chb_raw", top="freight/concrete_rough", w="freight/chb_white")
    box(62, 0, 6, 62.3, 3.2, 42, "freight/chb_raw", top="freight/concrete_rough", w="freight/chb_white")
    box(61.8, 0, -6, 62.0, 2.8, 6, "freight/steel_grey", w="freight/steel_grey")          # the shut sliding gate
    box(61.6, 2.8, -6.2, 62.3, 3.4, 6.2, "freight/steel_yellow")
    box(61.2, 2.4, -1.4, 61.8, 3.6, 1.4, "freight/sign_yard", w="freight/sign_yard", fit=True)
    end_group()
    group("West quay edge")
    for zz in range(-38, 40, 7):
        cyl(-61.3, zz, 0.22, 0, 0.55, "freight/concrete_rough", top="freight/concrete_rough")
    box(-62, 0, -42, -61.75, 0.22, 42, "freight/concrete_rough", top="freight/hazard")
    end_group()
    layer("Clip")
    group("Play area bounds")
    C = "freight/clip"
    box(-63, 0, -46, -62, 16, 46, C)            # west (over the water)
    box(62, 0, -46, 63, 16, 46, C)              # east
    box(-63, 0, -45.4, 63, 16, -42.0, C)       # north (flush with the stack's face)
    box(-63, 0, 41.75, 63, 16, 43, C)           # south
    end_group()


def west_pier():
    layer("West spawn - Pantalan")
    group("Fish landing shed")
    for xx in (-57.6, -47.4):
        for zz in (-10.6, -5.3, 0.0, 5.3, 10.6):
            post(xx, zz, 0, 4.25 if xx < -50 else 4.75, "freight/steel_rust", 0.18)
    for zz in (-10.6, -5.3, 0.0, 5.3, 10.6):
        slab((-58.2, 4.25, zz - 0.06), (-46.8, 4.75, zz - 0.06), (-46.8, 4.75, zz + 0.06), (-58.2, 4.25, zz + 0.06), 0.18, "freight/steel_rust")
    roof(-58, -11, -47, 11, 4.3, 4.85, "freight/yero_old", fall="w", over=0.6)
    end_group()
    group("Shed floor clutter")
    for (xx, zz, r) in ((-56, -9, False), (-54.4, -9.2, False), (-52, 8.4, True), (-50, 8.0, False), (-56.2, 8.6, False), (-49.5, -9.4, True)):
        icebox(xx, zz, r)
    # crates and the gutting table stay off the spawn pad (x -57..-48, z -6..6: respawns need 0.8 m clear)
    for (xx, zz, nn) in ((-59.4, 2.6, 3), (-59.5, 3.4, 2), (-47.2, -7.8, 3), (-46.6, -7.3, 2), (-51.5, 7.2, 1)):
        crate_stack(xx, zz, nn, "freight/plastic_red" if nn == 2 else "freight/plastic_blue")
    box(-59.6, 0, -2.0, -58.8, 0.9, 2.0, "freight/planks", top="freight/planks_dark")    # the gutting table
    end_group()
    group("Pier sheds and cover")
    container(-60.0, -24.0, "x", C40, "blue", key="wp1")
    container(-56.0, -36.6, "z", C40, "grey", key="wp2")
    container(-56.0, -36.6, "z", C20, "orange", y0=CH, key="wp3")
    for (xx, zz) in ((-50, -30), (-48.6, -30.2), (-50, -28.6)):
        pallet_stack(xx, zz, 5)
    sacks(-52, 15.0, -48, 15.8)
    sacks(-59, -15.8, -55, -15.0)
    drum(-46.5, -17.0)
    drum(-45.9, -16.4, "freight/plastic_red")
    end_group()
    group("Bangka on blocks")
    for zz in (13.5, 22.0):
        box(-60.4, 0, zz, -58.4, 0.45, zz + 0.6, "freight/concrete_rough")
    slab((-60.5, 0.5, 12.8), (-58.3, 0.5, 12.8), (-58.3, 0.5, 23.2), (-60.5, 0.5, 23.2), 0.12, "freight/wood_red")
    for s in (-1, 1):
        x = -59.4 + s * 1.0
        slab((x, 0.5, 13.0), (x + s * 0.35, 1.35, 13.0), (x + s * 0.35, 1.35, 23.0), (x, 0.5, 23.0), 0.08, "freight/wood_red")
    for zz in (15.0, 21.0):
        box(-63.0, 1.0, zz - 0.06, -55.8, 1.12, zz + 0.06, "freight/timber")
    end_group()
    group("Pier guard hut")
    shack(-58.5, 28.0, -53.0, 33.0, 2.5, "freight/planks", "freight/yero_rust", doors=[("e", 30.5, 1.4)], windows=[("n", -55.8, 1.0)], fall="w")
    end_group()
    group("Pier spawn signs")
    box(-46.2, 2.0, 11.6, -45.9, 3.2, 13.6, "freight/sign_pier", e="freight/sign_pier", fit=True)
    post(-46.0, 11.8, 0, 2.0, "freight/steel_rust", 0.1)
    post(-46.0, 13.4, 0, 2.0, "freight/steel_rust", 0.1)
    end_group()
    layer("Lights")
    group("West lights")
    for zz in (-14.5, 14.5):
        post(-60.2, zz, 0, 8.0, "freight/steel_grey", 0.22)
        box(-60.5, 7.8, zz - 0.4, -59.8, 8.1, zz + 0.4, "freight/steel_grey")
        light((-59.6, 7.7, zz), "flood", (255, 170, 90), 3.2, 34.0, angle=0, pitch=40)
    for zz, f in ((-8.5, ""), (-3.0, ""), (0.5, "starter"), (4.5, ""), (8.5, "")):
        light((-52.5, 4.15, zz), "tube", (220, 236, 255), 1.3, 10.0, f, angle=90)
    bulb_on_wire((-55.6, 2.0, 30.5), "flicker", 0.8, 7.0)
    end_group()
    layer("Spawns")
    group("West Team spawn")
    k = 0
    for xx in (-56.0, -53.6, -51.2, -48.8):
        for zz in (-4.8, -1.6, 1.6, 4.8):
            point("info_team_spawn", (xx, 0.05, zz), team=1, angle=0)
            k += 1
    end_group()


def canyon():
    layer("Container Canyon")
    group("Canyon obstacles")
    container(-36.0, -42.0, "z", C20, "red", hollow=True, open_ends=("b",), key="o1")
    container(-8.0, -42.0, "z", C20, "green", key="o3")
    container(-8.0, -42.0, "z", C20, "blue", y0=CH, key="o3b")
    container(20.0, -42.0, "z", C20, "yellow", hollow=True, open_ends=("b",), key="o5")
    container(46.0, -42.0, "z", C20, "grey", key="o7")
    container(-44.0, -42.0, "z", C20, "orange", key="o0")
    for (xx, zz) in ((-27, -35.5), (-25.6, -35.8), (2.0, -38.4), (3.3, -38.1), (27.5, -36.0), (40.0, -35.0)):
        pallet_stack(xx, zz, 6)
    sacks(-14.0, -39.0, -11.0, -38.2)
    sacks(12.0, -34.0, 15.0, -33.2)
    tire_stack(-18.0, -40.0, 5)
    tire_stack(-17.2, -40.5, 3)
    end_group()
    # Balconies: single containers reaching from the inner row into the canyon, their roofs part of the deck.
    group("Canyon balconies (2nd floor)")
    for (xx, colr) in ((-22.0, "orange"), (4.0, "red"), (30.0, "blue")):
        footings(xx, -37.06, "z", C20)
        container(xx, -37.06, "z", C20, colr, y0=0.3, key="bal%g" % xx)
    end_group()
    layer("Lights")
    group("Canyon lights")
    for (xx, zz, f) in ((-40, -41.6, ""), (-24, -41.6, "flicker"), (-2, -41.6, ""), (14, -41.6, "dying"), (34, -41.6, ""), (52, -41.6, "")):
        light((xx, 3.4, zz), "lamp", (255, 176, 96), 1.4, 11.0, f)
        box(xx - 0.12, 3.5, -41.99, xx + 0.12, 3.62, -41.7, "freight/steel_grey")
    light((-33.0, 2.3, -38.0), "tube", (210, 230, 255), 0.8, 7.0, "", angle=90)
    light((21.2, 2.3, -38.5), "bulb", (255, 120, 80), 0.7, 6.0, "flicker")
    end_group()


def inner_row():
    """The inner row: two containers deep on footings, roofs at L1, gaps for two ground passages; one through-home."""
    layer("Inner row and deck (2nd floor)")
    cols = ["blue", "red", "green", "grey", "orange", "yellow"]
    segs = [(-36.47, [C40, C40]), (-9.09, [C20, C20, C20]), (12.09, [C20, C20, C40])]
    k = 0
    for (x0, lens) in segs:
        group("Inner row %g" % x0)
        x = x0
        for ln in lens:
            for row, z0 in ((0, -31.0), (1, -28.56)):
                footings(x, z0, "x", ln)
                through = abs(x - 18.15) < 0.05
                home = (row == 1 and abs(x + 36.47) < 0.05)
                if through:
                    container(x, z0, "x", ln, cols[(k + row) % 6], y0=0.3, hollow=True,
                              cut=[("n" if row == 0 else "s", x + ln / 2, 1.6), ("s" if row == 0 else "n", x + ln / 2, 1.6)], key="ir%d%d" % (k, row))
                elif home:
                    container(x, z0, "x", ln, "green", y0=0.3, hollow=True, cut=[("s", x + 4.0, 1.5)], key="home")
                else:
                    container(x, z0, "x", ln, cols[(k * 5 + row * 2) % 6], y0=0.3, key="ir%d%d" % (k, row))
            x += ln
            k += 1
        end_group()
    group("Deck bridges over the passages")
    for (x0, x1) in ((-12.09, -9.09), (9.09, 12.09)):
        box(x0, L1 - 0.14, -29.8, x1, L1, -27.4, "freight/planks", top="freight/planks")
        for zz in (-29.8, -27.4):
            railing(x0, zz, x1, zz, L1, h=1.0)
    end_group()
    group("Deck edge parapets")
    for (x0, x1) in ((-36.3, -31.5), (-24.5, -16.0), (-7.0, -2.0), (2.0, 7.0), (24.0, 30.0)):
        parapet(x0, -26.2, x1, -26.2, L1, "freight/plywood")
    for (x0, x1) in ((-36.3, -30.5), (-19.0, -13.0), (-6.0, 6.0), (24.0, 29.5), (33.0, 36.3)):
        parapet(x0, -30.95, x1, -30.95, L1, "freight/yero_rust")
    end_group()
    group("Deck clutter")
    for (xx, zz) in ((-34.5, -29.5), (-34.0, -28.5), (5.0, -29.0), (33.5, -27.8)):
        drum(xx, zz, "freight/plastic_blue", 0.9)
    for (x0, x1, zz) in ((-24.0, -16.0, -29.0), (0.0, 8.0, -29.6), (24.0, 34.0, -28.2)):
        laundry_line(x0, zz, x1, zz, L1 + 2.0)
    sacks(-6.0, -28.6, -3.4, -27.9, 0.9)
    sacks(28.0, -30.2, 30.6, -29.5, 0.9)
    end_group()


def lift(fn, dy):
    """Run fn and raise every brush and point it adds by dy (build rooftop pieces with the ground helpers)."""
    marks = {id(e): len(e.brushes) for e in [WORLD] + list(LAYERS.values()) + GROUPS + ENTITIES}
    npts = len(ENTITIES)
    fn()
    du = round(dy * U)
    for e in [WORLD] + list(LAYERS.values()) + GROUPS + ENTITIES:
        start = marks.get(id(e), 0)
        for b in e.brushes[start:]:
            nf = []
            for f in b.faces:
                p1, p2, p3 = [(p[0], p[1], p[2] + du) for p in f[:3]]
                u, uo, v, vo, sx, sy = f[4], f[5], f[6], f[7], f[8], f[9]
                vo2 = vo - (du * v[2]) / sy if abs(v[2]) > 1e-6 else vo
                nf.append((p1, p2, p3, f[3], u, uo, v, vo2, sx, sy))
            b.faces = nf
    for e in ENTITIES[npts:]:
        if "origin" in e.props:
            x, y, z = [float(t) for t in e.props["origin"].split()]
            e.props["origin"] = "%g %g %g" % (x, y, z + du)


def deck_kubols():
    group("Deck kubols")
    shack(-30.0, -31.0, -25.0, -27.6, 2.3, "freight/yero_blue", "freight/tarp_blue", doors=[("s", -27.5, 1.3)], windows=[("n", -28.0, 1.2)], floor_tex="freight/plywood")
    shack(16.0, -31.0, 21.0, -27.8, 2.3, "freight/plywood", "freight/yero_rust", doors=[("w", -29.4, 1.3)], windows=[("n", 18.5, 1.4)], floor_tex="freight/plywood")
    end_group()


def bodega():
    layer("Bodega (warehouse) + Stair A")
    group("Bodega shell")
    X0, X1, Z0, Z1, H = -43.0, -25.0, -16.0, 12.0, 7.0
    t = 0.25
    lower = "freight/chb_raw"
    upper = "freight/yero_rust"
    # walls: hollow block to 1.2 m, sheet above; openings
    for (axis, at, a0, a1, holes, inner) in (
            ("z", X0, Z0, Z1, [(0.0, 5.0, 0.0, 3.6)], "e"),                                   # west: the big door to the pier
            ("z", X1 - t, Z0, Z1, [(-0.5, 3.0, 0.0, 2.6), (7.5, 2.4, 0.0, 2.3)], "w"),        # east: door + broken hole to the plaza
            ("x", Z0, X0 + t, X1 - t, [(-34.0, 2.0, 0.0, 2.25), (-30.5, 1.8, L1, L1 + 2.2)], "s"),  # north: door, upper door to the bridge
            ("x", Z1 - t, X0 + t, X1 - t, [(-36.75, 2.5, 0.0, 2.3), (-28.0, 2.0, 0.0, 2.3)], "n")):  # south: two doors to the alley
        low = [(c, w, h0, min(h1, 1.2)) for (c, w, h0, h1) in holes if h0 < 1.2]
        wall(axis, at, a0, a1, 0.0, 1.2, t, lower, holes=low)
        up = [(c, w, max(h0, 1.2), h1) for (c, w, h0, h1) in holes if h1 > 1.2]
        wall(axis, at, a0, a1, 1.2, H, t, upper, holes=up, **{inner: "freight/yero_old"})
    # rolling shutter over the west door (half down)
    box(X0 - 0.05, 3.6, -2.5, X0 + 0.2, 4.2, 2.5, "freight/steel_grey")
    box(X0 - 0.3, 4.2, -2.7, X0 + 0.25, 4.6, 2.7, "freight/steel_grey")
    # gable roof, ridge along z at the middle
    xm = (X0 + X1) / 2
    for (xa, xb) in ((X0 - 0.4, xm), (xm, X1 + 0.4)):
        ya = H if xa < xm else 8.6
        yb = 8.6 if xa < xm else H
        slab((xa, ya, Z0 - 0.4), (xb, yb, Z0 - 0.4), (xb, yb, Z1 + 0.4), (xa, ya, Z1 + 0.4), 0.08, "freight/yero_rust", under="freight/yero_old")
    for zz in range(-14, 12, 5):     # trusses
        box(X0 + t, H - 0.3, zz - 0.08, X1 - t, H - 0.1, zz + 0.08, "freight/steel_rust")
    # gable ends filled
    for zz in (Z0, Z1 - t):
        add(hull_brush([(X0, H, zz), (X1, H, zz), (xm, 8.55, zz), (X0, H, zz + t), (X1, H, zz + t), (xm, 8.55, zz + t)], upper))
    box(X0 + t, -0.02, Z0 + t, X1 - t, 1.0 / U, Z1 - t, "freight/concrete_wet", top="freight/concrete_wet")
    end_group()
    group("Bodega mezzanine (2nd floor)")
    MZ1 = -9.5
    box(X0 + t, L1 - 0.2, Z0 + t, X1 - t, L1, MZ1, "freight/steel_grey", top="freight/tread_plate", bottom="freight/steel_grey")
    for xx in (-39.0, -34.0, -29.0):
        post(xx, MZ1 - 0.2, 0, L1 - 0.2, "freight/steel_yellow", 0.25)
    railing(-40.8, MZ1 - 0.05, X1 - t - 0.05, MZ1 - 0.05, L1, "freight/steel_yellow")
    # racks on the mezzanine
    for xx in (-36.0, -30.0):
        box(xx, L1, -15.4, xx + 3.0, L1 + 1.6, -14.6, "freight/steel_blue", top="freight/plywood")
    box(-41.8, L1, -13.0, -40.4, L1 + 1.0, -11.6, "freight/sack")
    end_group()
    group("Stair A (west)")
    stairs(X0 + t + 0.02, X0 + t + 1.62, MZ1, MZ1 + 15 * STEP_RUN + 0.01, "n", 0.0, L1, "freight/concrete_rough",
           side_tex="freight/concrete_rough", solid=True, name="Stair A", ramp_tex="freight/clip_concrete")
    end_group()
    group("Bodega racks and stock")
    for xx in (-37.5, -31.5):
        for (z0, z1) in ((-6.0, 1.5), (3.5, 9.5)):
            rack(xx, z0, xx + 1.0, z1, key="%g%g" % (xx, z0))
    sacks(-41.5, 4.0, -39.0, 5.0, 1.2)
    sacks(-28.0, -6.0, -26.0, -3.5, 1.2)
    pallet_stack(-29.0, 5.0, 6)
    pallet_stack(-41.0, 8.0, 4, True)
    box(-35.0, 0, -3.5, -33.4, 1.1, -1.9, "freight/plywood", top="freight/plywood")   # crates
    box(-34.6, 1.1, -3.1, -33.6, 1.9, -2.1, "freight/plywood", top="freight/plywood")
    end_group()
    layer("Lights")
    group("Bodega lights")
    for (xx, zz, f) in ((-34.0, -12.6, ""), (-37.0, -3.0, "dying"), (-31.0, 3.0, ""), (-34.0, 8.5, "flicker"), (-28.0, -6.0, "")):
        hang = 4.6 if zz > -9 else L1 - 0.3
        if hang > L1:
            box(xx - 0.006, hang + 0.05, zz - 0.006, xx + 0.006, 6.7, zz + 0.006, "freight/rubber", ent=_illus())   # the chain
        light((xx, hang, zz), "tube", (214, 232, 255), 1.6, 12.0, f, angle=0)
    light((-42.0, 3.0, -9.0), "bulb", (255, 170, 100), 0.9, 7.0, "")
    light((-30.5, 5.2, -16.6), "lamp", (255, 176, 96), 1.0, 9.0, "")
    end_group()
    layer("Inner row and deck (2nd floor)")
    group("Bridge A (mezzanine - deck)")
    box(-31.6, L1 - 0.12, -26.12, -29.4, L1, -16.0, "freight/grate", top="freight/grate", bottom="freight/grate")
    for zz in (-23.0, -19.2):
        post(-31.5, zz, 0, L1 - 0.12, "freight/steel_rust", 0.18)
        post(-29.5, zz, 0, L1 - 0.12, "freight/steel_rust", 0.18)
    railing(-31.55, -26.1, -31.55, -16.2, L1, "freight/steel_rust")
    railing(-29.45, -26.1, -29.45, -16.2, L1, "freight/steel_rust")
    end_group()


def plaza():
    layer("Plaza (crane yard)")
    group("Gantry crane tower")
    for (xx, zz) in ((-2.6, -2.6), (2.0, -2.6), (-2.6, 2.0), (2.0, 2.0)):
        box(xx, 0, zz, xx + 0.6, 11.0, zz + 0.6, "freight/steel_yellow", top="freight/steel_yellow")
    for yy in (1.4, 6.5, 9.4):     # cross beams
        box(-2.6, yy, -2.6, 2.6, yy + 0.35, -2.25, "freight/steel_yellow")
        box(-2.6, yy, 2.25, 2.6, yy + 0.35, 2.6, "freight/steel_yellow")
        box(-2.6, yy, -2.25, -2.25, yy + 0.35, 2.25, "freight/steel_yellow")
        box(2.25, yy, -2.25, 2.6, yy + 0.35, 2.25, "freight/steel_yellow")
    # the platform at the second floor, round the legs
    box(-3.6, L1 - 0.15, -3.6, 3.6, L1, 3.6, "freight/steel_grey", top="freight/tread_plate", bottom="freight/steel_grey")
    railing(-3.55, -3.55, -1.15, -3.55, L1, "freight/hazard")
    railing(1.15, -3.55, 3.55, -3.55, L1, "freight/hazard")
    railing(-3.55, 3.55, -1.15, 3.55, L1, "freight/hazard")
    railing(1.15, 3.55, 3.55, 3.55, L1, "freight/hazard")
    railing(-3.55, -3.55, -3.55, 3.55, L1, "freight/hazard")
    railing(3.55, -3.55, 3.55, 3.55, L1, "freight/hazard")
    box(-2.0, L1, -0.6, -1.0, L1 + 1.0, 0.6, "freight/plywood", top="freight/plywood")   # crate cover on the platform
    # the machine house and the boom, high above
    box(-3.4, 11.0, -3.4, 3.4, 13.4, 3.4, "freight/steel_yellow", top="freight/steel_grey", bottom="freight/steel_grey")
    box(3.4, 12.0, -0.6, 30.0, 12.9, 0.6, "freight/steel_yellow", ent=_illus())
    box(-12.0, 12.0, -0.6, -3.4, 12.9, 0.6, "freight/steel_yellow", ent=_illus())
    box(-12.0, 10.6, -1.4, -9.0, 12.0, 1.4, "freight/concrete_rough", ent=_illus())
    end_group()
    group("Plaza bridges (2nd floor)")
    for (z0, z1) in ((-26.12, -3.6), (3.6, 16.0)):
        box(-1.1, L1 - 0.14, z0, 1.1, L1, z1, "freight/planks", top="freight/planks", bottom="freight/timber")
        zz = z0 + 4.5
        while zz < z1 - 1.0:
            post(-1.05, zz, 0, L1 - 0.14, "freight/timber", 0.2)
            post(1.05, zz, 0, L1 - 0.14, "freight/timber", 0.2)
            zz += 5.5
        railing(-1.08, z0 + 0.1, -1.08, z1 - 0.1, L1, "freight/timber", h=0.95, posts=2.0)
        railing(1.08, z0 + 0.1, 1.08, z1 - 0.1, L1, "freight/timber", h=0.95, posts=2.0)
    parapet(-1.08, -18.0, -1.08, -12.0, L1, "freight/plywood")
    parapet(1.08, -10.0, 1.08, -6.5, L1, "freight/yero_red")
    parapet(-1.08, 7.0, -1.08, 11.0, L1, "freight/yero_blue")
    end_group()
    group("Sari-sari store")
    shack(-21.0, 2.0, -15.0, 7.5, 2.6, {"n": "freight/chb_mint", "s": "freight/chb_mint", "w": "freight/planks", "e": "freight/chb_mint"},
          "freight/yero_green", doors=[("s", -19.5, 1.2)], windows=[("e", 4.75, 2.6)], fall="w", floor_tex="freight/concrete_rough")
    box(-15.2, 0.9, 3.4, -14.6, 1.0, 6.1, "freight/planks", top="freight/planks")       # the counter ledge
    box(-15.1, 2.25, 2.6, -14.95, 2.65, 6.9, "freight/sign_sarisari", e="freight/sign_sarisari", fit=True)
    box(-14.9, 1.0, 3.6, -14.6, 1.95, 6.0, "freight/chain_link", ent=_illus())
    roof(-15.0, 2.0, -12.8, 7.5, 2.25, 2.55, "freight/tarp_orange", fall="e", over=0.1)   # awning
    post(-12.9, 2.2, 0, 2.25, "freight/timber", 0.1)
    post(-12.9, 7.3, 0, 2.25, "freight/timber", 0.1)
    end_group()
    group("Videoke shack")
    shack(14.0, -6.5, 20.5, 0.0, 2.7, {"n": "freight/plywood", "s": "freight/plywood", "w": "freight/planks", "e": "freight/chb_pink"},
          "freight/yero_red", doors=[("w", -3.25, 3.2)], windows=[("s", 17.5, 1.4)], fall="e", floor_tex="freight/concrete_rough")
    box(14.05, 2.2, -6.0, 14.15, 2.65, -0.5, "freight/sign_videoke", w="freight/sign_videoke", fit=True)
    box(19.6, 0, -4.4, 20.3, 1.1, -2.2, "freight/plastic_white", top="freight/rubber")     # the machine and the tv
    box(19.8, 1.1, -4.0, 20.2, 1.7, -2.6, "freight/rubber")
    box(19.75, 1.15, -3.95, 19.79, 1.65, -2.65, "freight/glow_cool")
    for (xx, zz) in ((16.0, -4.5), (17.0, -2.0), (15.5, -1.5)):
        box(xx, 0, zz, xx + 0.42, 0.45, zz + 0.42, "freight/plastic_red", top="freight/plastic_red")
    roof(11.5, -6.5, 14.0, 0.0, 2.3, 2.55, "freight/tarp_blue", fall="w", over=0.1)
    post(11.6, -6.3, 0, 2.3, "freight/timber", 0.1)
    post(11.6, -0.2, 0, 2.3, "freight/timber", 0.1)
    end_group()
    group("Plaza cover")
    container(-15.0, -17.0, "x", C20, "orange", key="pz1")
    container(7.0, 6.5, "z", C20, "grey", key="pz2")
    container(-10.5, 8.0, "x", C20, "blue", key="pz3")
    sacks(-6.5, -9.0, -3.5, -8.2)
    sacks(3.5, 8.2, 6.5, 9.0)
    sacks(-23.0, -8.0, -22.2, -4.5)
    sacks(9.0, -18.0, 12.0, -17.2)
    for (xx, zz) in ((-8.0, 4.0), (-7.4, 4.6), (10.5, -10.0), (19.0, 10.0), (19.6, 10.5), (-20.5, -20.0)):
        drum(xx, zz, "freight/plastic_blue" if xx < 0 else "freight/plastic_red")
    tire_stack(5.5, -14.0, 5)
    tire_stack(6.2, -13.4, 4)
    tire_stack(-12.0, 13.0, 4)
    pallet_stack(16.0, 4.0, 5)
    pallet_stack(-18.0, -12.0, 6, True)
    box(-14.5, 0, -6.5, -12.5, 1.0, -5.5, "freight/trash", top="freight/trash")     # garbage heap
    prism([(-14.8, -7.0), (-12.0, -7.0), (-11.6, -5.0), (-14.0, -4.6)], 0, 0.7, "freight/trash", top="freight/trash", sides="freight/trash")
    end_group()
    group("Basketball ring")
    post(14.0, -21.0, 0, 3.5, "freight/steel_grey", 0.14)
    box(13.9, 3.0, -21.9, 14.0, 4.0, -20.1, "freight/paint_white")
    box(13.4, 3.05, -21.2, 13.9, 3.08, -20.8, "freight/plastic_red", ent=_illus())
    end_group()
    group("Shrine of the Sto. Nino")
    box(-24.6, 0, -24.0, -23.4, 1.0, -22.6, "freight/chb_white", top="freight/concrete_rough")
    box(-24.6, 1.0, -24.0, -23.5, 2.0, -22.6, "freight/sign_shrine", e="freight/sign_shrine", fit=True)
    roof(-24.8, -24.2, -23.2, -22.4, 2.1, 2.3, "freight/yero_red", fall="e", over=0.05)
    end_group()
    group("Plaza laundry")
    laundry_line(-24.0, -12.5, -16.0, -12.5, 2.6)
    laundry_line(8.0, 12.5, 14.0, 12.5, 2.5)
    end_group()
    layer("Lights")
    group("Plaza lights")
    light((-0.3, 10.8, 3.2), "flood", (255, 168, 86), 3.6, 40.0, angle=225, pitch=55)
    light((0.3, 10.8, -3.2), "flood", (255, 168, 86), 3.0, 36.0, angle=60, pitch=50, fault="sag")
    for (xx, zz, f) in ((-18, -24.6, ""), (-8, -22.0, "flicker"), (10, -22.0, ""), (22, -12.0, ""), (-22.5, 0.0, ""), (22.0, 6.0, "dying"), (-10.0, 14.0, ""), (12.0, 14.5, "")):
        bulb_on_wire((xx, 2.7, zz), f)
    light((-16.2, 2.2, 4.75), "tube", (220, 255, 230), 1.1, 8.0, "", angle=90)
    light((17.0, 2.4, -3.2), "lamp", (255, 60, 170), 1.2, 7.0, "", )
    light((19.5, 1.4, -3.3), "bulb", (120, 170, 255), 0.6, 4.5, "flicker")
    light((-23.4, 1.15, -23.3), "candle", (255, 150, 60), 0.5, 3.5, "candle")
    light((-23.4, 1.15, -23.0), "candle", (255, 150, 60), 0.4, 3.0, "candle")
    end_group()
    layer("Landmarks")
    point("info_landmark", (0, 0.1, 0), name="Crane Tower")
    point("info_landmark", (-34, 0.1, -2), name="Bodega")
    point("info_landmark", (34, 0.1, -1), name="Talyer")
    point("info_landmark", (0, 0.1, -36), name="Container Canyon")
    point("info_landmark", (0, 0.1, 29.5), name="Eskinita")
    point("info_landmark", (-54, 0.1, 0), name="Pantalan 3")
    point("info_landmark", (54, 0.1, 0), name="Truck Gate")


def talyer():
    layer("Talyer (repair shop) + Stair B")
    group("Talyer shell")
    X0, X1, Z0, Z1, H = 25.0, 43.0, -13.25, 12.0, 4.0
    t = 0.2
    wall("x", Z0, X0, X1, 0, H, t, "freight/chb_yellow", holes=[(35.0, 2.2, 0.0, 2.3)], s="freight/chb_raw")
    wall("x", Z1 - t, X0, X1, 0, H, t, "freight/chb_raw", holes=[(31.0, 2.0, 0.0, 2.3), (39.5, 1.8, 0.0, 2.3)])
    wall("z", X1 - t, Z0 + t, Z1 - t, 0, H, t, "freight/chb_yellow", holes=[(-0.5, 4.2, 0.0, 3.3)], w="freight/chb_raw")
    # the open front toward the plaza: posts and a low wall at each end
    box(X0, 0, Z0 + t, X0 + t, H, -9.0, "freight/chb_yellow")
    box(X0, 0, 7.5, X0 + t, H, Z1 - t, "freight/chb_yellow")
    for zz in (-4.5, 0.0, 4.0):
        post(X0 + 0.1, zz, 0, H, "freight/steel_rust", 0.22)
    box(X0 - 0.2, H - 0.5, -9.0, X0 + 0.2, H, 7.5, "freight/steel_rust")
    box(X0 - 0.25, H - 0.95, -6.0, X0 - 0.15, H - 0.5, 3.0, "freight/sign_talyer", w="freight/sign_talyer", fit=True)
    roof(X0, Z0, X1, Z1, H, H + 0.8, "freight/yero_red", fall="w", over=0.4, under="freight/yero_old")
    box(X0 + t, -0.02, Z0 + t, X1 - t, 1.0 / U, Z1 - t, "freight/concrete_wet", top="freight/concrete_wet")
    # inside: a partition with a door (the office) at the south-east
    wall("x", 5.0, 36.0, X1 - t, 0, 2.6, 0.12, "freight/plywood", holes=[(39.0, 1.2, 0.0, 2.1)])
    wall("z", 36.0, 5.12, Z1 - t, 0, 2.6, 0.12, "freight/plywood", holes=[(8.5, 1.4, 1.1, 1.8)])
    end_group()
    group("Talyer floor")
    # a car body on blocks, its cabin
    for (xx, zz) in ((29.0, -6.0), (29.0, -2.2), (31.4, -6.0), (31.4, -2.2)):
        box(xx, 0, zz, xx + 0.4, 0.4, zz + 0.4, "freight/concrete_rough")
    box(28.8, 0.4, -6.4, 32.0, 1.2, -1.6, "freight/steel_blue", top="freight/steel_blue")
    box(29.1, 1.2, -5.2, 31.7, 1.85, -2.6, "freight/steel_blue", top="freight/steel_blue")
    tire_stack(34.0, -10.5, 5)
    tire_stack(34.8, -11.2, 4)
    tire_stack(26.6, 9.5, 3)
    box(40.0, 0, -12.6, 42.6, 1.0, -11.4, "freight/steel_grey", top="freight/tread_plate")     # workbenches
    box(37.0, 0, -12.6, 39.4, 1.0, -11.4, "freight/steel_grey", top="freight/tread_plate")
    for (xx, zz) in ((41.8, -8.0), (41.8, -7.2), (28.0, 3.5)):
        drum(xx, zz, "freight/steel_rust", 0.95)
    box(32.0, 0, 2.0, 34.0, 1.3, 3.2, "freight/plywood", top="freight/plywood")
    box(37.5, 0, 9.5, 42.6, 0.75, 11.6, "freight/planks", top="freight/planks")     # the office desk and cot
    end_group()
    group("Stair B container stack")
    # the inner row turns south here: one container along z on footings, its roof at the second floor
    footings(36.40, -26.12, "z", C40)
    container(36.40, -26.12, "z", C40, "grey", y0=0.3, key="legB")
    # (r21) the stack's roof met the deck's only at one corner, so nobody could walk from one to the other: a tread
    # plate laid over the corner joins them (2 cm proud of both roofs)
    box(35.6, L1 - 0.12, -26.9, 37.2, L1 + 0.02, -25.3, "freight/tread_plate", top="freight/tread_plate", bottom="freight/steel_rust")
    end_group()
    group("Stair B (east)")
    sx0, sx1 = 38.95, 40.55
    top_z = -19.0
    stairs(sx0, sx1, top_z, top_z + 15 * STEP_RUN, "n", 0.0, L1, "freight/tread_plate", side_tex="freight/steel_rust", solid=False, name="Stair B", ramp_tex="freight/clip_steel")
    box(sx0, L1 - 0.12, top_z - 2.0, sx1, L1, top_z, "freight/tread_plate", top="freight/tread_plate", bottom="freight/steel_rust")
    post(sx1 - 0.08, top_z - 1.9, 0, L1 - 0.12, "freight/steel_rust", 0.12)
    post(sx1 - 0.08, top_z - 0.1, 0, L1 - 0.12, "freight/steel_rust", 0.12)
    railing(sx1 + 0.03, top_z - 2.0, sx1 + 0.03, top_z, L1, "freight/steel_rust")
    railing(sx0, top_z - 2.0, sx1, top_z - 2.0, L1, "freight/steel_rust")
    end_group()
    layer("Lights")
    group("Talyer lights")
    light((30.5, 3.6, -4.0), "tube", (220, 236, 255), 1.3, 11.0, "", angle=90)
    light((38.0, 3.6, -9.0), "tube", (220, 236, 255), 1.1, 9.0, "starter", angle=0)
    light((39.5, 2.3, 8.5), "bulb", (255, 170, 100), 0.9, 6.0, "")
    light((40.6, 3.0, -20.0), "lamp", (255, 176, 96), 1.2, 10.0, "flicker")
    end_group()


def east_gate():
    layer("East spawn - Truck Gate")
    group("Guard booth")
    shack(55.0, 8.0, 59.0, 11.5, 2.6, "freight/chb_white", "freight/yero_blue", doors=[("w", 9.75, 1.0)], windows=[("n", 57.0, 2.2), ("w", 10.9, 0.6)], fall="e", floor_tex="freight/concrete_rough")
    end_group()
    group("Weighbridge and trailer")
    box(48.0, 0, -4.0, 59.0, 0.3, 4.0, "freight/concrete_rough", top="freight/tread_plate")
    # a container on a flatbed trailer: chassis, wheels (blocks of tyre), the box
    box(48.6, 0.95, -1.4, 60.6, 1.25, 1.4, "freight/steel_rust", top="freight/steel_rust")
    for xx in (49.4, 50.6, 58.6, 59.8):
        for zz in (-1.25, 0.85):
            box(xx - 0.5, 0.3, zz, xx + 0.5, 1.3, zz + 0.4, "freight/tire", top="freight/rubber")
    container(48.5, -1.22, "x", C40, "red", y0=1.25, key="trailer")
    end_group()
    group("Gate yard cover")
    container(46.0, -24.0, "x", C40, "green", key="eg1")
    container(50.0, 17.0, "z", C40, "blue", key="eg2")
    container(50.0, 17.0, "z", C20, "yellow", y0=CH, key="eg3")
    sacks(46.0, 8.0, 46.8, 11.5)
    sacks(46.0, -12.0, 46.8, -8.5)
    for (xx, zz) in ((47.0, 14.0), (47.6, 14.6), (58.0, -14.0)):
        drum(xx, zz, "freight/steel_rust", 0.95)
    pallet_stack(55.0, -16.0, 5)
    pallet_stack(56.4, -16.0, 3)
    tire_stack(46.5, -30.0, 5)
    end_group()
    layer("Lights")
    group("East lights")
    for zz in (-13.0, 13.0):
        post(60.6, zz, 0, 8.0, "freight/steel_grey", 0.22)
        box(59.9, 7.8, zz - 0.4, 60.6, 8.1, zz + 0.4, "freight/steel_grey")
        light((59.8, 7.7, zz), "flood", (255, 170, 90), 3.2, 34.0, angle=180, pitch=40)
    light((57.0, 2.3, 9.75), "tube", (220, 236, 255), 1.0, 7.0, "", angle=0)
    light((61.0, 3.8, -6.6), "lamp", (255, 60, 40), 0.6, 5.0, "", )
    end_group()
    layer("Spawns")
    group("East Team spawn")
    for xx in (47.8, 50.2, 52.6):
        for zz in (-10.6, -8.0, -5.4, 5.4, 8.0, 10.6):
            point("info_team_spawn", (xx, 0.05, zz), team=2, angle=180)
    end_group()


def eskinita():
    """The shanty maze south of the plaza, the Taas (two storeys) with Stair C, the courtyard."""
    layer("Eskinita (shanties)")
    walls = ["freight/planks", "freight/plywood", "freight/yero_rust", "freight/yero_blue", "freight/chb_pink", "freight/chb_mint",
             "freight/planks_dark", "freight/yero_green", "freight/chb_white", "freight/yero_old", "freight/chb_yellow"]
    roofs = ["freight/yero_rust", "freight/yero_old", "freight/tarp_blue", "freight/yero_red", "freight/tarp_orange", "freight/yero_green"]
    k = [0]

    def wt(i):
        return walls[(i * 7 + k[0] * 3) % len(walls)]

    def S(x0, z0, x1, z1, doors=(), windows=(), h=2.3, fall="s", name=None):
        k[0] += 1
        i = k[0]
        tex = {"n": wt(i), "s": wt(i + 1), "w": wt(i + 2), "e": wt(i + 3)}
        hh = h + (i % 3) * 0.08
        # roofs stay under 2.7 m: from the second floor (3.2 m) the shanties are rooftops below, not a floor
        shack(x0, z0, x1, z1, hh, tex, roofs[i % len(roofs)], doors=doors, windows=windows, fall=fall,
              floor_tex="freight/planks_dark" if i % 2 else "freight/concrete_rough", roof_hi=hh + 0.2, name=name or "Shanty %d" % i)

    # Row 1 (z 15-23), west side: Alley A to the north (z 12-15), Alley B to the south (z 23-26)
    S(-43.0, 15.0, -38.5, 23.0, doors=[("n", -41.0, 1.3)], windows=[("s", -41.0, 1.0)])
    S(-38.5, 15.0, -34.0, 23.0, doors=[("n", -36.2, 1.3), ("s", -36.0, 1.3)], windows=[("e", 21.0, 0.9)])            # through
    S(-31.5, 15.0, -26.3, 19.1, doors=[("n", -29.0, 1.4)], windows=[("e", 17.0, 1.0)])
    S(-31.5, 19.1, -26.3, 23.0, doors=[("s", -29.0, 1.4), ("e", 21.0, 1.2)])
    S(-26.3, 15.0, -21.0, 23.0, doors=[("w", 21.0, 1.2), ("n", -23.5, 1.4)], windows=[("e", 18.0, 1.0)])               # through
    S(-18.5, 16.0, -14.0, 23.0, doors=[("w", 19.0, 1.3), ("e", 19.5, 1.3)], windows=[("n", -16.5, 1.2)])
    # mirror on the east
    S(14.0, 16.0, 18.5, 23.0, doors=[("e", 19.0, 1.3), ("w", 19.5, 1.3)], windows=[("n", 16.5, 1.2)])
    S(21.0, 15.0, 26.3, 23.0, doors=[("e", 21.0, 1.2), ("n", 23.5, 1.4)], windows=[("w", 18.0, 1.0)])
    S(26.3, 15.0, 31.5, 19.1, doors=[("n", 29.0, 1.4)], windows=[("w", 17.0, 1.0)])
    S(26.3, 19.1, 31.5, 23.0, doors=[("s", 29.0, 1.4), ("w", 21.0, 1.2)])
    S(34.0, 15.0, 38.5, 23.0, doors=[("n", 36.2, 1.3), ("s", 36.0, 1.3)], windows=[("w", 21.0, 0.9)])
    S(38.5, 15.0, 43.0, 23.0, doors=[("n", 41.0, 1.3)], windows=[("s", 41.0, 1.0)])
    # Row 2 (z 26-33): Alley B north, Alley C south (z 33-36); the courtyard x -4..4
    S(-43.0, 26.0, -38.0, 33.0, doors=[("n", -40.5, 1.3), ("e", 31.0, 1.1)], windows=[("e", 28.0, 1.0)])
    S(-38.0, 26.0, -34.0, 33.0, doors=[("s", -36.0, 1.3), ("w", 31.0, 1.1)])
    S(-31.5, 26.0, -21.0, 29.5, doors=[("n", -27.0, 1.4), ("e", 27.7, 1.3)], windows=[("n", -23.0, 1.2)])
    S(-31.5, 29.5, -21.0, 33.0, doors=[("s", -26.0, 1.4), ("w", 31.3, 1.2)], windows=[("s", -29.5, 1.2)])
    S(-18.5, 26.0, -11.0, 33.0, doors=[("n", -15.0, 1.4), ("s", -13.0, 1.4)], windows=[("s", -17.0, 1.2)])
    S(-11.0, 26.0, -4.0, 30.1, doors=[("e", 28.0, 1.3)], windows=[("n", -8.0, 1.2)])
    S(-11.0, 30.1, -4.0, 33.0, doors=[("s", -7.5, 1.3)], windows=[("e", 31.5, 1.0)])
    S(4.0, 26.0, 11.0, 30.1, doors=[("w", 28.0, 1.3)], windows=[("n", 8.0, 1.2)])
    S(4.0, 30.1, 11.0, 33.0, doors=[("s", 7.5, 1.3)], windows=[("w", 31.5, 1.0)])
    S(11.0, 26.0, 18.5, 33.0, doors=[("n", 15.0, 1.4), ("s", 13.0, 1.4)], windows=[("s", 17.0, 1.2)])
    S(21.0, 26.0, 31.5, 29.5, doors=[("n", 27.0, 1.4), ("w", 27.7, 1.3)], windows=[("n", 23.0, 1.2)])
    S(21.0, 29.5, 31.5, 33.0, doors=[("s", 26.0, 1.4), ("e", 31.3, 1.2)], windows=[("s", 29.5, 1.2)])
    S(34.0, 26.0, 38.0, 33.0, doors=[("s", 36.0, 1.3), ("e", 31.0, 1.1)])
    S(38.0, 26.0, 43.0, 33.0, doors=[("n", 40.5, 1.3), ("w", 31.0, 1.1)], windows=[("w", 28.0, 1.0)])
    # Row 3 (z 36-41.5) backing onto the estero wall
    for (x0, x1, d) in ((-43.0, -36.0, -39.5), (-36.0, -27.0, -31.0), (-27.0, -19.0, -23.0), (-19.0, -10.0, -14.5), (-10.0, -2.0, -6.0),
                        (2.0, 10.0, 6.0), (10.0, 19.0, 14.5), (19.0, 27.0, 23.0), (27.0, 36.0, 31.0), (36.0, 43.0, 39.5)):
        S(x0, 36.0, x1, 41.5, doors=[("n", d, 1.3)], windows=[("n", d + (2.2 if d < 0 else -2.2), 1.0)], fall="s")
    # the narrow passage between -2 and 2 to the estero wall stays open (a dead-end nook with the pump)
    end_group()
    group("Alley clutter")
    for (xx, zz) in ((-36.0, 24.5), (-20.2, 31.0), (-12.0, 34.6), (20.0, 24.6), (33.0, 30.0), (12.0, 34.4), (-33.0, 18.0), (32.8, 14.0)):
        drum(xx, zz, "freight/plastic_blue" if xx < 0 else "freight/steel_rust", 0.85)
    sacks(-30.0, 23.8, -27.0, 24.6)
    sacks(25.0, 34.1, 28.0, 34.9)
    box(-33.8, 0, 34.0, -32.0, 1.0, 35.2, "freight/trash", top="freight/trash")
    box(32.0, 0, 23.5, 33.8, 0.9, 25.0, "freight/trash", top="freight/trash")
    for (x0, x1, zz, y) in ((-43, -34, 24.5, 2.4), (-31, -21, 34.5, 2.3), (21, 31, 24.5, 2.4), (34, 43, 34.5, 2.3), (-18, -4, 34.5, 2.4), (4, 18, 34.5, 2.4)):
        laundry_line(x0, zz, x1, zz, y)
    end_group()
    group("Courtyard (looban)")
    box(-0.35, 0, 31.0, 0.35, 0.9, 31.7, "freight/steel_blue", top="freight/steel_blue")    # the hand pump
    box(-0.1, 0.9, 31.2, 0.1, 1.4, 31.5, "freight/steel_blue")
    box(-1.2, 0, 30.2, 1.2, 0.08, 32.6, "freight/concrete_rough", top="freight/concrete_rough")
    for (xx, zz) in ((-3.2, 27.0), (2.6, 32.2)):
        drum(xx, zz, "freight/plastic_blue", 0.9)
    sacks(-2.6, 33.4, 2.6, 34.2, 0.8)
    roof(-4.0, 26.0, 0.0, 29.0, 2.3, 2.5, "freight/tarp_green", fall="w", over=0.0)
    post(-0.1, 26.1, 0, 2.3, "freight/timber", 0.1)
    post(-0.1, 28.9, 0, 2.3, "freight/timber", 0.1)
    box(-2.8, 0, 26.3, -1.0, 0.75, 27.4, "freight/planks", top="freight/planks")     # bench / table under the tarp
    end_group()
    layer("Taas (two-storey) + Stair C")
    group("Taas ground floor")
    X0, X1, Z0, Z1 = -14.0, 14.0, 16.0, 23.0
    t = 0.2
    # ground floor: north wall with two lagusan (covered passages) and a shop front; south wall the same
    wall("x", Z0, X0, X1, 0, L1 - 0.2, t, "freight/chb_mint", holes=[(-8.0, 2.0, 0.0, 2.4), (8.0, 2.0, 0.0, 2.4), (0.0, 3.0, 0.9, 2.2), (-3.0, 1.2, 0.0, 2.2)], s="freight/chb_white")
    wall("x", Z1 - t, X0, X1, 0, L1 - 0.2, t, "freight/chb_pink", holes=[(-8.0, 2.0, 0.0, 2.4), (8.0, 2.0, 0.0, 2.4), (11.0, 1.2, 0.0, 2.2)], n="freight/chb_white")
    wall("z", X0, Z0 + t, Z1 - t, 0, L1 - 0.2, t, "freight/chb_mint", holes=[(19.5, 1.3, 0.0, 2.2)])
    wall("z", X1 - t, Z0 + t, Z1 - t, 0, L1 - 0.2, t, "freight/chb_mint", holes=[(19.5, 1.3, 0.0, 2.2)])
    # partitions: the lagusan walls (each passage 2 m wide, walled both sides), rooms between
    for xx in (-9.2, -7.0, 6.8, 9.0):
        wall("z", xx, Z0 + t, Z1 - t, 0, L1 - 0.2, 0.2, "freight/chb_white", holes=[(19.5, 1.0, 0.0, 2.1)] if xx in (-7.0, 6.8) else [])
    box(X0 + t, -0.02, Z0 + t, X1 - t, 0.06, Z1 - t, "freight/concrete_rough", top="freight/concrete_rough")
    box(-2.5, 0, 17.0, 2.5, 0.95, 17.6, "freight/planks", top="freight/planks")       # shop counter behind the front
    end_group()
    group("Taas upper floor (2nd floor)")
    box(X0, L1 - 0.2, Z0, X1, L1, Z1, "freight/concrete_rough", top="freight/planks_dark", bottom="freight/concrete_rough")
    H2 = L1 + 2.7
    # upper walls: windows over the plaza (north) and the alley (south); the bridge door at x = 0 on the north
    wall("x", Z0, X0, X1, L1, H2, t, "freight/yero_blue", s="freight/plywood", holes=[(0.0, 1.8, L1, L1 + 2.2), (-11.0, 1.6, L1 + 0.9, L1 + 1.9), (-5.5, 1.6, L1 + 0.9, L1 + 1.9),
                                                                    (5.5, 1.6, L1 + 0.9, L1 + 1.9), (11.0, 1.6, L1 + 0.9, L1 + 1.9)])
    wall("x", Z1 - t, X0, X1, L1, H2, t, "freight/planks", holes=[(-1.0, 1.4, L1, L1 + 2.2), (-5.5, 1.4, L1, L1 + 2.2), (9.0, 1.4, L1 + 0.9, L1 + 1.9)], n="freight/plywood")
    wall("z", X0, Z0 + t, Z1 - t, L1, H2, t, "freight/yero_old", holes=[(19.5, 1.4, L1 + 0.9, L1 + 1.9)], e="freight/plywood")
    wall("z", X1 - t, Z0 + t, Z1 - t, L1, H2, t, "freight/yero_old", holes=[(19.5, 1.4, L1 + 0.9, L1 + 1.9)], w="freight/plywood")
    # corridor along the north windows (z 16.2-18.4), rooms to the south with doorways
    wall("x", 18.4, X0 + t, X1 - t, L1, H2, 0.1, "freight/plywood", holes=[(-10.0, 1.2, L1, L1 + 2.15), (-3.0, 1.2, L1, L1 + 2.15), (3.0, 1.2, L1, L1 + 2.15), (10.0, 1.2, L1, L1 + 2.15)])
    for xx in (-6.5, 0.0, 6.5):
        wall("z", xx, 18.5, Z1 - t, L1, H2, 0.1, "freight/plywood")
    roof(X0, Z0, X1, Z1, H2, H2 + 0.7, "freight/yero_rust", fall="s", over=0.5)
    box(-12.5, L1, 21.0, -10.5, L1 + 0.5, 22.6, "freight/curtain_rose", top="freight/curtain_rose")     # beds, a cabinet
    box(10.5, L1, 21.0, 12.5, L1 + 0.5, 22.6, "freight/curtain_blue", top="freight/curtain_blue")
    box(-4.2, L1, 21.8, -2.0, L1 + 1.8, 22.6, "freight/planks_dark", top="freight/planks_dark")
    box(4.0, L1, 19.0, 5.2, L1 + 1.0, 20.2, "freight/plywood", top="freight/plywood")
    end_group()
    group("Stair C (south) and the back balcony")
    # Stair C runs up the Taas's south wall in Alley B, rising west, onto a balcony along the wall
    sz0, sz1 = Z1, Z1 + 1.5
    bx = 0.5
    stairs(bx, bx + 15 * STEP_RUN, sz0, sz1, "w", 0.0, L1, "freight/planks", side_tex="freight/planks_dark", solid=True, name="Stair C", ramp_tex="freight/clip_wood")
    box(-7.5, L1 - 0.15, sz0, bx, L1, sz1, "freight/planks", top="freight/planks", bottom="freight/timber")
    for xx in (-7.3, -3.5, 0.3):
        post(xx, sz1 - 0.12, 0, L1 - 0.15, "freight/timber", 0.16)
    railing(-7.5, sz1 - 0.05, bx, sz1 - 0.05, L1, "freight/timber", h=0.95)
    railing(-7.5, sz0 + 0.05, -7.5, sz1 - 0.05, L1, "freight/timber", h=0.95)
    end_group()
    layer("Lights")
    group("Eskinita lights")
    for (xx, zz, f) in ((-40.0, 13.5, ""), (-35.0, 24.5, "flicker"), (-24.0, 24.5, ""), (-12.0, 24.5, ""), (-19.8, 20.0, "dying"),
                        (-32.8, 30.0, ""), (-22.0, 34.5, "flicker"), (-8.0, 34.5, ""), (0.0, 34.6, ""), (8.0, 34.5, "flicker"),
                        (19.8, 28.0, ""), (24.0, 24.5, ""), (35.0, 24.5, "dying"), (32.8, 20.0, ""), (40.0, 13.5, ""), (22.0, 34.5, ""), (38.0, 34.5, "flicker"),
                        (-40.0, 34.5, "")):
        bulb_on_wire((xx, 2.45, zz), f, 1.25, 9.0)
    for (xx, zz) in ((-28.9, 17.0), (28.9, 21.0), (-15.0, 29.5), (7.5, 28.0), (-40.5, 29.5), (-36.0, 19.0), (36.0, 19.0), (-26.0, 31.3), (26.0, 27.7)):
        light((xx, 2.2, zz), "tube" if (int(xx) % 3 == 0) else "bulb", (220, 236, 255) if int(xx) % 3 == 0 else (255, 180, 110), 0.9, 6.5, "flicker" if int(zz) % 4 == 0 else "", angle=0)
    light((-0.1, 2.1, 27.5), "bulb", (255, 190, 120), 0.9, 7.0, "")
    light((0.0, 1.0, 31.35), "candle", (255, 150, 60), 0.35, 2.5, "candle")
    for (xx, f) in ((-10.0, ""), (-3.0, "flicker"), (3.0, ""), (10.0, "dying")):
        light((xx, L1 + 2.4, 17.3), "bulb", (255, 176, 104), 0.9, 7.0, f)
    for xx in (-10.0, -3.0, 3.0, 10.0):
        light((xx, L1 + 2.3, 20.8), "bulb", (255, 160, 96), 0.7, 5.5, "")
    light((-8.0, 2.3, 19.5), "bulb", (255, 176, 104), 0.8, 6.0, "")
    light((8.0, 2.3, 19.5), "bulb", (255, 176, 104), 0.8, 6.0, "flicker")
    light((0.0, 2.6, 19.0), "tube", (220, 236, 255), 1.0, 7.0, "", angle=0)
    light((-2.0, L1 + 2.1, 24.6), "bulb", (255, 176, 104), 1.0, 8.0, "")
    end_group()


def deck_lights():
    layer("Lights")
    group("Deck lights")
    for (xx, zz, f) in ((-27.5, -27.2, ""), (18.5, -27.5, "flicker"), (-10.6, -28.6, ""), (10.6, -28.6, "dying"), (0.0, -27.0, ""), (34.0, -29.5, ""), (37.7, -16.0, "")):
        bulb_on_wire((xx, L1 + 2.2, zz), f, 1.0, 8.0)
    light((-27.5, L1 + 2.0, -29.4), "bulb", (255, 150, 90), 0.7, 5.0, "")
    light((18.5, L1 + 2.0, -29.4), "tube", (220, 236, 255), 0.8, 5.0, "starter", angle=0)
    light((-1.0, L1 + 1.9, -1.0), "bulb", (255, 176, 104), 0.9, 7.0, "flicker")
    light((-30.5, L1 + 2.2, -21.0), "bulb", (255, 176, 104), 0.9, 7.0, "")
    end_group()


def build():
    load_surfaces()
    ground()
    perimeter()
    west_pier()
    canyon()
    inner_row()
    layer("Inner row and deck (2nd floor)")
    lift(deck_kubols, L1)
    bodega()
    plaza()
    talyer()
    east_gate()
    eskinita()
    deck_lights()


# ------------------------------------------------------------------ writing

def fmt(v):
    if abs(v - round(v)) < 1e-6:
        return str(int(round(v)))
    return ("%.6f" % v).rstrip("0").rstrip(".")


def write_brush(f, b):
    f.write("{\n")
    for (p1, p2, p3, tex, u, uo, v, vo, sx, sy) in b.faces:
        f.write("( %s ) ( %s ) ( %s ) %s [ %s %s ] [ %s %s ] 0 %s %s\n" % (
            " ".join(fmt(c) for c in p1), " ".join(fmt(c) for c in p2), " ".join(fmt(c) for c in p3), tex,
            " ".join(fmt(c) for c in u), fmt(uo), " ".join(fmt(c) for c in v), fmt(vo), fmt(sx), fmt(sy)))
    f.write("}\n")


def write(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    nb = 0
    with open(path, "w", newline="\n") as f:
        f.write("// Game: Aetherion\n// Format: Valve\n")
        allents = [WORLD] + list(LAYERS.values()) + GROUPS + ENTITIES
        for i, e in enumerate(allents):
            f.write("// entity %d\n{\n" % i)
            for k, v in e.props.items():
                f.write('"%s" "%s"\n' % (k, v))
            for j, b in enumerate(e.brushes):
                f.write("// brush %d\n" % j)
                write_brush(f, b)
                nb += 1
            f.write("}\n")
    return nb


def main():
    force = "--force" in sys.argv
    out = OUT
    for a in sys.argv[1:]:
        if a.startswith("--out="):
            out = Path(a.split("=", 1)[1])
    stamp = out.with_suffix(".map.gen")
    if out.exists() and not force:
        cur = hashlib.md5(out.read_bytes()).hexdigest()
        if not stamp.exists() or stamp.read_text().strip() != cur:
            print("%s has been edited since this script wrote it; not overwriting (use --force)" % out)
            sys.exit(1)
    build()
    nb = write(out)
    stamp.write_text(hashlib.md5(out.read_bytes()).hexdigest())
    npt = sum(1 for e in ENTITIES if "origin" in e.props)
    print("wrote %s: %d brushes, %d point entities, %d layers, %d groups" % (out, nb, npt, len(LAYERS), len(GROUPS)))


if __name__ == "__main__":
    main()
