"""r4: README sections for the new menu, lobby, outfits, stats server, loudspeakers, destruction and tests."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

f = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'README.md')
patch(f, '''The main menu offers **Play** (Host a game, Join a game, Practice with bots), **Settings** and **Quit**. In the lobby,
join a team, mark **Ready**, and the host presses **Start Match**. A match holds up to 50 players; by default the host
adds 20 bots (Game Setup in the lobby changes it).
''', '''### Main menu

The menu opens on key art of the settlement at night under the artificial sun. Along the top: **Home**, **Play**,
**Locker**, **Profile**, **Leaderboard**, your level and XP (tap it for your profile) and **Settings**.

- **Home**: **PLAY NOW** starts a practice match at once (you and 19 bots in 5 squads of 4). **Find a game** and
  **Host a game** open Play. The right side lists who is online (with a **Join** button when they are in an open
  game) and your last match.
- **Play**: **Host a game** with a name, the number of teams (2 to 7, 5 by default), squad size (Solo, Duo, Trio,
  Squad), whether bots fill empty slots (on by default) and the safe zone's speed. **Open games** lists games on your
  Wi-Fi/LAN (hosts announce themselves on the network) and on the stats server, each with a **Join** button; or join
  by address.
- **Locker**: dress your character: hair, headwear, face, jacket, inner shirt, hands, elbow pads, knee pads, pants,
  footwear and backpack (at least four models in each, five in most), each with colourways, and four skin tones. A
  3D preview turns on its own (drag to turn); **Random** and **Reset**. Everything is saved at once and worn in
  matches; other players and bots see it.
- **Profile**: level, XP to the next level, career stats (matches, wins, top 5, kills, deaths, K/D, damage, time
  played, best place) and your recent matches. Your name is edited here.
- **Leaderboard**: everyone the stats server has seen, by level, wins or kills.

Phones get the same screens, drawn 1.5x larger, with shorter text where space is tight.

### Lobby and teams

A match has *teams x squad size* slots (5 x 4 = 20 by default, at most 7 teams of up to 4 = 28 players). Every
team is a card with its seats: players, the bots that will take empty seats, and **Tap to join** on teams you can move
to; you start in the first team with room. The host's **Game Setup** changes teams, squad size, bots and the safe zone
(everyone else sees the settings); **Outfit** opens the Locker without leaving. Others press **READY**; the host
presses **START MATCH**, and bots fill whatever the humans left open.

### Levels, XP and the stats server

Every match gives XP: 100 for playing, 60 per kill, 1 per 4 damage dealt, 1 per 3 seconds alive, and 50 to 400 for
your team's place. Levels need 500 XP at first and 150 more each level. The results screen shows what you earned and
any level reached; the profile keeps counting on your device even with no server.

The stats server keeps profiles, the leaderboard, who is online and the list of open games. It is part of the game:

```bash
# a stats server only (any PC on the network; phones and PCs on the same Wi-Fi find it by themselves)
godot --headless --path game -- --master [--master_port=27420] [--data=<folder>]
# a dedicated match server that is also the stats server
godot --headless --path game -- --server --stats --bots=19 --autostart=2 --expect_players=1
```

Players elsewhere set its address in **Settings → Online** (or `--stats_server=host:port`). The host of each match
reports it; there are no accounts (a profile is a random id made on the device), so run it for friends.
''')
patch(f, '''### Day and night
''', '''### Day and night: the loudspeakers

Horn loudspeakers stand on street poles across the settlement (one roughly every 85 m). Before every change of the
artificial sun a man's voice comes over them: an attention chime and a warning 60 seconds ahead ("The sun will ignite
in sixty seconds" / "Lights out in sixty seconds"), again at 30 seconds, then a countdown from ten, and a siren for
7 seconds as the sun ignites or starts to die. You hear it from the nearest horns (the next one down the line a
moment later, like a real PA), muffled indoors; the countdown also shows under the compass. The voice is the Windows
"David" text-to-speech voice put through a loudspeaker horn and street echoes (`tools/make_announcer.py`).

### Day and night
''')
patch(f, '''### Radio
''', '''### Damage to the world

Rounds leave holes that suit what they hit (concrete and hollow block craters with cracks, splintered wood, punched
metal, cracked glass, frayed cloth, soil) and exit holes where they come through; holes on doors and loose props move
with them. Impacts throw dust, chips, splinters, sparks, shards or blood mist; guns leave muzzle smoke and spent cases
that tinkle on the ground; a round cracking past your head darkens the edges of your view for a moment.

Furniture and crates break chunk by chunk where they are hit: a chair or table loses pieces (the real piece of the
model falls away), its legs can be shot out so it drops, and it collapses when most of it is gone. Doors and window
shutters lose panels where they are shot; rounds and eyes pass through the holes, and once the hinge side is shot
out (or most of the leaf) the door falls and the doorway stays open. Grenades knock props apart and blow panels out
of nearby doors. Everything is decided by the server and the same for every player (and for players who join late).

### Radio
''')
patch(f, '''Polish-run checks (`--autotest=r3`):''', '''r4 checks (`--autotest=r4`; `--r4_only=outfits,pa,holes,chunks,doors,blast,realism,fx_perf` runs some): outfits in a
match (variety, two draw surfaces per body), the loudspeaker schedule at forced match times (every cue heard from a
horn) and horn coverage, bullet holes and impact particles measured in captures, a table or chair losing chunks shot
by shot until it collapses, holes moving with a door that swings, a door's panels shot out until it falls and the
doorway is clear, a grenade among furniture, shell casings and muzzle smoke, suppression from a near miss, and the cost
of an impact every frame (GPU time):

```bash
godot --path game -- --host --bots=11 --autostart=1 --autotest=r4 --shots=<folder>
bash tools/online_test.sh      # stats server + host + client: presence, open game, join, results, leaderboard, XP
godot --path game -- --ui_tour=<folder> --ui_sizes=1920x1080,3840x2160      # every menu page, lobby, Locker
godot --path game -- --mobile --ui_tour=<folder> --ui_sizes=1800x810        # the phone layout
```

Polish-run checks (`--autotest=r3`):''')
patch(f, '''## Rebuilding generated content''', '''## Rebuilding the outfits, menu art, impacts and announcer

```bash
python -I tools/make_gear_textures.py                                                        # fabric texture array
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/make_gear.py   # outfits
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/render_gear.py # check renders
python -I tools/gear_contact_sheet.py                                                        # work/gear/sheet_<slot>.png
python -I tools/make_ui_textures.py                                                          # panels, buttons, card pictures
python -I tools/make_impact_textures.py                                                      # bullet-hole atlas, particle sprites
python -I tools/make_announcer.py                                                            # loudspeaker voice and siren
python -I tools/add_r4_sounds.py                                                             # spent cases
bash tools/import.sh
```

The menu backgrounds (`game/assets/ui/*_bg.jpg`) are frames of the game's own map from `tools/map_preview.tscn`,
colour-graded (see `work/lemondev/r4/HANDOFF.md`). Outfit pieces and colourways are listed in `game/data/cosmetics.json`.

## Rebuilding generated content''')
