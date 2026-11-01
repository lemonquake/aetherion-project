"""Draws the plan of a map-editor map (game/maps/<id>/map.json): one picture per level, every piece with its id,
the spawns, lights, bot spots, landmarks and the QA notes pinned in the editor (game/maps/<id>/qa.json).

    python -I tools/map_plan.py <map_id> [--scale 12] [--out <dir>] [--no-ids]

Writes work/maps/<id>/plan.png (level 1) and plan_L2.png ... (the levels above, with the floors below greyed); outside
game/ so Godot does not import them into the game.
x east, z south (north is up in the picture); a 5 m grid with its coordinates. Needs Pillow.
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MAPS = ROOT / "game" / "maps"
BG = (24, 26, 30)
GRID = (40, 43, 50)
GRID5 = (56, 60, 70)
TEAM = {1: (70, 130, 255), 2: (255, 95, 70), 3: (80, 220, 100)}
SPOT = {"hide": (170, 90, 255), "snipe": (255, 60, 60), "cover": (255, 160, 200)}
NOTE = {"open": (255, 50, 50), "question": (255, 180, 30), "fixed": (80, 220, 90), "wontfix": (150, 150, 150)}


def font(size):
    for name in ("segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def rot(x, z, yaw):
    """Local (x, z) turned by a compass bearing (clockwise from north)."""
    b = math.radians(yaw)
    return x * math.cos(b) - z * math.sin(b), x * math.sin(b) + z * math.cos(b)


def frame(p):
    if p.get("type") == "wall":
        a, b = p["from"], p["to"]
        yaw = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        return ((a[0] + b[0]) / 2, float(p.get("y", 0)), (a[1] + b[1]) / 2), yaw
    at = p.get("at", [0, 0, 0])
    return (float(at[0]), float(at[1]), float(at[2])), float(p.get("yaw", 0))


def rect_pts(cx, cz, w, d, yaw, ox=0.0, oz=0.0):
    pts = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        lx, lz = ox + sx * w / 2, oz + sz * d / 2
        rx, rz = rot(lx, lz, yaw)
        pts.append((cx + rx, cz + rz))
    return pts


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def mat_colour(mat):
    m = (mat or "").lower()
    table = [("grass", (70, 110, 60)), ("asphalt", (70, 72, 78)), ("gravel", (120, 112, 100)), ("mud", (105, 85, 60)),
             ("water", (40, 80, 120)), ("plank", (150, 110, 70)), ("timber", (140, 100, 60)), ("plywood", (170, 140, 95)),
             ("wood", (150, 100, 70)), ("pallet", (160, 125, 80)), ("chb_white", (200, 200, 195)), ("chb_pink", (215, 160, 170)),
             ("chb_mint", (160, 210, 185)), ("chb_yellow", (220, 200, 120)), ("chb", (170, 165, 155)), ("yero", (150, 160, 165)),
             ("container", (170, 90, 60)), ("steel", (130, 135, 140)), ("tarp", (60, 100, 160)), ("tread", (120, 125, 130)),
             ("tile", (190, 185, 175)), ("paint", (210, 210, 205)), ("concrete", (135, 135, 130))]
    for k, c in table:
        if k in m:
            return c
    return (140, 140, 140)


class Plan:
    def __init__(self, doc, scale, ids=True):
        self.doc = doc
        self.s = scale
        self.ids = ids
        b = doc.get("bounds", [-40, -40, 40, 40])
        self.x0, self.z0, self.x1, self.z1 = b[0] - 6, b[1] - 6, b[2] + 6, b[3] + 6
        self.w = int((self.x1 - self.x0) * scale)
        self.h = int((self.z1 - self.z0) * scale) + 46
        self.fh = float(doc.get("level_height", 3.2))
        self.f_small = font(max(10, int(scale * 0.85)))
        self.f_label = font(max(12, int(scale * 1.1)))
        self.f_title = font(22)

    def px(self, x, z):
        return ((x - self.x0) * self.s, (z - self.z0) * self.s + 46)

    def poly(self, dr, pts, fill=None, outline=None, width=1):
        dr.polygon([self.px(x, z) for x, z in pts], fill=fill, outline=outline, width=width)

    def level_of(self, y):
        return max(0, int(math.floor((y + 0.5) / self.fh)))

    def draw(self, level, notes):
        img = Image.new("RGB", (self.w, self.h), BG)
        dr = ImageDraw.Draw(img, "RGBA")
        pieces = self.doc.get("pieces", [])
        order = {"floor": 0, "poly": 1, "ramp": 2, "stairs": 3, "box": 4, "column": 5, "wall": 6, "prop": 7, "light": 8,
                 "spot": 9, "spawn": 10, "landmark": 11}
        labels = []
        for p in sorted(pieces, key=lambda q: (order.get(q.get("type"), 5), frame(q)[0][1])):
            (cx, cy, cz), yaw = frame(p)
            t = p.get("type")
            top = cy + self.height(p)
            lv_lo = self.level_of(cy)
            lv_hi = self.level_of(top - 0.3) if t in ("wall", "column", "box") else lv_lo
            if t == "stairs":
                lv_hi = self.level_of(cy + float(p.get("rise", 3.2)))
            if lv_lo > level:
                continue
            here = lv_lo <= level <= lv_hi
            k = 1.0 if here else 0.42
            self.piece(dr, p, (cx, cy, cz), yaw, k, here, labels, level)
        self.grid(dr)
        for nt in notes:
            at = nt.get("at", [0, 0, 0])
            if self.level_of(float(at[1])) != level:
                continue
            x, y = self.px(at[0], at[2])
            c = NOTE.get(nt.get("status", "open"), (255, 50, 50))
            r = max(6, self.s * 0.6)
            dr.ellipse((x - r, y - r, x + r, y + r), fill=c, outline=(255, 255, 255), width=2)
            txt = "%s %s" % (nt.get("id", ""), (nt.get("text", "") or "")[:48])
            dr.text((x + r + 3, y - r), txt, fill=(255, 255, 255), font=self.f_label, stroke_width=3, stroke_fill=(0, 0, 0))
        if self.ids:
            for (x, y), txt, c in labels:
                dr.text((x, y), txt, fill=c, font=self.f_small, anchor="mm", stroke_width=2, stroke_fill=(0, 0, 0))
        title = "%s  ·  level %d (y %.1f m)  ·  %s" % (self.doc.get("name", ""), level + 1, level * self.fh, self.doc.get("id", ""))
        dr.rectangle((0, 0, self.w, 44), fill=(14, 15, 18))
        dr.text((10, 10), title, fill=(240, 240, 240), font=self.f_title)
        return img

    def height(self, p):
        t = p.get("type")
        if t == "box":
            return float(p.get("size", [2, 2, 2])[1])
        if t == "wall":
            return float(p.get("h", 3))
        if t in ("column", "poly"):
            return float(p.get("h", 3 if t == "column" else 0.2))
        if t == "stairs":
            return float(p.get("rise", 3.2))
        if t == "ramp":
            return float(p.get("rise", 1))
        return 0.0

    def grid(self, dr):
        b = self.doc.get("bounds", [-40, -40, 40, 40])
        for gx in range(int(math.floor(self.x0)), int(math.ceil(self.x1)) + 1):
            if gx % 5 == 0:
                c = (255, 255, 255, 46) if gx % 10 == 0 else (255, 255, 255, 22)
                dr.line([self.px(gx, self.z0), self.px(gx, self.z1)], fill=c, width=1)
                if gx % 10 == 0:
                    dr.text((self.px(gx, self.z0)[0] + 2, 48), str(gx), fill=(200, 205, 215), font=self.f_small, stroke_width=2, stroke_fill=(0, 0, 0))
        for gz in range(int(math.floor(self.z0)), int(math.ceil(self.z1)) + 1):
            if gz % 5 == 0:
                c = (255, 255, 255, 46) if gz % 10 == 0 else (255, 255, 255, 22)
                dr.line([self.px(self.x0, gz), self.px(self.x1, gz)], fill=c, width=1)
                if gz % 10 == 0:
                    dr.text((2, self.px(self.x0, gz)[1] + 2), str(gz), fill=(200, 205, 215), font=self.f_small, stroke_width=2, stroke_fill=(0, 0, 0))
        self.poly(dr, [(b[0], b[1]), (b[2], b[1]), (b[2], b[3]), (b[0], b[3])], outline=(255, 210, 60, 200), width=2)
        x, y = self.px(self.x1 - 3, self.z0 + 3)
        dr.text((x, y), "N", fill=(230, 230, 230), font=self.f_label, anchor="mm")
        dr.line([(x, y + 8), (x, y + 22)], fill=(230, 230, 230), width=2)

    def piece(self, dr, p, c, yaw, k, here, labels, level):
        t = p.get("type")
        cx, cy, cz = c
        pid = p.get("id", "")
        lab = (pid, (230, 230, 230) if here else (120, 120, 120))
        if t == "floor":
            w, d = p.get("size", [4, 4])
            col = shade(mat_colour(p.get("mat")), 0.55 * k + 0.15 * min(cy / self.fh, 2))
            self.poly(dr, rect_pts(cx, cz, w, d, yaw), fill=col + (235,), outline=shade(col, 1.4) + (255,))
            if w * d > 30:
                labels.append((self.px(cx, cz), pid, lab[1]))
        elif t == "box":
            w, h, d = p.get("size", [2, 2, 2])
            col = shade(mat_colour(p.get("top", p.get("mat"))), 0.8 * k)
            self.poly(dr, rect_pts(cx, cz, w, d, yaw), fill=col + (255,), outline=(20, 20, 20, 255))
            labels.append((self.px(cx, cz), pid, lab[1]))
        elif t == "poly":
            pts = [(cx + rot(q[0], q[1], yaw)[0], cz + rot(q[0], q[1], yaw)[1]) for q in p.get("points", [])]
            if len(pts) >= 3:
                col = shade(mat_colour(p.get("top", p.get("mat"))), 0.7 * k)
                self.poly(dr, pts, fill=col + (235,), outline=shade(col, 1.4) + (255,))
                labels.append((self.px(cx, cz), pid, lab[1]))
        elif t == "column":
            r = float(p.get("r", 0.2))
            x, y = self.px(cx, cz)
            rr = max(2, r * self.s)
            dr.ellipse((x - rr, y - rr, x + rr, y + rr), fill=shade((190, 190, 190), k), outline=(20, 20, 20))
        elif t == "wall":
            self.wall(dr, p, k, level)
            a, b = p["from"], p["to"]
            mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            x, y = self.px(mx, mz)
            labels.append(((x, y - 9), pid, (255, 220, 150) if here else (120, 110, 90)))
        elif t in ("stairs", "ramp"):
            w = float(p.get("w", 1.2 if t == "stairs" else 2))
            if t == "stairs":
                rise = float(p.get("rise", 3.2))
                n = max(2, round(rise / 0.18))
                run = float(p.get("run", 0.28))
                ln = (n - 1) * run
                for i in range(n - 1):
                    zz = -(i + 0.5) * run
                    self.poly(dr, rect_pts(cx, cz, w, run, yaw, 0, zz), fill=shade((200, 170, 90), (0.5 + 0.5 * i / n) * k) + (255,), outline=(40, 30, 10, 255))
            else:
                ln = float(p.get("len", 4))
                self.poly(dr, rect_pts(cx, cz, w, ln, yaw, 0, -ln / 2), fill=shade((180, 160, 110), k) + (255,), outline=(40, 30, 10, 255))
            ax, az = rot(0, -ln * 0.85, yaw)
            dr.line([self.px(cx, cz), self.px(cx + ax, cz + az)], fill=(255, 255, 255, int(220 * k)), width=2)
            hx, hz = rot(0, -ln * 0.5, yaw)
            labels.append((self.px(cx + hx, cz + hz), "%s ↑%.1f" % (pid, float(p.get("rise", 1))), (255, 230, 140) if here else (120, 110, 80)))
        elif t == "prop":
            x, y = self.px(cx, cz)
            r = max(3, self.s * 0.4)
            dr.rectangle((x - r, y - r, x + r, y + r), fill=shade((160, 120, 80), k), outline=(20, 20, 20))
            if here:
                labels.append(((x, y + r + 7), p.get("model", ""), (200, 170, 130)))
        elif t == "light" and here:
            x, y = self.px(cx, cz)
            col = p.get("color", "#ffc98a").lstrip("#")
            rgb = tuple(int(col[i:i + 2], 16) for i in (0, 2, 4)) if len(col) == 6 else (255, 200, 140)
            rng = float(p.get("range", 9)) * self.s
            dr.ellipse((x - rng, y - rng, x + rng, y + rng), fill=rgb + (14,))
            dr.ellipse((x - 4, y - 4, x + 4, y + 4), fill=rgb + (255,), outline=(0, 0, 0))
            if p.get("fault"):
                dr.text((x + 6, y - 6), "~", fill=rgb, font=self.f_small)
        elif t == "spawn" and here:
            col = TEAM.get(int(p.get("team", 1)), (255, 255, 255))
            f = rot(0, -1, yaw)
            s = 0.55
            pts = [(cx + f[0] * s * 1.6, cz + f[1] * s * 1.6), (cx + rot(-s, s, yaw)[0], cz + rot(-s, s, yaw)[1]), (cx + rot(s, s, yaw)[0], cz + rot(s, s, yaw)[1])]
            self.poly(dr, pts, fill=col + (255,), outline=(255, 255, 255, 255))
        elif t == "spot" and here:
            col = SPOT.get(p.get("kind", "hide"), (255, 255, 255))
            x, y = self.px(cx, cz)
            dr.ellipse((x - 5, y - 5, x + 5, y + 5), outline=col, width=3)
            f = rot(0, -3, yaw)
            dr.line([self.px(cx, cz), self.px(cx + f[0], cz + f[1])], fill=col, width=2)
            labels.append(((x, y + 12), p.get("name", "") or pid, col))
        elif t == "landmark" and here:
            x, y = self.px(cx, cz)
            dr.text((x, y), p.get("name", ""), fill=(255, 225, 90), font=self.f_label, anchor="mm", stroke_width=3, stroke_fill=(0, 0, 0))

    def wall(self, dr, p, k, level):
        a, b = p["from"], p["to"]
        ln = math.dist(a, b)
        if ln < 1e-3:
            return
        ux, uz = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        t = max(float(p.get("t", 0.2)), 0.12)
        col = shade(mat_colour(p.get("mat")), 1.1 * k)
        # the openings at this level's height (a two-storey wall has its door below and its window above)
        base = float(p.get("y", 0))
        lo, hi = level * self.fh - base, (level + 1) * self.fh - base
        ops = sorted([o for o in p.get("openings", []) if float(o.get("sill", 0)) < hi - 0.2
                      and float(o.get("sill", 0)) + float(o.get("h", 2.1)) > lo + 0.3], key=lambda o: o.get("at", 0))
        x = 0.0
        segs = []
        for o in ops:
            c = float(o.get("at", 0))
            w = float(o.get("w", 1))
            if c - w / 2 > x:
                segs.append((x, c - w / 2, "solid", o))
            segs.append((c - w / 2, c + w / 2, "door" if float(o.get("sill", 0)) < 0.05 else "window", o))
            x = c + w / 2
        if ln > x:
            segs.append((x, ln, "solid", None))
        nx, nz = -uz * t / 2, ux * t / 2
        for s0, s1, kind, o in segs:
            p0 = (a[0] + ux * s0, a[1] + uz * s0)
            p1 = (a[0] + ux * s1, a[1] + uz * s1)
            pts = [(p0[0] + nx, p0[1] + nz), (p1[0] + nx, p1[1] + nz), (p1[0] - nx, p1[1] - nz), (p0[0] - nx, p0[1] - nz)]
            if kind == "solid":
                self.poly(dr, pts, fill=col + (255,), outline=(10, 10, 10, 255))
            elif kind == "window":
                self.poly(dr, pts, fill=(120, 190, 230, int(200 * k)))
            else:
                if o and o.get("door"):
                    # the leaf, hinged at the opening's start, swung open a little
                    hx, hz = p0
                    ang = math.atan2(uz, ux) + 0.6
                    w = s1 - s0
                    dr.line([self.px(hx, hz), self.px(hx + math.cos(ang) * w, hz + math.sin(ang) * w)], fill=(230, 180, 90, int(255 * k)), width=2)


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    mid = args[0]
    scale = 12
    out = None
    ids = True
    i = 1
    while i < len(args):
        if args[i] == "--scale":
            scale = int(args[i + 1]); i += 2
        elif args[i] == "--out":
            out = Path(args[i + 1]); i += 2
        elif args[i] == "--no-ids":
            ids = False; i += 1
        else:
            i += 1
    path = MAPS / mid / "map.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    qa = MAPS / mid / "qa.json"
    notes = json.loads(qa.read_text(encoding="utf-8")).get("notes", []) if qa.exists() else []
    out = out or (ROOT / "work" / "maps" / mid)
    out.mkdir(parents=True, exist_ok=True)
    plan = Plan(doc, scale, ids)
    written = []
    for lv in range(int(doc.get("levels", 1))):
        img = plan.draw(lv, notes)
        name = "plan.png" if lv == 0 else "plan_L%d.png" % (lv + 1)
        img.save(out / name)
        written.append(str(out / name))
    print("plan: %d pieces, %d notes -> %s" % (len(doc.get("pieces", [])), len(notes), ", ".join(written)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
