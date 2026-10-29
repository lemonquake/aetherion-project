"""Z-fighting finder over a map's drawn faces.

    godot --path game res://tools/map_preview.tscn -- [--map=lawless_sub] --dumpfaces=<file>
    python -I tools/zfight_faces.py <file> [--gap=0.015] [--min_area=0.02] [--top=40] [--csv=<out>]

Two faces z-fight when they face the same way, lie within a centimetre or so of the same plane and overlap: the depth
buffer cannot tell which is in front, so they flicker through each other as the camera moves. Lists such pairs grouped
by the materials and "what" tags of the two faces (from GeoSink), with the overlapping area and an example position.
Decal materials are skipped (their shader pulls them toward the eye).
"""
import argparse
import collections
import math
import struct
import sys

import numpy as np


def load(path):
    with open(path, "rb") as f:
        n = struct.unpack("<I", f.read(4))[0]
        a = np.frombuffer(f.read(n * 12 * 4), dtype="<f4").reshape(n, 12).astype(np.float64)
    names = open(path + ".names", encoding="utf-8").read().split("\n")
    return a, names


def clip(poly, a, b):
    """Clips a polygon to the half-plane left of the edge a->b (Sutherland-Hodgman step)."""
    out = []
    def side(p):
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        sp, sq = side(p), side(q)
        if sp >= 0:
            out.append(p)
        if (sp >= 0) != (sq >= 0):
            t = sp / (sp - sq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def area(poly):
    s = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        s += x0 * y1 - x1 * y0
    return abs(s) * 0.5


def overlap(fa, fb):
    ca, eu, ev = fa[0:3], fa[6:9], fa[9:12]
    lu, lv = np.linalg.norm(eu), np.linalg.norm(ev)
    if lu < 1e-4 or lv < 1e-4:
        return 0.0
    u, v = eu / lu, ev / lv
    rect = [(-lu, -lv), (lu, -lv), (lu, lv), (-lu, lv)]
    cb, bu, bv = fb[0:3], fb[6:9], fb[9:12]
    pts = []
    for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        p = cb + bu * su + bv * sv - ca
        pts.append((float(p @ u), float(p @ v)))
    if area(pts) < 1e-6:
        return 0.0
    # Make both counter-clockwise for the clipper.
    def ccw(poly):
        s = sum(poly[i][0] * poly[(i + 1) % 4][1] - poly[(i + 1) % 4][0] * poly[i][1] for i in range(4))
        return poly if s > 0 else poly[::-1]
    poly = ccw(pts)
    rect = ccw(rect)
    for i in range(4):
        poly = clip(poly, rect[i], rect[(i + 1) % 4])
        if not poly:
            return 0.0
    return area(poly)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--gap", type=float, default=0.015)
    ap.add_argument("--min_area", type=float, default=0.02)
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--cell", type=float, default=4.0)
    ap.add_argument("--csv", default="")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--at", default="", help="x,y,z: list the faces whose centre is within 0.6 m and stop")
    args = ap.parse_args()
    a, names = load(args.dump)
    if args.at:
        p = np.array([float(v) for v in args.at.split(",")])
        d = np.linalg.norm(a[:, 0:3] - p, axis=1)
        for i in np.argsort(d)[:14]:
            print("%-40s c %s n %s eu %s ev %s d %.2f" % (names[i][:40], np.round(a[i, 0:3], 3), np.round(a[i, 3:6], 2), np.round(a[i, 6:9], 3), np.round(a[i, 9:12], 3), d[i]))
        return 0
    n = len(a)
    mats = [s.split("|", 1)[0] for s in names]
    skip = np.array([m.startswith("decal") or m in ("puddle", "decal_atlas", "wire") for m in mats])
    nrm = a[:, 3:6]
    ln = np.linalg.norm(nrm, axis=1)
    ok = (ln > 0.5) & ~skip
    nrm = nrm / np.maximum(ln, 1e-9)[:, None]
    # Bounding boxes of the faces.
    c = a[:, 0:3]
    ext = np.abs(a[:, 6:9]) + np.abs(a[:, 9:12])
    lo = np.floor((c - ext) / args.cell).astype(np.int64)
    hi = np.floor((c + ext) / args.cell).astype(np.int64)
    grid = collections.defaultdict(list)
    for i in np.nonzero(ok)[0]:
        span = (hi[i] - lo[i] + 1)
        if span.prod() > 4000:
            continue
        for gx in range(lo[i][0], hi[i][0] + 1):
            for gy in range(lo[i][1], hi[i][1] + 1):
                for gz in range(lo[i][2], hi[i][2] + 1):
                    grid[(gx, gy, gz)].append(i)
    seen = set()
    groups = collections.defaultdict(lambda: [0, 0.0, None])
    pairs = 0
    for cell, ids in grid.items():
        if len(ids) < 2:
            continue
        ids = np.array(ids)
        nn = nrm[ids]
        dd = np.einsum("ij,ij->i", nn, c[ids])
        for k in range(len(ids)):
            i = ids[k]
            same = (nn @ nrm[i] > 0.999) & (np.abs(dd - dd[k]) < args.gap)
            same[: k + 1] = False
            for j in ids[same]:
                key = (min(i, j), max(i, j))
                if key in seen:
                    continue
                seen.add(key)
                ar = overlap(a[i], a[j])
                if ar < args.min_area:
                    continue
                pairs += 1
                g = tuple(sorted((names[i], names[j])))
                e = groups[g]
                e[0] += 1
                e[1] += ar
                if e[2] is None or ar > e[2][0]:
                    e[2] = (ar, tuple(float(v) for v in np.round(c[i], 2)), round(float(abs(dd[k] - (nrm[i] @ c[j]))), 4), tuple(float(v) for v in np.round(nrm[i], 2)), int(i), int(j))
    print("faces %d, checked %d, z-fighting pairs %d (gap < %.3f m, overlap >= %.2f m2)" % (n, int(ok.sum()), pairs, args.gap, args.min_area))
    rows = sorted(groups.items(), key=lambda kv: -kv[1][1])
    for g, (cnt, ar, ex) in rows[: args.top]:
        print("%6d pairs %9.1f m2  %-45s <> %-45s  e.g. %.2f m2 at %s gap %s n %s" % (cnt, ar, g[0][:45], g[1][:45], ex[0], ex[1], ex[2], ex[3]))
        if args.verbose:
            for q in ex[4:6]:
                print("         %-40s c %s n %s eu %s ev %s" % (names[q][:40], np.round(a[q, 0:3], 3), np.round(a[q, 3:6], 2), np.round(a[q, 6:9], 3), np.round(a[q, 9:12], 3)))
    if args.csv:
        with open(args.csv, "w", encoding="utf-8") as f:
            f.write("count,area,a,b,example\n")
            for g, (cnt, ar, ex) in rows:
                f.write('%d,%.2f,"%s","%s","%s"\n' % (cnt, ar, g[0], g[1], ex))
    return 0


if __name__ == "__main__":
    sys.exit(main())
