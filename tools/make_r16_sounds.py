"""r16 sounds made from code: the hum and crackle of failing light fittings in Malasugue Mall.

    python -I tools/make_r16_sounds.py

Writes game/assets/audio/r16/lamp_buzz.wav (mono 22.05 kHz, a 4 s seamless loop): a ballast's 120 Hz hum with its
harmonics, a little hiss, and irregular crackles (the arcing of a tube that will not strike). Adds the "lamp_buzz" id
to game/data/sounds.json (Lighting plays it at the faulty fittings nearest the listener, in time with their flicker).
"""
import json, os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'audio', 'r16')
SR = 22050


def lamp_buzz(seconds=4.0):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    rng = np.random.default_rng(16)
    # whole cycles of every partial in the loop's length, so the loop point is seamless
    hum = np.zeros(n)
    for k, a in [(1, 0.5), (2, 0.32), (3, 0.22), (4, 0.12), (6, 0.08), (9, 0.05)]:
        hum += a * np.sin(2 * np.pi * 120.0 * k * t + k * 0.7)
    # a ballast's rasp: the hum clipped a little
    hum = np.tanh(hum * 1.8) * 0.28
    hiss = np.convolve(rng.standard_normal(n), np.ones(6) / 6, mode='same') * 0.02
    crack = np.zeros(n)
    for _ in range(26):
        at = rng.integers(0, n - 2000)
        ln = rng.integers(60, 900)
        burst = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln * 0.25)) * rng.uniform(0.25, 0.7)
        crack[at:at + ln] += burst
    y = hum + hiss + crack
    # the crackles fade in and out of the loop so its ends join
    edge = 400
    y[:edge] *= np.linspace(0.6, 1.0, edge)
    y[-edge:] *= np.linspace(1.0, 0.6, edge)
    return np.clip(y * 0.8, -1.0, 1.0)


def write(path, y):
    pcm = (y * 32000.0).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write(os.path.join(OUT, 'lamp_buzz.wav'), lamp_buzz())
    sp = os.path.join(ROOT, 'game', 'data', 'sounds.json')
    raw = open(sp, 'rb').read()
    doc = json.loads(raw.decode('utf-8'))
    doc['sounds']['lamp_buzz'] = {'files': ['assets/audio/r16/lamp_buzz.wav'], 'db': -14.0, 'dist': 9.0, 'pitch': 0.0, 'prio': 3, 'unit': 2.5, 'loop': True}
    out = json.dumps(doc, indent=1, ensure_ascii=False).encode('utf-8')
    if b'\r\n' in raw:
        out = out.replace(b'\n', b'\r\n')
    open(sp, 'wb').write(out)
    print('wrote', OUT)
