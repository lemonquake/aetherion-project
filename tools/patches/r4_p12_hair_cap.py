"""r4: hair as a cap with a real hairline (forehead, temples, above the ears, down to the nape)."""
import os
import re

f = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'blender', 'make_gear.py')
s = open(f, encoding='utf-8').read()
new = '''    # ---------------- hair (on the skull; left off under headwear and the hood)
    hair = (0.06, 0.05, 0.045)

    def cap(b, grow, front=0.92, side=1.48, back=2.05, segs=28, rings=8, bump=0.0):
        """A cap over the skull whose lower edge follows a hairline: high at the forehead, above the ears, low at
        the nape. theta 0 = the front (-y)."""
        r = Vector((hr.x + grow, hr.y + grow, hr.z + grow))
        def phimax(th):
            c = math.cos(th)                  # 1 front, -1 back
            a = abs(math.sin(th))             # 1 at the sides
            base = front * max(c, 0.0) + back * max(-c, 0.0) + side * a
            return base / (max(c, 0.0) + max(-c, 0.0) + a)
        rr = []
        for k in range(rings + 1):
            ring = []
            for j in range(segs):
                th = 2 * math.pi * j / segs
                ph = phimax(th) * k / rings
                swell = 1.0 + bump * math.sin(math.pi * k / rings)
                ring.append(Vector((crown.x + r.x * swell * math.sin(ph) * math.sin(th), crown.y - r.y * swell * math.sin(ph) * math.cos(th),
                                    crown.z + r.z * math.cos(ph))))
            rr.append(ring)
        # the top ring is a single point repeated: close it with a fan by letting quad_strip make thin quads
        b.quad_strip(rr, closed=True)

    b = Builder('head').spec(KNIT, 0.95, hair, 1.0, 0.02)
    cap(b, 0.009, front=0.95, side=1.5, back=2.0)
    hard('hair_buzz', b, arm, body)

    b = Builder('head').spec(KNIT, 0.9, hair, 1.0, 0.015)
    cap(b, 0.02, front=1.08, side=1.5, back=2.05, bump=0.06)
    hard('hair_short', b, arm, body)

    b = Builder('head').spec(KNIT, 0.95, hair, 1.0, 0.02)
    cap(b, 0.008, front=0.95, side=1.2, back=1.95)
    pts = []
    rad = []
    for k in range(10):
        # front hairline over the top to the back of the head, along the middle
        ph = -0.85 + 2.6 * k / 9.0
        pts.append(Vector((0.0, crown.y - (hr.y + 0.022) * math.sin(ph), crown.z + (hr.z + 0.022) * math.cos(ph))))
        rad.append(0.012 + 0.016 * math.sin(math.pi * (k + 0.5) / 10.0))
    b.tube(pts, 0.02, segs=6, radii=rad)
    hard('hair_mohawk', b, arm, body)

    b = Builder('head').spec(KNIT, 0.9, hair, 1.0, 0.015)
    cap(b, 0.016, front=0.98, side=1.5, back=1.85, bump=0.04)
    b.ellipsoid(Vector((0.0, crown.y + hr.y + 0.03, crown.z + 0.045)), Vector((0.042, 0.038, 0.042)), segs=10, rings=6)
    hard('hair_bun', b, arm, body)

'''
pat = re.compile(r"    # ---------------- hair \(on the skull.*?\n(?=    # ---------------- face)", re.S)
s2, n = pat.subn(lambda m: new, s)
print('replaced', n)
open(f, 'w', encoding='utf-8', newline='\n').write(s2)
