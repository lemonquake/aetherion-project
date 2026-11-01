"""Lays out the first version of San Roque Covered Court (game/maps/covered_court/map.json) in stages, so each stage
can be looked at before the next. After the first version the map file is the source: edit it in the Godot map editor
(editor/maps/covered_court.tscn) or by hand. This script refuses to overwrite a map edited since (--force starts over).

    python -I work/r26/build_covered_court.py --upto 5 [--force]

Plan (x east, z south, metres; north is the road):
  north     Rizal St (asphalt) and its kerb; a jeepney parked
  middle    the covered court (30 x 17, steel columns, a blue yero gable roof at 7-9.4 m, floodlights), bleachers on
            its south side; the Barangay Hall north of it (two storeys, a balcony over the court, an outside stair
            to the balcony and one inside), the sari-sari store north-east
  east      the kapilya (chapel), East Team spawns behind it
  west      the tricycle terminal (a shed on posts), West Team spawns under it
  south     the eskinita: two rows of small houses with alleys, two of them two storeys
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "maps" / "covered_court" / "map.json"
STAMP = ROOT / "work" / "r26" / "covered_court.last_written"

FH = 3.2
pieces = []


def add(**p):
    pieces.append(p)
    return p


def floor(pid, layer, at, size, mat, t=0.2, **kw):
    return add(id=pid, type="floor", layer=layer, at=list(at), size=list(size), t=t, mat=mat, **kw)


def box(pid, layer, at, size, mat, **kw):
    return add(id=pid, type="box", layer=layer, at=list(at), size=list(size), mat=mat, **kw)


def wall(pid, layer, a, b, mat, h=3.0, y=0.0, t=0.2, openings=None, **kw):
    return add(id=pid, type="wall", layer=layer, **{"from": list(a)}, to=list(b), y=y, h=h, t=t, mat=mat,
               openings=openings or [], **kw)


def door(at, w=0.9, h=2.05, mat="plywood"):
    return {"at": at, "w": w, "h": h, "sill": 0, "door": mat}


def gap(at, w=1.0, h=2.1, sill=0.0):
    return {"at": at, "w": w, "h": h, "sill": sill}


def window(at, w=1.2, h=1.1, sill=1.0):
    return {"at": at, "w": w, "h": h, "sill": sill}


def light(pid, layer, at, kind="bulb", color="#ffc98a", energy=1.2, rng=9, fault="", **kw):
    return add(id=pid, type="light", layer=layer, at=list(at), kind=kind, color=color, energy=energy, range=rng, fault=fault, **kw)


def prop(pid, layer, at, model, yaw=0, physics=False):
    return add(id=pid, type="prop", layer=layer, at=list(at), model=model, yaw=yaw, physics=physics)


def column(pid, layer, at, h, r=0.18, mat="freight/steel_grey", sides=8):
    return add(id=pid, type="column", layer=layer, at=list(at), r=r, h=h, sides=sides, mat=mat)


def stairs(pid, layer, at, yaw, rise, w=1.2, mat="freight/concrete_rough", **kw):
    return add(id=pid, type="stairs", layer=layer, at=list(at), yaw=yaw, w=w, rise=rise, run=0.28, mat=mat, **kw)


# ------------------------------------------------------------------ stage 1: ground, road, court floor, spawns

def stage1():
    floor("ground", "Ground", (0, 0, 0), (104, 80), "brgy/plaza", t=0.3)
    floor("road", "Ground", (0, 0.02, -28), (104, 8), "freight/asphalt", t=0.1)
    floor("kerb_n", "Ground", (0, 0.15, -23.25), (104, 1.5), "freight/concrete_wet", t=0.2)
    floor("eskinita_ground", "Ground", (0, 0.01, 24.5), (104, 16), "freight/gravel", t=0.1)
    floor("court", "Court", (0, 0.06, 2), (30, 17), "brgy/court_green", t=0.1, edge="freight/concrete_rough")
    lines = "brgy/court_line"
    floor("line_n", "Court", (0, 0.072, -5.5), (28, 0.08), lines, t=0.012, solid=False)
    floor("line_s", "Court", (0, 0.072, 9.5), (28, 0.08), lines, t=0.012, solid=False)
    floor("line_w", "Court", (-14, 0.072, 2), (0.08, 15.08), lines, t=0.012, solid=False)
    floor("line_e", "Court", (14, 0.072, 2), (0.08, 15.08), lines, t=0.012, solid=False)
    floor("line_mid", "Court", (0, 0.072, 2), (0.08, 15), lines, t=0.012, solid=False)
    for side, x in (("w", -14), ("e", 14)):
        k = 1 if side == "w" else -1
        floor("key_%s" % side, "Court", (x + k * 2.9, 0.071, 2), (5.8, 4.9), "brgy/court_red", t=0.011, solid=False)
    # the play area's edge: invisible, stops bodies (not bullets)
    b = (-44, -32, 44, 32)
    for pid, a, c in (("clip_n", (b[0], b[1]), (b[2], b[1])), ("clip_e", (b[2], b[1]), (b[2], b[3])),
                      ("clip_s", (b[2], b[3]), (b[0], b[3])), ("clip_w", (b[0], b[3]), (b[0], b[1]))):
        wall(pid, "Bounds", a, c, "freight/clip", h=12, t=0.4, edge="freight/clip")
    # West Team under the tricycle terminal's shed, East Team behind the kapilya
    k = 0
    for z in (-8.5, -5.5, -2.5, 0.5):
        for x in (-40.5, -37.5):
            k += 1
            add(id="t1_%d" % k, type="spawn", layer="Spawns", at=[x, 0, z], team=1, yaw=90)
    k = 0
    for z in (-5.5, -1.5, 2.5, 6.5):
        for x in (40.0, 42.0):
            k += 1
            add(id="t2_%d" % k, type="spawn", layer="Spawns", at=[x, 0, z], team=2, yaw=270)


# ------------------------------------------------------------------ stage 2: the covered court

def stage2():
    xs = (-15.5, -9.3, -3.1, 3.1, 9.3, 15.5)
    for i, x in enumerate(xs):
        column("col_n%d" % (i + 1), "Court roof", (x, 0.06, -7), 6.94, r=0.16)
        column("col_s%d" % (i + 1), "Court roof", (x, 0.06, 11), 6.94, r=0.16)
        box("truss_%d" % (i + 1), "Court roof", (x, 6.7, 2), (0.18, 0.3, 18.4), "freight/steel_grey", solid=False)
    box("beam_n", "Court roof", (0, 6.65, -7), (31.4, 0.35, 0.22), "freight/steel_grey")
    box("beam_s", "Court roof", (0, 6.65, 11), (31.4, 0.35, 0.22), "freight/steel_grey")
    span, rise = 9.6, 2.4
    slope = math.hypot(span, rise)
    pitch = math.degrees(math.atan2(rise, span))
    box("roof_n", "Court roof", (0, 7.0 + rise / 2, 2 - span / 2), (32.4, 0.08, slope), "freight/yero_blue",
        tilt=[-round(pitch, 2), 0], under="freight/yero_old")
    box("roof_s", "Court roof", (0, 7.0 + rise / 2, 2 + span / 2), (32.4, 0.08, slope), "freight/yero_blue",
        tilt=[round(pitch, 2), 0], under="freight/yero_old")
    box("ridge", "Court roof", (0, 9.36, 2), (32.4, 0.14, 0.45), "freight/steel_grey")
    box("court_sign", "Court roof", (0, 6.15, -7.14), (8.0, 1.0, 0.05), "brgy/sign_court", solid=False)
    prop("hoop_w", "Court", (-15.1, 0.06, 2), "basketball_hoop", yaw=90)
    prop("hoop_e", "Court", (15.1, 0.06, 2), "basketball_hoop", yaw=270)
    # bleachers: four tiers a step high each (walkable), a wall behind for cover
    for i in range(4):
        box("bleacher_%d" % (i + 1), "Bleachers", (0, 0.06, 12.3 + 0.8 * i), (22, 0.34 * (i + 1), 0.8), "freight/concrete_rough",
            top="freight/paint_white" if i % 2 else "freight/concrete_wet")
    wall("bleacher_back", "Bleachers", (-11, 15.35), (11, 15.35), "freight/chb_pink", h=2.6, mat2="freight/chb_raw")
    wall("bleacher_end_w", "Bleachers", (-11.1, 11.9), (-11.1, 15.25), "freight/chb_pink", h=1.6)
    wall("bleacher_end_e", "Bleachers", (11.1, 11.9), (11.1, 15.25), "freight/chb_pink", h=1.6)
    for i, (x, z) in enumerate(((-9.3, -1), (0, -1), (9.3, -1), (-9.3, 5), (0, 5), (9.3, 5))):
        light("flood_%d" % (i + 1), "Lights", (x, 6.45, z), kind="down", color="#e6eeff", energy=3.2, rng=17,
              fault="flicker" if i == 4 else "", pitch=90, cone=75)
    for i, x in enumerate((-8, 0, 8)):
        prop("bench_court_%d" % (i + 1), "Court", (x, 0.06, -6.3), "monobloc", yaw=180, physics=True)


# ------------------------------------------------------------------ stage 3: the Barangay Hall

def stage3():
    L = "Barangay Hall"
    H = 6.4
    wm, wi = "freight/chb_mint", "freight/chb_white"
    # south face (to the court): doors and windows below, the balcony door and windows above
    wall("hall_s", L, (-12, -11), (6, -11), wm, h=H, mat2=wi, openings=[
        door(4.0), window(8.0, w=1.6), gap(13.0, w=1.8, h=2.3), window(16.6, w=1.0, sill=1.2),
        window(4.0, w=1.6, h=1.2, sill=4.2), gap(8.6, w=1.2, h=2.2, sill=3.2), window(14.0, w=1.6, h=1.2, sill=4.2)])
    wall("hall_n", L, (6, -19), (-12, -19), wm, h=H, mat2=wi, openings=[
        window(3.0), door(10.0), window(15.0), window(4.0, sill=4.2), window(9.0, sill=4.2), window(14.0, sill=4.2)])
    wall("hall_w", L, (-12, -19), (-12, -11), wm, h=H, mat2=wi, openings=[door(4.0), window(4.0, w=1.4, sill=4.2)])
    wall("hall_e", L, (6, -11), (6, -19), wm, h=H, mat2=wi, openings=[window(2.0, sill=1.1), window(4.0, sill=4.2)])
    floor("hall_floor", L, (-3, 0.1, -15), (17.8, 7.8), "freight/concrete_wet", t=0.1)
    wall("hall_part", L, (-4, -18.9), (-4, -11.1), wi, h=2.95, openings=[door(3.6)])
    # upper floor, with the stairwell left open over the inside stair (east end, climbing north)
    floor("hall_up", L, (-3.95, FH, -15), (15.9, 7.8), "freight/planks", t=0.25, under="freight/paint_white")
    # the stair's foot stands 0.7 m clear of the south wall: a body (and a bot) has room to turn onto it
    floor("hall_up_e", L, (4.95, FH, -18.0), (1.9, 1.8), "freight/planks", t=0.25, under="freight/paint_white")
    stairs("hall_stair_in", L, (4.85, 0.1, -12.6), 0, FH - 0.1, w=1.3, mat="freight/concrete_wet", rail=True)
    wall("hall_well_rail", L, (3.95, -17.1), (3.95, -11.4), wi, h=1.0, y=FH, t=0.12)
    floor("hall_roof", L, (-3, H + 0.2, -15), (18.6, 8.6), "freight/concrete_rough", t=0.2)
    # the balcony over the court and the outside stair up to it
    floor("balcony", L, (-3.4, FH, -10.0), (10.8, 2.0), "freight/concrete_rough", t=0.2)
    wall("balcony_rail_s", L, (-8.8, -9.06), (2.0, -9.06), wi, h=1.05, y=FH, t=0.12)
    wall("balcony_rail_e", L, (2.0, -9.06), (2.0, -10.9), wi, h=1.05, y=FH, t=0.12)
    column("balcony_post_w", L, (-8.6, 0, -9.2), FH - 0.2, r=0.14, mat="freight/concrete_rough")
    column("balcony_post_e", L, (1.8, 0, -9.2), FH - 0.2, r=0.14, mat="freight/concrete_rough")
    stairs("hall_stair_out", L, (-13.6, 0, -9.8), 90, FH, w=1.2, mat="freight/concrete_rough", rail=True)
    box("hall_sign", L, (-3.0, 5.35, -10.88), (5.0, 2.0, 0.06), "brgy/sign_hall", solid=False)
    for i, (x, z, y) in enumerate(((-8, -15, 2.9), (0, -15, 2.9), (-8, -15, 6.1), (1, -15, 6.1))):
        light("hall_tube_%d" % (i + 1), "Lights", (x, y, z), kind="tube", color="#dff3ff", energy=1.3, rng=8,
              fault="starter" if i == 2 else "", yaw=90)
    light("balcony_bulb", "Lights", (-3.0, 6.0, -10.6), color="#ffc98a", energy=1.0, rng=7)
    prop("hall_desk_1", L, (-9.5, 0.1, -16.5), "desk_metal", yaw=180)
    prop("hall_desk_2", L, (-6.5, 0.1, -16.5), "desk_metal", yaw=180)
    prop("hall_cab", L, (-1.5, 0.1, -18.4), "drawer_cabinet", yaw=180)
    prop("hall_table", L, (-3.5, FH, -15.5), "dining_table", yaw=0)
    for i, x in enumerate((-6, -5, -2, -1)):
        prop("hall_chair_%d" % (i + 1), L, (x, FH, -14.3 if i % 2 else -16.7), "school_chair", yaw=0 if i % 2 else 180, physics=True)


# ------------------------------------------------------------------ stage 4: store, kapilya, terminal

def stage4():
    L = "Sari-sari store"
    ym = "freight/chb_yellow"
    wall("store_n", L, (9, -20), (15, -20), ym, h=3.0, openings=[window(3.0, w=3.2, h=1.2, sill=1.0)])
    wall("store_e", L, (15, -20), (15, -14), ym, h=3.0, openings=[door(3.0)])
    wall("store_s", L, (15, -14), (9, -14), ym, h=3.0, openings=[window(3.0, w=1.2)])
    wall("store_w", L, (9, -14), (9, -20), ym, h=3.0)
    floor("store_floor", L, (12, 0.08, -17), (5.8, 5.8), "freight/concrete_wet", t=0.08)
    floor("store_roof", L, (12, 3.12, -17.2), (7.2, 7.4), "freight/yero_red", t=0.08, under="freight/plywood")
    box("store_sign", L, (12, 2.2, -20.16), (3.4, 0.75, 0.05), "freight/sign_sarisari", solid=False)
    box("store_counter", L, (12, 0.08, -19.3), (3.2, 1.0, 0.5), "freight/planks")
    prop("store_shelf_1", L, (9.6, 0.08, -16.5), "steel_shelves", yaw=90)
    prop("store_shelf_2", L, (12.0, 0.08, -14.5), "steel_shelves2", yaw=0)
    light("store_tube", "Lights", (12, 2.9, -17), kind="tube", color="#e8fbff", energy=1.4, rng=8, yaw=90)
    prop("store_table", L, (12.5, 0.15, -22.0), "picnic_table", yaw=90)
    prop("store_crate_1", L, (16.0, 0, -18.5), "crate_plastic", physics=True)
    prop("store_crate_2", L, (16.1, 0, -19.3), "crate_plastic2", physics=True)
    prop("store_drum", L, (16.2, 0, -15.0), "drum_blue", physics=True)

    L = "Kapilya"
    cw = "freight/chb_white"
    H = 5.5
    wall("kap_w", L, (26, 10), (26, -8), cw, h=H, openings=[door(8.5, w=1.0, h=2.6, mat="planks"), door(9.5, w=1.0, h=2.6, mat="planks")])
    wall("kap_e", L, (38, -8), (38, 10), cw, h=H, openings=[door(9.0, w=0.9)])
    wall("kap_n", L, (26, -8), (38, -8), cw, h=H, openings=[window(a, w=0.9, h=1.6, sill=2.2) for a in (2.5, 6.0, 9.5)])
    wall("kap_s", L, (38, 10), (26, 10), cw, h=H, openings=[window(a, w=0.9, h=1.6, sill=2.2) for a in (2.5, 6.0, 9.5)])
    floor("kap_floor", L, (32, 0.12, 1), (11.8, 17.8), "freight/concrete_wet", t=0.12)
    span, rise = 6.4, 2.5
    roll = math.degrees(math.atan2(rise, span))
    slope = math.hypot(span, rise)
    box("kap_roof_w", L, (32 - span / 2, H + rise / 2, 1), (slope, 0.08, 18.8), "freight/yero_red", tilt=[0, round(roll, 2)])
    box("kap_roof_e", L, (32 + span / 2, H + rise / 2, 1), (slope, 0.08, 18.8), "freight/yero_red", tilt=[0, -round(roll, 2)])
    for z, nm in ((-8, "n"), (10, "s")):
        add(id="kap_gable_%sw" % nm, type="ramp", layer=L, at=[26.0, H, z], yaw=90, w=0.2, len=6.0, rise=rise - 0.05, mat=cw)
        add(id="kap_gable_%se" % nm, type="ramp", layer=L, at=[38.0, H, z], yaw=270, w=0.2, len=6.0, rise=rise - 0.05, mat=cw)
    box("kap_sign", L, (25.86, 3.3, 1), (0.05, 0.9, 2.25), "brgy/sign_kapilya", solid=False)
    box("kap_altar", L, (36.6, 0.12, 1), (1.2, 1.0, 3.0), "freight/wood_red")
    box("kap_cross", L, (37.85, 2.6, 1), (0.08, 2.0, 0.18), "freight/timber", solid=False)
    box("kap_cross_bar", L, (37.84, 3.6, 1), (0.08, 0.18, 1.1), "freight/timber", solid=False)
    for row in range(5):
        for side in (-1, 1):
            box("pew_%d%s" % (row + 1, "n" if side < 0 else "s"), L, (28.5 + row * 1.5, 0.12, 1 + side * 3.0), (0.5, 0.48, 4.2), "freight/planks_dark")
    for i, z in enumerate((-0.2, 2.2)):
        light("kap_candle_%d" % (i + 1), "Lights", (36.6, 1.35, z), kind="candle", color="#ffb35c", energy=0.8, rng=5, fault="candle")
    light("kap_bulb", "Lights", (32, 5.0, 1), color="#ffd9a3", energy=1.0, rng=10, fault="dying")
    light("kap_door_lamp", "Lights", (25.6, 3.0, 1), color="#ffc98a", energy=1.1, rng=8)

    L = "Tricycle terminal"
    for i, (x, z) in enumerate(((-41.5, -11.5), (-41.5, -3), (-41.5, 5.5), (-30.5, -11.5), (-30.5, -3), (-30.5, 5.5))):
        column("term_post_%d" % (i + 1), L, (x, 0, z), 3.25 if x < -35 else 3.95, r=0.1, mat="freight/steel_rust")
    box("term_roof", L, (-36, 3.25, -3), (12.6, 0.08, 18.4), "freight/yero_rust", tilt=[0, 3.6], under="freight/yero_old")
    box("term_booth", L, (-32.0, 0, -9.5), (1.6, 2.3, 1.6), "freight/plywood", top="freight/yero_green")
    box("term_sign", L, (-30.45, 2.2, -3), (0.05, 1.0, 2.5), "brgy/sign_toda", solid=False)
    for i, (x, z, yaw, m) in enumerate(((-34.5, -6.0, 0, "tricycle_a"), (-34.5, -1.0, 0, "tricycle_b"), (-34.5, 4.0, 0, "tricycle_a"), (-39.5, 3.5, 90, "tricycle_b"))):
        prop("trike_%d" % (i + 1), L, (x, 0, z), m, yaw=yaw)
    prop("term_bench", L, (-31.4, 0, -3), "street_bench", yaw=270)
    for i, z in enumerate((-8, 1)):
        light("term_tube_%d" % (i + 1), "Lights", (-36, 3.05, z), kind="tube", color="#e0f6ff", energy=1.2, rng=9, fault="starter" if i else "", yaw=0)


# ------------------------------------------------------------------ stage 5: the eskinita, cover, lights, names, bot spots

HOUSE_COLOURS = ["freight/chb_pink", "freight/chb_mint", "freight/chb_yellow", "freight/chb_white", "freight/chb_raw"]
ROOFS = ["freight/yero_rust", "freight/yero_red", "freight/yero_blue", "freight/yero_green", "freight/yero_old"]


def house(n, x0, z0, w, d, door_side, two_storey=False):
    """A small house of CHB walls: a door on door_side (n / s), a window on each other wall, a yero roof. Two-storey
    houses get an inside stair along the back wall and windows upstairs."""
    L = "Eskinita"
    col = HOUSE_COLOURS[n % len(HOUSE_COLOURS)]
    H = 6.0 if two_storey else 2.9
    x1, z1 = x0 + w, z0 + d
    up = lambda a: window(a, w=1.0, h=1.0, sill=FH + 1.0)
    n_open = [door(w * 0.3)] if door_side == "n" else [window(w * 0.55)]
    s_open = [door(w * 0.7)] if door_side == "s" else [window(w * 0.45)]
    if two_storey:
        n_open.append(up(w * 0.6))
        s_open.append(up(w * 0.4))
    # the walls run clockwise round the house, so the face on the left (mat2) is the outside
    inside = "freight/paint_white"
    wall("h%d_n" % n, L, (x0, z0), (x1, z0), inside, h=H, mat2=col, edge=col, openings=n_open)
    wall("h%d_e" % n, L, (x1, z0), (x1, z1), inside, h=H, mat2=col, edge=col, openings=[window(d * 0.5, w=0.9)] + ([up(d * 0.5)] if two_storey else []))
    wall("h%d_s" % n, L, (x1, z1), (x0, z1), inside, h=H, mat2=col, edge=col, openings=s_open)
    wall("h%d_w" % n, L, (x0, z1), (x0, z0), inside, h=H, mat2=col, edge=col, openings=[window(d * 0.5, w=0.9)] if not two_storey else [up(d * 0.5)])
    floor("h%d_floor" % n, L, (x0 + w / 2, 0.12, z0 + d / 2), (w - 0.2, d - 0.2), "freight/planks", t=0.1)
    if two_storey:
        # the stair climbs east along the middle; the floor above leaves its well open
        zc = z0 + d / 2
        # the foot 1.5 m in from the west wall (room to step onto it), the top on the floor above
        stairs("h%d_stair" % n, L, (x0 + 1.5, 0.12, zc), 90, FH - 0.12, w=1.0, mat="freight/planks", top="freight/planks")
        top_x = x0 + 1.5 + (round((FH - 0.12) / 0.18) - 1) * 0.28
        zn, zs = zc - 0.6, zc + 0.6
        floor("h%d_up_n" % n, L, (x0 + w / 2, FH, (z0 + 0.1 + zn) / 2), (w - 0.2, zn - z0 - 0.1), "freight/planks", t=0.2, under="freight/plywood")
        floor("h%d_up_s" % n, L, (x0 + w / 2, FH, (zs + z1 - 0.1) / 2), (w - 0.2, z1 - 0.1 - zs), "freight/planks", t=0.2, under="freight/plywood")
        floor("h%d_up_e" % n, L, ((top_x + x1 - 0.1) / 2, FH, zc), (x1 - 0.1 - top_x, zs - zn), "freight/planks", t=0.2, under="freight/plywood")
        light("h%d_bulb_up" % n, "Lights", (x0 + w * 0.6, FH + 2.5, z0 + d * 0.25), color="#ffc07a", energy=0.8, rng=6, fault="flicker" if n % 3 == 0 else "")
    roof_y = H + 0.05
    box("h%d_roof" % n, L, (x0 + w / 2, roof_y, z0 + d / 2), (w + 0.6, 0.06, d + 0.6), ROOFS[n % len(ROOFS)],
        tilt=[4.0 if door_side == "n" else -4.0, 0], under="freight/plywood")
    light("h%d_bulb" % n, "Lights", (x0 + w * 0.5, 2.5, z0 + d * 0.5), color="#ffc07a", energy=0.7, rng=6,
          fault="dying" if n % 4 == 1 else "")


def stage5():
    # north row (doors onto the lane by the court), south row (doors onto the back alley)
    north = [(-38, 6), (-30, 6), (-22, 7.5), (-8, 6), (6, 7.5), (16, 6), (24, 5)]
    for i, (x, w) in enumerate(north):
        house(i + 1, x, 18, w, 5.6, "n", two_storey=i in (2, 4))
    south = [(-36, 6), (-26, 6), (-12, 6), (4, 6), (18, 6)]
    for i, (x, w) in enumerate(south):
        house(10 + i, x, 26, w, 5.4, "s" if i % 2 else "n")
    wall("fence_s", "Eskinita", (-44, 31.7), (44, 31.7), "freight/chb_raw", h=2.6, t=0.2)
    # cover round the court and in the plaza
    L = "Cover"
    prop("jeepney", L, (-6, 0.02, -28.5), "jeepney_painted", yaw=90)
    prop("car_1", L, (18, 0.02, -27.5), "car_sedan_80s", yaw=270)
    for i, (x, z, yaw) in enumerate(((-20, -2, 0), (-20, 6, 0), (20, -2, 0), (20, 6, 0))):
        for k in range(3):
            box("sandbag_%d_%d" % (i + 1, k + 1), L, (x, 0.0 + 0.18 * k, z), (2.4 - 0.3 * k, 0.18, 0.5), "freight/sack", yaw=yaw)
    for i, (x, z) in enumerate(((-24, -14), (22, -10), (-22, 12), (22, 13))):
        box("crates_%d" % (i + 1), L, (x, 0, z), (1.2, 1.2, 1.2), "freight/pallet", yaw=15 * i)
        prop("drum_%d" % (i + 1), L, (x + 1.1, 0, z + 0.6), "drum", physics=True)
    box("water_tank_base", L, (-25, 0, -18), (2.4, 2.2, 2.4), "freight/concrete_rough")
    add(id="water_tank", type="column", layer=L, at=[-25, 2.2, -18], r=1.1, h=1.8, sides=12, mat="freight/plastic_blue")
    # street lamps on the road
    for i, x in enumerate((-36, -18, 0, 18, 36)):
        column("pole_%d" % (i + 1), "Lights", (x, 0.15, -23.0), 6.2, r=0.09, mat="freight/steel_grey")
        light("street_%d" % (i + 1), "Lights", (x, 6.1, -23.8), kind="street", color="#ffb46b", energy=2.2, rng=20,
              fault="dying" if i == 3 else "", yaw=180, pitch=70, cone=80)
    light("alley_bulb_1", "Lights", (-28, 3.2, 25), color="#ffc07a", energy=0.9, rng=8, fault="flicker")
    light("alley_bulb_2", "Lights", (12, 3.2, 25), color="#ffc07a", energy=0.9, rng=8)
    # names on the SmarTab map
    for nm, x, z in (("Covered Court", 0, 2), ("Barangay Hall", -3, -15), ("Sari-sari Store", 12, -17), ("Kapilya", 32, 1),
                     ("Tricycle Terminal", -36, -3), ("Eskinita", 0, 25), ("Rizal St", 0, -28)):
        add(id="lm_" + nm.lower().replace(" ", "_").replace("-", "_"), type="landmark", layer="Names", at=[x, 0, z], name=nm)
    # places bots hold by design
    S = "Bot spots"
    add(id="spot_balcony", type="spot", layer=S, at=[-3, FH, -9.7], kind="snipe", yaw=180, name="Hall balcony")
    add(id="spot_hall_n", type="spot", layer=S, at=[-8, FH, -18.2], kind="snipe", yaw=0, name="Hall, north windows")
    add(id="spot_bleachers", type="spot", layer=S, at=[4, 1.42, 14.6], kind="cover", yaw=0, name="Top of the bleachers")
    add(id="spot_kapilya", type="spot", layer=S, at=[35, 0.12, 6], kind="hide", yaw=270, name="Kapilya, by the altar")
    add(id="spot_store", type="spot", layer=S, at=[13.5, 0.08, -15.2], kind="hide", yaw=0, name="Behind the store counter")
    add(id="spot_booth", type="spot", layer=S, at=[-33.4, 0, -9.5], kind="cover", yaw=90, name="Terminal booth")
    add(id="spot_h3_up", type="spot", layer=S, at=[-16.5, FH, 19.0], kind="snipe", yaw=0, name="Upstairs, house 3")
    add(id="spot_h5_up", type="spot", layer=S, at=[11.5, FH, 19.0], kind="snipe", yaw=0, name="Upstairs, house 5")


# ------------------------------------------------------------------ stage 6: what is seen past the play area

def stage6():
    """A wider ground and blocks of the barangay round the play area (drawn only), so the edge of the map is a
    neighbourhood, not the end of the world."""
    L = "Backdrop"
    floor("backdrop_ground", L, (0, -0.04, 0), (420, 420), "brgy/plaza", t=0.2, solid=False, tex_size=6)
    floor("backdrop_road", L, (0, -0.02, -28), (420, 8), "freight/asphalt", t=0.1, solid=False)
    import random
    rnd = random.Random(26)
    walls = ["freight/chb_white", "freight/chb_mint", "freight/chb_pink", "freight/chb_yellow", "freight/chb_raw"]
    roofs = ["freight/yero_rust", "freight/yero_red", "freight/yero_blue", "freight/yero_green"]
    k = 0
    def block(x, z, w, d, h):
        nonlocal k
        k += 1
        m = rnd.choice(walls)
        box("bd_%d" % k, L, (x, 0, z), (w, h, d), m, top=rnd.choice(roofs), solid=False)
    for side in (-1, 1):
        # east and west: rows of houses two to four storeys, beyond the play area (|x| > 48)
        for z in range(-60, 64, 9):
            if -33 < z < -23:
                continue   # the road runs through
            for ring, x0 in enumerate((54, 68, 84)):
                if rnd.random() < 0.2:
                    continue
                block(side * (x0 + rnd.uniform(0, 4)), z + rnd.uniform(-1, 1), rnd.uniform(7, 11), rnd.uniform(6, 8), rnd.choice([3.2, 6.2, 6.2, 9.4]) + ring * 1.5)
    for x in range(-90, 92, 10):
        # north of the road and south of the eskinita's fence
        if rnd.random() < 0.85:
            block(x + rnd.uniform(-1, 1), -40 - rnd.uniform(0, 3), rnd.uniform(8, 9.5), rnd.uniform(7, 9), rnd.choice([6.2, 9.4, 12.6]))
        if rnd.random() < 0.85:
            block(x + rnd.uniform(-1, 1), 40 + rnd.uniform(0, 3), rnd.uniform(8, 9.5), rnd.uniform(7, 9), rnd.choice([3.2, 6.2, 9.4]))
        if rnd.random() < 0.6:
            block(x + rnd.uniform(-2, 2), 54 + rnd.uniform(0, 6), rnd.uniform(8, 12), rnd.uniform(8, 10), rnd.choice([6.2, 9.4, 15.8]))
            block(x + rnd.uniform(-2, 2), -54 - rnd.uniform(0, 6), rnd.uniform(8, 12), rnd.uniform(8, 10), rnd.choice([9.4, 15.8, 22.0]))
    for i in range(10):
        a = rnd.uniform(0, 6.283)
        prop("bd_palm_%d" % (i + 1), L, (math.cos(a) * rnd.uniform(50, 70), 0, math.sin(a) * rnd.uniform(40, 60)), rnd.choice(["palm_a", "palm_b", "banana_a"]), yaw=rnd.uniform(0, 360))


STAGES = [stage1, stage2, stage3, stage4, stage5, stage6]


def main():
    upto = len(STAGES)
    force = "--force" in sys.argv
    if "--upto" in sys.argv:
        upto = int(sys.argv[sys.argv.index("--upto") + 1])
    if OUT.exists() and STAMP.exists() and not force:
        if OUT.read_text(encoding="utf-8") != STAMP.read_text(encoding="utf-8"):
            print("refusing: %s was edited since this script wrote it (--force starts over)" % OUT)
            return 1
    for st in STAGES[:upto]:
        st()
    doc = {"format": "aetherion-map/1", "id": "covered_court", "name": "San Roque Covered Court", "code": "CC",
           "modes": ["deathmatch"], "bounds": [-44, -32, 44, 32], "levels": 2, "level_height": FH, "night_only": False,
           "field_optional": True, "teams": {"max_teams": 2, "max_team_size": 8, "team_size": 6},
           "note": "A barangay's covered court (r26, the first map made in the map editor). West Team: tricycle terminal; East Team: behind the kapilya.",
           "pieces": pieces}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(doc, indent=1)
    OUT.write_text(text, encoding="utf-8")
    STAMP.write_text(text, encoding="utf-8")
    print("stage %d: %d pieces -> %s" % (upto, len(pieces), OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
