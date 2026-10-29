"""Synthesises the sounds added in run r4 and merges them into game/data/sounds.json.

    python -I tools/add_r4_sounds.py          (then bash tools/import.sh)

Run it again after tools/build_audio.py (which rewrites sounds.json), with add_work_sounds.py, add_r3_sounds.py and
make_announcer.py.
- casing_drop: a spent brass case landing on concrete: two or three bright pings, each shorter and quieter.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import build_audio as ba

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUNDS = os.path.join(ROOT, 'game', 'data', 'sounds.json')
SR = ba.SR
RNG = np.random.default_rng(77)


def ping(f0, dur, amp):
    n = int(SR * dur)
    t = np.arange(n) / SR
    # A small brass tube rings at a few inharmonic partials.
    y = sum(np.sin(2 * np.pi * f0 * k * t + RNG.uniform(0, 6)) * w for k, w in ((1.0, 1.0), (2.76, 0.55), (5.4, 0.3), (8.9, 0.15)))
    y = y * np.exp(-t * (38 + RNG.uniform(-6, 6)))
    click = ba.highpass_fast(RNG.standard_normal(n), 3000) * np.exp(-t * 900) * 0.6
    return (y + click) * amp


def main():
    files = []
    for v in range(4):
        f0 = RNG.uniform(3600, 4700)
        parts = []
        amp = 1.0
        for b in range(RNG.integers(2, 4)):
            dur = 0.09 - b * 0.02
            parts.append(ping(f0 * RNG.uniform(0.97, 1.03), dur, amp))
            parts.append(np.zeros(int(SR * RNG.uniform(0.05, 0.11) * (0.8 ** b))))
            amp *= 0.5
        x = np.concatenate(parts)
        files.append(ba.rel(ba.synth('casing_drop_%d' % v, ba.fade(x, 0.5, 15))))
    out = {'casing_drop': {'files': files, 'db': -14.0, 'dist': 18.0, 'pitch': 0.06, 'prio': 1, 'unit': 1.0}}
    with open(SOUNDS, encoding='utf-8') as fh:
        data = json.load(fh)
    data['sounds'].update(out)
    with open(SOUNDS, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=1)
    print('merged', sorted(out))


if __name__ == '__main__':
    main()
