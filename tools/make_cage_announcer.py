"""Makes Lawless Sub's cage announcer (r11) and merges it into game/data/sounds.json.

    python -I tools/make_cage_announcer.py          (then bash tools/import.sh)

Run it after tools/make_announcer.py (it reuses that script's helpers and adds pa_cage_* entries; the classic map's
pa_* lines stay as they are). Run it again after tools/build_audio.py, which rewrites sounds.json.

Voice: Windows "Microsoft David Desktop" (System.Speech, offline), spoken slowly and dropped about a semitone.
Chain, in the order a real announcement goes:
- the mic and the radio link to the speakers: a key-up click, band-limited 300 Hz - 3.4 kHz with a presence peak,
  soft clipping, a little hiss under the voice and a squelch tail when the key is released;
- the loudspeaker stack: horn resonances, overdriven amplifier;
- the arena: a flutter echo between the parallel steel walls, slap-back delays off the far side of the cage
  (0.18 - 1.3 s) and a long, dark diffuse tail. The game adds the real distance delays between speakers.
- a "far" variant for listeners well away from the nearest speaker: duller, more delay and tail than voice.
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
import make_announcer as ma

ROOT = ma.ROOT
GAME = ma.GAME
SOUNDS = ma.SOUNDS
OUT = os.path.join(GAME, 'assets', 'audio', 'announcer_cage')
RAW = os.path.join(ROOT, 'tools', 'cache', 'announcer_cage')
SR = ba.SR
RNG = np.random.default_rng(7171)

NUMBERS = ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten']
LINES = {
    'pa_cage_ign_60': 'Attention, subjects. The daylight phase begins in sixty seconds.',
    'pa_cage_ign_30': 'Thirty seconds to daylight. Thirty seconds.',
    'pa_cage_dusk_60': 'Attention, subjects. The night phase begins in sixty seconds. Lights will be withdrawn.',
    'pa_cage_dusk_30': 'Thirty seconds to darkness. Thirty seconds.',
    'pa_cage_start': 'Attention, subjects. The trial has begun. Only one team will leave this enclosure.',
    'pa_cage_zone': 'Containment is closing. Move inside the marked area.',
    'pa_cage_zone_final': 'Final containment phase. Remain inside the line.',
    'pa_cage_team_out': 'A team has been eliminated.',
    'pa_cage_end': 'The trial is over. Survivors, remain where you are. Collection will begin shortly.',
    'pa_cage_amb_1': 'Remain calm. You are being observed.',
    'pa_cage_amb_2': 'Do not approach the perimeter wall.',
    'pa_cage_amb_3': 'Reminder. Teams that work together survive longer.',
    'pa_cage_amb_4': 'Food and water are not provided. Please do not ask.',
    'pa_cage_amb_5': 'This enclosure is for your protection.',
    'pa_cage_amb_6': 'Subjects found at the wall will be... discouraged.',
}
for i, w in enumerate(NUMBERS):
    LINES['pa_cage_n%d' % (i + 1)] = w.capitalize() + '.'

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
    spec = {k: {'text': v, 'rate': (0 if '_n' in k else -2)} for k, v in LINES.items()}
    lst = os.path.join(RAW, 'lines.json')
    with open(lst, 'w', encoding='utf-8') as f:
        json.dump(spec, f)
    ps = os.path.join(RAW, 'speak.ps1')
    with open(ps, 'w', encoding='utf-8') as f:
        f.write(PS1.replace('__LIST__', lst).replace('__DIR__', RAW))
    subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps], check=True)


def deepen(x, ratio=0.945):
    """About a semitone down (and a touch slower): resample, played back at the original rate."""
    n = int(len(x) / ratio)
    return signal.resample(x, n)


def radio(x):
    """Mic into a radio link: key-up click, narrow band, presence peak, clipping, hiss, squelch tail."""
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = ma.band(x, 300.0, 3400.0, 4)
    x = ma.peaking(x, 2000.0, 6.0, 1.0)
    x = ma.peaking(x, 700.0, -3.0, 0.8)
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = np.tanh(3.2 * x) / np.tanh(3.2)
    lead = int(0.09 * SR)
    tail = int(0.22 * SR)
    y = np.zeros(lead + len(x) + tail)
    # Key-up: a short click and a breath of carrier before the voice.
    click = np.exp(-np.arange(int(0.012 * SR)) / (0.002 * SR)) * RNG.choice([-1.0, 1.0], int(0.012 * SR))
    y[:len(click)] += click * 0.6
    y[lead:lead + len(x)] += x
    hiss = ma.band(RNG.standard_normal(len(y)), 1200.0, 3400.0, 2)
    hiss = hiss / (np.max(np.abs(hiss)) + 1e-9) * 0.035
    y += hiss
    # Squelch tail when the key is released: a burst of band-limited noise, gone in 150 ms.
    sq = ma.band(RNG.standard_normal(tail), 500.0, 3200.0, 2)
    sq = sq / (np.max(np.abs(sq)) + 1e-9) * 0.28 * np.exp(-np.arange(tail) / (0.05 * SR))
    y[lead + len(x):] += sq
    return ma.band(y, 260.0, 3800.0, 2)


def speaker(x, drive=2.6):
    """The cage's speaker stack: horn resonances and a hard-driven amplifier."""
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = ma.peaking(x, 1250.0, 4.0, 1.4)
    x = ma.peaking(x, 2600.0, 3.0, 1.6)
    d = int(0.0016 * SR)
    x = x + 0.25 * np.concatenate([np.zeros(d), x[:-d]])
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = np.tanh(drive * x) / np.tanh(drive)
    return ma.band(x, 240.0, 4500.0, 2)


def arena(x, far=False):
    """Steel walls a long way apart: flutter, slap-backs off the far sides, a long dark tail."""
    total = len(x) + int(3.4 * SR)
    y = np.zeros(total)
    y[:len(x)] += x * (0.5 if far else 1.0)
    # Flutter echo between parallel steel panels (short, metallic, decaying).
    fl = np.zeros(int(0.5 * SR))
    for k in range(1, 12):
        idx = int(k * 0.034 * SR)
        if idx < len(fl):
            fl[idx] = 0.42 ** k
    flut = signal.fftconvolve(ma.band(x, 900.0, 4000.0, 2), fl)[:total]
    y[:len(flut)] += flut * (0.5 if far else 0.35)
    taps = [(0.18, 0.34, 3000), (0.43, 0.26, 2500), (0.77, 0.19, 2000), (1.06, 0.14, 1600), (1.31, 0.1, 1300)]
    for (dt, g, fc) in taps:
        dd = int(dt * SR)
        e = ma.lowpass(x, fc * (0.7 if far else 1.0))
        y[dd:dd + len(e)] += e * g * (1.6 if far else 1.0)
    ir = ma.tail_ir(3.1 if not far else 3.6, 3.3, 2200 if not far else 1300)
    wet = signal.fftconvolve(x, ir)[:total]
    y[:len(wet)] += wet * (0.16 if not far else 0.36)
    if far:
        y = ma.lowpass(y, 1600.0, 2)
    return y


def main():
    if '--no-tts' not in sys.argv:
        tts()
    os.makedirs(OUT, exist_ok=True)
    out = {}
    for name in LINES:
        v = ma.trim(ma.read(os.path.join(RAW, name + '.wav')))
        v = deepen(v)
        s = speaker(radio(v))
        near = arena(s)
        far = arena(s, far=True)
        is_num = '_n' in name
        p_near = os.path.join(OUT, name + '.wav')
        p_far = os.path.join(OUT, name + '_far.wav')
        ba.write_wav(p_near, ma.fade_out(near), 0.9)
        ba.write_wav(p_far, ma.fade_out(far), 0.9)
        db = 4.0 if is_num else 3.0
        out[name] = {'files': [ba.rel(p_near)], 'db': db, 'dist': 1300.0, 'pitch': 0.0, 'prio': 9, 'unit': 26.0,
                     'far': name + '_far', 'far_from': 90.0}
        out[name + '_far'] = {'files': [ba.rel(p_far)], 'db': db, 'dist': 1300.0, 'pitch': 0.0, 'prio': 9, 'unit': 26.0}
    c = ma.chime()
    for nm, sig in [('pa_cage_chime', c), ('pa_cage_siren', ma.siren(7.0))]:
        p_near = os.path.join(OUT, nm + '.wav')
        p_far = os.path.join(OUT, nm + '_far.wav')
        ba.write_wav(p_near, ma.fade_out(arena(speaker(sig, 1.8))), 0.9)
        ba.write_wav(p_far, ma.fade_out(arena(speaker(sig, 1.8), True)), 0.9)
        out[nm] = {'files': [ba.rel(p_near)], 'db': 2.0, 'dist': 1500.0, 'pitch': 0.0, 'prio': 9, 'unit': 30.0,
                   'far': nm + '_far', 'far_from': 110.0}
        out[nm + '_far'] = {'files': [ba.rel(p_far)], 'db': 2.0, 'dist': 1500.0, 'pitch': 0.0, 'prio': 9, 'unit': 30.0}
    ba.source_json(OUT, {
        'source': 'Generated by tools/make_cage_announcer.py',
        'title': 'Lawless Sub cage announcer: day/night, match and ambient lines, chime and siren',
        'authors': ['Speech: Windows "Microsoft David Desktop" text-to-speech voice (System.Speech, offline)',
                    'Processing, chime and siren: synthesised for this project'],
        'license': 'Generated for this project; speech produced with the Windows built-in TTS voice (licence for commercial use not verified)',
        'attribution_required': False, 'kind': 'audio', 'retrieved': '2026-10-29',
        'modifications': 'pitched down, radio link (band limit, clip, hiss, key click, squelch), speaker stack overdrive, steel-wall flutter, slap-back delays, long tail; far variants duller and wetter'})
    with open(SOUNDS, encoding='utf-8') as fh:
        data = json.load(fh)
    data['sounds'].update(out)
    with open(SOUNDS, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=1)
    for k in sorted(out):
        if not k.endswith('_far'):
            p = os.path.join(GAME, out[k]['files'][0])
            with wave.open(p) as w:
                print('%-20s %.2f s' % (k, w.getnframes() / w.getframerate()))


if __name__ == '__main__':
    main()
