"""PERFORMANCE.md: what the loot costs and how it is kept cheap (loot run 2026-10-26).

    python -I tools/patches/p66_perf_doc_loot.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'docs', 'PERFORMANCE.md')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')
a = '''## Phones (the Mobile profile)
'''
assert s.count(a) == 1
s = s.replace(a, '''## Loot: ground items and loot boxes (2026-10-26)

The map now starts with ~6,600 items on the ground and ~3,800 loot boxes. How they stay cheap:

- **Ground items have no scene nodes**: each is a static physics body (for the Use ray) and a render instance made
  directly on the servers, with a short draw distance (12 m; 22 m for guns and packs, scaled by the draw-distance
  setting), no shadow, and the interior layer indoors (hidden from the air). Freed when the match is torn down.
- **Loot boxes are MultiMesh instances** like the furniture, with no shadows. A box's open model is a render instance
  of its own, created only when the box is first opened: registering the open models in every cell cost a draw
  call per cell, model and surface even while hidden (the first version: +300 to +480 draw calls at the ground
  spots).
- Hidden MultiMesh instances (picked-up props, broken windows, opened boxes) are scaled to nothing where they stand;
  they used to be moved 1 km below the map, which stretched their whole cell's bounds.

Measured with `--autotest=perf --attrib` (new `loot` toggle: every ground item and box hidden, same view), RTX 4060,
1600x900, 11 bots, under ~100% background CPU load: densest ground spot 10.4-10.7 ms with loot, 9.7 ms without
(about 0.9 ms; 110-200 of ~3,300 draw calls). The fixed ground spots against the same day's baseline before the loot
work: market 7.27 -> 7.36 ms, looban 7.12 -> 7.55 ms, looban_east 10.65 -> 9.83 ms, rail 7.09 -> 6.88 ms (the new
placement also shifted furniture, so spots do not hold identical scenes). Not measured on a phone.

## Phones (the Mobile profile)
''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
