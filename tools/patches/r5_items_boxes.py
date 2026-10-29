"""r5: region boxes for the moving parts of guns whose sources do not name them."""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'tools', 'blender', 'process_items.py')
s = open(p, 'rb').read().decode()

BOXES = {
    'pistol_9': "boxes={'slide': [[0.0, 1.0, 0.72, 1.0]]}, cut=['slide']",
    'pistol_45': "boxes={'slide': [[0.0, 1.0, 0.72, 1.0]]}, cut=['slide']",
    'shotgun_pump': "boxes={'pump': [[0.16, 0.37, 0.5, 0.72]]}, cut=['pump']",
    'smg_9': "boxes={'mag': [[0.22, 0.42, 0.0, 0.52]]}",
    'rifle_762': "boxes={'mag': [[0.45, 0.62, 0.0, 0.5]]}",
    'rifle_scar': "boxes={'mag': [[0.44, 0.58, 0.0, 0.48]]}",
    'rifle_m416': "boxes={'mag': [[0.42, 0.56, 0.0, 0.48]]}",
    'rifle_m762': "boxes={'mag': [[0.48, 0.63, 0.0, 0.5]]}",
    'dmr_mini14': "boxes={'mag': [[0.44, 0.58, 0.05, 0.55]]}, cut=['mag']",
    'bolt_kar98': "boxes={'bolt': [[0.62, 0.78, 0.45, 0.7]]}",
    'smg_tommy': "boxes={'mag': [[0.45, 0.56, 0.0, 0.88]]}",
    'lmg_m249': "boxes={'mag': [[0.48, 0.6, 0.25, 0.56]]}, cut=['mag']",
    'shotgun_saiga': "boxes={'mag': [[0.38, 0.52, 0.0, 0.55]]}",
    'shotgun_double': "boxes={'barrel': [[0.0, 0.62, 0.55, 1.0]]}, cut=['barrel']",
    'sumpak': "boxes={'barrel': [[0.0, 0.38, 0.85, 1.0]]}, cut=['barrel']",
    'marksman_308': "boxes={'mag': [[0.5, 0.63, 0.0, 0.53]]}",
}
for gid, extra in BOXES.items():
    m = re.search(r"(    '%s': dict\(src=[^\n]*?)(\),?\r?\n)" % gid, s)
    if not m or 'boxes=' in m.group(1):
        print('skip', gid)
        continue
    line = m.group(1)
    s = s[:m.start()] + line + ', ' + extra + m.group(2) + s[m.end():]
s = s.replace("rot=(17, 0, 0),", "upflip=True,")
open(p, 'wb').write(s.encode())
print('patched')
