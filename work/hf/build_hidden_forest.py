"""Lays out the first version of Hidden Forest (game/maps/hidden_forest/map.json) and drafts its Terrain3D ground
(work/hf/terrain_draft/: heights, texture control map, ground cover), which game/tools/terrain_import.gd writes into
the map's Terrain3D data. After this first version the map file and the Terrain3D data are the source: edit them in
the Godot map editor (editor/maps/hidden_forest.tscn). This script refuses to overwrite a map edited since (--force
starts over).

    python -I work/hf/build_hidden_forest.py [--force]

Hidden Forest: an ancient city swallowed by the jungle, always at night, lit by torches and braziers. x east, z south,
metres. The jungle floor (level 0) is carved into clearings and trails between steep earth banks three to seven metres
high, thick with ferns, taro, banana and trees; the banks are the walls. Temple tops, terraces, the ball court's
platforms and a rope bridge are level 1 (4 m).

  north    Temple of the Sun: a four-tier pyramid with twin shrines on top; Team 3 (three teams) behind it
  north-west  the Serpent Wall: ruined rooms behind a wall of carved serpent scales
  north-east  the Moon Well: a sacred sinkhole in a ring of shrines, vines hanging into it
  centre   Heart of the Forest: a pyramid with a tunnel and a crypt through its base, the sun stone on top,
           a rope bridge from its top to a lookout over the east trail
  east     the Ball Court: the I-shaped court between two sloping benches, platforms on top
  west     the Observatory: a round tower on a platform, windows over the west trails
  south-west  the Temazcal: steam-bath huts round a hearth
  south    the Court of Skulls: a sunken plaza under terraces, the skull rack in the middle
  south-east  the Jade Shrine
  spawns   Team 1 the Eagle Gate (west), Team 2 the Jaguar Gate (east), Team 3 behind the Temple of the Sun
Hidden paths (narrow, overgrown) cut between the areas, under root arches and through the pyramid.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
MAP_ID = "hidden_forest"
OUT = ROOT / "game" / "maps" / MAP_ID / "map.json"
STAMP = ROOT / "work" / "hf" / "hidden_forest.last_written"
DRAFT = ROOT / "work" / "hf" / "terrain_draft"
SIZES = json.loads((ROOT / "work" / "hf" / "models" / "sizes.json").read_text())

FH = 4.0
BOUNDS = (-78.0, -78.0, 78.0, 78.0)
AREA = (-128.0, -128.0, 128.0, 128.0)
SP = 0.5
N = int(round((AREA[2] - AREA[0]) / SP)) + 1          # 513 samples a side
XS = AREA[0] + np.arange(N) * SP
GX, GZ = np.meshgrid(XS, XS)                          # [iz, ix]

pieces = []
_ids = set()


def add(**p):
    pid = p["id"]
    k = 2
    while pid in _ids:
        pid = "%s_%d" % (p["id"], k)
        k += 1
    p["id"] = pid
    _ids.add(pid)
    pieces.append(p)
    return p


def r3(v):
    return [round(float(c), 3) for c in v]


def box(pid, layer, at, size, mat, **kw):
    return add(id=pid, type="box", layer=layer, at=r3(at), size=r3(size), mat=mat, **kw)


def floor(pid, layer, at, size, mat, t=0.3, **kw):
    return add(id=pid, type="floor", layer=layer, at=r3(at), size=r3(size), t=t, mat=mat, **kw)


def wall(pid, layer, a, b, mat, h=3.0, y=0.0, t=0.6, openings=None, **kw):
    return add(id=pid, type="wall", layer=layer, **{"from": r3(a)}, to=r3(b), y=round(y, 3), h=round(h, 3), t=t, mat=mat,
               openings=openings or [], **kw)


def column(pid, layer, at, h, r=0.35, mat="jungle/temple_stone", sides=10, **kw):
    return add(id=pid, type="column", layer=layer, at=r3(at), r=r, h=round(h, 3), sides=sides, mat=mat, **kw)


def poly(pid, layer, at, pts, h, mat, **kw):
    return add(id=pid, type="poly", layer=layer, at=r3(at), points=[r3(q) for q in pts], h=round(h, 3), mat=mat, **kw)


def stairs(pid, layer, at, yaw, rise, w, mat="jungle/temple_steps", **kw):
    return add(id=pid, type="stairs", layer=layer, at=r3(at), yaw=yaw, w=w, rise=rise, run=0.28, mat=mat, **kw)


def light(pid, layer, at, kind="torch", color="#ff913c", energy=1.6, rng=9.0, fault="torch", **kw):
    return add(id=pid, type="light", layer=layer, at=r3(at), kind=kind, color=color, energy=energy, range=rng, fault=fault, **kw)


def prop(pid, layer, at, model, yaw=0.0, **kw):
    return add(id=pid, type="prop", layer=layer, at=r3(at), model=model, yaw=round(yaw % 360.0, 1), physics=False, **kw)


def vines(pid, layer, a, b, drop=2.5, density=3.0, **kw):
    return add(id=pid, type="vines", layer=layer, **{"from": r3(a)}, to=r3(b), drop=round(drop, 2), density=density, **kw)


def spawn(pid, at, team, yaw, use=""):
    return add(id=pid, type="spawn", layer="Spawns", at=r3(at), team=team, yaw=round(yaw % 360.0, 1), **({"for": use} if use else {}))


def spot(pid, at, kind, yaw, name=""):
    return add(id=pid, type="spot", layer="Bot spots", at=r3(at), kind=kind, yaw=round(yaw % 360.0, 1), name=name)


def landmark(pid, at, name):
    return add(id=pid, type="landmark", layer="Landmarks", at=r3(at), name=name)


def bearing(a, b):
    """Compass bearing from a to b (0 north = -z, 90 east = +x)."""
    return math.degrees(math.atan2(b[0] - a[0], -(b[1] - a[1]))) % 360.0


# ------------------------------------------------------------------ the walkable network (jungle floor, level 0)

def octagon(cx, cz, r, rot=22.5):
    return [(cx + r * math.sin(math.radians(rot + 45 * k)), cz - r * math.cos(math.radians(rot + 45 * k))) for k in range(8)]


def rect(x0, z0, x1, z1):
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def circle(cx, cz, r, n=28):
    return [(cx + r * math.cos(t * math.tau / n), cz + r * math.sin(t * math.tau / n)) for t in range(n)]


CLEARINGS = {
    "eagle_gate": octagon(-60, 36, 15.5),
    "jaguar_gate": rect(48, 12, 74, 36),
    "sun_temple": rect(-27, -77, 19, -43),
    "serpent_wall": rect(-56, -55, -29, -33),
    "moon_well": circle(44, -46, 16),
    "heart": rect(-24, -28, 17, 10),
    "ball_court": rect(20, -25, 58, 2),
    "observatory": circle(-56, -8, 15.5),
    "temazcal": rect(-39, 11, -19, 29),
    "skull_court": rect(-15, 39, 29, 71),
    "jade_shrine": rect(28, 31, 45, 49),
}
# trails: (points, width, kind)  kind: trail | sacbe (paved causeway) | hidden (narrow, overgrown)
TRAILS = [
    ([(-50, 31), (-41, 25), (-33, 21)], 5.0, "trail"),            # Eagle Gate -> Temazcal
    ([(-22, 15), (-18, 6)], 5.0, "trail"),                         # Temazcal -> Heart
    ([(50, 17), (49, 8), (51, 1)], 5.0, "trail"),                  # Jaguar Gate -> Ball Court (its east end)
    ([(22, -9), (13, -9)], 5.5, "trail"),                          # Ball Court -> Heart (under the lookout)
    ([(-62, 22), (-60, 10), (-58, 5)], 4.5, "trail"),              # Eagle Gate -> Observatory
    ([(-52, -20), (-50, -30), (-47, -34)], 4.5, "trail"),          # Observatory -> Serpent Wall
    ([(-31, -46), (-26, -52)], 4.5, "trail"),                      # Serpent Wall -> Temple of the Sun
    ([(64, 12), (61, -4), (57, -20), (52, -34)], 4.5, "trail"),    # Jaguar Gate -> Moon Well
    ([(56, -10), (60, -8)], 4.0, "trail"),                         # Ball Court east end -> the east trail
    ([(30, -52), (18, -57)], 4.5, "trail"),                        # Moon Well -> Temple of the Sun
    ([(-4, -44), (-4, -27)], 7.0, "sacbe"),                        # the north causeway
    ([(-4, 9), (0, 24), (4, 40)], 7.0, "sacbe"),                   # the south causeway
    ([(-53, 48), (-40, 53), (-27, 51), (-13, 42.5)], 4.5, "trail"),  # Eagle Gate -> Court of Skulls (its open north side)
    ([(57, 35), (50, 40), (45, 40)], 4.5, "trail"),                # Jaguar Gate -> Jade Shrine
    ([(-31, -37), (-25, -31), (-21, -27)], 2.6, "hidden"),         # Serpent Wall -> Heart (under a root arch)
    ([(46, -31), (50, -21)], 2.6, "hidden"),                       # Moon Well -> Ball Court
    ([(-26, 28), (-20, 36), (-13, 42)], 2.6, "hidden"),            # Temazcal -> Court of Skulls
    ([(-46, 2), (-42, 7), (-38, 13)], 2.6, "hidden"),              # Observatory -> Temazcal
    ([(29, 32), (21, 20), (14, 9)], 2.8, "hidden"),                # Jade Shrine -> Heart
    ([(17, -50), (24, -46), (30, -44)], 2.6, "hidden"),            # Temple of the Sun -> Moon Well
]
# ground that is levelled flat under a structure: (polygon, height, blend metres)
FLATS = []


def flat(pts, h=0.0, blend=1.5):
    FLATS.append((pts, h, blend))


def px(x, z):
    return ((x - AREA[0]) / SP, (z - AREA[1]) / SP)


def raster(polys=(), lines=(), size=N):
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    for pts in polys:
        d.polygon([px(*q) for q in pts], fill=255)
    for pts, w in lines:
        p = [px(*q) for q in pts]
        d.line(p, fill=255, width=max(1, int(round(w / SP))))
        for q in p:
            r = w / SP / 2
            d.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=255)
    return np.asarray(im) > 127


def fbm(scales, seed, amps=None):
    rng = np.random.default_rng(seed)
    out = np.zeros((N, N))
    tot = 0.0
    for i, s in enumerate(scales):
        a = (amps[i] if amps else 0.5 ** i)
        g = rng.standard_normal((N // s + 4, N // s + 4))
        z = ndimage.zoom(g, s, order=3)[:N, :N]
        out += z * a
        tot += a
    out /= tot
    return out / (np.percentile(np.abs(out), 99) + 1e-6)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ structures

def tiers(pid, layer, cx, cz, w0, d0, n, th, sw, sd, side="jungle/temple_talud", top="jungle/temple_floor", holes=(), y0=0.0):
    """A stepped platform: n tiers th tall, each sw / sd smaller on every side; holes: axis-aligned [x0, z0, x1, z1, y_top]
    rectangles kept clear up to y_top (a tunnel, a crypt)."""
    out = []
    for k in range(n):
        w = w0 - 2 * k * sw
        d = d0 - 2 * k * sd
        ya = y0 + k * th
        yb = ya + th
        rects = [(cx - w / 2, cz - d / 2, cx + w / 2, cz + d / 2)]
        for hx0, hz0, hx1, hz1, hy in holes:
            if ya >= hy:
                continue
            nxt = []
            for (a0, b0, a1, b1) in rects:
                if hx1 <= a0 or hx0 >= a1 or hz1 <= b0 or hz0 >= b1:
                    nxt.append((a0, b0, a1, b1))
                    continue
                # cut the rectangle round the hole: north, south, west, east pieces
                if hz0 > b0:
                    nxt.append((a0, b0, a1, hz0))
                if hz1 < b1:
                    nxt.append((a0, hz1, a1, b1))
                zz0, zz1 = max(b0, hz0), min(b1, hz1)
                if hx0 > a0:
                    nxt.append((a0, zz0, hx0, zz1))
                if hx1 < a1:
                    nxt.append((hx1, zz0, a1, zz1))
            rects = nxt
        for i, (a0, b0, a1, b1) in enumerate(rects):
            hh = th
            for hx0, hz0, hx1, hz1, hy in holes:
                pass
            if a1 - a0 < 0.05 or b1 - b0 < 0.05:
                continue
            out.append(box("%s_t%d%s" % (pid, k, chr(97 + i) if len(rects) > 1 else ""), layer,
                           ((a0 + a1) / 2, ya, (b0 + b1) / 2), (a1 - a0, hh, b1 - b0), side, top=top))
    return out


def stair_flight(pid, layer, foot, yaw, rise, w, alfardas=True, mat="jungle/temple_steps", balustrade="jungle/temple_stone", y0=0.0):
    """Stairs up from foot (x, z) toward bearing yaw, with balustrades (alfardas) sloping beside them."""
    n = max(2, int(round(rise / 0.18)))
    run = n * 0.28
    stairs(pid, layer, (foot[0], y0, foot[1]), yaw, rise, w, mat=mat)
    if alfardas:
        fx, fz = math.sin(math.radians(yaw)), -math.cos(math.radians(yaw))
        rx, rz = -fz, fx
        # They stop at 60% of the climb: a balustrade's top near the upper floor's height would read as floor to the
        # bots' survey (stranded waypoints on it).
        k = 0.6
        L = math.hypot(run, rise) * k
        pitch = math.degrees(math.atan2(rise, run))
        for s in (-1, 1):
            cx = foot[0] + fx * (run * k / 2 - 0.28) + rx * s * (w / 2 + 0.35)
            cz = foot[1] + fz * (run * k / 2 - 0.28) + rz * s * (w / 2 + 0.35)
            box("%s_alf%s" % (pid, "l" if s < 0 else "r"), layer, (cx, y0 + rise * k / 2 - 0.1, cz), (0.7, 0.55, L + 0.4), balustrade,
                yaw=yaw, tilt=[round(pitch, 2), 0])
    return run


def shrine(pid, layer, cx, cz, y, w, d, h, mat, door_face="s", roof="jungle/temple_stone", comb=True):
    """A roofed room on a platform: one doorway, a flat roof and a roof comb."""
    x0, x1, z0, z1 = cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2
    door = [{"at": w / 2, "w": 1.6, "h": 2.4, "sill": 0}]
    # walls counter-clockwise seen from above (left = inside)
    wall(pid + "_n", layer, (x1, z0), (x0, z0), mat, h=h, y=y, t=0.7, openings=door if door_face == "n" else [])
    wall(pid + "_w", layer, (x0, z0), (x0, z1), mat, h=h, y=y, t=0.7, openings=[{"at": d / 2, "w": 1.6, "h": 2.4, "sill": 0}] if door_face == "w" else [])
    wall(pid + "_s", layer, (x0, z1), (x1, z1), mat, h=h, y=y, t=0.7, openings=door if door_face == "s" else [])
    wall(pid + "_e", layer, (x1, z1), (x1, z0), mat, h=h, y=y, t=0.7, openings=[{"at": d / 2, "w": 1.6, "h": 2.4, "sill": 0}] if door_face == "e" else [])
    floor(pid + "_roof", layer, (cx, y + h + 0.35, cz), (w + 0.6, d + 0.6), roof, t=0.35)
    if comb:
        box(pid + "_comb", layer, (cx, y + h + 0.35, cz), (w * 0.7, 1.4, 0.6), "jungle/fret_panel")
        for k in range(5):
            box(pid + "_merlon%d" % k, layer, (cx - w * 0.3 + k * w * 0.15, y + h + 1.75, cz), (0.45, 0.5, 0.5), "jungle/stucco_white")


def rubble(pid, layer, cx, cz, n, spread, seed, y=0.0, solid_big=True):
    rng = np.random.default_rng(seed)
    for k in range(n):
        s = rng.uniform(0.25, 0.85)
        big = s > 0.65
        box("%s_r%d" % (pid, k), layer, (cx + rng.uniform(-spread, spread), y - 0.08, cz + rng.uniform(-spread, spread)),
            (s * rng.uniform(0.9, 1.6), s * rng.uniform(0.5, 1.0), s * rng.uniform(0.8, 1.3)), "jungle/temple_rubble",
            yaw=float(rng.uniform(0, 360)), tilt=[round(float(rng.uniform(-14, 14)), 1), round(float(rng.uniform(-14, 14)), 1)],
            **({} if (big and solid_big) else {"solid": False}))


def broken_wall(pid, layer, a, b, mat, hmin, hmax, seed, t=0.7, y=0.0, segs=None):
    """A ruined wall: segments of uneven height, gaps where it fell, rubble at its foot."""
    rng = np.random.default_rng(seed)
    L = math.dist(a, b)
    n = segs or max(2, int(L / 2.2))
    for k in range(n):
        t0, t1 = k / n, (k + 1) / n
        if rng.random() < 0.15 and 0 < k < n - 1:
            rubble("%s_gap%d" % (pid, k), layer, a[0] + (b[0] - a[0]) * (t0 + t1) / 2, a[1] + (b[1] - a[1]) * (t0 + t1) / 2, 3, 0.8, seed + k, y=y)
            continue
        p0 = (a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0)
        p1 = (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)
        wall("%s_%d" % (pid, k), layer, p0, p1, mat, h=float(rng.uniform(hmin, hmax)), y=y, t=t)


def torch(pid, layer, x, z, H, mount="pole", minor=False, pole=1.9, **kw):
    y = H(x, z) + pole if mount == "pole" else kw.pop("y")
    return light(pid, layer, (x, y, z), kind="torch", color="#ff8a34", energy=2.8, rng=13.0, fault="torch",
                 mount=mount, **({"pole": pole} if mount == "pole" and pole != 1.9 else {}), **({"minor": True} if minor else {}), **kw)


def brazier(pid, layer, x, y, z, mount="stand", energy=4.2, rng=17.0, minor=False, yaw=0.0):
    top = {"stand": 1.08, "bowl": 0.42, "none": 0.0}[mount]
    return light(pid, layer, (x, y + top + 0.12, z), kind="brazier", color="#ff7a2a", energy=energy, rng=rng, fault="torch",
                 mount=mount, yaw=yaw, **({"minor": True} if minor else {}))


# ------------------------------------------------------------------ the ground

def build_terrain():
    walk = raster(polys=CLEARINGS.values(), lines=[(p, w) for p, w, k in TRAILS])
    trail = raster(lines=[(p, w) for p, w, k in TRAILS if k == "trail"])
    sacbe = raster(lines=[(p, w) for p, w, k in TRAILS if k == "sacbe"])
    hidden = raster(lines=[(p, w) for p, w, k in TRAILS if k == "hidden"])
    d_out = ndimage.distance_transform_edt(~walk) * SP
    d_in = ndimage.distance_transform_edt(walk) * SP
    low = fbm([96, 48], 11)
    mid = fbm([24, 12], 12)
    fine = fbm([8, 4, 2], 13)
    vfine = fbm([2, 1], 14)
    bank = 4.6 + 1.5 * low + 0.7 * mid
    # tall knolls and rock spines here and there on the banks
    knolls = np.maximum(fbm([40, 20], 15), 0) ** 2 * 3.5
    bank = np.clip(bank + knolls, 3.6, 10.0)
    ox = np.maximum(np.abs(GX) - BOUNDS[2], 0)
    oz = np.maximum(np.abs(GZ) - BOUNDS[3], 0)
    outer = np.sqrt(ox * ox + oz * oz)
    bank += np.clip(outer * 0.3, 0, 9.0)
    edge_w = 2.3 + 0.9 * mid
    t = np.clip((d_out - 0.25) / edge_w, 0, 1)
    prof = 1 - (1 - t) ** 2.4
    micro = 0.15 * fine + 0.05 * vfine
    micro = micro - 0.12 * smooth(-low, 0.3, 0.9)          # boggy hollows in the clearings
    h = micro * (1 - prof) + (bank + 0.35 * fine) * prof
    # level the ground under every structure (and pave the causeways flat)
    for pts, target, blend in FLATS + [(None, 0.0, 1.0)]:
        if pts is None:
            m = sacbe
        else:
            m = raster(polys=[pts])
        dist = ndimage.distance_transform_edt(~m) * SP
        wgt = np.clip(1 - dist / max(blend, 0.01), 0, 1) * (1 - prof * 0.98)
        flat_h = target + 0.03 * vfine
        h = h * (1 - wgt) + flat_h * wgt
    # the Moon Well's sinkhole
    r = np.hypot(GX - 44, GZ + 46)
    pit = smooth(-r, -7.1, -6.2)
    h = h * (1 - pit) + (-7.2 + 0.35 * fine) * pit
    # keep the floor within the bots' step band, the banks clear of the floor
    h = np.where(walk & (pit < 0.01), np.clip(h, -0.32, 0.32), h)
    # ------------------------------------------------ texture control: base, overlay, blend (Terrain3D's bit layout)
    gz, gx = np.gradient(h, SP)
    slope = np.hypot(gx, gz)
    nz = fbm([16, 6], 21) * 0.5 + 0.5
    nz2 = fbm([10, 3], 22) * 0.5 + 0.5
    LIT, SPR, SOIL, ROOTS, TRAIL, LICH, CLIFF, FLAG, GRASS = range(9)
    base = np.full((N, N), LIT, np.uint32)
    over = np.full((N, N), SPR, np.uint32)
    blend = np.clip(nz * 255 * 0.9, 0, 255)
    # banks: roots and soil on the slopes, rock where steep, leafy grass and litter on top
    onbank = ~walk
    base = np.where(onbank, np.where(slope > 1.3, CLIFF, np.where(slope > 0.45, ROOTS, GRASS)), base)
    over = np.where(onbank, np.where(slope > 1.3, LICH, np.where(slope > 0.45, SOIL, LIT)), over)
    blend = np.where(onbank, np.clip(nz2 * 230, 0, 255), blend)
    # trails: packed earth with leaves blown over it; hidden paths: roots and soil
    base = np.where(trail, TRAIL, base)
    over = np.where(trail, LIT, over)
    blend = np.where(trail, np.clip((nz - 0.35) * 255 * 1.4 + np.clip(1.6 - d_in, 0, 1) * 120, 0, 255), blend)
    base = np.where(hidden, ROOTS, base)
    over = np.where(hidden, SOIL, over)
    # causeways and plazas: the old paving, half buried in litter
    pav = sacbe.copy()
    for pts, target, b in FLATS:
        pav |= raster(polys=[pts])
    base = np.where(pav & walk, FLAG, base)
    over = np.where(pav & walk, LIT, over)
    blend = np.where(pav & walk, np.clip((nz2 - 0.45) * 255 * 2.0, 0, 210), blend)
    base = np.where(pit > 0.02, SOIL, base)
    over = np.where(pit > 0.02, LICH, over)
    ctl = ((base & 0x1F) << 27) | ((over & 0x1F) << 22) | ((blend.astype(np.uint32) & 0xFF) << 14)
    return h.astype(np.float32), ctl.astype(np.uint32), walk, d_out, d_in, pav, trail | sacbe | hidden


# ------------------------------------------------------------------ the map

def build(h, walk, d_out, d_in, pav, paths):
    def H(x, z):
        fx = (x - AREA[0]) / SP
        fz = (z - AREA[1]) / SP
        ix = int(np.clip(math.floor(fx), 0, N - 2))
        iz = int(np.clip(math.floor(fz), 0, N - 2))
        tx, tz = fx - ix, fz - iz
        a = h[iz, ix] * (1 - tx) + h[iz, ix + 1] * tx
        b = h[iz + 1, ix] * (1 - tx) + h[iz + 1, ix + 1] * tx
        return float(a * (1 - tz) + b * tz)

    def DOUT(x, z):
        i, j = int((z - AREA[1]) / SP), int((x - AREA[0]) / SP)
        return float(d_out[np.clip(i, 0, N - 1), np.clip(j, 0, N - 1)])

    def HMIN(x, z, r):
        return min(H(x + dx, z + dz) for dx, dz in ((0, 0), (r, 0), (-r, 0), (0, r), (0, -r)))

    # ---------------------------------------------------------------- Eagle Gate (Team 1, west)
    L = "Eagle Gate"
    cx, cz, R = -60.0, 36.0, 11.5
    exits = [bearing((cx, cz), (-62, 22)), bearing((cx, cz), (-50, 31)), bearing((cx, cz), (-53, 48))]
    verts = [(cx + R * math.sin(math.radians(22.5 + 45 * k)), cz - R * math.cos(math.radians(22.5 + 45 * k))) for k in range(8)]
    for k in range(8):
        mid_b = (45 * k + 45) % 360
        if any(min(abs(mid_b - e), 360 - abs(mid_b - e)) < 26 for e in exits):
            continue
        a, b = verts[k], verts[(k + 1) % 8]
        wall("eg_wall%d" % k, L, a, b, "jungle/temple_stone", h=2.8, t=0.9)
        box("eg_cap%d" % k, L, ((a[0] + b[0]) / 2, 2.8, (a[1] + b[1]) / 2), (math.dist(a, b) + 0.3, 0.3, 1.2), "jungle/tezontle",
            yaw=bearing(a, b) - 90)
        vines("eg_vines%d" % k, L, (a[0], 3.0, a[1]), (b[0], 3.0, b[1]), drop=1.8, density=2.5, seed=100 + k)
    flat(octagon(cx, cz, R + 1.5))
    box("eg_altar", L, (cx, 0, cz), (4.0, 1.1, 4.0), "jungle/temple_stone", top="jungle/temple_floor")
    box("eg_altar_frieze", L, (cx, 1.1, cz), (3.2, 0.5, 3.2), "jungle/glyph_panel")
    prop("eg_eagle", L, (cx, 1.6, cz), "hf_stone_figure", 90, foot=0.4)
    for k, (dx, dz) in enumerate([(-6.5, -3.5), (-6.5, 3.5), (-2.0, 7.0), (-2.0, -7.0)]):
        box("eg_cover%d" % k, L, (cx + dx, 0, cz + dz), (2.2, 1.2, 0.9), "jungle/temple_rubble", yaw=float(30 * k + 15))
    for k, e in enumerate(exits):
        for s in (-1, 1):
            g = math.radians(e + s * 19)
            bx_, bz_ = cx + (R + 0.8) * math.sin(g), cz - (R + 0.8) * math.cos(g)
            brazier("eg_brazier%d%s" % (k, "ab"[s > 0]), L, bx_, 0.0, bz_, minor=(s > 0))
    for k in range(8):
        a = math.radians(30 + k * 45)
        spawn("t1_%d" % k, (cx + 6.5 * math.sin(a) * 0.9, 0.05, cz - 6.5 * math.cos(a) * 0.9), 1, bearing((cx, cz), (0, 0)))
    landmark("lm_eagle", (cx, 0, cz), "Eagle Gate")
    prop("eg_jaguar_w", L, (cx - 9.5, 0, cz), "hf_effigy", 90, foot=0.5)

    # ---------------------------------------------------------------- Jaguar Gate (Team 2, east)
    L = "Jaguar Gate"
    x0, z0, x1, z1 = 51.0, 15.0, 71.0, 33.0
    flat(rect(x0 - 1.5, z0 - 1.5, x1 + 1.5, z1 + 1.5))
    # outer walls, counter-clockwise, with gates west (to the Ball Court trail), north (to the east trail), south
    wall("jg_wall_n", L, (x1, z0), (x0, z0), "jungle/temple_stone", h=3.2, t=0.9, openings=[{"at": 7.0, "w": 3.6, "h": 3.2, "sill": 0}])
    wall("jg_wall_w", L, (x0, z0), (x0, z1), "jungle/temple_stone", h=3.2, t=0.9, openings=[{"at": 4.5, "w": 3.6, "h": 3.2, "sill": 0}, {"at": 14.0, "w": 2.4, "h": 3.2, "sill": 0}])
    wall("jg_wall_s", L, (x0, z1), (x1, z1), "jungle/temple_stone", h=3.2, t=0.9, openings=[{"at": 6.0, "w": 3.6, "h": 3.2, "sill": 0}])
    wall("jg_wall_e", L, (x1, z1), (x1, z0), "jungle/temple_stone", h=3.2, t=0.9)
    for nm, a, b in [("n", (x1, z0), (x0, z0)), ("w", (x0, z0), (x0, z1)), ("s", (x0, z1), (x1, z1)), ("e", (x1, z1), (x1, z0))]:
        vines("jg_vines_" + nm, L, (a[0], 3.3, a[1]), (b[0], 3.3, b[1]), drop=2.0, density=2.2, seed=hash(nm) % 1000)
    # the dais at the east end, jaguars watching the gates
    box("jg_dais", L, (68.0, 0, 24.0), (4.0, 1.2, 12.0), "jungle/temple_stone", top="jungle/temple_floor")
    box("jg_dais_frieze", L, (65.9, 0, 24.0), (0.2, 1.2, 12.0), "jungle/fret_panel", solid=False)
    stairs("jg_dais_st", L, (64.6, 0, 24.0), 90, 1.2, 3.0)
    prop("jg_jaguar_n", L, (68.5, 1.2, 19.5), "hf_jaguar", 270, foot=[1.3, 1.9], foot_h=2.4)
    prop("jg_jaguar_s", L, (68.5, 1.2, 28.5), "hf_jaguar", 270, foot=[1.3, 1.9], foot_h=2.4)
    # a colonnade down the middle and low inner walls for cover
    for k in range(5):
        column("jg_col%d" % k, L, (57.5, 0, 17.5 + k * 3.25), 3.4, r=0.42, mat="jungle/stucco_red")
    floor("jg_colroof", L, (57.5, 3.75, 24.0), (2.4, 15.0), "jungle/temple_stone", t=0.35)
    broken_wall("jg_inner_a", L, (61.0, 16.5), (61.0, 21.0), "jungle/rubble_wall", 1.1, 1.5, 31, t=0.6)
    broken_wall("jg_inner_b", L, (61.0, 27.0), (61.0, 31.5), "jungle/rubble_wall", 1.1, 1.5, 32, t=0.6)
    for k, (bx_, bz_) in enumerate([(50.0, 17.0), (50.0, 21.5), (54.0, 13.8), (60.0, 13.8), (55.0, 34.2), (59.0, 34.2)]):
        brazier("jg_brazier%d" % k, L, bx_, 0.0, bz_, minor=(k % 2 == 1))
    torch("jg_wt1", L, 51.6, 27.0, H, mount="wall", y=2.6, yaw=90)
    torch("jg_wt2", L, 70.4, 20.0, H, mount="wall", y=2.6, yaw=270, minor=True)
    for k in range(8):
        spawn("t2_%d" % k, (64.0 + (k % 2) * 2.5, 0.05, 17.5 + (k // 2) * 4.0), 2, bearing((65, 24), (0, 0)))
    landmark("lm_jaguar", (61, 0, 24), "Jaguar Gate")

    # ---------------------------------------------------------------- Temple of the Sun (north)
    L = "Temple of the Sun"
    tcx, tcz = -4.0, -62.0
    flat(rect(-23, -75, 15, -45), blend=2.0)
    tiers("sun", L, tcx, tcz, 26.0, 18.0, 4, 1.0, 1.25, 1.125)
    # the top: 16 x 9.5 at 4 m. Front stair (south), side stairs (east and west, narrower)
    ztop = tcz + (18.0 - 2 * 3 * 1.125) / 2
    run = stair_flight("sun_st", L, (tcx, ztop + 22 * 0.28 + 0.02), 0, 4.0, 5.0)
    xside = tcx + (26.0 - 2 * 3 * 1.25) / 2
    stair_flight("sun_st_e", L, (xside + 6.18, tcz + 1.5), 270, 4.0, 2.6)
    stair_flight("sun_st_w", L, (tcx - (xside - tcx) - 6.18, tcz + 1.5), 90, 4.0, 2.6)
    prop("sun_serpent_l", L, (tcx - 3.4, 0, ztop + 6.9), "hf_serpent_head", 180, foot=[1.6, 1.4], foot_h=2.2)
    prop("sun_serpent_r", L, (tcx + 3.4, 0, ztop + 6.9), "hf_serpent_head", 180, foot=[1.6, 1.4], foot_h=2.2)
    # twin shrines: red for the sun and war (west), blue-white for the rain (east)
    shrine("sun_shrine_w", L, tcx - 4.3, tcz - 1.2, FH, 5.6, 5.2, 3.2, "jungle/stucco_red")
    shrine("sun_shrine_e", L, tcx + 4.3, tcz - 1.2, FH, 5.6, 5.2, 3.2, "jungle/stucco_white")
    brazier("sun_braz_tl", L, tcx - 7.0, FH, ztop - 0.6, mount="bowl")
    brazier("sun_braz_tr", L, tcx + 7.0, FH, ztop - 0.6, mount="bowl")
    brazier("sun_braz_in_w", L, tcx - 4.3, FH, tcz - 1.6, mount="bowl", energy=1.6, rng=6.0, minor=True)
    brazier("sun_braz_in_e", L, tcx + 4.3, FH, tcz - 1.6, mount="bowl", energy=1.6, rng=6.0, minor=True)
    brazier("sun_braz_foot_l", L, tcx - 4.8, 0.0, ztop + 7.6)
    brazier("sun_braz_foot_r", L, tcx + 4.8, 0.0, ztop + 7.6)
    for k, (vx0, vz, vx1) in enumerate([(tcx - 13, tcz + 9, tcx - 3), (tcx + 3, tcz + 9, tcx + 13)]):
        vines("sun_vines_f%d" % k, L, (vx0, 1.0, vz), (vx1, 1.0, vz), drop=0.9, density=2.0, seed=200 + k)
    vines("sun_vines_top_w", L, (tcx - 8.0, 4.0, ztop), (tcx - 3.4, 4.0, ztop), drop=2.6, density=2.6, seed=210)
    vines("sun_vines_top_e", L, (tcx + 3.4, 4.0, ztop), (tcx + 8.0, 4.0, ztop), drop=2.6, density=2.6, seed=211)
    vines("sun_vines_sh_w", L, (tcx - 7.1, FH + 3.6, tcz + 1.6), (tcx - 1.5, FH + 3.6, tcz + 1.6), drop=1.5, density=3.0, seed=212)
    vines("sun_vines_sh_e", L, (tcx + 1.5, FH + 3.6, tcz + 1.6), (tcx + 7.1, FH + 3.6, tcz + 1.6), drop=1.5, density=3.0, seed=213)
    # the plaza in front: stelae, an altar, broken columns
    for k, x in enumerate([-15.0, 7.0]):
        prop("sun_stela%d" % k, L, (x, 0, -50.0), "hf_serpent_stele", 180, foot=[1.4, 1.2], foot_h=2.9)
    box("sun_altar", L, (tcx, 0, -47.5), (3.0, 0.9, 1.6), "jungle/skull_rack", top="jungle/temple_floor")
    for k, (x, z, hh) in enumerate([(-19, -60, 2.4), (-19, -66, 1.3), (11, -60, 2.9), (11, -66, 1.6), (-12, -47, 1.1), (4, -46, 1.9)]):
        column("sun_col%d" % k, L, (x, 0, z), hh, r=0.45, mat="jungle/temple_cobble")
    rubble("sun_rub_a", L, -20.5, -55, 6, 1.6, 41)
    rubble("sun_rub_b", L, 12.5, -54, 6, 1.6, 42)
    # Team 3 waits behind the temple (three teams only)
    for k in range(8):
        spawn("t3_%d" % k, (-14.0 + k * 3.4, 0.05, -73.0 + (k % 2) * 1.2), 3, 180, use="3")
    box("sun_back_wall_a", L, (-15, 0, -70.0), (5.0, 1.3, 0.8), "jungle/rubble_wall")
    box("sun_back_wall_b", L, (7, 0, -70.0), (5.0, 1.3, 0.8), "jungle/rubble_wall")
    torch("sun_t_back_w", L, -22.0, -71.0, H)
    torch("sun_t_back_e", L, 14.0, -71.0, H, minor=True)
    landmark("lm_sun", (tcx, FH, tcz), "Temple of the Sun")
    spot("sp_sun_top_w", (tcx - 6.5, FH, ztop - 0.8), "snipe", 200, "Temple of the Sun, west corner")
    spot("sp_sun_top_e", (tcx + 6.5, FH, ztop - 0.8), "snipe", 160, "Temple of the Sun, east corner")
    spot("sp_sun_shrine", (tcx - 4.3, FH, tcz - 2.0), "hide", 180, "Red shrine")

    # ---------------------------------------------------------------- the Serpent Wall (north-west)
    L = "Serpent Wall"
    flat(rect(-54, -53, -31, -36), blend=1.2)
    wall("sw_serpent", L, (-53.0, -38.5), (-34.0, -38.5), "jungle/serpent_scales", h=2.6, t=1.0,
         openings=[{"at": 6.0, "w": 2.2, "h": 2.6, "sill": 0}, {"at": 14.5, "w": 2.2, "h": 2.6, "sill": 0}])
    box("sw_serpent_cap", L, (-43.5, 2.6, -38.5), (19.4, 0.35, 1.4), "jungle/tezontle")
    vines("sw_vines_wall", L, (-53.0, 2.9, -38.0), (-34.0, 2.9, -38.0), drop=1.8, density=3.2, seed=300)
    # three ruined rooms behind it
    for k, rx in enumerate([-50.0, -43.5, -37.0]):
        broken_wall("sw_room%d_n" % k, L, (rx - 2.8, -51.5), (rx + 2.8, -51.5), "jungle/rubble_wall", 1.0, 2.6, 310 + k)
        broken_wall("sw_room%d_w" % k, L, (rx - 2.8, -51.5), (rx - 2.8, -44.0), "jungle/temple_stone", 0.9, 2.4, 320 + k, segs=3)
        wall("sw_room%d_s" % k, L, (rx - 2.8, -44.0), (rx + 2.8, -44.0), "jungle/temple_stone", h=2.2, t=0.6,
             openings=[{"at": 2.8, "w": 1.6, "h": 2.2, "sill": 0}])
        rubble("sw_room%d_rub" % k, L, rx, -48.0, 4, 1.4, 330 + k)
        spot("sp_sw_room%d" % k, (rx, 0, -49.0), "hide", 180, "Serpent Wall room")
    broken_wall("sw_room_e", L, (-34.2, -51.5), (-34.2, -44.0), "jungle/temple_stone", 0.9, 2.4, 340, segs=3)
    prop("sw_pillar", L, (-43.5, 0, -41.5), "hf_tribal_pillar", 180, foot=[1.3, 1.2], foot_h=3.6)
    prop("sw_atlantean_a", L, (-55.0, 0, -36.0), "hf_atlantean", 135, foot=0.5, foot_h=3.6)
    torch("sw_t1", L, -54.5, -43.0, H)
    torch("sw_t2", L, -32.5, -41.0, H, minor=True)
    torch("sw_wt", L, -43.5, -38.0, H, mount="wall", y=2.2, yaw=180)
    landmark("lm_serpent", (-43, 0, -44), "Serpent Wall")

    # ---------------------------------------------------------------- the Moon Well (north-east)
    L = "Moon Well"
    wcx, wcz = 44.0, -46.0
    flat(circle(wcx, wcz, 13.5), blend=1.5)
    n = 18
    for k in range(n):
        a0, a1 = k * math.tau / n, (k + 1) * math.tau / n
        p0 = (wcx + 7.0 * math.cos(a0), wcz + 7.0 * math.sin(a0))
        p1 = (wcx + 7.0 * math.cos(a1), wcz + 7.0 * math.sin(a1))
        wall("mw_parapet%d" % k, L, p0, p1, "jungle/temple_stone", h=1.0, t=0.6)
        if k % 2 == 0:
            q0 = (wcx + 6.4 * math.cos(a0), wcz + 6.4 * math.sin(a0))
            q1 = (wcx + 6.4 * math.cos(a1), wcz + 6.4 * math.sin(a1))
            vines("mw_vines%d" % k, L, (q0[0], 0.9, q0[1]), (q1[0], 0.9, q1[1]), drop=5.5, density=3.5, seed=400 + k)
    add(id="mw_clip", type="column", layer=L, at=r3((wcx, -8.0, wcz)), r=7.05, h=11.5, sides=18, mat="freight/clip")
    floor("mw_water", L, (wcx, -6.2, wcz), (12.6, 12.6), "jungle/cenote_water", t=0.1, solid=False)
    for k, a in enumerate([0, 90, 180, 270]):
        g = math.radians(a)
        sx, sz = wcx + 11.0 * math.sin(g), wcz - 11.0 * math.cos(g)
        box("mw_shrine%d" % k, L, (sx, 0, sz), (3.0, 1.0, 3.0), "jungle/temple_stone", top="jungle/temple_floor", yaw=a)
        prop("mw_stela%d" % k, L, (sx, 1.0, sz), ["hf_tribal_pillar", "hf_atlantean", "hf_effigy", "hf_stone_figure"][k], a + 180, foot=0.6, foot_h=3.0)
        brazier("mw_braz%d" % k, L, wcx + 7.8 * math.sin(g + 0.4), 0.0, wcz - 7.8 * math.cos(g + 0.4), mount="bowl", minor=(k % 2 == 1))
    landmark("lm_well", (wcx, 0, wcz), "Moon Well")
    spot("sp_well_n", (wcx, 0, wcz - 11.5), "cover", 180, "Moon Well shrine")

    # ---------------------------------------------------------------- Heart of the Forest (centre)
    L = "Heart of the Forest"
    hcx, hcz = -4.0, -9.0
    flat(rect(-23, -27, 15, 9), blend=1.5)
    # the pyramid, 18 x 18, with a tunnel (west-east) and a crypt through its base
    tun = (hcx - 9.5, hcz - 1.5, hcx + 9.5, hcz + 1.5, 2.8)
    crypt = (hcx - 3.5, hcz - 3.5, hcx + 3.5, hcz + 3.5, 2.8)
    tiers("hrt", L, hcx, hcz, 18.0, 18.0, 4, 1.0, 1.0, 1.0, holes=[tun, crypt])
    floor("hrt_tun_ceiling", L, (hcx, 3.0, hcz), (17.0, 3.0), "jungle/temple_stone", t=0.2, under="jungle/temple_rubble")
    floor("hrt_crypt_ceiling", L, (hcx, 3.0, hcz), (7.0, 7.0), "jungle/temple_stone", t=0.2, under="jungle/glyph_panel")
    floor("hrt_tun_floor", L, (hcx, 0.06, hcz), (18.0, 3.0), "jungle/temple_floor", t=0.2)
    floor("hrt_crypt_floor", L, (hcx, 0.07, hcz), (7.0, 7.0), "jungle/temple_paving", t=0.2)
    box("hrt_crypt_altar", L, (hcx, 0.05, hcz - 2.2), (2.6, 0.95, 1.2), "jungle/skull_rack", top="jungle/temple_floor")
    prop("hrt_crypt_effigy", L, (hcx, 1.0, hcz - 2.5), "hf_effigy", 180, foot=0.35, foot_h=1.0)
    brazier("hrt_crypt_braz_a", L, hcx - 2.6, 0.05, hcz + 2.4, mount="bowl", energy=1.8, rng=7.0)
    brazier("hrt_crypt_braz_b", L, hcx + 2.6, 0.05, hcz + 2.4, mount="bowl", energy=1.8, rng=7.0, minor=True)
    torch("hrt_tun_wt_w", L, hcx - 7.0, hcz - 1.25, H, mount="wall", y=2.1, yaw=180)
    torch("hrt_tun_wt_e", L, hcx + 7.0, hcz + 1.25, H, mount="wall", y=2.1, yaw=0, minor=True)
    spot("sp_crypt", (hcx + 2.0, 0.07, hcz - 2.0), "hide", 90, "The crypt")
    # stairs north and south to the top (10 x 10 at 4 m), the sun stone standing on it
    stair_flight("hrt_st_n", L, (hcx, hcz - 6.0 - 6.18), 180, 4.0, 3.6)
    stair_flight("hrt_st_s", L, (hcx, hcz + 6.0 + 6.18), 0, 4.0, 3.6)
    prop("hrt_sun_stone", L, (hcx, FH, hcz - 1.0), "hf_sun_stone", 180, foot=[3.6, 0.6], foot_h=3.8)
    brazier("hrt_top_braz_w", L, hcx - 3.8, FH, hcz + 3.6, mount="bowl")
    brazier("hrt_top_braz_e", L, hcx + 3.8, FH, hcz + 3.6, mount="bowl")
    for k, (a, b) in enumerate([((hcx - 9, -0.1), (hcx - 2.4, -0.1)), ((hcx + 2.4, -0.1), (hcx + 9, -0.1)),
                                ((hcx - 9, hcz - 9.1), (hcx - 2.4, hcz - 9.1)), ((hcx + 2.4, hcz - 9.1), (hcx + 9, hcz - 9.1))]):
        vines("hrt_vines%d" % k, L, (a[0], 1.0, a[1]), (b[0], 1.0, b[1]), drop=0.95, density=2.4, seed=500 + k)
    vines("hrt_vines_tun_w", L, (hcx - 9.0, 2.9, hcz - 1.4), (hcx - 9.0, 2.9, hcz + 1.4), drop=1.6, density=4.0, seed=510)
    vines("hrt_vines_tun_e", L, (hcx + 9.0, 2.9, hcz - 1.4), (hcx + 9.0, 2.9, hcz + 1.4), drop=1.6, density=4.0, seed=511)
    spot("sp_heart_top_n", (hcx + 3.0, FH, hcz - 3.5), "snipe", 0, "Heart of the Forest, top")
    spot("sp_heart_top_s", (hcx - 3.0, FH, hcz + 3.5), "snipe", 180, "Heart of the Forest, top")
    # the plaza round it: altars and stelae for cover, paving
    for k, (x, z, yaw) in enumerate([(-18.0, -20.0, 45), (10.0, -20.0, 315), (-18.0, 3.0, 135), (10.0, 3.0, 225)]):
        box("hrt_plinth%d" % k, L, (x, 0, z), (3.4, 1.15, 2.2), "jungle/temple_stone", top="jungle/temple_floor", yaw=yaw)
        prop("hrt_plinth%d_st" % k, L, (x, 1.15, z), ["hf_stone_figure", "hf_effigy", "hf_effigy", "hf_stone_figure"][k], yaw + 180)
        brazier("hrt_plinth%d_braz" % k, L, x + 2.6 * math.sin(math.radians(yaw)), 0.0, z - 2.6 * math.cos(math.radians(yaw)), minor=(k % 2 == 1))
    prop("hrt_pillar_w", L, (-20.5, 0, -9.0), "hf_tribal_pillar", 90, foot=[1.3, 1.2], foot_h=3.6)
    prop("hrt_olmec", L, (11.5, 0, -14.0), "hf_olmec_head", 250, foot=1.15, foot_h=2.6)
    prop("hrt_trunk", L, (12.0, 0, 5.5), "hf_buttress_trunk", 30, foot=1.5, foot_h=4.0)
    landmark("lm_heart", (hcx, FH, hcz), "Heart of the Forest")
    # the rope bridge from the top (east edge) to the lookout over the east trail
    lx, lz = 13.0, -9.0
    bx0, bx1 = hcx + 5.0, lx - 2.5
    floor("hrt_bridge", L, ((bx0 + bx1) / 2, FH, hcz), (bx1 - bx0, 1.9), "jungle/planks", t=0.12)
    for k in range(int(bx1 - bx0) // 2 + 1):
        x = bx0 + 0.5 + k * 2.0
        if x > bx1:
            break
        for s in (-1, 1):
            column("hrt_br_post%d%s" % (k, "ab"[s > 0]), L, (x, FH, hcz + s * 1.0), 1.05, r=0.05, mat="jungle/wood_moss", sides=6)
    for s in (-1, 1):
        box("hrt_br_rope%s" % "ab"[s > 0], L, ((bx0 + bx1) / 2, FH + 0.95, hcz + s * 1.0), (bx1 - bx0, 0.05, 0.05), "jungle/torch_wrap", solid=False)
        box("hrt_br_rail%s" % "ab"[s > 0], L, ((bx0 + bx1) / 2, FH, hcz + s * 1.0), (bx1 - bx0, 1.0, 0.08), "freight/clip")
    vines("hrt_br_vines", L, (bx0 + 1.0, FH - 0.1, hcz + 0.9), (bx1 - 1.0, FH - 0.1, hcz + 0.9), drop=1.4, density=2.0, sag=0.3, seed=520)
    # the lookout: a platform on posts over the trail, stairs down on its east side
    floor("lk_floor", L, (lx, FH, lz), (5.0, 5.0), "jungle/planks", t=0.25)
    for sx in (-1, 1):
        for sz_ in (-1, 1):
            column("lk_post%d%d" % (sx, sz_), L, (lx + sx * 2.3, -0.3, lz + sz_ * 2.3), FH + 1.4, r=0.22, mat="jungle/wood_moss", sides=8)
    wall("lk_rail_n", L, (lx - 2.5, lz - 2.5), (lx + 2.5, lz - 2.5), "jungle/planks", h=1.0, y=FH, t=0.12)
    wall("lk_rail_e", L, (lx + 2.5, lz - 2.5), (lx + 2.5, lz + 2.5), "jungle/planks", h=1.0, y=FH, t=0.12)
    wall("lk_rail_s", L, (lx + 2.5, lz + 2.5), (lx + 0.1, lz + 2.5), "jungle/planks", h=1.0, y=FH, t=0.12)
    stair_flight("lk_st", L, (lx - 1.0, lz + 2.5 + 6.18), 0, 4.0, 1.5, alfardas=False, mat="jungle/planks")
    torch("lk_t", L, lx + 2.3, lz - 2.3, H, mount="none", y=FH + 1.1)
    spot("sp_lookout", (lx, FH, lz), "snipe", 90, "The lookout")

    # ---------------------------------------------------------------- the Ball Court (east)
    L = "Ball Court"
    flat(rect(21, -21, 57, 0), blend=1.2)
    bc_x0, bc_x1, alley_z0, alley_z1 = 27.0, 51.0, -13.0, -7.0
    floor("bc_alley", L, ((bc_x0 + bc_x1) / 2, 0.05, (alley_z0 + alley_z1) / 2), (bc_x1 - bc_x0 + 8.0, alley_z1 - alley_z0), "jungle/stucco_white", t=0.2)
    px0, px1 = 31.0, 47.0
    for side, zs in {"n": alley_z0, "s": alley_z1}.items():
        sgn = -1 if side == "n" else 1
        # the sloping bench, then the upright wall, then the platform on top (level 1), stairs up at both its ends
        box("bc_bench_" + side, L, ((bc_x0 + bc_x1) / 2, 0, zs + sgn * 1.25), (bc_x1 - bc_x0, 1.0, 2.5), "jungle/stucco_red",
            top="jungle/temple_floor")
        box("bc_slope_" + side, L, ((bc_x0 + bc_x1) / 2, 1.0, zs + sgn * 3.0), (bc_x1 - bc_x0, 3.0, 1.0), "jungle/glyph_panel",
            top="jungle/temple_floor")
        box("bc_plat_" + side, L, ((px0 + px1) / 2, 0, zs + sgn * 5.75), (px1 - px0, FH, 4.5), "jungle/temple_stone",
            top="jungle/temple_floor")
        box("bc_ring_" + side, L, ((bc_x0 + bc_x1) / 2, 2.2, zs + sgn * 2.45), (1.5, 1.5, 0.3), "jungle/sun_disc", solid=False)
        stair_flight("bc_st_%sw" % side, L, (px0 - 6.18, zs + sgn * 5.75), 90, 4.0, 2.6)
        stair_flight("bc_st_%se" % side, L, (px1 + 6.18, zs + sgn * 5.75), 270, 4.0, 2.6)
        brazier("bc_braz_%sw" % side, L, px0 + 1.0, FH, zs + sgn * 7.2, mount="bowl")
        brazier("bc_braz_%se" % side, L, px1 - 1.0, FH, zs + sgn * 7.2, mount="bowl", minor=True)
        vines("bc_vines_" + side, L, (px0 + 1, FH, zs + sgn * 3.5), (px1 - 1, FH, zs + sgn * 3.5), drop=1.8, density=1.8, seed=600 + (side == "s"))
        spot("sp_bc_%s" % side, ((px0 + px1) / 2 - 4.0, FH, zs + sgn * 6.0), "snipe", 90 if side == "n" else 270, "Ball Court platform")
    for k, x in enumerate([bc_x0 - 2.0, bc_x1 + 2.0]):
        box("bc_end%d" % k, L, (x, 0, -10.0), (1.0, 0.9, 6.0), "jungle/temple_rubble", top="jungle/temple_floor")
    torch("bc_t_w", L, 23.0, -15.5, H)
    torch("bc_t_e", L, 55.0, -4.5, H, minor=True)
    landmark("lm_ball", (39, 0, -10), "Ball Court")

    # ---------------------------------------------------------------- the Observatory (west)
    L = "Observatory"
    ocx, ocz = -56.0, -8.0
    flat(circle(ocx, ocz, 11.5), blend=1.5)
    tiers("obs", L, ocx, ocz, 12.0, 12.0, 2, 2.0, 0.6, 0.6, side="jungle/temple_talud")
    stair_flight("obs_st", L, (ocx + 5.4 + 6.18, ocz), 270, 4.0, 2.8)
    n = 12
    for k in range(n):
        a0, a1 = k * math.tau / n, (k + 1) * math.tau / n
        p0 = (ocx + 3.4 * math.cos(a0), ocz + 3.4 * math.sin(a0))
        p1 = (ocx + 3.4 * math.cos(a1), ocz + 3.4 * math.sin(a1))
        mid = (a0 + a1) / 2
        east = math.cos(mid) > 0.8
        ops = [{"at": math.dist(p0, p1) / 2, "w": 1.5, "h": 2.3, "sill": 0}] if east else ([{"at": math.dist(p0, p1) / 2, "w": 0.8, "h": 0.7, "sill": 1.1}] if k % 2 == 0 else [])
        wall("obs_tower%d" % k, L, p0, p1, "jungle/stucco_white", h=3.6, y=FH, t=0.5, openings=ops)
    floor("obs_dome", L, (ocx, FH + 3.9, ocz), (7.6, 7.6), "jungle/temple_stone", t=0.35)
    box("obs_dome2", L, (ocx, FH + 3.9, ocz), (5.2, 1.0, 5.2), "jungle/stucco_white", yaw=45)
    torch("obs_t_in", L, ocx - 1.5, ocz, H, mount="none", y=FH + 2.3, minor=True)
    brazier("obs_braz_a", L, ocx + 5.2, FH, ocz - 4.4, mount="bowl")
    brazier("obs_braz_b", L, ocx + 9.0, 0.0, ocz - 4.2)
    vines("obs_vines", L, (ocx - 6.0, 2.0, ocz + 6.0), (ocx + 2.0, 2.0, ocz + 6.0), drop=1.9, density=2.6, seed=700)
    spot("sp_obs_w", (ocx - 2.0, FH, ocz), "snipe", 300, "Observatory window")
    spot("sp_obs_s", (ocx, FH, ocz + 2.0), "snipe", 200, "Observatory window")
    landmark("lm_obs", (ocx, FH, ocz), "Observatory")

    # ---------------------------------------------------------------- the Temazcal (south-west)
    L = "Temazcal"
    flat(rect(-38, 12, -20, 28), blend=1.0)
    for k, (bx_, bz_, door) in enumerate([(-34.5, 15.5, "e"), (-34.5, 24.5, "e"), (-24.0, 25.0, "n")]):
        shrine("tz_bath%d" % k, L, bx_, bz_, 0.0, 4.4, 4.4, 2.7, "jungle/stucco_red" if k != 1 else "jungle/temple_stone", door_face=door, comb=False)
        box("tz_bath%d_dome" % k, L, (bx_, 3.05, bz_), (3.2, 0.7, 3.2), "jungle/temple_rubble", yaw=45)
        brazier("tz_bath%d_coals" % k, L, bx_, 0.0, bz_, mount="bowl", energy=1.4, rng=5.0, minor=True)
        spot("sp_tz%d" % k, (bx_ + 0.8, 0, bz_ + 0.8), "hide", 90, "Steam bath")
    box("tz_hearth", L, (-27.0, 0, 17.0), (2.6, 0.6, 2.6), "jungle/basalt", top="jungle/basalt")
    brazier("tz_hearth_fire", L, -27.0, 0.6, 17.0, mount="none", energy=2.2, rng=10.0)
    box("tz_wall_s", L, (-29.0, 0, 28.2), (16.0, 1.4, 0.7), "jungle/rubble_wall")
    prop("tz_log", L, (-23.0, 0, 13.6), "hf_log_2", 80, foot=[0.9, 3.8], foot_h=0.9)
    landmark("lm_tz", (-29, 0, 20), "Temazcal")

    # ---------------------------------------------------------------- the Court of Skulls (south)
    L = "Court of Skulls"
    flat(rect(-14, 40, 28, 70), blend=1.5)
    # terraces round three sides (level 1), their faces carved with skulls
    box("sk_ter_s", L, (7.0, 0, 66.5), (42.0, FH, 7.0), "jungle/skull_rack", top="jungle/temple_floor")
    box("sk_ter_w", L, (-11.0, 0, 53.0), (6.0, FH, 20.0), "jungle/skull_rack", top="jungle/temple_floor")
    box("sk_ter_e", L, (25.0, 0, 56.0), (6.0, FH, 14.0), "jungle/skull_rack", top="jungle/temple_floor")
    stair_flight("sk_st_s1", L, (0.0, 63.0 - 6.18), 180, 4.0, 3.2)
    stair_flight("sk_st_s2", L, (15.0, 63.0 - 6.18), 180, 4.0, 3.2)
    stair_flight("sk_st_w", L, (-8.0 + 6.18, 47.0), 270, 4.0, 2.6)
    stair_flight("sk_st_e", L, (22.0 - 6.18, 51.0), 90, 4.0, 2.6)
    for k, x in enumerate([-12.0, 26.0]):
        prop("sk_atlantean%d" % k, L, (x, FH, 64.5), "hf_atlantean", 0, foot=0.5, foot_h=3.6)
    # the skull rack (tzompantli) in the middle: a platform carved with skulls, a rack of poles on it
    box("sk_rack_base", L, (7.0, 0, 52.0), (14.0, 1.3, 3.2), "jungle/skull_rack", top="jungle/temple_floor")
    for k in range(7):
        column("sk_rack_post%d" % k, L, (1.0 + k * 2.0, 1.3, 52.0), 2.6, r=0.11, mat="jungle/wood_moss", sides=6)
    for k in range(3):
        box("sk_rack_bar%d" % k, L, (7.0, 1.9 + k * 0.6, 52.0), (12.4, 0.07, 0.07), "jungle/wood_moss", solid=False)
    box("sk_altar", L, (7.0, 0, 45.0), (3.2, 1.0, 2.0), "jungle/basalt", top="jungle/temple_floor")
    prop("sk_olmec", L, (-6.5, 0, 44.5), "hf_olmec_head", 160, foot=1.15, foot_h=2.6)
    for k, (x, z) in enumerate([(-3.0, 58.0), (17.0, 58.0), (13.0, 44.5)]):
        box("sk_block%d" % k, L, (x, 0, z), (2.6, 1.15, 1.4), "jungle/temple_cobble", yaw=float(k * 23))
    for k, (x, y, z) in enumerate([(-6.0, FH, 62.5), (20.0, FH, 62.5), (-11.0, FH, 45.0), (25.0, FH, 51.0), (2.5, 0.0, 49.0), (11.5, 0.0, 49.0)]):
        brazier("sk_braz%d" % k, L, x, y, z, mount="bowl" if y > 0 else "stand", minor=(k % 2 == 1))
    vines("sk_vines_s", L, (-13.0, FH, 63.0), (27.0, FH, 63.0), drop=2.2, density=1.6, seed=800)
    spot("sp_sk_ter_s", (7.0, FH, 66.0), "snipe", 0, "Court of Skulls terrace")
    spot("sp_sk_ter_w", (-11.0, FH, 52.0), "snipe", 90, "Court of Skulls terrace")
    spot("sp_sk_rack", (7.0, 0, 54.5), "cover", 0, "The skull rack")
    landmark("lm_skulls", (7, 0, 55), "Court of Skulls")

    # ---------------------------------------------------------------- the Jade Shrine (south-east)
    L = "Jade Shrine"
    flat(rect(29, 32, 44, 48), blend=1.0)
    box("js_plat", L, (37.0, 0, 40.0), (6.0, 1.0, 6.0), "jungle/temple_talud", top="jungle/temple_floor")
    prop("js_jaguar", L, (37.0, 1.0, 40.0), "hf_jaguar", 315, foot=[1.3, 1.9], foot_h=2.4)
    for k, (x, z, hh) in enumerate([(32.0, 35.0, 2.2), (42.0, 35.0, 1.2), (32.0, 45.0, 0.9), (42.0, 45.0, 2.8)]):
        column("js_col%d" % k, L, (x, 0, z), hh, r=0.42, mat="jungle/temple_cobble")
    brazier("js_braz", L, 33.5, 0.0, 40.0)
    rubble("js_rub", L, 41.0, 38.0, 5, 1.4, 900)
    landmark("lm_jade", (37, 0, 40), "Jade Shrine")

    # ---------------------------------------------------------------- the sacbe (causeways): raised paving and stelae
    L = "Causeways"
    for k, (a, b) in enumerate([((-4, -43.0), (-4, -28.0)), ((-4, 10.0), (0.4, 24.0)), ((0.4, 24.0), (4, 39.0))]):
        c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        floor("cw_pave%d" % k, L, (c[0], 0.1, c[1]), (6.0, math.dist(a, b)), "jungle/temple_paving", t=0.4, yaw=bearing(a, b))
    for k, (x, z, m) in enumerate([(-8.2, -38.0, "hf_serpent_stele"), (0.2, -33.0, "hf_atlantean"), (-6.0, 17.0, "hf_tribal_pillar"), (6.5, 31.0, "hf_serpent_stele")]):
        prop("cw_stela%d" % k, L, (x, H(x, z), z), m, bearing((x, z), (-4, 0)), foot=0.55, foot_h=3.0)

    # ---------------------------------------------------------------- the root arches over the hidden paths
    L = "Jungle"
    for k, (x, z, yaw) in enumerate([(-26.0, -32.0, 45), (-20.0, 35.0, 140)]):
        prop("arch%d" % k, L, (x, HMIN(x, z, 2.0) - 0.4, z), "hf_root_arch", yaw)
        g = math.radians(yaw + 90)
        for s in (-1, 1):
            add(id="arch%d_leg%s" % (k, "ab"[s > 0]), type="column", layer=L, at=r3((x + s * 3.0 * math.sin(g), -0.5, z - s * 3.0 * math.cos(g))),
                r=0.9, h=6.0, sides=8, mat="freight/clip")
        vines("arch%d_vines" % k, L, (x - 2.0 * math.sin(g), 5.5, z + 2.0 * math.cos(g)), (x + 2.0 * math.sin(g), 5.5, z - 2.0 * math.cos(g)),
              drop=3.5, density=4.0, seed=950 + k)

    # ---------------------------------------------------------------- trees, rocks, logs: the jungle round it all
    rng = np.random.default_rng(77)
    placed = []

    def far(x, z, r):
        return all(math.dist((x, z), q) >= r for q in placed)

    def scatter(model, count, dmin, dmax, spacing, seed, yaw_any=True, foot=None, foot_h=2.5, inner=78.0, sink=0.3, minh=None):
        rr = np.random.default_rng(seed)
        got = 0
        for _ in range(count * 60):
            if got >= count:
                break
            x, z = rr.uniform(-inner - 6, inner + 6), rr.uniform(-inner - 6, inner + 6)
            d = DOUT(x, z)
            if d < dmin or d > dmax or not far(x, z, spacing):
                continue
            y = HMIN(x, z, 1.2) - sink
            if minh is not None and y < minh:
                continue
            placed.append((x, z))
            extra = {"foot": foot, "foot_h": foot_h} if (foot and d < 1.5) else {}
            prop("%s_%d" % (model.replace("hf_", ""), got), L, (x, y, z), model, float(rr.uniform(0, 360)), **extra)
            got += 1
        return got

    counts = {}
    counts["ceiba"] = scatter("hf_ceiba", 16, 3.5, 14.0, 24.0, 1)
    counts["canopy"] = scatter("hf_canopy_tree", 30, 2.0, 16.0, 13.0, 2)
    counts["island"] = scatter("tree_island", 10, 1.5, 12.0, 10.0, 3)
    counts["island2"] = scatter("tree_island2", 8, 1.5, 12.0, 10.0, 4)
    counts["buttress"] = scatter("hf_buttress_trunk", 10, 0.6, 6.0, 9.0, 5, foot=1.5, foot_h=4.0, sink=0.4)
    counts["cliff"] = 0
    # rock faces set into the steepest banks, turned to the trail
    rr = np.random.default_rng(6)
    gz, gx = np.gradient(h, SP)
    for _ in range(3000):
        if counts["cliff"] >= 26:
            break
        x, z = rr.uniform(-78, 78), rr.uniform(-78, 78)
        d = DOUT(x, z)
        if d < 1.2 or d > 3.0 or not far(x, z, 9.0):
            continue
        i, j = int((z - AREA[1]) / SP), int((x - AREA[0]) / SP)
        g = (gx[i, j], gz[i, j])
        if math.hypot(*g) < 1.0:
            continue
        face = bearing((0, 0), (-g[0], -g[1]))   # downhill: toward the trail
        placed.append((x, z))
        # set deep into the bank, only where the bank stands tall behind it (no slab overhanging the trail)
        bx_, bz_ = x + g[0] / math.hypot(*g) * 4.0, z + g[1] / math.hypot(*g) * 4.0
        if H(bx_, bz_) < 4.2:
            placed.pop()
            continue
        prop("cliff_%d" % counts["cliff"], L, (x, H(x, z) - 3.4, z), "hf_cliff_face_%d" % (1 + counts["cliff"] % 2), face + 180 + float(rr.uniform(-20, 20)))
        counts["cliff"] += 1
    # mossy boulders along the trail edges (cover), logs and stumps in the clearings
    counts["rocks"] = 0
    for k in range(70):
        m = ["hf_mossrock_%d" % (1 + k % 5), "hf_mossrock_s%d" % (1 + k % 3)][k % 2]
        c = scatter(m, 1, 0.0, 1.0, 7.0, 100 + k, foot=0.75 if "_s" in m else 1.0, foot_h=1.4 if "_s" in m else 2.2, sink=0.25)
        counts["rocks"] += c
    for k in range(8):
        scatter("hf_log_%d" % (1 + k % 2), 1, 0.0, 0.8, 9.0, 200 + k, foot=0.45, foot_h=0.8, sink=0.05)
    for k in range(10):
        scatter("hf_stump_%d" % (1 + k % 2), 1, 0.0, 2.0, 8.0, 300 + k, sink=0.15)
    for k in range(12):
        scatter("hf_root_cluster", 1, 0.5, 4.0, 8.0, 400 + k, sink=0.2)
    print("  trees and rocks:", counts)

    # ---------------------------------------------------------------- torches along every trail, curtains of lianas
    L = "Torches"
    tk = 0
    for ti, (pts, w, kind) in enumerate(TRAILS):
        step = 12.0 if kind != "hidden" else 15.0
        acc = step * 0.5
        side = 1
        for a, b in zip(pts, pts[1:]):
            seg = math.dist(a, b)
            u = ((b[0] - a[0]) / seg, (b[1] - a[1]) / seg)
            nrm = (-u[1], u[0])
            t = acc
            while t < seg:
                x = a[0] + u[0] * t + nrm[0] * side * (w / 2 + 0.3)
                z = a[1] + u[1] * t + nrm[1] * side * (w / 2 + 0.3)
                if DOUT(x, z) < 0.9 and all(math.dist((x, z), (p["at"][0], p["at"][2])) > 5.0 for p in pieces if p["type"] == "light"):
                    torch("tt%d" % tk, L, x, z, H, minor=(tk % 2 == 1))
                    tk += 1
                side = -side
                t += step
            acc = t - seg
    # torches round the clearings' edges where nothing else lights them
    for ci, (name, pts) in enumerate(CLEARINGS.items()):
        ring = pts + [pts[0]]
        per = sum(math.dist(p, q) for p, q in zip(ring, ring[1:]))
        k = 0
        t = 0.0
        acc = 0.0
        for a, b in zip(ring, ring[1:]):
            seg = math.dist(a, b)
            while acc < seg:
                f = acc / seg
                x, z = a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f
                cx_, cz_ = np.mean([p[0] for p in pts]), np.mean([p[1] for p in pts])
                v = (cx_ - x, cz_ - z)
                vl = math.hypot(*v)
                x, z = x + v[0] / vl * 0.9, z + v[1] / vl * 0.9
                if DOUT(x, z) < 0.5 and all(math.dist((x, z), (p["at"][0], p["at"][2])) > 8.0 for p in pieces if p["type"] == "light"):
                    torch("tc%d" % tk, L, x, z, H, minor=(k % 2 == 1))
                    tk += 1
                    k += 1
                acc += 13.0
            acc -= seg
    print("  torches and braziers:", sum(1 for p in pieces if p["type"] == "light"))
    # lianas hanging over the trails from the canopy
    L = "Lianas"
    vk = 0
    for ti, (pts, w, kind) in enumerate(TRAILS):
        for a, b in zip(pts, pts[1:]):
            seg = math.dist(a, b)
            u = ((b[0] - a[0]) / seg, (b[1] - a[1]) / seg)
            nrm = (-u[1], u[0])
            t = 4.0
            while t < seg - 2.0:
                s = 1 if (vk % 2 == 0) else -1
                x = a[0] + u[0] * t + nrm[0] * s * (w / 2 + 0.8)
                z = a[1] + u[1] * t + nrm[1] * s * (w / 2 + 0.8)
                top = max(H(x, z), 0.0) + float(rng.uniform(6.5, 9.0))
                L2 = float(rng.uniform(2.5, 4.5))
                vines("liana%d" % vk, L, (x - u[0] * L2 / 2, top, z - u[1] * L2 / 2), (x + u[0] * L2 / 2, top, z + u[1] * L2 / 2),
                      drop=float(rng.uniform(3.5, 6.0)), density=float(rng.uniform(2.0, 3.5)), sag=0.4, seed=1000 + vk)
                vk += 1
                t += float(rng.uniform(7.0, 12.0))
    print("  vines:", sum(1 for p in pieces if p["type"] == "vines"))

    # ---------------------------------------------------------------- the play area's edge
    L = "Bounds"
    x0, z0, x1, z1 = BOUNDS
    for nm, a, b in [("n", (x0, z0), (x1, z0)), ("e", (x1, z0), (x1, z1)), ("s", (x1, z1), (x0, z1)), ("w", (x0, z1), (x0, z0))]:
        wall("bound_" + nm, L, a, b, "freight/clip", h=24.0, y=-6.0, t=1.0)


def ground_cover(h, walk, d_out, d_in, paths):
    """The plants Terrain3D instances on the ground: dense on the banks' faces and lips, thin in the clearings, none
    on the paths or the paving."""
    rng = np.random.default_rng(5150)
    # name, model, density on banks (per m2, near the walk), density in clearings, scale range, max distance from walk
    plants = [
        ("fern_a", 0.30, 0.025, (0.9, 1.5), 9.0),
        ("fern_b", 0.22, 0.02, (0.9, 1.4), 9.0),
        ("weed_leaves", 0.14, 0.04, (0.8, 1.3), 7.0),
        ("periwinkle", 0.05, 0.03, (0.8, 1.2), 6.0),
        ("taro", 0.07, 0.006, (0.8, 1.35), 10.0),
        ("exotic_plant", 0.04, 0.004, (0.8, 1.3), 8.0),
        ("banana", 0.03, 0.0, (0.8, 1.2), 12.0),
        ("banana_tree", 0.012, 0.0, (0.75, 1.15), 14.0),
        ("mossrock_s1", 0.012, 0.004, (0.3, 0.6), 10.0),
        ("mossrock_s3", 0.010, 0.003, (0.25, 0.5), 10.0),
        ("root_flat", 0.008, 0.004, (0.7, 1.1), 8.0),
    ]
    out = {}
    lim = BOUNDS[2] + 12.0
    for name, dens_bank, dens_in, (s0, s1), dmax in plants:
        pts = []
        area = (2 * lim) ** 2
        n = int(area * max(dens_bank, dens_in) * 1.0)
        xs = rng.uniform(-lim, lim, n)
        zs = rng.uniform(-lim, lim, n)
        for x, z in zip(xs, zs):
            i, j = int((z - AREA[1]) / SP), int((x - AREA[0]) / SP)
            if walk[i, j]:
                if dens_in <= 0 or paths[i, j] or d_in[i, j] > 3.0:
                    continue
                if rng.random() > dens_in / max(dens_bank, dens_in):
                    continue
            else:
                d = d_out[i, j]
                if d > dmax:
                    if rng.random() > 0.15:
                        continue
                if rng.random() > dens_bank / max(dens_bank, dens_in):
                    continue
            y = float(h[i, j])
            pts.append([round(x, 2), round(y - 0.04, 3), round(z, 2), round(float(rng.uniform(0, 360)), 1), round(float(rng.uniform(s0, s1)), 2)])
        out[name] = pts
    print("  ground cover:", {k: len(v) for k, v in out.items()})
    return out


def main():
    force = "--force" in sys.argv
    if OUT.exists() and STAMP.exists() and not force:
        if OUT.read_bytes() != STAMP.read_bytes():
            print("refusing: %s was edited since this script wrote it (--force starts over)" % OUT)
            sys.exit(1)
    # the structures declare their levelled ground first (FLATS), then the ground is shaped, then the map is placed
    global pieces
    pieces = []
    _ids.clear()
    h0 = np.zeros((N, N), np.float32)
    build(h0, np.ones((N, N), bool), np.zeros((N, N)), np.zeros((N, N)), None, None)   # dry run: collects FLATS
    flats = list(FLATS)
    pieces = []
    _ids.clear()
    FLATS.clear()
    FLATS.extend(flats)
    h, ctl, walk, d_out, d_in, pav, paths = build_terrain()
    FLATS.clear()
    build(h, walk, d_out, d_in, pav, paths)
    cover = ground_cover(h, walk, d_out, d_in, paths)
    doc = {
        "format": "aetherion-map/1", "id": MAP_ID, "name": "Hidden Forest", "code": "HF", "modes": ["deathmatch"],
        "bounds": list(BOUNDS), "levels": 2, "level_height": FH, "night_only": True, "field_optional": True,
        "teams": {"max_teams": 3, "max_team_size": 7, "team_size": 7},
        "night_grade": {"moon_k": 0.95, "ambient": "#22362f", "ambient_energy": 0.34, "fog": 0.0055, "fog_color": "#0d1714",
                        "vol_fog": 0.012, "exposure_k": 1.4, "saturation": 0.95, "contrast": 1.06, "sky_glow": "#0e120d", "sky_cloud": 0.4},
        "terrain": {"dir": "res://maps/%s/terrain" % MAP_ID, "spacing": SP, "region_size": 256, "area": [-96, -96, 96, 96], "phys": "dirt"},
        "dm_centre": [-4, -4],
        "note": "Hidden Forest (r27): an ancient city swallowed by the jungle, always night. Team 1 the Eagle Gate (west), "
                "Team 2 the Jaguar Gate (east), Team 3 behind the Temple of the Sun (north). Ground: Terrain3D.",
        "pieces": pieces,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    head = ["format", "id", "name", "code", "modes", "bounds", "levels", "level_height", "night_only", "field_optional",
            "teams", "night_grade", "terrain", "dm_centre", "note"]
    lines = ["{"]
    for k in head:
        lines.append(" %s: %s," % (json.dumps(k), json.dumps(doc[k])))
    lines.append(' "pieces": [')
    for i, p in enumerate(pieces):
        lines.append("  %s%s" % (json.dumps(p), "," if i < len(pieces) - 1 else ""))
    lines.append(" ]")
    lines.append("}")
    text = "\n".join(lines) + "\n"
    OUT.write_text(text, encoding="utf-8")
    STAMP.write_text(text, encoding="utf-8")
    DRAFT.mkdir(parents=True, exist_ok=True)
    h.astype("<f4").tofile(DRAFT / "heights.f32")
    ctl.astype("<u4").tofile(DRAFT / "control.u32")
    (DRAFT / "cover.json").write_text(json.dumps(cover))
    (DRAFT / "meta.json").write_text(json.dumps({"area": list(AREA), "spacing": SP, "n": N, "min": float(h.min()), "max": float(h.max())}))
    Image.fromarray((np.clip((h - h.min()) / (h.max() - h.min()), 0, 1) * 255).astype(np.uint8)).save(DRAFT / "heights_preview.png")
    Image.fromarray((walk * 255).astype(np.uint8)).save(DRAFT / "walk.png")
    kinds = {}
    for p in pieces:
        kinds[p["type"]] = kinds.get(p["type"], 0) + 1
    print("wrote %s: %d pieces %s; terrain %.1f .. %.1f m" % (OUT, len(pieces), kinds, h.min(), h.max()))


if __name__ == "__main__":
    main()
