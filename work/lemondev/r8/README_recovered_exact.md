# Aetherion Project by Aljay Leodones

A multiplayer survival battle royale set in a dense Philippine riverside settlement. Players parachute in with their
squad, search dark houses and roofed-over lanes for weapons and batteries, and listen for the others. Every match
starts at night; after five minutes an artificial sun ignites over the settlement and lights it for five minutes,
then it goes dark again, and so on. Built with Godot 4.7.

- **Status and test evidence:** [docs/CHECKLIST.md](docs/CHECKLIST.md)
- **Third-party assets and licences:** [docs/ASSET_MANIFEST.md](docs/ASSET_MANIFEST.md)
- **Performance (frame rates, how to measure, what each system costs):** [docs/PERFORMANCE.md](docs/PERFORMANCE.md)

## Requirements

- Godot **4.7.2** (standard build). On this machine: `A:\Installer\Godot_v4.7.2-stable_win64\`.
- Windows 10/11 or Linux, a Vulkan GPU (tested on an RTX 4060); Android 7+ phones (arm64), Vulkan or OpenGL ES 3.
- For rebuilding assets only: Python 3.11+ with numpy and Pillow, Blender 5.2.

The first time the project is opened (or after new assets are added), import them:

```bash
bash tools/import.sh
```

## Playing

Open `game/project.godot` in the Godot editor and press Play, or run it directly:

```bash
"/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe" --path game
```

### Main menu

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

### Game modes: Classic and Deathmatch

- **Classic** is the battle royale: parachute in from the plane, loot weapons and gear, stay ahead of the haze, and
  live through the 5-minute nights and days on Sitio Kalinaw.
- **Deathmatch** is two teams of up to 10 (bots fill empty seats) on Lawless Sub. In the lobby's **Game Setup** each
  player picks a primary and a secondary gun; everyone starts on the ground at their team's spawn with those guns,
  spare magazines, a plate carrier and a heavy-plate helmet. Nothing is bought: loot buildings and swap guns as you
  go. There is no downed state; the dead watch their living teammates (Fire or Space for the next, right-click for
  the previous) until the round ends, which is when one team has nobody standing. The haze still closes in and the
  day/night cycle still runs (a round starts at a random point in it).

```bash
godot --path game -- --host --game_mode=deathmatch --bots=19 --autostart=1     # a practice round on Lawless Sub
```

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

### Controls (rebindable in Settings)

| Action | Key | Action | Key |
|---|---|---|---|
| Move | W A S D | Jump / vault / open canopy / flare | Space |
| Sprint / walk / crouch | Shift / Ctrl / C | Use, open, take weapons and items, revive (hold) | E |
| Fire / aim | Left / right mouse | Reload | R |
| Weapons | 1 2 3, wheel, X holster | Fire mode | B |
| Flashlight on/off | F (tap) | Change battery | F (hold) |
| SmarTab (next to a box or body: shows what is inside) | Tab (hold) | SmarTab pages | Q / E while held |
| Map page | M (hold) | Quick heal | H |
| Grab, drag or carry an object (again: put it down) | T | Throw a frag grenade | G |
| Ping your position to the team (radio click) | V | Push to talk | Caps Lock |
| Text chat | Y | Menu | Esc |
| Climb a ladder | walk into it (W up, S down) | Let go of a ladder | Space |

Jump right in front of a low wall, a crate, a table or a window opening and you vault over or through it instead
(the gun drops out of sight while you do and comes back up after). The lite minimap (top left) shows the streets
around you, the roofed lanes (dark) and the courtyards, and the safe area; a teammate appears on it only when they
ping, as a green dot that blinks for 5 seconds. Enemies never show on it. Under the minimap a compass shows the
bearing you face in degrees (0 = north, clockwise; N, NE, E... and a number every 15 degrees), so you can call
"north one-twenty" on the radio; teammates' pings show on it as green marks.

Walk into a ladder (on house fronts, up to flat roof decks) facing the wall and you climb it: W climbs, S goes down
(or W while facing away from the wall or looking down), Space lets go. At the top, keep walking to step on to the
roof; walk off a roof edge at a ladder and it catches you.

### Day and night: the loudspeakers

Horn loudspeakers stand on street poles across the settlement (one roughly every 85 m). Before every change of the
artificial sun a man's voice comes over them: an attention chime and a warning 60 seconds ahead ("The sun will ignite
in sixty seconds" / "Lights out in sixty seconds"), again at 30 seconds, then a countdown from ten, and a siren for
7 seconds as the sun ignites or starts to die. You hear it from the nearest horns (the next one down the line a
moment later, like a real PA), muffled indoors; the countdown also shows under the compass. The voice is the Windows
"David" text-to-speech voice put through a loudspeaker horn and street echoes (`tools/make_announcer.py`).

### Day and night

Matches start at night. At 5:00 the artificial sun ignites (a warning toast and a distant siren come 30 and 5
seconds before) and the whole settlement is in daylight until 10:00, when it goes dark again; the cycle repeats every
ten minutes, the same moment for every player (it follows the server's clock). By day you see and are seen far across
open ground (bots too), but rooms and the roofed lanes stay dark: the lane roofs keep the sun out except through
their gaps, so you still need your flashlight in there.

### Damage to the world

Rounds leave holes that suit what they hit (concrete and hollow block craters with cracks, splintered wood, punched
metal, cracked glass, frayed cloth, soil) and exit holes where they come through; holes on doors and loose props move
with them. Impacts throw dust, chips, splinters, sparks, shards or blood mist; guns leave muzzle smoke and spent cases
that tinkle on the ground; a round cracking past your head darkens the edges of your view for a moment.

Furniture and crates break chunk by chunk where they are hit: a chair or table loses pieces (the real piece of the
model falls away), its legs can be shot out so it drops, and it collapses when most of it is gone. Doors and window
shutters lose panels where they are shot; rounds and eyes pass through the holes, and once the hinge side is shot
out (or most of the leaf) the door falls and the doorway stays open. Grenades knock props apart and blow panels out
of nearby doors. Everything is decided by the server and the same for every player (and for players who join late).

People bleed where they are shot. A round through a body throws droplets on along its path and a few back toward the
shooter; each flies a short arc and lands as a wet red mark, round where it fell straight and stretched with a tail
where it hit at a glancing angle. A wall right behind takes a burst with runs dripping down it, the ground where they
stood takes drops, the wounded leave a drip trail for a while, the downed smear the ground as they crawl, and a body
lies in a pool that spreads for half a minute. Shooting a body again sprays it again. Blood on doors and loose props
moves with them. All of it is drawn locally by each player (cosmetic, not sent over the network).

Every material has its own bullet-impact sound (concrete, wood, sheet metal, steel, dirt and sand, water, glass,
cloth, plastic, foliage, tile), as do flesh, heads, helmets and vests, ricochets, near misses, brass and shotgun shells
landing and bodies falling. Reloads sound step by step in time with the hands: the magazine out, a fresh one from the
pouch, the magazine seated, the charging handle or slide, the bolt lifted, drawn, run home and turned down, each shell
into the tube, the cylinder opened, loaded and closed, the barrels broken open and shut. You hear other players'
reloads the same way.

### Radio

Push to talk keys your handheld radio: a click when you key up, your speech on your teammates' radios (narrow-band,
with a hiss), the squelch tail when you let go. Radios can be overheard: anyone within about 12 m of one of your
teammates hears what you say coming out of that radio, and anyone within about 9 m of you hears your voice. Farther
away nobody gets anything. Ranges are in `game/data/rules.json` (`radio`). Third-party voice apps cannot make these
sounds in the game.

### The map

Sitio Kalinaw is built from the map seed on every machine. Besides the river, the estero, the bridges, the market,
the church and the port, the dense districts are cut by narrow lanes, and many of those are roofed over from house to
house (*lagusan*): long dark tunnels lined with doors and windows, a bare bulb every several metres (some dead, some
flickering), a candle at a little shrine, rags and wires hanging from patched sheets, and a gap here and there where
the sky (or the sun) gets in. Some blocks are left open as *loobans*: courtyards with a hand pump, washing, a
basketball ring, a kiosk whose roof you can reach from a crate stack, hip-high walls and sandbags to vault and fight
from. Junk barricades cut some lanes. Many hollow-block houses have flat roof decks (water tank, washing, plants,
something stashed) with a ladder up the front; about one house in six is three storeys; a third of the
ground-floor windows have no glass and are sized to vault through, and some neighbours have knocked holes through
their side walls into the next house. Walls carry graffiti, stencilled "BAWAL" signs, posters, census numbers, rust,
damp and mould, and in the roofed lanes the frightened writing (handprints, eyes, X marks, "HUWAG KANG LALABAS SA
GABI"). Open doors swing aside when you walk or run into them and latch shut with a click when
pushed back into the frame.

### Lawless Sub (Deathmatch)

A walled Philippine subdivision nobody polices any more, at the edge of a city, built from
`game/data/maps/lawless_sub.json` (440 m square play area). A four-lane avenue with a median and a central
intersection (zebra crossings on every arm, traffic lights, a wreck pile of police cars and a jeepney) splits it; a
walled canal and an angular basin cut the west side, a shallow estero the south (wade it, or take the road bridge).
West Team spawns in the office tower's parking plaza, East Team in the plastics factory's loading yard, about 420 m
apart. Some 230 two-storey houses, bungalows and shophouses have real interiors (sala, dining, kitchen, toilet, stair
hall downstairs; bedrooms, bathroom and hall upstairs), furniture, loot, doors on two sides and vault-sized ground-floor
windows. The big buildings: Lawless Tower (four floors of offices round a stair core, roof ladder), the Canal Flats,
the clubhouse with its empty pool and covered court, the chapel, Lawless Mart (aisles, chillers, stock room) and its
shop strip, the gas station, the plastics factory (machine lines, offices under a mezzanine), the warehouse, the tanks
and the container yard. Parked cars and burnt wrecks fill the lots and streets. Bots climb out of the canals by its
ladders.

### Loot, weapons and attachments

Loot lies where people would leave it: loose on floors (guns, ammunition, attachments, medicine, batteries,
armour, packs), in drawers, cabinets and wardrobes, and in **loot boxes** you can see: balikbayan boxes, storage
bins, footlockers and rifle cases in houses, iceboxes in kitchens, at the market and on the fish pier, toolboxes and
ammo cans in workshops, first aid cases in clinics and comfort rooms, ammo cans and rifle cases at police posts and
in the container yard. Use (E) on a box opens its contents on the SmarTab; its lid stays open for everyone, so an
opened box tells you somebody has been there. A gun found loose usually has some of its own ammunition beside it.

Twelve guns: 9 mm and .45 pistols, .357 revolver, pump and double-barrel shotguns, the *sumpak* (an improvised
12-gauge pipe gun), 9 mm SMG and machine pistol, 5.56 and 7.62 rifles, a .308 marksman rifle and a .308 bolt rifle.
Each takes one attachment per mount, as listed in `game/data/weapons.json`:

| Mount | Attachments |
|---|---|
| Sight | red dot, holographic (1x, reticle in the sight window); 2x, 3x, 4x, 6x, 8x scopes (scope view while aiming) |
| Muzzle | pistol/SMG suppressor, rifle suppressor (much quieter, no flash), compensator (less recoil, louder), flash hider, shotgun choke (tighter pattern) |
| Grip | vertical (less climb), angled (faster aiming), half grip (faster recovery), laser sight (tighter hip fire; its red dot is visible to everyone) |
| Magazine | extended, quickdraw, extended quickdraw (pistol/SMG and rifle), extended marksman |
| Stock | tactical stock (machine pistol), cheek pad (marksman and bolt rifle), bullet loops (shotguns, bolt rifle) |
| Light | weapon light |

Picking up an attachment fits it to the gun that gains most from it (what it replaces goes in the bag); picking up a
gun fits the compatible attachments you carry. The SmarTab **Weapons** page lists each gun's mounts with **Fit** and
**Off** buttons. Other players see your attachments, and hear and see a suppressed shot as such.

Bots loot the same way: a gun first, then ammunition for the guns they carry, attachments that improve them, armour,
a bigger bag, medicine and batteries; they walk to loose items they see and search loot boxes, leave ammunition they
cannot fire, and pick the gun that suits the distance.

### Phones, PCs and cross-play

Phones and PCs run the same game and play in the same matches: same rules, same netcode, same map (every machine
builds it from the match seed). The lobby shows each player's platform ("PC" or "Mobile"). Players must run the
same version: a client from another version is turned away, and a client whose map comes out different is warned
and logged on the server (`[map]` fingerprint).

On a phone the game uses the Mobile renderer (Vulkan; OpenGL where Vulkan is missing), the **Mobile** quality
preset (70 % render scale, no shadow maps, AO or fog volumes, shorter lamp and draw distances, 60 fps cap), a UI
drawn 1.5× larger, and on-screen controls: a floating move stick on the left (push past the ring to sprint), drag on
the right to look (also while holding Fire), and buttons for Fire (two), Aim, Jump, Crouch, Reload, Use, Light (hold
to change batteries), Phone (SmarTab), Heal, Weapon, Radio and Menu. Practice and hosted matches add 20 bots by default on
phones and PCs alike (up to 28 players in a match: 7 teams of 4). Try the phone profile on a PC with `--mobile`
(and `--rendering-method mobile` for the phone renderer).

### Local multiplayer

Every process is a full game; one of them hosts (or runs as a dedicated server):

```bash
# dedicated server, 6 bots, starts when 2 humans are connected
godot --headless --path game -- --server --port=27415 --bots=6 --autostart=2 --expect_players=2
# each player
godot --path game -- --join=127.0.0.1 --port=27415 --name=Alpha
```

Launch options (after `--`): `--host`, `--server` (dedicated), `--join=<address>`, `--port=<n>`, `--name=<player>`,
`--mode=solo|duo|squad`, `--bots=<n>`, `--seed=<map seed>`, `--match_seed=<n>`, `--zone_speed=<multiplier>`,
`--autostart=<seconds>`, `--expect_players=<n>`, `--rematch`, `--matchlog` (match events on stdout, always on for a
dedicated server).

## Testing

```bash
bash tools/check.sh       # compile every script
bash tools/import.sh      # import new assets
bash tools/net_test.sh    # dedicated server + two real clients checking each other (results in work/screens/net)
```

Scripted play-through on a host (deploys, enters a dark house, uses the flashlight and SmarTab, fires, drains and
swaps a battery, loots a corpse, photographs each step):

```bash
godot --path game -- --host --bots=11 --autostart=1 --matchlog --autotest=tour --shots=<folder>
```

Loot play-through (model census, loot boxes and floor loot across the map, items resting on surfaces, each
attachment's effect, pickups that fit attachments, a loot box opening, sights on the bullet line, scope views, and
photographs of every droppable item laid out):

```bash
godot --path game -- --host --bots=11 --autostart=1 --autotest=loot --shots=<folder>
```

r7 Deathmatch checks (`--autotest=dm`, `--dm_only=map,kit,body,arms,haze`): the round is on Lawless Sub with
10 v 10 standing, you spawn at your team's spawn with both guns, the plate carrier and the heavy helmet, nothing of your
own body shows when you look straight down, the first-person arms stay clear of the camera through an empty reload,
and the haze runs on the Deathmatch schedule. With `--autotest=perf` and `--game_mode=deathmatch` the perf run measures
the spawn, the intersection, a house street, the mart lot, the factory yard, the canal row, a room by flashlight and two
spots by day:

```bash
godot --path game -- --host --game_mode=deathmatch --bots=19 --autostart=1 --autotest=dm --shots=<folder>
```

Z-fighting (two surfaces in the same place flickering through each other) is checked over the map's geometry: dump
every drawn face, then list the pairs that face the same way, lie within 1.5 cm of each other and overlap:

```bash
godot --headless --path game res://tools/map_preview.tscn -- [--map=lawless_sub] --dumpfaces=<file>
python -I tools/zfight_faces.py <file> --verbose
```

r6 checks (`--autotest=r6`; `--r6_only=sounds,bob,cues,blood`, `--r6_fast=1` skips the parachute): every sound the
game asks for exists and loads, each impact material has several takes, the walking camera's sway, empty reloads of a
rifle, pistol, pump gun and bolt rifle (every step's sound in order), a bot's reload heard beside the player, and blood:
three rifle hits on a bot in front of a light wall (marks, blood-red pixels on the wall and at its feet), a body's pool
spreading on screen, rounds into the body, and the spray's cost per hit:

```bash
godot --path game -- --host --bots=11 --autostart=1 --autotest=r6 --shots=<folder>
```

r4 checks (`--autotest=r4`; `--r4_only=outfits,pa,holes,chunks,doors,blast,realism,fx_perf` runs some): outfits in a
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

Polish-run checks (`--autotest=r3`): map census (roofed lanes, three-storey houses, roof decks and ladders, vault
cover, decals), the day/night schedule, the same courtyard view at night and at noon, roofed lanes dark at noon and
lit by the flashlight, climbing a ladder to a roof and back down, vaulting on to crates, the compass bearing, and the
radio's overhearing rules (`--r3_only=day,ladder,...` runs some of them):

```bash
godot --path game -- --host --bots=11 --autostart=1 --autotest=r3 --shots=<folder>
```

Fix-list play-through (guns on house floors and in balikbayan boxes, readable loot in the dark, climbing 24 real stair
flights, Tab beside a box, T versus E, pings on the minimap, doors opening forward / pushed / latching, vaulting
through windows, trash that blocks nothing, every gun firing and reloading, shared calibres, a frag grenade, every
work/sounds file in use). `--fixes_only=stairs,vault,...` runs just those checks while working on one:

```bash
godot --path game -- --host --bots=3 --autostart=1 --autotest=fixes --autotest_timeout=950 --shots=<folder>
```

The bot-match log prints a `[lootstats]` line every 15 s: bots armed, armed with ammunition for their gun,
attachments fitted, and rounds of ammunition carried that fit no gun they hold.

On Windows, `powershell -ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds 600 -Log <file> -ArgLine "..."`
runs any of these with a time limit that also stops the engine process (bash `timeout` stops only the console
wrapper, and the server keeps its port).

Frame-rate benchmark through a real deploy and six ground spots (vsync off; add `--attrib` to switch rendering
features off one at a time; see [docs/PERFORMANCE.md](docs/PERFORMANCE.md)):

```bash
godot --path game -- --host --bots=11 --autostart=1 --autotest=perf --shots=<folder>
```

Bot-only match on a dedicated server with per-15 s status, server tick timing and bot diagnostics:

```bash
godot --headless --path game -- --server --bots=40 --autostart=1 --expect_players=0 --zone_speed=2
```

`--testcheats` on a server lets clients request teleports and items (used only by the network test).
`--netdebug` prints large client prediction corrections and deep server input queues.
`--bottrace=<name part>|first` prints one bot's plan every second.
`--bot_lod_off` runs every bot every tick (normally bots far from every human think and move every 2nd or 4th tick).
`--mobile` uses the phone settings profile and touch controls on a PC (its settings are not saved).
`--shot=<png>` saves the screen after 3 s (`--shot_after=<s>`) and quits: menus and lobby at any window size.

Map checks on the preview tool: `--mmstats` (instanced models, loot containers and props by type), `--doorcheck`
(swings every outer door and lists what jams it), `--perf=<view>` (frame cost with features toggled):

```bash
godot --path game res://tools/map_preview.tscn -- --doorcheck
```

## Rebuilding the loot models and sounds

The attachments, small items, ammunition boxes, loot boxes and the double-barrel, sumpak and marksman rifle are
modelled in code (no downloads):

```bash
python -I tools/make_loot_textures.py                                            # labels and surfaces
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/make_loot_models.py
bash tools/import.sh
python -I tools/build_audio.py --suppressed                                       # suppressed gunshots only
python -I tools/add_work_sounds.py                                                # work/sounds (rerun after build_audio)
python -I tools/add_r3_sounds.py                                                  # sun, radio key/squelch, ladder (rerun after both)
python -I tools/make_vandal_atlas.py                                              # wall/ground decal atlas (game/assets/fx)
python -I tools/build_r6_sounds.py fetch                                          # Freesound sources (CC0 / CC BY) into tools/cache
python -I tools/build_r6_sounds.py build                                          # impacts, reload steps... (rerun after all of the above)
python -I tools/make_blood_textures.py                                            # blood mark atlas (game/assets/fx)
```

Downloaded guns (Sketchfab CC-BY models via the Objaverse mirror, listed in `tools/asset_sources.json`) are processed
with `tools/blender/process_items.py` (check renders in `work/items/`). Ammunition boxes are coloured per calibre from
`game/data/items.json` (`color`); every gun firing that calibre shows the same colour in the SmarTab.

Check renders of every model go to `work/loot_models/`.

## Building the Windows EXE and the Android APK

Both builds come from the same revision (cross-play requires it). Export templates for Godot 4.7.2, the Android
SDK and a JDK must be installed (Editor Settings → Export → Android).

```bash
python -I tools/write_export_presets.py   # game/export_presets.cfg (leaves out the unused Poly Haven originals)
cd game && godot --headless --path . --export-release "Windows Desktop" ../builds/windows/Aetherion.exe && cd ..
python -I tools/build_android.py          # builds/android/Aetherion.apk
```

`builds/windows/Aetherion.exe` is a single file (the game data is embedded, ~1.1 GB). `tools/build_android.py`
exports from `builds/_android_stage/`, a copy of the project with textures capped at 512 px (phones do not need
more; ~330 MB instead of ~1 GB), signed with the Android SDK's debug key unless `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`,
`_USER` and `_PASSWORD` are set: fine to install and test, but sign with your own key for a store.
`--gl --out builds/android/Aetherion-opengl.apk` builds an OpenGL variant for phones (and emulators) whose Vulkan
does not work; `--args "--join=<address> ..."` bakes launch options into a test APK.

Install on a phone with USB debugging on: `adb install -r builds/android/Aetherion.apk`. From an Android emulator
the PC is `10.0.2.2`.

## Rebuilding the outfits, menu art, impacts and announcer

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

## Rebuilding generated content

```bash
python -I tools/fetch_assets.py            # download third-party assets listed in tools/asset_sources.json
python -I tools/fetch_assets.py --manifest # regenerate docs/ASSET_MANIFEST.md
python -I tools/build_audio.py             # cut, synthesise and register the sound set (data/sounds.json)
python -I tools/make_noise.py              # bake the noise texture the wall, terrain and water shaders sample
python -I tools/fix_texture_imports.py     # VRAM compression + mipmaps for 3D textures (then tools/import.sh)
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/process_items.py
```

## Layout

| Path | Contents |
|---|---|
| `game/data/` | Tunable gameplay data: weapons, ballistics, items, loot tables, match rules, sounds |
| `game/src/core/` | Autoloads: definitions, settings, game flow |
| `game/src/net/` | Transport, lobby, snapshots |
| `game/src/match/` | World (server simulation and replication), match server, interaction |
| `game/src/player/` | Character, motor, health, controller, first-person view, third-person visuals |
| `game/src/weapons/` | Weapon state, ballistics, server projectiles |
| `game/src/world/` | Procedural map: layout, districts, houses, roofed lanes (lagusan), courtyards and barricades (looban), decals (vandal), dressing, doors/props, lighting and the day cycle, entrance steps |
| `game/src/audio/` | Sound system, acoustics (rooms and openings), footsteps, voice, ambience |
| `game/src/ai/` | Bots and their navigation grid |
| `game/src/ui/` | Menus, lobby, settings, HUD, SmarTab |
| `game/src/debug/` | Scripted play-through and network tests |
| `tools/` | Asset fetching and processing, audio build, checks, patches applied during development |
