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

The main menu offers **Play** (Host a game, Join a game, Practice with bots), **Settings** and **Quit**. In the lobby,
join a team, mark **Ready**, and the host presses **Start Match**. A match holds up to 50 players; by default the host
adds 20 bots (Game Setup in the lobby changes it).

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

### Day and night

Matches start at night. At 5:00 the artificial sun ignites (a warning toast and a distant siren come 30 and 5
seconds before) and the whole settlement is in daylight until 10:00, when it goes dark again; the cycle repeats every
ten minutes, the same moment for every player (it follows the server's clock). By day you see and are seen far across
open ground (bots too), but rooms and the roofed lanes stay dark: the lane roofs keep the sun out except through
their gaps, so you still need your flashlight in there.

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
phones and PCs alike (up to 50 players in a match). Try the phone profile on a PC with `--mobile`
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
