"""r22 (0.22.0): the tester site's static text: versions, the 0.22.0 feature block, notes, the loadout screenshot.

    python -I work/r22/ai/patch_site.py

The live page fills versions, sizes and notes from /downloads/index.json; this is the fallback and the feature copy.
"""
import re
import sys
from pathlib import Path

P = Path("website/index.html")
s = P.read_text(encoding="utf-8")
nl = "\r\n" if "\r\n" in s else "\n"
s = s.replace("\r\n", "\n")


def rep(old, new, cnt=1):
    global s
    n = s.count(old)
    if n != cnt:
        sys.exit("expected %d, found %d: %s" % (cnt, n, old[:120]))
    s = s.replace(old, new)


s = s.replace('data-fill="game-version">0.21.0<', 'data-fill="game-version">0.22.0<')
rep('data-fill="apk-version">0.21.0<', 'data-fill="apk-version">0.22.0<')
rep('data-fill="launcher-version">1.3.0<', 'data-fill="launcher-version">1.4.0<')

rep("Choose the map on the Home screen; the official server plays them in turn. Pick a primary and a secondary gun; everyone starts with armour and a helmet.",
    "Choose the map on the Home screen; the official server plays them in turn. Pick a primary and a secondary gun and fit them with sights, magazines and more; everyone starts with armour and a helmet. Hosts set how well the bots play: Easy, Normal, Hard or Pro.")

feature = """<section class="band band-alt" aria-labelledby="r22-title">
  <div class="wrap mall-feature">
    <figure><a href="/assets/img/loadout.webp"><img src="/assets/img/loadout.webp" width="1600" height="900" loading="lazy" alt="Deathmatch Game Setup: a Vector with a 3x scope and an extended magazine, and a Deagle with a red dot"></a><figcaption>Actual game capture · Deathmatch Game Setup</figcaption></figure>
    <div><p class="update-label">Deathmatch update · 0.22.0</p><h2 id="r22-title">Bots that come and find you</h2>
      <p>Bots no longer camp in one spot until the round stalls, and the host now chooses how well they play.</p>
      <ul><li>Pick the bot difficulty: Easy, Normal, Hard or Pro. Pro bots fight by their gun: scoped at range with a sniper rifle, rushing you with a pistol, pushing when you reload.</li><li>When a side is down to its last few, bots sweep the whole map with their team until they find you.</li><li>Fit sights, muzzles, grips, magazines, stocks and lights to both guns in Game Setup. Each gun remembers its setup.</li><li>A thrown grenade comes with a radio-distorted &quot;Fire in the hole!&quot;, and Freight Delight has 40 more lights.</li></ul>
      <a class="text-link" href="#download">Get the update →</a>
    </div>
  </div>
</section>

<section class="band band-alt" aria-labelledby="freight-title">"""
rep('<section class="band band-alt" aria-labelledby="freight-title">', feature)
rep('<p class="update-label">New map · 0.21.0</p>', '<p class="update-label">Map · 0.21.0</p>')
rep("""<li>The lamps carry the light: floodlights, bare bulbs on wires, flickering tubes, videoke neon and shrine candles.</li>""",
    """<li>The lamps carry the light: floodlights, bare bulbs on wires, flickering tubes, videoke neon and shrine candles, with 40 more in the darkest lanes since 0.22.0.</li>""")

rep("""    <ul class="shots">
""", """    <ul class="shots">
      <li><a href="/assets/img/loadout.webp"><img src="/assets/img/loadout-thumb.webp" width="640" height="360" loading="lazy" alt="Deathmatch Game Setup with attachment pickers for the primary and secondary"></a><span>Game Setup: guns and their attachments</span></li>
""")

notes = [l.strip()[2:] for l in Path("tools/release/notes/0.22.0.md").read_text(encoding="utf-8").splitlines() if l.startswith("- ")]
esc = lambda t: t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&#x27;")
m = re.search(r'(<ul class="notes" id="notes-list">\n)(.*?)(    </ul>)', s, re.S)
if not m:
    sys.exit("notes list not found")
s = s[:m.start(2)] + "".join("      <li>%s</li>\n" % esc(n) for n in notes) + s[m.end(2):]

P.write_text(s.replace("\n", nl), encoding="utf-8", newline="")
print("site patched,", len(notes), "notes")
