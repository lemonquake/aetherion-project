"""r14: model functions for the new attachments in tools/blender/make_loot_models.py (run once; idempotent)."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'tools', 'blender', 'make_loot_models.py')
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
if 'def m_sight_reflex' in s:
    raise SystemExit('already applied')

anchor = "# ------------------------------------------------------------------ attachments: muzzle, grips, lasers, mags, stocks"
assert s.count(anchor) == 1
NEW_SIGHTS = r'''# r14 sights

def m_sight_reflex():
    # Open reflex sight (Kobra style): a low base with an angled glass window in a steel frame.
    z = 0.028
    parts = [cube('base', (0.026, 0.07, 0.012), (0, 0, 0.006), M('blued'), bev=0.002)]
    parts.append(cube('body', (0.03, 0.03, 0.018), (0, -0.022, 0.02), M('blued'), bev=0.003))
    for sx in (-1, 1):
        parts.append(cube('post%d' % sx, (0.004, 0.012, 0.036), (sx * 0.017, 0.022, 0.03), M('blued'), bev=0.001))
    parts.append(cube('bridge', (0.038, 0.012, 0.004), (0, 0.022, 0.049), M('blued'), bev=0.001))
    parts.append(cube('window', (0.03, 0.002, 0.03), (0, 0.022, 0.032), M('lens_clear'), rot=Matrix.Rotation(-0.12, 4, 'X')))
    parts.append(cyl('dial', 0.006, 0.008, (0.018, -0.022, 0.022), M('rubber'), axis='X', segs=14))
    INFO['sight_reflex'] = {'axis': z}
    return parts


def m_scope_lpvo():
    # 1-4x low-power variable: short 30 mm tube, big eyepiece with a throw lever.
    axis = 0.045
    parts = scope_tube(4, 0.25, 0.015, 0.0205, 0.021, axis)
    parts.append(lathe('zoom_ring', [(0.0215, 0), (0.023, 0.002), (0.023, 0.018), (0.0215, 0.02)], M('rubber'), loc=(0, -0.105, axis)))
    parts.append(cube('throw', (0.006, 0.01, 0.022), (0.021, -0.096, axis + 0.016), M('blued'), bev=0.002, rot=Matrix.Rotation(0.5, 4, 'Y')))
    INFO['scope_lpvo'] = {'axis': axis}
    return parts


def m_scope_night():
    # Night vision scope: boxy body, intensifier tube, IR illuminator on the left, rubber eyecup.
    axis = 0.05
    parts = [cube('body', (0.05, 0.16, 0.05), (0, 0, axis), M('olive'), bev=0.008, segs=3)]
    parts.append(lathe('obj', [(0, 0), (0.024, 0), (0.026, 0.035), (0.026, 0.045), (0, 0.045)], M('olive'), loc=(0, 0.08, axis)))
    parts.append(cyl('lens_f', 0.023, 0.002, (0, 0.126, axis), M('lens_red'), segs=28))
    parts.append(lathe('eye', [(0, 0), (0.019, 0), (0.022, 0.025), (0.017, 0.032), (0, 0.032)], M('rubber'), loc=(0, -0.112, axis)))
    parts.append(cyl('ir', 0.011, 0.07, (-0.033, 0.03, axis + 0.01), M('blued'), segs=18))
    parts.append(cyl('ir_lens', 0.009, 0.002, (-0.033, 0.066, axis + 0.01), M('lens_red'), segs=18))
    parts.append(cyl('knob', 0.009, 0.012, (0.03, -0.02, axis), M('rubber'), axis='X', segs=16))
    parts.append(cube('base', (0.024, 0.09, 0.012), (0, 0, 0.006), M('parker'), bev=0.001))
    parts.append(cube('riser', (0.03, 0.08, axis - 0.03), (0, 0, 0.012 + (axis - 0.03) / 2), M('parker'), bev=0.001))
    INFO['scope_night'] = {'axis': axis}
    return parts


def m_scope_thermal():
    # Thermal scope: square housing, germanium lens (dark, wide), display eyepiece, battery cap and buttons.
    axis = 0.052
    parts = [cube('body', (0.056, 0.15, 0.058), (0, 0.005, axis), M('polymer'), bev=0.008, segs=3)]
    parts.append(lathe('obj', [(0, 0), (0.028, 0), (0.029, 0.03), (0.027, 0.04), (0, 0.04)], M('polymer'), loc=(0, 0.08, axis)))
    parts.append(cyl('lens_f', 0.026, 0.002, (0, 0.121, axis), M('glass'), segs=32))
    parts.append(lathe('eye', [(0, 0), (0.018, 0), (0.021, 0.03), (0.016, 0.036), (0, 0.036)], M('rubber'), loc=(0, -0.106, axis)))
    parts.append(cyl('battery', 0.012, 0.05, (0, -0.02, axis + 0.035), M('alu'), axis='Y', segs=18))
    for k in range(3):
        parts.append(cube('btn%d' % k, (0.012, 0.012, 0.004), (0.0, -0.045 + k * 0.018, axis + 0.031), M('rubber'), bev=0.002))
    parts.append(cube('base', (0.024, 0.09, 0.012), (0, 0, 0.006), M('parker'), bev=0.001))
    parts.append(cube('riser', (0.03, 0.08, axis - 0.03), (0, 0, 0.012 + (axis - 0.03) / 2), M('parker'), bev=0.001))
    INFO['scope_thermal'] = {'axis': axis}
    return parts


def m_scope_15x():
    axis = 0.062
    parts = scope_tube(15, 0.42, 0.017, 0.033, 0.021, axis)
    parts.append(lathe('shade', [(0.0325, 0), (0.0345, 0), (0.0345, 0.07), (0.0325, 0.07)], M('blued'), loc=(0, 0.21, axis)))
    parts.append(cyl('wheel', 0.024, 0.007, (-0.025, 0.0, axis), M('blued'), axis='X', segs=28))
    parts.append(cyl('lever', 0.004, 0.03, (0.0, -0.13, axis + 0.025), M('blued'), axis='Z', segs=10))
    INFO['scope_15x'] = {'axis': axis}
    return parts


'''
s = s.replace(anchor, NEW_SIGHTS + anchor)

anchor2 = "# ------------------------------------------------------------------ items"
assert s.count(anchor2) == 1
NEW_REST = r'''# r14 muzzle devices, grips, stock

def m_muzzle_brake():
    # Two-chamber brake: wide side ports.
    L, r = 0.07, 0.013
    body = lathe('body', [(0, 0), (0.009, 0), (0.009, 0.008), (r, 0.011), (r, L - 0.003), (r * 0.92, L), (0.0045, L), (0, L - 0.002)], M('blued'))
    cutters = []
    for k, y in enumerate([0.03, 0.05]):
        cutters.append(cube('side%d' % k, (0.04, 0.011, 0.014), (0, y, 0), M('dark'), bev=0.0))
    cut(body, cutters)
    return [body, cyl('bore', 0.0045, 0.002, (0, L + 0.0002, 0), M('dark'), segs=12)]


def m_duckbill():
    # Shotgun duckbill: round collar flattening into a wide, thin spout.
    parts = [lathe('collar', [(0, 0), (0.0115, 0), (0.0125, 0.004), (0.0125, 0.022), (0, 0.022)], M('steel'), segs=28)]
    parts.append(cube('bill', (0.042, 0.04, 0.012), (0, 0.04, 0), M('steel'), bev=0.003))
    parts.append(cube('slot', (0.034, 0.002, 0.004), (0, 0.0605, 0), M('dark'), bev=0.0))
    return parts


def m_grip_thumb():
    parts = rail_clamp('g', 0.05)
    parts.append(profile('stub', [(0.025, -0.011), (-0.025, -0.011), (-0.022, -0.026), (0.012, -0.03), (0.026, -0.02)], 0.024, M('polymer'), bev=0.004))
    parts.append(cube('rest', (0.03, 0.022, 0.006), (0.015, 0.0, -0.01), M('rubber'), bev=0.002, rot=Matrix.Rotation(0.3, 4, 'Y')))
    return parts


def m_grip_light():
    # Lightweight grip: thin skeleton post with a cut-out.
    parts = rail_clamp('g', 0.04)
    post = profile('post', [(0.014, -0.011), (-0.014, -0.011), (-0.012, -0.085), (0.012, -0.085)], 0.018, M('tan'), bev=0.004)
    cut(post, [cube('hole', (0.03, 0.012, 0.05), (0, 0, -0.045), M('dark'), bev=0.0)])
    parts.append(post)
    return parts


def m_grip_ergonomic():
    parts = rail_clamp('g', 0.05)
    parts.append(profile('body', [(0.02, -0.011), (-0.02, -0.011), (-0.026, -0.04), (-0.018, -0.075), (0.006, -0.082), (0.018, -0.06), (0.012, -0.03)], 0.026, M('olive'), bev=0.005))
    return parts


def m_stock_heavy():
    # Heavy fixed stock: solid polymer body, thick butt pad.
    parts = [cube('hinge', (0.032, 0.03, 0.045), (0, -0.015, 0), M('alu'), bev=0.003)]
    parts.append(profile('body', [(-0.03, 0.03), (-0.25, 0.04), (-0.27, 0.03), (-0.27, -0.1), (-0.25, -0.11), (-0.18, -0.06), (-0.03, -0.03)], 0.04, M('polymer'), bev=0.005))
    parts.append(cube('pad', (0.044, 0.018, 0.145), (0, -0.28, -0.03), M('rubber'), bev=0.005))
    parts.append(cube('cheek', (0.044, 0.08, 0.012), (0, -0.16, 0.038), M('rubber'), bev=0.004))
    return parts


'''
s = s.replace(anchor2, NEW_REST + anchor2)
old = "    'mag_ext_sniper': m_mag_ext_sniper, 'stock_tactical': m_stock_tactical, 'cheek_pad': m_cheek_pad, 'bullet_loops': m_bullet_loops,\n}"
assert s.count(old) == 1
s = s.replace(old, old[:-2] + "\n    'sight_reflex': m_sight_reflex, 'scope_lpvo': m_scope_lpvo, 'scope_night': m_scope_night, 'scope_thermal': m_scope_thermal,\n"
              "    'scope_15x': m_scope_15x, 'muzzle_brake': m_muzzle_brake, 'duckbill': m_duckbill, 'grip_thumb': m_grip_thumb,\n"
              "    'grip_light': m_grip_light, 'grip_ergonomic': m_grip_ergonomic, 'stock_heavy': m_stock_heavy,\n}")
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('applied', 'crlf' if nl == '\r\n' else 'lf')
