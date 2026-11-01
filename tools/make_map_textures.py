"""Textures for the maps made in the map editor, drawn like Freight Delight's (tools/make_freight_textures.py: noise and
shapes, nothing downloaded). Each set is a folder under game/assets/maps/textures/ ("brgy/court_green" in a map file);
surfaces.json gets their entries (the other sets' entries are kept).

    python -I tools/make_map_textures.py [--only=name,name]

Then run `bash tools/import.sh` so Godot imports the new pictures.
"""
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("freight_tex", HERE / "make_freight_textures.py")
ft = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ft)
col, mix, noise, smooth, blobs, cracks, blur = ft.col, ft.mix, ft.noise, ft.smooth, ft.blobs, ft.cracks, ft.blur
N = ft.N


def court_paint(name, seed, paint):
    """Painted court concrete: the paint worn through to grey where feet turn, scuffs from rubber soles, hairline
    cracks; matte. One repeat is 4 m."""
    n1 = noise(seed=seed, beta=2.2)
    n2 = noise(seed=seed + 1, beta=1.0, hi=230)
    base = mix(col(120, 118, 112), col(96, 94, 90), n1)
    alb = mix(paint * 0.92, paint * 1.08, n2)
    wear = smooth(noise(seed=seed + 2, beta=2.6) * (0.6 + 0.4 * n2), 0.62, 0.8)
    alb = mix(alb, base, wear * 0.75)
    scuff = smooth(noise(seed=seed + 3, beta=1.4, ax=2.0, ay=0.7), 0.8, 0.92)
    alb = mix(alb, col(40, 40, 42), scuff * 0.35)
    cr = blur(cracks((N, N), 6, seed + 4, (40, 200), 1), 0.5)
    alb = mix(alb, col(50, 50, 50), cr * 0.6)
    ft.save(name, alb, n1 + n2 * 0.5 - cr * 2, 1.5, phys="concrete", rough=0.62, size=4.0)


def line_paint(name, seed):
    n = noise(seed=seed, beta=1.6)
    alb = mix(col(236, 234, 226), col(200, 198, 190), n)
    chips = smooth(noise(seed=seed + 1, beta=2.0), 0.72, 0.78)
    alb = mix(alb, col(110, 108, 104), chips * 0.8)
    ft.save(name, alb, n - chips, 1.0, phys="concrete", rough=0.55, size=1.0)


def plaza(name, seed):
    """Swept plaza concrete: 2 m bays with saw-cut joints, a faint broom texture, a few stains. Lighter and calmer
    than the yard's concrete."""
    y, x = np.mgrid[0:N, 0:N] / N
    n1 = noise(seed=seed, beta=2.0)
    broom = noise(seed=seed + 1, beta=1.0, ax=0.15, ay=4.0, hi=240)
    alb = mix(col(158, 154, 146), col(132, 129, 122), n1)
    alb *= (0.94 + 0.1 * broom)[..., None]
    joint = np.maximum(smooth(1 - np.minimum(x % 1.0, 1.0 - x % 1.0) * 400, 0, 1), smooth(1 - np.minimum(y % 1.0, 1.0 - y % 1.0) * 400, 0, 1))
    alb = mix(alb, col(70, 68, 64), joint * 0.7)
    st = blobs((N, N), 5, seed + 2, (14, 50), 12) * noise(seed=seed + 3, beta=1.6)
    alb = mix(alb, col(96, 90, 82), smooth(st, 0.15, 0.55) * 0.45)
    ft.save(name, alb, n1 + broom * 0.4 - joint * 2, 1.6, phys="concrete", rough=0.85, size=4.0)


def build(only=None):
    ft.FOLDER = "brgy"
    jobs = {
        "court_green": lambda: court_paint("court_green", 901, col(46, 112, 74)),
        "court_red": lambda: court_paint("court_red", 907, col(150, 46, 40)),
        "court_line": lambda: line_paint("court_line", 911),
        "plaza": lambda: plaza("plaza", 913),
    }
    signs = {
        "sign_hall": ([("BARANGAY SAN ROQUE", 70, None), ("BULWAGANG PAMBARANGAY", 44, (250, 220, 120))], (24, 70, 140), (250, 250, 245), "metal", (250, 220, 120)),
        "sign_toda": ([("SAN ROQUE TODA", 84, None), ("TERMINAL • P15 ISANG SAKAY", 40, (40, 40, 40))], (250, 200, 40), (30, 40, 110), "metal", (30, 40, 110)),
        "sign_kapilya": ([("KAPILYA NG SAN ROQUE", 66, (255, 230, 140)), ("MISA TUWING LINGGO • 6 NG UMAGA", 34, None)], (90, 40, 30), (245, 240, 230), "wood", (255, 230, 140)),
        "sign_court": ([("SAN ROQUE COVERED COURT", 62, None), ("LIGA NG BARANGAY • BAWAL ANG NAKAPANTSINELAS", 26, (255, 230, 90))], (20, 90, 60), (250, 250, 245), "metal", (255, 230, 90)),
    }
    for k, (lines, bg, fg, board, border) in signs.items():
        jobs[k] = (lambda k=k, lines=lines, bg=bg, fg=fg, board=board, border=border: ft.sign(k, 700 + len(k), lines, bg, fg, board=board, border=border))
    for k, fn in jobs.items():
        if only and k not in only:
            continue
        fn()
        print("  brgy/" + k)
    path = ft.OUT / "surfaces.json"
    old = json.loads(path.read_text()) if path.exists() else {}
    old.update(ft.SURFACES)
    path.write_text(json.dumps(dict(sorted(old.items())), indent=1))
    print("wrote %d surfaces to %s" % (len(ft.SURFACES), path))


if __name__ == "__main__":
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))
    build(only)
