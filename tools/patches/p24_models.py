"""r24: models for the new attachments in tools/blender/make_loot_models.py (drums, lightweight magazines, a
marksman suppressor, a tactical compensator, stubby and heavy grips, a green laser, rail covers, a sling)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p24_util import patch

P = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'blender', 'make_loot_models.py')

patch(P, [
    ("""        'lens_red': dict(color=(0.5, 0.05, 0.04), rough=0.1, alpha=0.6),
""", """        'lens_red': dict(color=(0.5, 0.05, 0.04), rough=0.1, alpha=0.6),
        'lens_green': dict(color=(0.06, 0.55, 0.12), rough=0.1, alpha=0.6),
"""),
    ("""# ------------------------------------------------------------------ items

def m_battery():""", """# r24: magazines, muzzle devices, grips and extras

def m_drum(r, w, neck_d, neck_h, material):
    # A neck that goes up into the magazine well (top at z = 0), the round drum below it.
    parts = mag_body('neck', neck_h, 0.024, neck_d, 0.0, ribs=False, material=material, base=False)
    parts.append(cyl('drum', r, w, (0, 0.006, -neck_h - r * 0.82), material, axis='X', segs=40, bev=0.003))
    parts.append(cyl('cap_l', r * 0.55, w + 0.006, (0, 0.006, -neck_h - r * 0.82), M('alu'), axis='X', segs=28))
    parts.append(cyl('wind', r * 0.16, w + 0.016, (0, 0.006, -neck_h - r * 0.82), M('steel'), axis='X', segs=12))
    return parts


def m_mag_drum_rifle():
    return m_drum(0.058, 0.062, 0.062, 0.05, M('polymer'))


def m_mag_drum_light():
    return m_drum(0.046, 0.05, 0.033, 0.04, M('parker'))


def m_mag_polymer_rifle():
    parts = mag_body('mag', 0.19, 0.024, 0.062, 0.05, material=M('tan'))
    # a see-through window down the side
    parts.append(cube('window', (0.0255, 0.012, 0.09), (0, 0.012, -0.08), M('glass'), bev=0.001))
    return parts


def m_mag_polymer_light():
    parts = mag_body('mag', 0.13, 0.024, 0.033, 0.0, material=M('tan'))
    parts.append(cube('window', (0.0255, 0.008, 0.06), (0, 0.004, -0.06), M('glass'), bev=0.001))
    return parts


def m_muzzle_tactical():
    # Short compensator with a toothed crown and slots on both sides.
    L, r = 0.058, 0.0125
    body = lathe('body', [(0, 0), (0.009, 0), (0.009, 0.008), (r, 0.01), (r, L), (0.0045, L), (0, L - 0.002)], M('olive'))
    cutters = []
    for k, y in enumerate([0.022, 0.034]):
        cutters.append(cube('side%d' % k, (0.032, 0.006, 0.012), (0, y, 0), M('dark'), bev=0.0))
    for k in range(6):
        a = 2 * math.pi * k / 6
        cutters.append(cube('tooth%d' % k, (0.007, 0.008, 0.007), (math.cos(a) * r, L - 0.003, math.sin(a) * r), M('dark'), bev=0.0))
    cut(body, cutters)
    return [body, cyl('bore', 0.0045, 0.002, (0, L + 0.0002, 0), M('dark'), segs=12)]


def m_grip_stubby():
    parts = rail_clamp('g', 0.04)
    parts.append(lathe('stub', [(0.0, -0.011), (0.013, -0.011), (0.0145, -0.02), (0.0135, -0.045), (0.015, -0.05), (0.0, -0.05)],
                       M('polymer'), axis='Z', uv='box'))
    return parts


def m_grip_heavy():
    parts = rail_clamp('g', 0.06)
    ridges = [(0.0, -0.011), (0.016, -0.011)]
    for k in range(5):
        z = -0.02 - k * 0.018
        ridges += [(0.017, z), (0.0155, z - 0.009)]
    ridges += [(0.017, -0.11), (0.024, -0.118), (0.024, -0.126), (0.0, -0.126)]
    parts.append(lathe('grip', [(r, z) for r, z in ridges], M('rubber'), axis='Z', uv='box'))
    return parts


def m_laser_green():
    parts = rail_clamp('l', 0.045)
    parts.append(cube('housing', (0.03, 0.075, 0.028), (0, 0.008, -0.026), M('olive'), bev=0.004))
    parts.append(cyl('lens', 0.0068, 0.003, (0.0, 0.046, -0.026), M('lens_green'), segs=16))
    parts.append(cube('switch', (0.012, 0.014, 0.006), (0, -0.03, -0.012), M('rubber'), bev=0.002))
    return parts


def m_rail_cover():
    # Two rubber rail covers, ribbed, hanging under the fore-end (top at z = 0).
    parts = []
    for k, y in enumerate([-0.045, 0.045]):
        parts.append(cube('cover%d' % k, (0.026, 0.075, 0.009), (0, y, -0.0045), M('rubber'), bev=0.002))
        for j in range(6):
            parts.append(cube('rib%d_%d' % (k, j), (0.027, 0.004, 0.003), (0, y - 0.03 + j * 0.012, -0.0095), M('rubber'), bev=0.0008))
    return parts


def m_sling_quick():
    # A quick-detach swivel on a small rail clamp and a loop of strap.
    parts = rail_clamp('s', 0.025)
    parts.append(cyl('swivel', 0.009, 0.012, (0, 0.0, -0.022), M('steel'), axis='X', segs=16))
    parts.append(sweep('strap', [(0, 0.0, -0.025), (0, -0.03, -0.06), (0, -0.07, -0.075), (0, -0.11, -0.06), (0, -0.13, -0.03)], 0.006, M('nylon_black')))
    return parts


# ------------------------------------------------------------------ items

def m_battery():"""),
    ("""    'grip_light': m_grip_light, 'grip_ergonomic': m_grip_ergonomic, 'stock_heavy': m_stock_heavy,
}""", """    'grip_light': m_grip_light, 'grip_ergonomic': m_grip_ergonomic, 'stock_heavy': m_stock_heavy,
    'mag_drum_rifle': m_mag_drum_rifle, 'mag_drum_light': m_mag_drum_light, 'mag_polymer_rifle': m_mag_polymer_rifle,
    'mag_polymer_light': m_mag_polymer_light, 'suppressor_sniper': lambda: m_suppressor(0.022, 0.22, 0.0145),
    'muzzle_tactical': m_muzzle_tactical, 'grip_stubby': m_grip_stubby, 'grip_heavy': m_grip_heavy, 'laser_green': m_laser_green,
    'rail_cover': m_rail_cover, 'sling_quick': m_sling_quick,
}"""),
])
