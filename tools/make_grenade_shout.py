"""'FIRE IN THE HOLE!' for grenade throws (r22): the line shouted by the same four Windows text-to-speech voices the bot
radio uses (tools/make_bot_radio.py: m1/m2 = David, f1/f2 = Zira), two takes each, then baked into a harsh handheld-radio
sound with numpy: band-passed, driven hard into clipping (shouting into a radio), a little sample-rate / bit-depth
grit, a static hiss bed with crackle pops under the voice, a squelch burst + click in front and a squelch tail behind.

    python -I tools/make_grenade_shout.py            # writes game/assets/audio/botradio/fire_hole_<voice>_<k>.wav,
                                                     # updates data/sounds.json, work/r22/shout/{contact_sheet.png,clips.md}

Ids: fire_hole_<voice>_<k> (voice m1, m2, f1, f2; k the take). They deliberately do not start with botr_ (make_bot_radio.py
deletes those). The thrower's voice is picked in src/weapons/grenades.gd _release(); the sound is heard from far
(dist 38 m) because the sound is not a radio transmission: it is a plain voice in the world that happens to sound like
one. Only the ids named fire_hole_* in data/sounds.json are touched.
"""
import json
import os
import subprocess
import sys
import tempfile
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_bot_radio as mbr   # noqa: E402  (same voices, SSML pipeline and wav helpers)

ROOT = mbr.ROOT
OUT = mbr.OUT
SOUNDS = mbr.SOUNDS
SHEET_DIR = os.path.join(ROOT, "work", "r22", "shout")
RATE = 22050
PREFIX = "fire_hole_"
TEXT = "Fire in the hole!"

# Entry shape of the botr_ sounds, but heard from far: a shout, not a whisper on the team net.
SOUND_DEF = {"db": 3.0, "dist": 38.0, "pitch": 0.02, "prio": 8, "unit": 6.0}

# take -> (pitch, rate) offsets in percent on top of the voice's own, and the SSML body (P and R are filled in).
TAKES = [
    ("urgent", 45.0, 32.0,
     '<prosody pitch="{P}" rate="{R}" volume="x-loud">%s</prosody>' % TEXT),
    ("stretched", 38.0, 30.0,
     '<prosody pitch="{P}" rate="{R}" volume="x-loud">Fire</prosody><break time="25ms"/>'
     '<prosody pitch="{P}" rate="{R}" volume="x-loud">in the </prosody>'
     '<prosody pitch="{P2}" rate="{R2}" volume="x-loud">hole!</prosody>'),
]


def combine(base: str, extra: float) -> str:
    """SSML percent strings multiply: the voice's own offset ('-14%') and the shout's offset (+45.0)."""
    b = float(base.strip("%"))
    return "%+.0f%%" % (((1.0 + b / 100.0) * (1.0 + extra / 100.0) - 1.0) * 100.0)


def ssml(vid: str, take: int) -> str:
    _name, ex_p, ex_r, body = TAKES[take]
    _voice, vp, vr = mbr.VOICES[vid]
    body = body.format(P=combine(vp, ex_p), R=combine(vr, ex_r), P2=combine(vp, ex_p + 12.0), R2=combine(vr, ex_r - 38.0))
    return ('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">%s</speak>' % body)


# ------------------------------------------------------------------ DSP

def bandpass(x, rate, lo, hi, order=3):
    """Zero-phase Butterworth-shaped band-pass by FFT (no scipy needed)."""
    n = x.size
    size = 1 << int(np.ceil(np.log2(n * 2 + 8)))
    spec = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1.0 / rate)
    f[0] = 1e-3
    h = 1.0 / np.sqrt(1.0 + (lo / f) ** (2 * order)) / np.sqrt(1.0 + (f / hi) ** (2 * order))
    return np.fft.irfft(spec * h, size)[:n].astype(np.float32)


def smooth(x, n):
    n = max(int(n), 1)
    return np.convolve(x, np.ones(n, dtype=np.float32) / n, mode="same")


def trim(x, rate, keep=0.0):
    env = smooth(np.abs(x), rate * 0.01)
    on = np.where(env > 0.05 * max(float(env.max()), 1e-6))[0]
    if on.size == 0:
        return x
    return x[max(on[0] - int(rate * keep), 0):min(on[-1] + int(rate * keep), x.size)]


def radio_voice(x, rate, rng):
    """Shouted speech -> overdriven, boxy radio voice (peak about 0.78, very dense)."""
    x = trim(x, rate, 0.01)
    x = bandpass(x, rate, 330.0, 3400.0, 2)
    # AGC like a radio's compander: quiet syllables are pulled up so the whole line is loud.
    env = smooth(np.abs(x), rate * 0.03) + 0.04 * float(np.abs(x).max())
    x = x / env
    x = x / float(np.abs(x).max())
    # Drive: soft knee then hard clip, with a little asymmetry (even harmonics) for the buzzy edge.
    y = np.tanh(x * 7.0)
    y = y + 0.18 * y * np.abs(y)
    y = np.clip(y * 1.25, -0.72, 0.72)
    y = bandpass(y, rate, 350.0, 3200.0, 3)          # the speaker/mic box takes the clip harmonics away again
    y = y / float(np.abs(y).max()) * 0.8
    # Grit: sample-and-hold every other sample (aliasing) and a 7-bit quantiser.
    y = np.repeat(y[::2], 2)[:y.size]
    y = np.round(y * 64.0) / 64.0
    # Dropouts: a couple of 12-20 ms dips where the signal breaks up into static.
    for _ in range(2):
        a = int(rng.uniform(0.08, 0.9) * y.size)
        n = int(rate * rng.uniform(0.012, 0.02))
        w = np.hanning(n)
        y[a:a + n] *= 1.0 - 0.7 * w[:y.size - a]
    return y.astype(np.float32)


def noise_burst(n, rate, rng, lo, hi, shape):
    z = bandpass(rng.standard_normal(n).astype(np.float32), rate, lo, hi, 2)
    z = z / float(np.abs(z).max())
    t = np.arange(n, dtype=np.float32) / rate
    return z * shape(t)


def click(rate, rng, amp):
    """A 'tck' of the push-to-talk key: a few samples of bipolar spike through a 1-4 kHz band."""
    n = int(rate * 0.012)
    k = np.zeros(n, dtype=np.float32)
    k[0], k[1], k[2], k[4] = 1.0, -0.9, 0.55, -0.3
    k = bandpass(k, rate, 900.0, 4500.0, 2)
    k = k / float(np.abs(k).max()) * amp
    return k * np.exp(-np.arange(n) / (rate * 0.003))


def build_clip(raw, rate, seed):
    rng = np.random.default_rng(seed)
    voice = radio_voice(raw, rate, rng)
    lead = int(rate * 0.115)       # squelch burst + click + a breath of static before the word
    tail = int(rate * 0.26)        # the closing squelch
    n = lead + voice.size + tail
    out = np.zeros(n, dtype=np.float32)
    out[lead:lead + voice.size] += voice

    # Hiss bed: the whole clip, a bit wavering, louder around the squelches than under the voice.
    hiss = bandpass(rng.standard_normal(n).astype(np.float32), rate, 550.0, 5200.0, 2)
    hiss = hiss / float(hiss.std())
    wob = 1.0 + 0.35 * smooth(rng.standard_normal(n).astype(np.float32), rate * 0.02) / 0.1
    wob = np.clip(wob, 0.5, 1.6)
    gate = np.full(n, 0.05, dtype=np.float32)        # under the voice
    gate[:lead] = 0.07
    gate[lead + voice.size:] = 0.09
    out += hiss * wob * smooth(gate, rate * 0.01)

    # Crackle pops: a Poisson spray of short decaying spits, thicker in the tails.
    rate_hz = np.full(n, 26.0, dtype=np.float32)
    rate_hz[:lead] = 40.0
    rate_hz[lead + voice.size:] = 45.0
    pops = (rng.random(n) < rate_hz / rate).astype(np.float32)
    pops *= np.minimum(rng.exponential(0.22, n), 0.7).astype(np.float32) * rng.choice([-1.0, 1.0], n).astype(np.float32)
    kern = np.exp(-np.arange(int(rate * 0.008)) / (rate * 0.0012)).astype(np.float32) * \
        rng.standard_normal(int(rate * 0.008)).astype(np.float32)
    out += np.convolve(pops, kern, mode="same") * 1.6

    # Squelch in: key click, then a 70 ms burst of noise that falls away as the carrier locks.
    c = click(rate, rng, 0.95)
    out[:c.size] += c
    bn = int(rate * 0.075)
    out[int(rate * 0.004):int(rate * 0.004) + bn] += noise_burst(bn, rate, rng, 600.0, 4600.0,
        lambda t: 0.9 * np.minimum(t / 0.004, 1.0) * np.exp(-t / 0.04))
    # Squelch out: the voice ends, the noise floor jumps up for ~150 ms and falls away, and the key lets go ('tck').
    s0 = lead + voice.size - int(rate * 0.01)
    tn = int(rate * 0.2)
    out[s0:s0 + tn] += noise_burst(tn, rate, rng, 500.0, 4300.0,
        lambda t: 0.8 * np.minimum(t / 0.006, 1.0) * np.exp(-t / 0.07))
    c2 = click(rate, rng, 0.8)
    k0 = s0 + int(rate * 0.155)
    out[k0:k0 + c2.size] += c2[:max(out.size - k0, 0)][:c2.size]

    # Final limiter and level: peak -1 dBFS.
    out = np.tanh(out * 1.25) / np.tanh(1.25)
    out = out / float(np.abs(out).max()) * (10.0 ** (-1.0 / 20.0))
    fade = int(rate * 0.004)
    out[-fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)
    return out.astype(np.float32)


# ------------------------------------------------------------------ speech, sounds.json, contact sheet

def synth(jobs, tmp):
    jp = os.path.join(tmp, "jobs.json")
    with open(jp, "w", encoding="utf-8") as f:
        json.dump(jobs, f)
    ps = os.path.join(tmp, "speak.ps1")
    with open(ps, "w", encoding="utf-8") as f:
        f.write(mbr.PS.format(jobs=jp))
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps], check=True)


def update_sounds(ids):
    with open(SOUNDS, "rb") as f:
        raw = f.read().decode("utf-8")
    crlf = "\r\n" in raw
    final_nl = raw.endswith("\n")
    doc = json.loads(raw)
    snd = doc["sounds"]
    for k in [k for k in snd if k.startswith(PREFIX) and k not in ids]:
        del snd[k]
    for sid, name in ids.items():
        e = {"files": ["assets/audio/botradio/" + name]}
        e.update(SOUND_DEF)
        snd[sid] = e
    out = json.dumps(doc, indent=1, ensure_ascii=False)
    if crlf:
        out = out.replace("\n", "\r\n")
    if final_nl:
        out += "\r\n" if crlf else "\n"
    with open(SOUNDS, "wb") as f:
        f.write(out.encode("utf-8"))


def contact_sheet(clips, path):
    """Waveform + spectrogram (0-8 kHz) of every clip, 300 px per second, on one image."""
    from PIL import Image, ImageDraw
    px_s, w, wave_h, spec_h, pad = 300, 540, 56, 190, 20
    cols = 2
    rows = (len(clips) + cols - 1) // cols
    cell_h = pad + wave_h + spec_h + 10
    img = Image.new("RGB", (cols * (w + 12) + 12, rows * cell_h + 8), (14, 14, 18))
    d = ImageDraw.Draw(img)
    stops = np.array([[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66], [245, 125, 21], [250, 193, 39], [252, 255, 164]],
                     dtype=np.float32)
    nfft, hop = 512, 64
    win = np.hanning(nfft).astype(np.float32)
    for i, (label, x) in enumerate(clips):
        cx = 12 + (i % cols) * (w + 12)
        cy = 4 + (i // cols) * cell_h
        d.text((cx, cy + 4), "%s   %.2f s   peak %.1f dBFS" % (label, x.size / RATE, 20 * np.log10(float(np.abs(x).max()))), fill=(230, 230, 230))
        cy += pad
        wv = Image.new("RGB", (w, wave_h), (24, 24, 30))
        wd = ImageDraw.Draw(wv)
        for px in range(min(w, int(x.size / RATE * px_s))):
            seg = x[int(px / px_s * RATE):int((px + 1) / px_s * RATE) + 1]
            wd.line([(px, wave_h / 2 - seg.max() * wave_h / 2), (px, wave_h / 2 - seg.min() * wave_h / 2)], fill=(120, 200, 255))
        img.paste(wv, (cx, cy))
        frames = 1 + (x.size - nfft) // hop
        sp = np.zeros((nfft // 2 + 1, frames), dtype=np.float32)
        for fi in range(frames):
            sp[:, fi] = np.abs(np.fft.rfft(x[fi * hop:fi * hop + nfft] * win))
        db = 20 * np.log10(sp + 1e-6)
        db = np.clip((db - (db.max() - 80.0)) / 80.0, 0.0, 1.0)
        top = int(8000 / (RATE / 2) * (nfft // 2))
        db = db[:top][::-1]                                   # 0-8 kHz, low at the bottom
        sheet = np.zeros((spec_h, w, 3), dtype=np.uint8)
        for yy in range(spec_h):
            row = db[min(int(yy / spec_h * db.shape[0]), db.shape[0] - 1)]
            for xx in range(w):
                fi = min(int(xx / px_s * RATE / hop), frames - 1)
                if xx / px_s * RATE >= x.size:
                    break
                v = row[fi] * (len(stops) - 1)
                a = min(int(v), len(stops) - 2)
                sheet[yy, xx] = (stops[a] + (stops[a + 1] - stops[a]) * (v - a)).astype(np.uint8)
        img.paste(Image.fromarray(sheet), (cx, cy + wave_h + 2))
    img.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(SHEET_DIR, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="fire_hole_")
    jobs = []
    for vid, (voice, _p, _r) in mbr.VOICES.items():
        for k in range(len(TAKES)):
            jobs.append({"voice": voice, "ssml": ssml(vid, k), "out": os.path.join(tmp, "%s_%d.wav" % (vid, k)), "vid": vid, "k": k})
    synth(jobs, tmp)
    ids = {}
    clips = []
    rows = []
    for j in jobs:
        x, rate = mbr.read_wav(j["out"])
        if rate != RATE:
            raise SystemExit("unexpected sample rate %d" % rate)
        y = build_clip(x, rate, zlib.crc32(("%s_%d" % (j["vid"], j["k"])).encode()))
        name = "%s%s_%d.wav" % (PREFIX, j["vid"], j["k"])
        mbr.write_wav(os.path.join(OUT, name), y, rate)
        ids[name[:-4]] = name
        clips.append((name, y))
        rms = float(np.sqrt(np.mean(y ** 2)))
        rows.append((name, TAKES[j["k"]][0], y.size / rate, 20 * np.log10(float(np.abs(y).max())), 20 * np.log10(rms)))
    update_sounds(ids)
    contact_sheet(clips, os.path.join(SHEET_DIR, "contact_sheet.png"))
    with open(os.path.join(SHEET_DIR, "clips.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# Grenade shout clips (tools/make_grenade_shout.py)\n\n"
                "Line: \"%s\". 22050 Hz mono 16-bit. Sound defs: %s\n\n| clip | take | duration s | peak dBFS | RMS dBFS |\n|---|---|---|---|---|\n"
                % (TEXT, json.dumps(SOUND_DEF)))
        for r in rows:
            f.write("| %s | %s | %.2f | %.1f | %.1f |\n" % r)
    for r in rows:
        print("%-22s %-10s %.2f s  peak %.1f dBFS  rms %.1f dBFS" % r)
    print("made %d clips; contact sheet in %s" % (len(rows), SHEET_DIR))


if __name__ == "__main__":
    sys.exit(main())
