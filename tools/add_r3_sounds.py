"""Synthesises the sounds added on 2026-10-27 (run r3) and merges them into game/data/sounds.json.

    python -I tools/add_r3_sounds.py          (then bash tools/import.sh)

Run it again after tools/build_audio.py and tools/add_work_sounds.py (build_audio rewrites sounds.json).
- sun_ignite: the artificial sun striking: a deep electrical thump, a rising hum and a crackle, heard everywhere.
- sun_fade: the sun winding down at dusk: a falling hum.
- sun_warn: a distant two-tone siren a few seconds before the sun ignites or goes dark.
- radio_key: the push-to-talk key going down (a double mechanical click), from the speaker's and every receiving
  teammate's radio.
- radio_squelch: the squelch tail when a transmission ends ("kshh"), on every receiving radio.
- ladder_step: a hand or boot on a metal or wooden rung.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import build_audio as ba

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUNDS = os.path.join(ROOT, 'game', 'data', 'sounds.json')
SR = ba.SR


def n(s):
    return int(SR * s)


def t(s):
    return np.arange(n(s)) / SR


def main():
    out = {}
    # Sun ignition: sub thump, a hum sweeping up from 40 to 110 Hz with harmonics, arcing crackle on top.
    d = 4.5
    tt = t(d)
    f = 40.0 + 70.0 * (1.0 - np.exp(-tt * 1.4))
    ph = 2 * np.pi * np.cumsum(f) / SR
    hum = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)) * ba.env(n(d), 0.25, 3.5, 0.15, 2.0) * 0.6
    thump = np.sin(2 * np.pi * 32 * tt) * np.exp(-tt * 5.0) * 1.2
    crackle = ba.highpass_fast(ba.noise(n(d)), 1800) * (ba.RNG.random(n(d)) < 0.02) * np.exp(-tt * 0.9) * 1.5
    ign = ba.lowpass_fast(hum + thump, 900) + crackle * 0.5
    out['sun_ignite'] = {'files': [ba.rel(ba.synth('sun_ignite', ba.fade(ign, 5, 400)))], 'db': -2.0, 'dist': 4000.0, 'pitch': 0.0, 'prio': 9, 'unit': 400.0}
    # Dusk: the hum winding down.
    d = 5.0
    tt = t(d)
    f = 105.0 - 70.0 * (1.0 - np.exp(-tt * 0.8))
    ph = 2 * np.pi * np.cumsum(f) / SR
    fade_hum = (np.sin(ph) + 0.4 * np.sin(2 * ph)) * ba.env(n(d), 0.4, 3.8, 0.0, 2.5) * 0.6
    out['sun_fade'] = {'files': [ba.rel(ba.synth('sun_fade', ba.fade(ba.lowpass_fast(fade_hum, 800), 300, 600)))], 'db': -4.0, 'dist': 4000.0, 'pitch': 0.0, 'prio': 9, 'unit': 400.0}
    # Warning: a distant two-tone siren, filtered as if far across the settlement.
    d = 3.2
    tt = t(d)
    f = np.where((tt % 0.8) < 0.4, 620.0, 465.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    siren = (np.sin(ph) + 0.3 * np.sin(3 * ph)) * ba.env(n(d), 0.3, 2.8, 0.4, 1.5)
    siren = ba.lowpass_fast(siren, 1500) * 0.5
    out['sun_warn'] = {'files': [ba.rel(ba.synth('sun_warn', ba.fade(siren, 200, 600)))], 'db': -6.0, 'dist': 4000.0, 'pitch': 0.0, 'prio': 8, 'unit': 400.0}
    # Push-to-talk key: two crisp clicks (press, contact) and a short carrier burst.
    def click(f0, dur, amp):
        return np.sin(2 * np.pi * f0 * t(dur)) * ba.env(n(dur), 0.0002, dur * 0.6) * amp
    key = np.concatenate([click(3400, 0.006, 1.0), np.zeros(n(0.028)), click(2600, 0.008, 0.8),
                          ba.highpass_fast(ba.lowpass_fast(ba.noise(n(0.07)), 3200), 500) * ba.env(n(0.07), 0.002, 0.05) * 0.25])
    out['radio_key'] = {'files': [ba.rel(ba.synth('radio_key', key))], 'db': -6.0, 'dist': 16.0, 'pitch': 0.04, 'prio': 6, 'unit': 1.4}
    # Squelch tail when the transmission ends.
    sq = ba.highpass_fast(ba.lowpass_fast(ba.noise(n(0.24)), 4200), 700) * ba.env(n(0.24), 0.002, 0.16, 0.0, 3.0) * 0.6
    sq = np.concatenate([click(2900, 0.005, 0.7), sq])
    out['radio_squelch'] = {'files': [ba.rel(ba.synth('radio_squelch', sq))], 'db': -7.0, 'dist': 16.0, 'pitch': 0.05, 'prio': 6, 'unit': 1.4}
    # Ladder rung: a dull knock with a short metallic ring.
    files = []
    for i, (fr, ring) in enumerate([(210, 1200), (180, 1450), (240, 980)]):
        d = 0.18
        tt = t(d)
        knock = np.sin(2 * np.pi * fr * tt) * np.exp(-tt * 40) + np.sin(2 * np.pi * ring * tt) * np.exp(-tt * 28) * 0.35
        knock += ba.lowpass_fast(ba.noise(n(d)), 2500) * np.exp(-tt * 70) * 0.4
        files.append(ba.rel(ba.synth('ladder_step_%d' % i, knock)))
    out['ladder_step'] = {'files': files, 'db': -10.0, 'dist': 14.0, 'pitch': 0.06, 'prio': 3, 'unit': 1.5}
    with open(SOUNDS, encoding='utf-8') as fh:
        data = json.load(fh)
    data['sounds'].update(out)
    with open(SOUNDS, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=1)
    print('merged', sorted(out))


if __name__ == '__main__':
    main()
