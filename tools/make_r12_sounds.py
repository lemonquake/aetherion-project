"""r12 sounds, synthesised (no recordings): the forcefield hum and its crackle and crush, and the parkour moves.

    python -I tools/make_r12_sounds.py          (then bash tools/import.sh)

Writes game/assets/audio/r12/*.wav (44.1 kHz mono 16-bit) and merges their ids into game/data/sounds.json (run it
again after tools/build_audio.py, which rewrites that file). The hum carries a WAV 'smpl' loop over the whole file,
which Godot's importer picks up ("detect from WAV"), and every one of its tones repeats a whole number of times in it,
so the loop is seamless.
"""
import json, os, struct
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, 'game')
OUT = os.path.join(GAME, 'assets', 'audio', 'r12')
SOUNDS = os.path.join(GAME, 'data', 'sounds.json')
SR = 44100
rng = np.random.default_rng(1212)


def band(x, lo, hi, order=4):
    nyq = SR / 2
    if lo <= 0:
        sos = butter(order, hi / nyq, 'low', output='sos')
    elif hi >= nyq:
        sos = butter(order, lo / nyq, 'high', output='sos')
    else:
        sos = butter(order, [lo / nyq, hi / nyq], 'band', output='sos')
    return sosfilt(sos, x)


def env(n, attack, release, curve=3.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((n / SR - t) / max(release, 1e-4), 0, 1) ** curve
    return a * r


def norm(x, peak=0.89):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def write(name, x, loop=False):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    fmt = struct.pack('<HHIIHH', 1, 1, SR, SR * 2, 2, 16)
    chunks = b'fmt ' + struct.pack('<I', len(fmt)) + fmt
    chunks += b'data' + struct.pack('<I', len(pcm)) + pcm
    if loop:
        n = len(x)
        smpl = struct.pack('<9I', 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack('<6I', 0, 0, 0, n - 1, 0, 0)
        chunks += b'smpl' + struct.pack('<I', len(smpl)) + smpl
    data = b'RIFF' + struct.pack('<I', 4 + len(chunks)) + b'WAVE' + chunks
    with open(os.path.join(OUT, name + '.wav'), 'wb') as f:
        f.write(data)


def crackle(n, rate, width_ms=(0.3, 2.5), lo=1800, hi=9000):
    """Sparse electric snaps: short noise bursts at random times."""
    out = np.zeros(n)
    k = rng.poisson(rate * n / SR)
    for _ in range(k):
        i = rng.integers(0, n)
        w = int(SR * rng.uniform(*width_ms) / 1000)
        seg = rng.normal(0, 1, w) * np.exp(-np.linspace(0, 6, w)) * rng.uniform(0.3, 1.0)
        j = min(n, i + w)
        out[i:j] += seg[:j - i]
    return band(out, lo, hi, 2)


def field_hum():
    L = 6.0
    n = int(SR * L)
    t = np.arange(n) / SR
    # Mains-like hum: 60 Hz and harmonics, each a whole number of cycles in 6 s; a slow beat from 60 vs 60.1667 Hz.
    x = 0.55 * np.sin(2 * np.pi * 60 * t) + 0.35 * np.sin(2 * np.pi * 120 * t + 0.4)
    x += 0.22 * np.sin(2 * np.pi * 180 * t + 1.1) + 0.12 * np.sign(np.sin(2 * np.pi * 240 * t)) * 0.4
    x += 0.25 * np.sin(2 * np.pi * (60 + 1 / 6) * t)
    # A thin high whine (a whole number of cycles), wavering.
    x += 0.05 * np.sin(2 * np.pi * 2400 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 3))
    # Crackle, faded out at both ends so the loop point is quiet.
    c = crackle(n, 9.0)
    fade = int(0.05 * SR)
    c[:fade] *= np.linspace(0, 1, fade)
    c[-fade:] *= np.linspace(1, 0, fade)
    x = x * 0.55 + norm(c, 0.6)
    return norm(x, 0.8)


def field_zap():
    n = int(SR * 0.4)
    x = crackle(n, 120.0, (0.2, 1.6), 1200, 12000) + 0.3 * band(rng.normal(0, 1, n), 2000, 8000, 2)
    t = np.arange(n) / SR
    x += 0.4 * np.sin(2 * np.pi * 120 * t) * np.exp(-t * 9)
    return norm(x * env(n, 0.002, 0.25))


def field_crush():
    n = int(SR * 1.1)
    t = np.arange(n) / SR
    x = crackle(n, 260.0, (0.2, 3.0), 900, 12000) * np.exp(-t * 2.5)
    x += 0.8 * band(rng.normal(0, 1, n), 40, 200) * np.exp(-t * 5)          # the body hitting the wall
    x += 0.5 * np.sin(2 * np.pi * (90 - 40 * t) * t) * np.exp(-t * 3.5)    # the discharge sagging
    return norm(x * env(n, 0.003, 0.6))


def slide():
    n = int(SR * 0.85)
    t = np.arange(n) / SR
    x = band(rng.normal(0, 1, n), 300, 3500) * (0.7 + 0.3 * np.sin(2 * np.pi * 23 * t))
    x += 0.25 * band(rng.normal(0, 1, n), 60, 250)
    return norm(x * env(n, 0.03, 0.4, 2.0), 0.7)


def wall_step():
    n = int(SR * 0.18)
    t = np.arange(n) / SR
    x = 0.9 * np.sin(2 * np.pi * (110 - 200 * t) * t) * np.exp(-t * 35)
    x += 0.4 * band(rng.normal(0, 1, n), 800, 4000) * np.exp(-t * 60)
    return norm(x * env(n, 0.001, 0.1), 0.8)


def ledge_grab():
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    x = 0.8 * band(rng.normal(0, 1, n), 1200, 7000) * np.exp(-t * 70)       # palms slapping concrete
    x += 0.6 * np.sin(2 * np.pi * 160 * t) * np.exp(-t * 30)
    x += 0.3 * band(rng.normal(0, 1, n), 200, 900) * np.exp(-t * 25)
    return norm(x * env(n, 0.0005, 0.12), 0.8)


def land_roll():
    n = int(SR * 0.65)
    t = np.arange(n) / SR
    x = 0.8 * np.sin(2 * np.pi * (80 - 30 * t) * t) * np.exp(-t * 14)       # the shoulder going down
    x += 0.5 * band(rng.normal(0, 1, n), 400, 3000) * np.exp(-((t - 0.25) / 0.15) ** 2)   # cloth over the ground
    x += 0.3 * band(rng.normal(0, 1, n), 100, 600) * np.exp(-((t - 0.45) / 0.08) ** 2)    # feet back under
    return norm(x * env(n, 0.002, 0.25), 0.75)


SPECS = {
    # id: (generator, loop, db, dist, unit, prio)
    # (2026-10-30: 10 dB down and heard from closer: the user found the field too distracting)
    'field_hum': (field_hum, True, -16.0, 25.0, 6.0, 4),
    'field_zap': (field_zap, False, -13.0, 20.0, 4.0, 5),
    'field_crush': (field_crush, False, 2.0, 70.0, 6.0, 7),
    'slide': (slide, False, -6.0, 25.0, 4.0, 4),
    'wall_step': (wall_step, False, -6.0, 22.0, 3.0, 4),
    'ledge_grab': (ledge_grab, False, -5.0, 22.0, 3.0, 4),
    'land_roll': (land_roll, False, -4.0, 25.0, 4.0, 5),
}


def main():
    with open(SOUNDS, 'rb') as f:
        raw = f.read()
    d = json.loads(raw)
    for sid, (gen, loop, db, dist, unit, prio) in SPECS.items():
        write(sid, gen(), loop)
        d['sounds'][sid] = {'files': ['assets/audio/r12/%s.wav' % sid], 'db': db, 'dist': dist, 'pitch': 0.0 if loop else 0.05,
                            'prio': prio, 'unit': unit}
    text = json.dumps(d, indent=1, ensure_ascii=False) + ('\n' if raw.endswith(b'\n') else '')
    if b'\r\n' in raw:
        text = text.replace('\r\n', '\n').replace('\n', '\r\n')   # keep the file's own line endings
    with open(SOUNDS, 'wb') as f:
        f.write(text.encode('utf-8'))
    print('wrote %d sounds to %s' % (len(SPECS), OUT))


if __name__ == '__main__':
    main()
