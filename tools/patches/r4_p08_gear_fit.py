"""r4: make_gear.py - clean plane cuts for hems, sleeves and shorts; head gear fitted to the measured skull;
elbow pads in a bare-arm and an over-the-sleeve size."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

f = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'blender', 'make_gear.py')

# a plane-cut helper
patch(f, '''def keep_by_vertex(bm, pred, frac=0.5):''', '''def cut(bm, co, no):
    """Cut the mesh along a plane and drop everything on the side the normal points to (a clean hem or sleeve end)."""
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, dist=0.0001, plane_co=Vector(co), plane_no=Vector(no).normalized(), clear_outer=True)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')


def cut_arm(arm, body, bm, bone_side, t):
    """Cut both arms (or legs) across bone bone_side % side at fraction t along it, dropping the far part."""
    for side in ('L', 'R'):
        a, b = bone_seg(arm, body, bone_side % side)
        cut(bm, a.lerp(b, t), b - a)


def keep_by_vertex(bm, pred, frac=0.5):''')

# shirts: hem and sleeves by planes
patch(f, '''    def shirt(name, keep, limb, torso, layer, rough, col, uvs=7.0, hem=0.98):
        bm = extract(body, {'Hoodie black', 'Hoodie rib'}, hood_free)
        dl = bm.verts.layers.deform.active
        keep_by_vertex(bm, lambda v: keep(v, dl) and v.co.z > hem)
        fit_bmesh(bm, arm, body, limb=limb, torso=torso, offset=0.0, torso_y=torso_y)
        return derived(name, bm, arm, body, layer, rough, col, 1.0, uv_scale=uvs, decimate=0.5)''', '''    def shirt(name, sleeve, limb, torso, layer, rough, col, uvs=7.0, hem=0.98):
        """sleeve: ('upper', t) cut on the upper arm, ('fore', t) on the forearm, 'tank' armholes, None full."""
        bm = extract(body, {'Hoodie black', 'Hoodie rib'}, hood_free)
        cut(bm, (0, 0, hem), (0, 0, -1))
        if sleeve == 'tank':
            for sx in (-1, 1):
                cut(bm, (sx * 0.15, 0, 1.36), (sx * 1.0, 0, 0.85))
        elif sleeve:
            cut_arm(arm, body, bm, 'upper_arm.%s' if sleeve[0] == 'upper' else 'forearm.%s', sleeve[1])
        fit_bmesh(bm, arm, body, limb=limb, torso=torso, offset=0.0, torso_y=torso_y)
        return derived(name, bm, arm, body, layer, rough, col, 1.0, uv_scale=uvs, decimate=0.5)''')
patch(f, '''    shirt('shirt_tee', upper_half, 0.68, 0.92, COTTON, 0.9, (0.92, 0.92, 0.9))
    shirt('shirt_tank', no_sleeves, 0.68, 0.91, COTTON, 0.9, (0.9, 0.9, 0.88))
    shirt('shirt_longsleeve', long_sleeves, 0.66, 0.92, KNIT, 0.95, (0.5, 0.52, 0.55), uvs=9.0)
    shirt('shirt_jersey', no_sleeves, 0.7, 0.95, MESH, 0.8, (0.95, 0.95, 0.95), uvs=8.0, hem=0.94)
    shirt('shirt_polo', upper_half, 0.7, 0.93, PLAID, 0.9, (1.0, 1.0, 1.0), uvs=4.0)''', '''    shirt('shirt_tee', ('upper', 0.5), 0.68, 0.92, COTTON, 0.9, (0.92, 0.92, 0.9))
    shirt('shirt_tank', 'tank', 0.68, 0.91, COTTON, 0.9, (0.9, 0.9, 0.88))
    shirt('shirt_longsleeve', ('fore', 0.93), 0.66, 0.92, KNIT, 0.95, (0.5, 0.52, 0.55), uvs=9.0)
    shirt('shirt_jersey', 'tank', 0.72, 0.96, MESH, 0.8, (0.95, 0.95, 0.95), uvs=8.0, hem=0.93)
    shirt('shirt_polo', ('upper', 0.42), 0.7, 0.93, PLAID, 0.9, (1.0, 1.0, 1.0), uvs=4.0)''')

# jackets: hem and wrist by planes, open fronts by vertex test (a gap, not a hem)
patch(f, '''        bm = extract(body, {'Hoodie black', 'Hoodie rib'}, hood_free)
        dl = bm.verts.layers.deform.active
        keep_by_vertex(bm, lambda v: v.co.z > cut_hem and dominant(v, dl, gn) not in ('hand.L', 'hand.R') and
                       (not open_front or not (abs(v.co.x) < 0.05 and v.co.y < torso_y and 1.0 < v.co.z < 1.5)))''', '''        bm = extract(body, {'Hoodie black', 'Hoodie rib'}, hood_free)
        cut(bm, (0, 0, cut_hem), (0, 0, -1))
        cut_arm(arm, body, bm, 'forearm.%s', 0.95)
        if open_front:
            for sx in (-1, 1):
                # Two planes leave a strip down the front open (the shirt shows).
                pass
            dl = bm.verts.layers.deform.active
            keep_by_vertex(bm, lambda v: not (abs(v.co.x) < 0.045 and v.co.y < torso_y and cut_hem < v.co.z < 1.48), frac=0.75)''')

# shorts by a plane above the knee
patch(f, '''    pants('pants_shorts', STRIPES, 0.8, (0.85, 0.85, 0.88), keep=shorts_keep, loose=1.16, uvs=3.0)''', '''    bm = extract(body, {'Jeans dark'})
    ta, tb = bone_seg(arm, body, 'thigh.L')
    cut(bm, ta.lerp(tb, 0.6), (0, 0, -1))
    fit_bmesh(bm, arm, body, limb=1.16, legs=1.16, torso=1.16, offset=0.002, torso_y=torso_y)
    derived('pants_shorts', bm, arm, body, STRIPES, 0.8, (0.85, 0.85, 0.88), 1.0, uv_scale=3.0, decimate=0.6)''')

# fingerless gloves and wraps by planes across the knuckles
patch(f, '''    def glove(name, layer, rough, col, off, keep=None, dec=0.6):
        bm = extract(body, {'Human skin'})
        dl = bm.verts.layers.deform.active
        keep_by_vertex(bm, lambda v: dominant(v, dl, gn) in ('hand.L', 'hand.R') and (keep is None or keep(v, dl)))''', '''    def glove(name, layer, rough, col, off, keep=None, dec=0.6, knuckles=None):
        bm = extract(body, {'Human skin'})
        dl = bm.verts.layers.deform.active
        keep_by_vertex(bm, lambda v: dominant(v, dl, gn) in ('hand.L', 'hand.R'))
        if knuckles:
            for sx in (-1, 1):
                cut(bm, (sx * knuckles, 0, 0), (sx, 0, 0))''')
patch(f, '''    glove('gloves_fingerless', LEATHER, 0.6, (0.18, 0.12, 0.08), 0.004, keep=lambda v, dl: abs(v.co.x) < knuckle_x)''', '''    glove('gloves_fingerless', LEATHER, 0.6, (0.18, 0.12, 0.08), 0.004, knuckles=knuckle_x)''')
patch(f, '''    glove('gloves_wraps', COTTON, 0.95, (0.92, 0.92, 0.9), 0.003, keep=lambda v, dl: abs(v.co.x) < knuckle_x + 0.005)''', '''    glove('gloves_wraps', COTTON, 0.95, (0.92, 0.92, 0.9), 0.003, knuckles=knuckle_x + 0.005)''')

# elbow pads in two sizes
patch(f, '''    def pad(prefix, kind, bone_side, at, front, radius, length, layer, rough, col, strap_col):
        for side in ('L', 'R'):''', '''    def pad(prefix, kind, bone_side, at, front, radius, length, layer, rough, col, strap_col, suffix=''):
        for side in ('L', 'R'):''')
patch(f, '''            hard('%s_%s_%s' % (prefix, kind, side), b, arm, body)''', '''            hard('%s_%s_%s%s' % (prefix, kind, side, suffix), b, arm, body)''')
patch(f, '''    pad('elbow', 'hard', 'forearm.%s', 0.06, Vector((0, 0.3, 0.1)), 0.062, 0.11, PLASTIC, 0.35, (0.15, 0.15, 0.16), (0.08, 0.08, 0.08))
    pad('elbow', 'foam', 'forearm.%s', 0.06, Vector((0, 0.3, 0.1)), 0.06, 0.12, RUBBER, 0.8, (0.2, 0.22, 0.2), (0.1, 0.1, 0.1))
    pad('elbow', 'skate', 'forearm.%s', 0.06, Vector((0, 0.3, 0.1)), 0.064, 0.13, PLASTIC, 0.25, (0.8, 0.15, 0.12), (0.1, 0.1, 0.1))
    pad('elbow', 'knit', 'forearm.%s', 0.06, Vector((0, 0.3, 0.1)), 0.058, 0.12, KNIT, 0.95, (0.35, 0.35, 0.36), (0.1, 0.1, 0.1))''', '''    # Two sizes: on a bare or short-sleeved arm, and over a jacket sleeve (the game picks).
    for suffix, grow in (('', 0.0), ('_over', 0.036)):
        pad('elbow', 'hard', 'forearm.%s', 0.06, Vector((0, 0.3, 0.1)), 0.062 + grow, 0.11, PLASTIC, 0.35, (0.15, 0.15, 0.16), (0.08, 0.08, 0.08), suffix)
        pad('elbow', 'foam', 'forearm.%s', 0.06, Vector((0, 0.3, 0.1)), 0.06 + grow, 0.12, RUBBER, 0.8, (0.2, 0.22, 0.2), (0.1, 0.1, 0.1), suffix)
        pad('elbow', 'skate', 'forearm.%s', 0.06, Vector((0, 0.3, 0.1)), 0.064 + grow, 0.13, PLASTIC, 0.25, (0.8, 0.15, 0.12), (0.1, 0.1, 0.1), suffix)
        pad('elbow', 'knit', 'forearm.%s', 0.06, Vector((0, 0.3, 0.1)), 0.058 + grow, 0.12, KNIT, 0.95, (0.35, 0.35, 0.36), (0.1, 0.1, 0.1), suffix)''')
patch(f, '''    pad('knee', 'hard', 'shin.%s', 0.02, Vector((0, -1, 0)), 0.072, 0.13,''', '''    pad('knee', 'hard', 'shin.%s', 0.02, Vector((0, -1, 0)), 0.084, 0.13,''')
patch(f, '''    pad('knee', 'foam', 'shin.%s', 0.02, Vector((0, -1, 0)), 0.07, 0.14,''', '''    pad('knee', 'foam', 'shin.%s', 0.02, Vector((0, -1, 0)), 0.082, 0.14,''')
patch(f, '''    pad('knee', 'skate', 'shin.%s', 0.02, Vector((0, -1, 0)), 0.074, 0.15,''', '''    pad('knee', 'skate', 'shin.%s', 0.02, Vector((0, -1, 0)), 0.086, 0.15,''')
patch(f, '''    pad('knee', 'knit', 'shin.%s', 0.02, Vector((0, -1, 0)), 0.068, 0.14,''', '''    pad('knee', 'knit', 'shin.%s', 0.02, Vector((0, -1, 0)), 0.08, 0.14,''')

# head gear on the measured skull (the earlier box included the neck)
patch(f, '''    # ---------------- headwear (bound to the head)
    hc, hr = head_c, head_r
    crown = Vector((hc.x, hc.y + 0.004, hc.z + 0.012))
    b = Builder('head').spec(CAMO, 0.85, (1, 1, 1), 1.0, 0.06)
    b.shell(crown, Vector((hr.x + 0.028, hr.y + 0.03, hr.z * 0.85 + 0.03)), 0.012, phi0=0.0, phi1=1.62, segs=20, rings=8)''', '''    # ---------------- headwear (bound to the head)
    # Skull measured on the body: top 1.80 m, widest +-0.095 at 1.68 m, front of the face -0.145, back +0.057, nose
    # tip -0.16 at 1.653 m. Shells are ellipsoids about the skull's centre.
    hc = Vector((0.0, -0.044, 1.68))
    hr = Vector((0.095, 0.102, 0.12))
    crown = hc.copy()
    b = Builder('head').spec(CAMO, 0.85, (1, 1, 1), 1.0, 0.06)
    b.shell(crown, Vector((hr.x + 0.026, hr.y + 0.028, hr.z + 0.024)), 0.012, phi0=0.0, phi1=1.72, segs=20, rings=8)''')
patch(f, '''    b = Builder('head').spec(PLASTIC, 0.35, (0.95, 0.75, 0.1), 1.0, 0.06)
    b.shell(crown + Vector((0, 0, 0.01)), Vector((hr.x + 0.03, hr.y + 0.035, hr.z * 0.8 + 0.035)), 0.008, phi0=0.0, phi1=1.5, segs=20, rings=7)
    b.ring(Vector((crown.x, crown.y, crown.z + (hr.z * 0.8 + 0.035) * math.cos(1.5) + 0.004)), Vector((0, 0, 1)), hr.x + 0.032, 0.008, 0.004, segs=24, flare=0.03)
    b.box(Vector((crown.x, crown.y - hr.y - 0.045, crown.z + 0.0)), (0.12, 0.05, 0.008), Matrix.Rotation(0.25, 3, 'X'))
    b.box(Vector((crown.x, crown.y, crown.z + hr.z * 0.8 + 0.04)), (0.025, hr.y * 1.6, 0.02))''', '''    b = Builder('head').spec(PLASTIC, 0.35, (0.95, 0.75, 0.1), 1.0, 0.06)
    hh = Vector((hr.x + 0.028, hr.y + 0.032, hr.z + 0.03))
    b.shell(crown, hh, 0.008, phi0=0.0, phi1=1.45, segs=20, rings=7)
    rim_z = crown.z + hh.z * math.cos(1.45)
    b.ring(Vector((crown.x, crown.y, rim_z + 0.004)), Vector((0, 0, 1)), max(hh.x, hh.y) * 0.97, 0.008, 0.004, segs=24, flare=0.028)
    b.box(Vector((crown.x, crown.y - hh.y - 0.03, rim_z + 0.01)), (0.13, 0.05, 0.008), Matrix.Rotation(0.2, 3, 'X'))
    b.box(Vector((crown.x, crown.y, crown.z + hh.z - 0.004)), (0.022, hh.y * 1.4, 0.016))''')
patch(f, '''    b = Builder('head').spec(PLASTIC, 0.15, (0.6, 0.08, 0.08), 1.0, 0.06)
    b.shell(crown + Vector((0, 0.01, -0.01)), Vector((hr.x + 0.035, hr.y + 0.04, hr.z + 0.035)), 0.014, phi0=0.0, phi1=2.15, segs=22, rings=9,
            theta0=0.7, theta1=2 * math.pi - 0.7, closed=False)
    b.spec(PLASTIC, 0.05, (0.06, 0.06, 0.08), 0.0, 0.06)
    b.ellipsoid(crown + Vector((0, 0.01, -0.01)), Vector((hr.x + 0.045, hr.y + 0.05, hr.z + 0.045)), phi0=0.95, phi1=1.75, theta0=-0.75, theta1=0.75, segs=10, rings=4, closed=False)''', '''    b = Builder('head').spec(PLASTIC, 0.15, (0.6, 0.08, 0.08), 1.0, 0.06)
    mh = Vector((hr.x + 0.034, hr.y + 0.036, hr.z + 0.03))
    b.shell(crown, mh, 0.014, phi0=0.0, phi1=2.05, segs=22, rings=9, theta0=0.62, theta1=2 * math.pi - 0.62, closed=False)
    b.shell(crown, mh, 0.014, phi0=0.0, phi1=1.0, segs=8, rings=4, theta0=-0.62, theta1=0.62, closed=False)
    b.spec(PLASTIC, 0.05, (0.06, 0.06, 0.08), 0.0, 0.06)
    b.ellipsoid(crown, Vector((mh.x + 0.008, mh.y + 0.012, mh.z + 0.006)), phi0=1.0, phi1=1.62, theta0=-0.7, theta1=0.7, segs=10, rings=3, closed=False)''')
patch(f, '''    b = Builder('head').spec(KNIT, 0.95, (0.15, 0.2, 0.32), 1.0, 0.035)
    b.shell(crown, Vector((hr.x + 0.014, hr.y + 0.016, hr.z * 0.85 + 0.022)), 0.006, phi0=0.0, phi1=1.48, segs=20, rings=7)
    cuff_z = crown.z + (hr.z * 0.85 + 0.022) * math.cos(1.4)
    b.ring(Vector((crown.x, crown.y, cuff_z)), Vector((0, 0, 1)), hr.x + 0.016, 0.035, 0.008, segs=20)''', '''    b = Builder('head').spec(KNIT, 0.95, (0.15, 0.2, 0.32), 1.0, 0.035)
    bh = Vector((hr.x + 0.012, hr.y + 0.014, hr.z + 0.016))
    b.shell(crown, bh, 0.006, phi0=0.0, phi1=1.38, segs=20, rings=7)
    cuff_z = crown.z + bh.z * math.cos(1.38) + 0.012
    b.ring(Vector((crown.x, crown.y, cuff_z)), Vector((0, 0, 1)), (bh.x + bh.y) * 0.5 + 0.004, 0.032, 0.008, segs=20)''')
patch(f, '''    b = Builder('head').spec(COTTON, 0.9, (0.85, 0.85, 0.82), 1.0, 0.06)
    b.shell(crown, Vector((hr.x + 0.016, hr.y + 0.018, hr.z * 0.8 + 0.025)), 0.006, phi0=0.0, phi1=1.45, segs=20, rings=6)
    brim_c = Vector((crown.x, crown.y - hr.y - 0.04, crown.z + (hr.z * 0.8 + 0.025) * math.cos(1.45) + 0.004))
    b.box(brim_c, (0.15, 0.09, 0.006), Matrix.Rotation(-0.12, 3, 'X'))''', '''    b = Builder('head').spec(COTTON, 0.9, (0.85, 0.85, 0.82), 1.0, 0.06)
    ch_ = Vector((hr.x + 0.012, hr.y + 0.014, hr.z + 0.012))
    b.shell(crown, ch_, 0.006, phi0=0.0, phi1=1.35, segs=20, rings=6)
    brim_c = Vector((crown.x, crown.y - ch_.y - 0.035, crown.z + ch_.z * math.cos(1.35) + 0.004))
    b.box(brim_c, (0.15, 0.085, 0.006), Matrix.Rotation(-0.15, 3, 'X'))''')
patch(f, '''    # ---------------- face
    eye_z = hc.z - hr.z * 0.05
    front_y = hc.y - hr.y
    b = Builder('head').spec(NYLON, 0.8, (0.12, 0.12, 0.12), 1.0, 0.04)
    b.ring(Vector((hc.x, hc.y + 0.005, eye_z + 0.012)), Vector((0, 0, 1)), max(hr.x, hr.y) + 0.012, 0.03, 0.004, segs=24)
    b.spec(PLASTIC, 0.05, (0.25, 0.2, 0.08), 0.0, 0.04)
    b.box(Vector((hc.x, front_y - 0.022, eye_z + 0.012)), (0.15, 0.03, 0.055))
    hard('face_goggles', b, arm, body)

    b = Builder('head').spec(CAMO, 0.95, (1, 1, 1), 1.0, 0.05)
    b.ellipsoid(Vector((hc.x, hc.y, hc.z - 0.02)), Vector((hr.x + 0.016, hr.y + 0.022, hr.z + 0.016)), phi0=1.72, phi1=2.6, theta0=-1.7, theta1=1.7, segs=14, rings=4, closed=False)
    hard('face_bandana', b, arm, body)

    b = Builder('head').spec(RUBBER, 0.6, (0.1, 0.1, 0.1), 1.0, 0.04)
    b.ellipsoid(Vector((hc.x, hc.y, hc.z - 0.02)), Vector((hr.x + 0.012, hr.y + 0.03, hr.z + 0.012)), phi0=1.6, phi1=2.55, theta0=-1.2, theta1=1.2, segs=12, rings=4, closed=False)
    b.spec(METAL, 0.4, (0.45, 0.45, 0.42), 0.0, 0.04)
    for sx in (-1, 1):
        cc = Vector((hc.x + sx * 0.045, front_y - 0.035, hc.z - hr.z * 0.55))
        b.tube([cc, cc + Vector((sx * 0.035, -0.035, -0.012))], 0.022, segs=10)
    b.spec(NYLON, 0.8, (0.08, 0.08, 0.08), 0.0, 0.04)
    b.ring(Vector((hc.x, hc.y + 0.01, hc.z - 0.03)), Vector((0, 0.25, 1)), max(hr.x, hr.y) + 0.008, 0.012, 0.003, segs=20)
    hard('face_respirator', b, arm, body)

    b = Builder('head').spec(PLASTIC, 0.2, (0.05, 0.05, 0.05), 1.0, 0.04)
    for sx in (-1, 1):
        b.box(Vector((hc.x + sx * 0.032, front_y - 0.012, eye_z)), (0.05, 0.006, 0.032))
        b.box(Vector((hc.x + sx * (hr.x + 0.004), hc.y - hr.y * 0.4, eye_z + 0.006)), (0.004, hr.y * 1.1, 0.006))
    b.box(Vector((hc.x, front_y - 0.012, eye_z + 0.008)), (0.016, 0.006, 0.006))
    hard('face_sunglasses', b, arm, body)''', '''    # ---------------- face (eyes at about 1.695 m, the brow at -0.145, nose tip -0.16 at 1.653, chin -0.11 at 1.56)
    eye_z = 1.695
    def head_loop(z, grow, n=24):
        """Points round the skull at height z, grown outward."""
        pts = []
        for j in range(n + 1):
            th = 2 * math.pi * j / n
            pts.append(Vector((hc.x + (hr.x + grow) * math.sin(th), hc.y - (hr.y + 0.004 + grow) * math.cos(th), z)))
        return pts
    b = Builder('head').spec(NYLON, 0.8, (0.12, 0.12, 0.12), 1.0, 0.04)
    b.tube(head_loop(eye_z + 0.008, 0.012), 0.006, segs=6, cap=False)
    b.spec(PLASTIC, 0.4, (0.1, 0.1, 0.1), 0.0, 0.04)
    for sx in (-1, 1):
        b.box(Vector((sx * 0.036, -0.157, eye_z + 0.004)), (0.058, 0.02, 0.042), Matrix.Rotation(sx * 0.25, 3, 'Z'))
    b.spec(PLASTIC, 0.03, (0.75, 0.5, 0.12), 0.0, 0.04)
    for sx in (-1, 1):
        b.box(Vector((sx * 0.037, -0.168, eye_z + 0.004)), (0.048, 0.004, 0.032), Matrix.Rotation(sx * 0.25, 3, 'Z'))
    hard('face_goggles', b, arm, body)

    b = Builder('head').spec(CAMO, 0.95, (1, 1, 1), 1.0, 0.05)
    bc = Vector((0.0, -0.046, 1.62))
    b.ellipsoid(bc, Vector((0.088, 0.118, 0.1)), phi0=1.16, phi1=2.6, theta0=-1.95, theta1=1.95, segs=16, rings=6, closed=False)
    # the knot's tails at the back of the neck
    b.box(Vector((0.0, 0.07, 1.6)), (0.04, 0.012, 0.07), Matrix.Rotation(0.3, 3, 'X'))
    hard('face_bandana', b, arm, body)

    b = Builder('head').spec(RUBBER, 0.6, (0.1, 0.1, 0.1), 1.0, 0.04)
    rc = Vector((0.0, -0.07, 1.615))
    b.ellipsoid(rc, Vector((0.07, 0.1, 0.075)), phi0=1.05, phi1=2.45, theta0=-1.25, theta1=1.25, segs=12, rings=5, closed=False)
    b.spec(METAL, 0.4, (0.45, 0.45, 0.42), 0.0, 0.04)
    for sx in (-1, 1):
        cc = Vector((sx * 0.05, -0.15, 1.6))
        b.tube([cc, cc + Vector((sx * 0.03, -0.028, -0.01))], 0.021, segs=10)
    b.spec(NYLON, 0.8, (0.08, 0.08, 0.08), 0.0, 0.04)
    strap = [p for p in head_loop(1.66, 0.006) if p.y > -0.1]
    b.tube(strap, 0.004, segs=5, cap=False)
    hard('face_respirator', b, arm, body)

    b = Builder('head').spec(PLASTIC, 0.2, (0.05, 0.05, 0.05), 1.0, 0.04)
    for sx in (-1, 1):
        b.box(Vector((sx * 0.032, -0.158, eye_z)), (0.046, 0.005, 0.03), Matrix.Rotation(sx * 0.2, 3, 'Z'))
        b.tube([Vector((sx * 0.056, -0.152, eye_z + 0.008)), Vector((sx * 0.092, -0.11, eye_z + 0.006)), Vector((sx * 0.097, -0.02, eye_z - 0.01))], 0.0025, segs=4)
    b.box(Vector((0.0, -0.16, eye_z + 0.008)), (0.016, 0.005, 0.005))
    hard('face_sunglasses', b, arm, body)''')
