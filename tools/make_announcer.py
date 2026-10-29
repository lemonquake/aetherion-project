"""Makes the loudspeaker announcer and the day/night siren, and merges them into game/data/sounds.json.

    python -I tools/make_announcer.py          (then bash tools/import.sh)

Run it again after tools/build_audio.py (which rewrites sounds.json), like add_work_sounds.py and add_r3_sounds.py.

The voice is the Windows "Microsoft David" text-to-speech voice (male, en-US; System.Speech, offline). Each line is
then made to sound like a man on a public-address horn out in the settlement:
- the horn: band limited to about 380 Hz - 4.2 kHz with a nasal peak near 1.9 kHz, a short comb from the horn's
  throat, and an overdriven amplifier (soft clipping);
- the street: slap-back echoes off the house fronts and from the other horns down the line (95 ms - 1.1 s), and a
  diffuse tail, so it carries the way a barangay PA does between tin walls;
- a "far" variant for listeners well away from the nearest horn: duller (air and walls), more echo than voice.

Lines: pa_ign_60 / pa_ign_30 (before the artificial sun ignites), pa_dusk_60 / pa_dusk_30 (before it goes dark),
pa_n10 ... pa_n1 (the countdown), pa_chime (the attention tones before a 60/30 s line), pa_siren (7 s wail at the
change itself).
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_audio as ba

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, 'game')
SOUNDS = os.path.join(GAME, 'data', 'sounds.json')
OUT = os.path.join(GAME, 'assets', 'audio', 'announcer')
RAW = os.path.join(ROOT, 'tools', 'cache', 'announcer')
SR = ba.SR
RNG = np.random.default_rng(4242)

NUMBERS = ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten']
LINES = {
    'pa_ign_60': 'Attention, all residents of Sitio Kalinaw! The sun will ignite in sixty seconds. Sixty seconds!',
    'pa_ign_30': 'Thirty seconds to sunrise! Thirty seconds! Get out of the open!',
    'pa_dusk_60': 'Attention, all residents of Sitio Kalinaw! Lights out in sixty seconds. Ready your flashlights!',
    'pa_dusk_30': 'Thirty seconds to darkness! Thirty seconds!',
}
for i, w in enumerate(NUMBERS):
    LINES['pa_n%d' % (i + 1)] = w.capitalize() + '!'

PS1 = r'''
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SelectVoice("Microsoft David Desktop")
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(48000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$lines = Get-Content -Raw -Encoding UTF8 "__LIST__" | ConvertFrom-Json
foreach ($p in $lines.PSObject.Properties) {
  $s.SetOutputToWaveFile((Join-Path "__DIR__" ($p.Name + ".wav")), $fmt)
  $s.Rate = $p.Value.rate
  $s.Volume = 100
  $s.Speak($p.Value.text)
}
$s.SetOutputToNull()
'''


def tts():
    os.makedirs(RAW, exist_ok=True)
    spec = {k: {'text': v, 'rate': (1 if k.startswith('pa_n') else -1)} for k, v in LINES.items()}
    lst = os.path.join(RAW, 'lines.json')
    with open(lst, 'w', encoding='utf-8') as f:
        json.dump(spec, f)
    ps = os.path.join(RAW, 'speak.ps1')
    with open(ps, 'w', encoding='utf-8') as f:
        f.write(PS1.replace('__LIST__', lst).replace('__DIR__', RAW))
    subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps], check=True)


def read(path):
    with wave.open(path) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
        assert w.getframerate() == SR, w.getframerate()
    return x


def trim(x, thr=0.01, pad=0.04):
    idx = np.nonzero(np.abs(x) > thr)[0]
    if len(idx) == 0:
        return x
    a = max(idx[0] - int(pad * SR), 0)
    b = min(idx[-1] + int(pad * 2 * SR), len(x))
    return x[a:b]


def peaking(x, f0, gain_db, q):
    # RBJ peaking EQ biquad.
    A = 10 ** (gain_db / 40.0)
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w0), 1 - al * A]
    a = [1 + al / A, -2 * np.cos(w0), 1 - al / A]
    return signal.lfilter(b, a, x)


def band(x, lo, hi, order=4):
    sos = signal.butter(order, [lo, hi], btype='band', fs=SR, output='sos')
    return signal.sosfilt(sos, x)


def lowpass(x, f, order=2):
    sos = signal.butter(order, f, btype='low', fs=SR, output='sos')
    return signal.sosfilt(sos, x)


def horn(x, drive=2.2):
    """The PA horn and its amplifier."""
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = band(x, 380.0, 4200.0)
    x = peaking(x, 1900.0, 7.0, 1.1)
    x = peaking(x, 900.0, 3.0, 0.9)
    d = int(0.0011 * SR)
    x = x + 0.32 * np.concatenate([np.zeros(d), x[:-d]])     # horn throat comb
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = np.tanh(drive * x) / np.tanh(drive)                    # overdriven amplifier
    x = band(x, 330.0, 5000.0, 2)
    return x


def tail_ir(rt60, n_s, cutoff):
    n = int(n_s * SR)
    t = np.arange(n) / SR
    ir = RNG.standard_normal(n) * np.exp(-6.91 * t / rt60)
    ir = lowpass(ir, cutoff, 2)
    ir[: int(0.03 * SR)] *= np.linspace(0, 1, int(0.03 * SR))
    return ir / np.sqrt(np.sum(ir ** 2))


def street(x, far=False):
    """Echoes off the house fronts and the other horns down the street, then a diffuse tail."""
    echoes = [(0.095, 0.28, 3400), (0.23, 0.22, 2800), (0.41, 0.16, 2200), (0.69, 0.11, 1700), (1.08, 0.07, 1300)]
    total = len(x) + int(2.4 * SR)
    y = np.zeros(total)
    direct = 0.55 if far else 1.0
    y[: len(x)] += x * direct
    for (dt, g, fc) in echoes:
        d = int(dt * SR)
        e = lowpass(x, fc if not far else fc * 0.7)
        y[d: d + len(e)] += e * g * (1.5 if far else 1.0)
    ir = tail_ir(1.7 if not far else 2.2, 2.2, 2600 if not far else 1500)
    wet = signal.fftconvolve(x, ir)[:total]
    y[: len(wet)] += wet * (0.12 if not far else 0.3)
    if far:
        y = lowpass(y, 1700.0, 2)
    return y


def fade_out(x, ms=180):
    n = min(int(SR * ms / 1000), len(x))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n) ** 2
    return x


def write(name, x, peak=0.9):
    p = os.path.join(OUT, name + '.wav')
    ba.write_wav(p, fade_out(x), peak)
    return ba.rel(p)


def chime():
    # Three falling tones, a mallet on a struck bar, through the same horn.
    t = np.arange(int(1.6 * SR)) / SR
    y = np.zeros_like(t)
    for i, f in enumerate([784.0, 659.3, 523.3]):
        s = int(i * 0.36 * SR)
        tt = t[: len(t) - s]
        tone = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * 2 * f * tt) + 0.12 * np.sin(2 * np.pi * 3.01 * f * tt))
        y[s:] += tone * np.exp(-tt * 3.2) * np.clip(tt / 0.004, 0, 1)
    return horn(y, 1.6)


def siren(seconds=7.0):
    # A motor siren: winds up to pitch, wails up and down twice, winds down with the last second.
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = np.empty(n)
    up = 1.3
    for i, tt in enumerate(t):
        if tt < up:
            f[i] = 140 + (590 - 140) * (1 - np.exp(-tt * 3.0)) / (1 - np.exp(-up * 3.0))
        elif tt < seconds - 1.2:
            f[i] = 590 + 85 * np.sin(2 * np.pi * (tt - up) / 2.3 - np.pi * 0.5) + 85
        else:
            k = (tt - (seconds - 1.2)) / 1.2
            f[i] = (590 + 85 * np.sin(2 * np.pi * (seconds - 1.2 - up) / 2.3 - np.pi * 0.5) + 85) * (1 - 0.55 * k * k)
    ph = 2 * np.pi * np.cumsum(f) / SR
    # Rotor chopping the air: a rich, slightly buzzy tone with a few odd harmonics.
    y = np.sin(ph) + 0.5 * np.sin(3 * ph) + 0.28 * np.sin(5 * ph) + 0.12 * np.sin(7 * ph)
    y += 0.25 * np.sign(np.sin(ph)) * 0.3
    am = 1.0 + 0.06 * np.sin(2 * np.pi * 21.0 * t)
    e = np.clip(t / 0.5, 0, 1) * np.clip((seconds - t) / 0.9, 0, 1) ** 0.7
    y = y * am * e
    y = band(y, 180.0, 5200.0, 2)
    y = peaking(y, 1300.0, 3.0, 0.8)
    y = np.tanh(1.8 * y / (np.max(np.abs(y)) + 1e-9))
    return y


def main():
    if '--no-tts' not in sys.argv:
        tts()
    os.makedirs(OUT, exist_ok=True)
    out = {}
    for name in LINES:
        v = trim(read(os.path.join(RAW, name + '.wav')))
        h = horn(v)
        near = street(h)
        far = street(h, far=True)
        is_num = name.startswith('pa_n')
        f_near = write(name, near)
        f_far = write(name + '_far', far)
        out[name] = {'files': [f_near], 'db': 2.0 if not is_num else 3.0, 'dist': 900.0, 'pitch': 0.0, 'prio': 9,
                     'unit': 22.0, 'far': name + '_far', 'far_from': 85.0}
        out[name + '_far'] = {'files': [f_far], 'db': 2.0 if not is_num else 3.0, 'dist': 900.0, 'pitch': 0.0,
                              'prio': 9, 'unit': 22.0}
    c = chime()
    out['pa_chime'] = {'files': [write('pa_chime', street(c))], 'db': 0.0, 'dist': 900.0, 'pitch': 0.0, 'prio': 9,
                       'unit': 22.0, 'far': 'pa_chime_far', 'far_from': 85.0}
    out['pa_chime_far'] = {'files': [write('pa_chime_far', street(c, True))], 'db': 0.0, 'dist': 900.0, 'pitch': 0.0,
                           'prio': 9, 'unit': 22.0}
    s = siren(7.0)
    out['pa_siren'] = {'files': [write('pa_siren', street(s))], 'db': 3.0, 'dist': 1400.0, 'pitch': 0.0, 'prio': 9,
                       'unit': 30.0, 'far': 'pa_siren_far', 'far_from': 110.0}
    out['pa_siren_far'] = {'files': [write('pa_siren_far', street(s, True))], 'db': 3.0, 'dist': 1400.0, 'pitch': 0.0,
                           'prio': 9, 'unit': 30.0}
    ba.source_json(OUT, {
        'source': 'Generated by tools/make_announcer.py',
        'title': 'Loudspeaker announcer lines, attention chime and day/night siren',
        'authors': ['Speech: Windows "Microsoft David Desktop" text-to-speech voice (System.Speech, offline)',
                    'Processing, chime and siren: synthesised for this project'],
        'license': 'Generated for this project; speech produced with the Windows built-in TTS voice',
        'attribution_required': False, 'kind': 'audio', 'retrieved': '2026-10-27',
        'modifications': 'loudspeaker horn, overdrive, street echoes and tail; far variants duller and wetter'})
    with open(SOUNDS, encoding='utf-8') as fh:
        data = json.load(fh)
    data['sounds'].update(out)
    with open(SOUNDS, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=1)
    for k in sorted(out):
        if not k.endswith('_far'):
            p = os.path.join(GAME, out[k]['files'][0])
            with wave.open(p) as w:
                print('%-12s %.2f s' % (k, w.getnframes() / w.getframerate()))


if __name__ == '__main__':
    main()
