"""Bot radio callouts: Windows text-to-speech (David, Zira) in four voices, trimmed and levelled, plus their sound
definitions. In game they play through the Radio bus (band-limited, a little grit) for teammates, and as a plain
voice in the world for anyone standing next to the bot.

    python -I tools/make_bot_radio.py            # writes game/assets/audio/botradio/*.wav, updates data/sounds.json

Ids: botr_<line>_<voice>_<k> (voice m1, m2, f1, f2; k the phrasing), one clip each, so the server picks the exact
phrasing and every client plays it and shows its words (data/bot_radio.json lists them).
"""
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "audio", "botradio")
SOUNDS = os.path.join(ROOT, "game", "data", "sounds.json")
LINES_JSON = os.path.join(ROOT, "game", "data", "bot_radio.json")

LINES = {
    "go_with": ["I'll go with you.", "Right behind you.", "Sticking with you. Let's go."],
    "this_way": ["This way.", "Follow me.", "On me. Let's move."],
    "contact": ["Contact!", "Enemy spotted!", "Eyes on one!"],
    "taking_fire": ["Taking fire!", "I'm hit!", "They're shooting at me!"],
    "reloading": ["Reloading!", "Cover me, reloading!"],
    "haze": ["Haze is coming. Move!", "Get inside the circle, now!", "We need to outrun the haze!"],
    "copy": ["Copy that.", "On my way.", "Roger. Moving."],
    "watching": ["I'll watch it.", "Eyes on it.", "I've got that angle."],
    "laser": ["Laser! Someone's pointing at us.", "Watch it, there's a laser.", "Follow that laser!"],
    "good_spot": ["Good spot here.", "Nice sniping spot. Marking it.", "This spot's safe."],
    "clear": ["Clear.", "Area clear.", "Nothing here."],
    "down": ["Man down!", "We lost one!"],
    "lost_you": ["Lost you. Going my own way.", "Can't keep up. Splitting off."],
    "kill": ["Got one!", "Enemy down!", "Scratch one."],
    "need_help": ["Need help here!", "I need backup!"],
    "inside": ["I'm holding this house.", "Taking this building.", "Inside. Watching the door."],
    "sniping": ["Setting up overwatch.", "Moving to a sniping spot."],
    "hunting": ["Going hunting.", "I'm pushing up.", "Let's find them."],
    "sneaking": ["Moving quiet.", "Flanking around.", "Going around them."],
}
# voice id -> (installed voice, SSML pitch, SSML rate)
VOICES = {
    "m1": ("Microsoft David Desktop", "+0%", "+8%"),
    "m2": ("Microsoft David Desktop", "-14%", "-2%"),
    "f1": ("Microsoft Zira Desktop", "+0%", "+6%"),
    "f2": ("Microsoft Zira Desktop", "-10%", "+14%"),
}

PS = r"""
Add-Type -AssemblyName System.Speech
$jobs = Get-Content -Raw -Encoding UTF8 '{jobs}' | ConvertFrom-Json
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
foreach ($j in $jobs) {{
  $s.SelectVoice($j.voice)
  $fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
  $s.SetOutputToWaveFile($j.out, $fmt)
  $s.SpeakSsml($j.ssml)
  $s.SetOutputToNull()
}}
"""


def ssml(text, pitch, rate):
    t = text.replace("&", "and").replace("<", "").replace(">", "")
    return ('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">'
            '<prosody pitch="%s" rate="%s">%s</prosody></speak>' % (pitch, rate, t))


def read_wav(path):
    with wave.open(path, "rb") as w:
        n = w.getnframes()
        data = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
        return data, w.getframerate()


def write_wav(path, x, rate):
    y = np.clip(x * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(y.tobytes())


def tidy(x, rate):
    """Trim silence (keeping 40 ms of air), level to -3 dBFS peak with a gentle soft clip so callouts sit forward."""
    env = np.abs(x)
    win = max(int(rate * 0.01), 1)
    env = np.convolve(env, np.ones(win) / win, mode="same")
    on = np.where(env > 0.01)[0]
    if on.size:
        a = max(on[0] - int(rate * 0.04), 0)
        b = min(on[-1] + int(rate * 0.06), x.size)
        x = x[a:b]
    peak = float(np.max(np.abs(x))) or 1.0
    x = x / peak * 0.9
    x = np.tanh(x * 1.6) / np.tanh(1.6) * 0.71
    fade = int(rate * 0.008)
    if x.size > fade * 2:
        x[:fade] *= np.linspace(0, 1, fade)
        x[-fade:] *= np.linspace(1, 0, fade)
    return x


def main():
    os.makedirs(OUT, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="botradio_")
    jobs = []
    for line, texts in LINES.items():
        for vid, (voice, pitch, rate) in VOICES.items():
            for k, text in enumerate(texts):
                jobs.append({"voice": voice, "ssml": ssml(text, pitch, rate), "out": os.path.join(tmp, "%s_%s_%d.wav" % (line, vid, k)),
                             "line": line, "vid": vid, "k": k})
    jp = os.path.join(tmp, "jobs.json")
    with open(jp, "w", encoding="utf-8") as f:
        json.dump(jobs, f)
    ps = os.path.join(tmp, "speak.ps1")
    with open(ps, "w", encoding="utf-8") as f:
        f.write(PS.format(jobs=jp))
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps], check=True)
    with open(SOUNDS, "rb") as f:
        raw = f.read().decode("utf-8")
    crlf = "\r\n" in raw
    doc = json.loads(raw)
    snd = doc["sounds"]
    for k in [k for k in snd if k.startswith("botr_")]:
        del snd[k]
    made = 0
    for j in jobs:
        x, rate = read_wav(j["out"])
        x = tidy(x, rate)
        name = "%s_%s_%d.wav" % (j["line"], j["vid"], j["k"])
        write_wav(os.path.join(OUT, name), x, rate)
        sid = "botr_%s_%s_%d" % (j["line"], j["vid"], j["k"])
        snd[sid] = {"files": ["assets/audio/botradio/" + name], "db": 0.0, "dist": 14.0, "pitch": 0.0, "prio": 7, "unit": 2.5}
        made += 1
    out = json.dumps(doc, indent=1, ensure_ascii=False)
    if crlf:
        out = out.replace("\n", "\r\n")
    with open(SOUNDS, "wb") as f:
        f.write(out.encode("utf-8"))
    with open(LINES_JSON, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"_doc": "Bot radio callouts (tools/make_bot_radio.py): line -> phrasings; sound id botr_<line>_<voice>_<index>.",
                   "voices": list(VOICES.keys()), "lines": LINES}, f, indent=1, ensure_ascii=False)
    print("made %d clips, %d sound ids" % (made, len([k for k in snd if k.startswith("botr_")])))


if __name__ == "__main__":
    sys.exit(main())
