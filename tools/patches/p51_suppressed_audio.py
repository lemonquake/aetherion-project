"""Adds suppressed gunshots to tools/build_audio.py (built from the cut near-shot files) and a --suppressed mode that
only builds those and merges them into data/sounds.json.

    python -I tools/patches/p51_suppressed_audio.py
    python -I tools/build_audio.py --suppressed
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'tools', 'build_audio.py')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''# ------------------------------------------------------------------ copied libraries''', '''def suppressed_variant(x):
    """A suppressed shot: the supersonic crack and action noise stay, the muzzle blast's boom and long tail go."""
    y = highpass_fast(x, 350) * 0.55
    n = len(y)
    e = env(n, 0.0005, 0.09, sustain=0.0, curve=5.0)
    y = y * e
    # The "thwip" of gas leaving the can: short band-limited noise.
    k = int(SR * 0.05)
    puff = highpass_fast(lowpass_fast(noise(k), 2500), 500) * env(k, 0.001, 0.035) * np.abs(y).max() * 0.6
    y[:k] += puff
    # Mechanical action a few milliseconds later.
    c = int(SR * 0.012)
    m = int(SR * 0.004)
    click = highpass_fast(noise(m), 2000) * env(m, 0.0002, 0.003) * np.abs(y).max() * 0.5
    y[c:c + m] += click
    return fade(y[:int(SR * 0.45)], 0.3, 120.0)


def build_suppressed():
    """Suppressed variants of every gun's near shots (shot_<sid>_sup): about a third of the reach, no distant echo."""
    folder = os.path.join(OUT, 'guns')
    for sid in GUNS:
        files = []
        for k in range(5):
            src = os.path.join(folder, f'{sid}_near_{k}.wav')
            if not os.path.exists(src):
                break
            dst = os.path.join(folder, f'{sid}_sup_{k}.wav')
            write_wav(dst, suppressed_variant(read_wav(src)), peak=0.7)
            files.append(dst)
        if files:
            define('shot_' + sid + '_sup', files, db=-1.0, dist=round(GUN_DIST[sid] * 0.3), pitch=0.04, prio=7, unit=6.0)
            print('suppressed', sid, len(files))


# ------------------------------------------------------------------ copied libraries''')
rep('''def main():
    build_guns()''', '''def main():
    if '--suppressed' in sys.argv:
        # Only the suppressed shots, merged into the existing sounds.json.
        build_suppressed()
        path = os.path.join(GAME, 'data', 'sounds.json')
        data = json.load(open(path, encoding='utf-8'))
        data['sounds'].update(SOUNDS)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=1)
        print('sounds:', len(data['sounds']))
        return
    build_guns()
    build_suppressed()''')
rep('''import json
import re''', '''import json
import re
import sys''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
