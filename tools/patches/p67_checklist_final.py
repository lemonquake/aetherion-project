"""Checklist: final-revision results of the loot run (EXE runs, clean exit).

    python -I tools/patches/p67_checklist_final.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'docs', 'CHECKLIST.md')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''| Loot play-through `--autotest=loot` (loot4, 11 bots) | 29 checks, 0 failed:''',
    '''| Loot play-through `--autotest=loot` (11 bots; editor loot4 and the exported EXE loot_exe2, version 0.3.0) | 29 checks, 0 failed on both:''')
rep('''| Same play-through on the exported EXE (31 bots) | 26 checks, 0 failed |''',
    '''| Same play-through on the exported EXE (31 bots, version 0.3.0, t26_exe) | 26 checks, 0 failed, clean exit. One run (t25_exe, with a second game running on the machine) failed `team_cluster`: a bot teammate 73.5 m away under canopy against a 60 m limit; five other runs 31–41 m |''')
rep('''| Reconnect / late join | Implemented | Not run this session |''',
    '''| Reconnect / late join | Implemented | Not run this session. Late joiners now get only the floor-item changes (items taken, items dropped) and the opened loot-box lids |
| Clean exit | Fixed | The exported game crashed on quitting (heap corruption, exit code 0xC0000374) after ground items became server-side render instances; the map now frees its bodies and render instances when it leaves the tree (on quit and on return to the menu). EXE runs loot_exe2 and t26_exe exit 0 |''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
