"""r14 sounds made from code: the ringing in the ears after a grenade goes off close by.

    python -I tools/make_r14_sounds.py

Writes game/assets/audio/r14/tinnitus.wav (mono 22.05 kHz): a high tone (with a fainter one just above it, beating
slowly) that swells in a fifth of a second and fades over seven, over a little hiss. Also points game/data/sounds.json
"explosion" at the user's own grenade recording only (audio/grenade_explosion1.mp3, converted in r13) and adds the
"tinnitus" id.
"""
import json, os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'audio', 'r14')
SR = 22050


def tinnitus(seconds=7.5):
    t = np.arange(int(SR * seconds)) / SR
    env = np.minimum(t / 0.18, 1.0) * np.exp(-t / 2.6)
    beat = 0.85 + 0.15 * np.sin(2 * np.pi * 2.3 * t)
    tone = np.sin(2 * np.pi * 3650.0 * t) + 0.35 * np.sin(2 * np.pi * 4120.0 * t + 0.7)
    rng = np.random.default_rng(14)
    hiss = rng.standard_normal(t.size)
    # A soft high hiss: differences of white noise (more top end), quiet and fading faster than the tone.
    hiss = np.diff(hiss, prepend=0.0) * 0.06 * np.exp(-t / 1.4)
    y = (tone * 0.32 * beat + hiss) * env
    y[-2000:] *= np.linspace(1.0, 0.0, 2000)
    return np.clip(y, -1.0, 1.0)


def write(path, y):
    pcm = (y * 32000.0).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write(os.path.join(OUT, 'tinnitus.wav'), tinnitus())
    sp = os.path.join(ROOT, 'game', 'data', 'sounds.json')
    raw = open(sp, 'rb').read()
    doc = json.loads(raw.decode('utf-8'))
    d = doc['sounds']
    d['explosion']['files'] = ['assets/audio/r13/grenade_explosion1.ogg']
    d['explosion']['pitch'] = 0.06
    d['tinnitus'] = {'files': ['assets/audio/r14/tinnitus.wav'], 'db': -3.0, 'dist': 1.0, 'pitch': 0.0, 'prio': 9, 'unit': 1.0}
    out = json.dumps(doc, indent=1, ensure_ascii=False).encode('utf-8')
    if b'\r\n' in raw:
        out = out.replace(b'\n', b'\r\n')
    open(sp, 'wb').write(out)
    print('wrote', OUT)
