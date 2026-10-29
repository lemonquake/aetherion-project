# Aetherion: tests, builds and asset pipeline

All facts below come from reading the code. I edited no files. The only command I ran was a compile check: it took 4 s, checked 102 scripts, 0 failed, and wrote its output to the scratchpad.

Paths in this report are relative to `A:/Python/aetherion-project`. `$GODOT` means `A:/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe`. Run every command from the project root in Git Bash.

## (a) Commands and timings

**1. Compile check**
- Command: `bash tools/check.sh`. It runs `$GODOT --headless --path . res://tools/check_scripts.tscn`, which writes to `tools/cache/check.txt`.
- It loops up to 4 times. Each pass runs `python -I tools/fix_infer.py`, which rewrites `var x :=` to `var x =` **in place on disk**. The path inside `fix_infer.py` is hardcoded, and it writes in text mode, so on Windows a fixed LF file becomes CRLF.
- Output: error lines, then `checked N scripts, M failed`.
- `check_scripts.gd:5-27` loads only scripts under `res://src` and `res://tools`.
- Read-only version that edits nothing: `"$GODOT" --headless --path game res://tools/check_scripts.tscn`. It takes about 4 s.
- A new `class_name` needs `bash tools/import.sh` once before other scripts can use it.

**2. Import**
- Command: `bash tools/import.sh`. It runs `$GODOT --headless --path . --import` up to 5 times (the headless editor sometimes crashes on exit), logging to `tools/cache/import.log`.
- After each pass it counts asset files (png, jpg, glb, wav, ogg) that still have no `.import` file.
- When none are missing it runs `python -I tools/fix_texture_imports.py`. That script switches textures under these folders to VRAM compression with mipmaps: `assets/thirdparty/polyhaven/textures`, `assets/thirdparty/polyhaven/models`, `assets/models`, `assets/fx`. Normal maps get BC5. If anything changed, it imports again.
- Success prints `import ok` and exits 0; otherwise it exits 1.
- **Textures placed anywhere else (for example the empty `game/assets/textures/`) do not get compression or mipmaps.**

**3. Run an autotest suite with screenshots** (template: `work/lemondev/r6/run_gates.sh`)
```
powershell -ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds 600 -Log work/lemondev/r7/gates/dm.log \
  -ArgLine "--path game -- --host --bots=11 --autostart=1 --autotest=r6 --shots=A:/Python/aetherion-project/work/lemondev/r7/gates/dm --port=27515"
grep -c 'autotest\] PASS' <log>; grep -c 'autotest\] FAIL' <log>
```
- `run_timed.ps1:9-16` kills the whole process tree when time runs out. Bash `timeout` only stops the console wrapper, and the engine keeps holding its port.
- `--path game` in `ArgLine` is relative to the current directory, so run from the project root.
- Give each run its own `--port`. The r6 gates used 27515-27521; the EXE test uses 27540.
- Optional flags:
  - `--size=WxH`: window size, set in `autotest.gd:27-29`.
  - `--autotest_timeout=S`: watchdog, default 420 s (`autotest.gd:30`). It must be shorter than `-Seconds`; the fixes suite uses 950.
  - `--mobile --rendering-method mobile`: phone profile on PC (`run_gates2.sh` r6_phone).
  - `--matchlog`, `--seed=N` (map seed), `--match_seed=N`, `--zone_speed=F`, `--end_after=S` (force the end of the match), `--quit_after_results`, `--profile=<name>`.
- Measured run times from `work/lemondev/r6/gates*/`:

| Suite | Time | Result |
|---|---|---|
| r6 | 118-127 s | 15-18 PASS |
| tour | 107-112 s | 24-26 PASS |
| fixes | 323 s | |
| r3 | 114 s | |
| r4 | 128 s (77 s with `--r4_only`) | |
| r5 with `--r5_fast` | 215 s | |
| r6_phone | 70 s | |
| fixes_grab | 70 s | |

- Map build takes 22-28 s inside a match (`[world] map built in 22119 ms`). mapscan adds about 121 s of scanning.
- Each check prints `[autotest] PASS|FAIL <name>: <detail>`. Each screenshot prints `[autotest] shot <path>` and is saved as `<shots>/NN_<name>.png`.
- At the end: `[autotest] done: N checks, M failed`, plus `<shots>/results.json` (an array of `[name, ok, detail]`). The process exits 1 if any check failed (`autotest.gd:1553-1559`).
- `RID ... leaked at exit` errors in `.log.err` are normal.

**4. map_preview (needs a window and GPU)**
```
"$GODOT" --path game res://tools/map_preview.tscn -- --out=A:/.../work/x --views=overview,plane,freefall [--times=0,450] [--bright] [--size=1600x900] [--seed=1729] [--timeout=400]
```
Options (`map_preview.gd:38-97`):
- `--out`: output folder, default `user://preview`.
- `--views=`: comma list of `VIEWS` keys (`:16-35`); default is all of them.
- `--times=`: match times in seconds; the sun is up from 300 to 600.
- `--bright`: raises ambient 6.0 and moon 1.4.
- `--size`: default 1600x900.
- `--seed`: map seed, default 1729.
- `--timeout`: watchdog, default 400 s, exit 2.
- `--mmstats`: instanced triangles, cells, LODs, containers, props.
- `--doorcheck`: swings every outer door and lists what jams it.
- `--perf=<view>`: frame cost with features toggled one at a time.

Each view renders 75 frames and saves `<view>[_bright][_t<time>].png`; the log line includes fps and luma. The map build takes 20-42 s.

**There is no real top-down view.** `overview` is oblique, from (140,160,260) toward (-20,0,-120); `plane` is at 320 m, `freefall` at 230 m. The map is always built with `MapBuilder.build(self, seed, 1)` (`:53`), and there is no option to choose a map.

**5. Network test**
- Command: `bash tools/net_test.sh`. Set `PORT=<n>` to override the default 24631.
- It starts a headless dedicated server (`--server --bots=6 --autostart=2 --expect_players=2 --testcheats --netdebug --match_seed=11`), then clients Alpha (`--autotest=net_a`) and Bravo (`--autotest=net_b`).
- Logs go to `work/screens/net/{server,alpha,bravo}.log`.
- It takes about 92 s; the last run had 17 PASS.
- It uses bash `timeout` and `kill`, so a server left running can keep the port.

**6. Builds** (`work/lemondev/r6/build_all.sh`; numbers from `build.txt`)

| Step | Command | Time | Size |
|---|---|---|---|
| Presets | `python -I tools/write_export_presets.py` | instant | |
| EXE | `(cd game && "$GODOT" --headless --path . --export-release "Windows Desktop" ../builds/windows/Aetherion.exe)` | 103 s | 1,289,235,024 B |
| Store APK | `python -I tools/build_android.py` | 135 s | 415,573,973 B |
| OpenGL APK | `python -I tools/build_android.py --gl --out builds/android/Aetherion-opengl.apk` | 51 s | 415,573,973 B |

- Both APKs being exactly the same size is odd; check that the OpenGL renderer setting really got in.
- The `build_android.py` docstring says to build the store APK last; `build_all.sh` builds the OpenGL one last.
- `--args "--join=..."` bakes launch options into a test APK.
- Signing uses `GODOT_ANDROID_KEYSTORE_RELEASE_*`, falling back to `%APPDATA%/Godot/keystores/debug.keystore`.
- Gotcha in `build_all.sh:6`: it renames `builds/windows/Aetherion.exe` to `Aetherion-0.6.0.exe` if that file is missing. It is missing now, so the next run would label the 0.7.0 EXE as 0.6.0. Write an r7 copy of the script instead.

**7. EXE test**
- Command: `powershell -ExecutionPolicy Bypass -File work/lemondev/r6/exe_test.ps1`. It runs `builds/windows/Aetherion.exe -- --host --bots=11 --autostart=1 --autotest=r6 --r6_fast=1 --shots=... --size=1600x900 --port=27540`.
- Time limit is 600 s; it prints `exit <code>`; the log is `work/lemondev/r6/exe/r6.log`. The last run had 14/14 and exit 0.
- Exit 1 means a check failed, not necessarily a crash.
- Frame-rate test on the exported build: `powershell -ExecutionPolicy Bypass -File tools/perf_exe.ps1 -Exe builds\windows\Aetherion.exe -Tag dm -OutDir work\lemondev\r7 -Bots 19 -Extra "<game args>" -Pre "<engine args such as --rendering-method mobile>"`.

## (b) Adding `--autotest=dm`

**How a scenario is chosen**
- `game.gd:282-283` (`_begin_match`, host, not dedicated) and `game.gd:301-302` (`_match_started`, clients) call `_add_autotest()` at `game.gd:286-293`.
- `_add_autotest()` picks `autotest_net.gd` if the name **starts with "net"**, otherwise `autotest.gd`. The node is added as `World/AutoTest`.
- `autotest._run()` (`:34-89`) first waits up to 20 s for `world.local_char` and `world.controller`. It then compares the name against `perf`, `loot`, `fixes`, `r3`, `r4`, `r5`, `r6` and `mapscan`.
- **Any unknown name silently runs the default tour**, which calls `_deploy()` and needs the plane (`:138-174`).

**Files to add**
- New file `game/src/debug/autotest_dm.gd`, following the `autotest_r6.gd` pattern:
```gdscript
extends RefCounted
## --autotest=dm: ...   godot --path game -- --host --bots=19 --autostart=1 --autotest=dm --shots=<dir> --port=27530 [--dm_only=a,b]
var t = null
var world = null
func _init(autotest) -> void:
	t = autotest
	world = autotest.world
func run() -> void:
	var only := str(Game.arg("dm_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	...
```
- Register it in `autotest.gd` `_run()`, next to `:66-73`:
```gdscript
	if str(Game.arg("autotest", "")) == "dm":
		await load("res://src/debug/autotest_dm.gd").new(self).run()
		_finish()
		return
```
  Use `load` (as mapscan does at `:71`), not `preload`. With `preload`, a compile error in the new file breaks `autotest.gd`, and with it every suite.
- Run `bash tools/import.sh` once to generate the `.uid` file.
- Also add it to an r7 `run_gates.sh`, the README "Testing" section, and a copy of `exe_test.ps1`.

**Helpers on `t`** (`autotest.gd`)

| Helper | Line | Notes |
|---|---|---|
| `_check(name, ok, detail)` | 1419 | |
| `_shot(name)` | 1438 | Waits for `frame_post_draw`; captures the root viewport, HUD included |
| `_view_luma() -> float` | 1424 | Must be awaited; mean luma (0-255) of the middle 40 % of the view |
| `_wait(s)` | 1501 | |
| `_until(cond: Callable, timeout) -> bool` | 1505 | Counts physics frames assuming 60 Hz |
| `_act_press` / `_act_release(action)` | 1515 / 1519 | Real `InputEventAction` |
| `_tap(action)` | 1532 | |
| `_hold(action, s, shot_name="")` | 1541 | |
| `_teleport(pos, yaw)` | 1406 | |
| `_look_at(p)` | 1413 | |
| `_teammates()` | 1382 | |
| `_pick_room()` | 1390 | Room types `bed`/`kitchen`/`living`/`store`/`front`/`sala`, at least 2.4 m |
| `_stand_by(target, floor_y, dist=1.2) -> bool` | 695 | |
| `_spawn_in_front(entry, d=1.0) -> int` | 761 | |
| `_open_patch(near)` | 900 | |
| `_nearest_box(in_house)` | 665 | |
| `_perf_open_spot(Vector2)` | 1365 | |
| `_touch(i, pos, pressed)`, `_drag`, `_touch_controls` | 1447-1467 | |

Frame timing from a suite: turn vsync off as `:1167-1170` does, then use `_perf_begin(phase, spin)`, `_perf_end()` or `_perf_hold(phase, frames)` (`:1075`, `:1089`, `:1257`). The row in `_perf_report` gives fps, p50, p95, p99 and draw counts.

**Helpers in `autotest_r6.gd` worth copying**
- `_surface_at` (:57), `_clear_around` (:65)
- `_grab() -> Image` (:75)
- `_red_px` (:80), `_new_red(before, after, rect)` (:94)
- `_screen_rect(img, world_p, half_px)` (:113), `_luma(img, rect)` (:188)
- `_fire_at(target, ammo, v0)` (:124): a real projectile on the server
- `_pick_bot()` (:130)

**Server-side calls available to tests**
- `world.server_set_mode(ch, Motor.GROUND)` (`world.gd:241`). The r6 fast path at `autotest_r6.gd:28-32` uses it instead of the plane, which is what a deathmatch spawn needs.
- `world.interaction.give(ch, {"id":..., "n":...})` (`interaction.gd:160`)
- `world.interaction.target(ch, {yaw, pitch})` (`interaction.gd:29`)
- `ch.health.apply_simple(amt, cause, part, attacker)` (`health.gd:225`) followed by `world._after_damage(ch, res, attacker)` (`world.gd:737`)
- `ch.health.reset()`
- `world.map_item_spawn_server(e, xf)` (`world.gd:1204`)
- `world.map.server_spawn_corpse(ch, impulse)`
- `world.match_server.force_end()` (`match_server.gd:415`)
- `world.map.lighting.forced_time = 450.0` (day), `-1` to release
- `world.characters`, `world.bots`

**Gotchas for a deathmatch suite**
- The suite starts only after the match starts, so it cannot drive the lobby's primary and secondary gun picker. Take the loadout from launch arguments, or check the picker UI with `--ui_tour=<dir>` (`ui_tour.gd`).
- `AutoTest` is a child of World. 25 s after results (`rules.json` `results_s`), `_return_to_lobby` → `teardown_world` frees it. With `--quit_after_results` the game quits 4 s after results.
- So round-end checks must call `_finish()` inside that window.
- A finished match also writes XP to the local profile (`game.gd:330-333`) and posts results online. Use `--profile=dmtest`.
- Don't use `--mode`: it already means solo, duo or squad (`net.gd:355-356`).
- `Net.MAX_TEAM_SIZE := 4` (`net.gd:42`), and `--team_size` is clamped to it. The ENet peer limit is `MAX_TEAMS*MAX_TEAM_SIZE+4` = 32 (`net.gd:68`).
- `--bots` sets the team count automatically to `ceil((bots+expect)/team_size)`, clamped to 2-7 (`game.gd:118-124`). Two teams of 10 needs changes in net and game code.
- Keep CLASSIC as the default. tour, fixes, r3-r6, loot, perf and net_a all depend on the plane: `_deploy`, and `autotest_net` waits for `match_info.plane`.

**Parts of existing suites that are hard-coded to the slum map** (they will fail or crash on Lawless Sub)
- `_perf_run` spots `market`, `looban` and the others at `autotest.gd:1206`, `:1237`, `:1352`.
- `_loot_census` thresholds: at least 2000 loot boxes, more than 300 weapons (`:559-566`).
- The r6 fast landing spot (40, 40).
- map_preview `VIEWS` (`:16-35`). `_place` calls `layout.river_x` and `estero_z`. `_place_feature` does `lanes[i % lanes.size()]`, a modulo by zero if the map has no tunnels, loobans or ladders.
- The tour expects `world.map.rooms` entries `{xf: Transform3D, size: Vector2, h, type}` and `world.map.dyn.lights` with `kind` bulb, tube, lamp or candle and `pos`.
- The r6 blood test expects `dyn.doors[{node, outward, xf}]`.
- mapscan expects `map.sink` recording (`map_builder.gd:76`) and building dicts `{kind, style, w, d, top}`.

**Frame-rate targets**
- The Mobile preset caps phones at 60 fps (`settings.gd:41-42`, `max_fps: 60`), so "100+ fps on phones" needs that cap lifted or measured with `--autotest=perf` (vsync off, `max_fps=0`).
- Measured phone-profile ground phases on this PC are 115+ fps. No real phone has been measured.

## (c) Asset download pipeline

**Fetcher**
- Command: `python -I tools/fetch_assets.py [section...]`, reading `tools/asset_sources.json`.
- Sections: `polyhaven_textures` (109, mostly 1k, a few 2k), `polyhaven_hdris` (3), `polyhaven_models` (152), `sketchfab` (74 uid entries), `kenney` (5), `commons` (4).
- No API keys anywhere. Methods that have worked:

| Source | Method | Where it lands |
|---|---|---|
| Poly Haven | `api.polyhaven.com/info/<id>` and `/files/<id>`, MD5-verified (`:91-160`) | Textures: `game/assets/thirdparty/polyhaven/textures/<id>/{albedo,normal,roughness,ao}.jpg`. Models: `.../models/<id>/` glTF. HDRIs: `.../hdri/<id>/` |
| Sketchfab | `api.sketchfab.com/v3/models/<uid>` for licence and author. Only "CC Attribution" or "CC0 Public Domain" is accepted, otherwise it raises (`:186-187`). The GLB itself comes from the Hugging Face Objaverse mirror (`huggingface.co/datasets/allenai/objaverse/resolve/main/<path>`), with paths from `tools/cache/objaverse/object-paths.json.gz` (19 MB) | `tools/cache/sketchfab/<name>/` |
| Sketchfab search | `python -I tools/sketchfab_search.py "query"...` (`/v3/search?downloadable=true`), filtered to CC models that are in the mirror. Objaverse is an older snapshot, so new uploads are missing | |
| `tools/fetch_r5.py` | Same `sketchfab()` call over a hard-coded candidate list | |
| Kenney | Scrapes `kenney.nl/assets/<slug>` for the zip and extracts it (`:213`). Only audio and particle packs used so far; 3D kits are untested | |
| Wikimedia Commons | `w/api.php`, 3 s sleep between calls, licence whitelist (`:240`) | |
| Freesound | HTML page scrape, licence regex taken from the page, public HQ ogg preview (`build_r6_sounds.py:99-145`) | 267 files in `tools/cache/freesound` |
| OpenGameArt | Manual downloads | `tools/cache/oga` |
| ambientCG, Quaternius | **Never used, and no fetcher exists** | |

**Converting to game-ready assets**
- Poly Haven models: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P tools/blender/process_props.py [-- id ... | --list | --before]`.
  - It processes only ids that appear as `"model": "<id>"` in `game/src/world/model_lib.gd` (regex at `:64-67`) plus `ITEM_IDS`. **Add the `ModelLib.PROPS` entry first.** Entry format, from `model_lib.gd:17`: `"key": {"model": "<ph_id>", "mass", "mat", "hp", "kind"}`.
  - Per-model settings in the `MODELS` dictionary (`:42-61`): `keep`, `scale`, `drop`, `tint`, `tris`, `tree`, `foliage`.
  - Triangle budget by size (`budget_for`, `:638-642`): 1k / 1.8k / 3k / 4k for under 0.3 / 0.6 / 1.2 m / larger. Materials are merged into one atlas; textures are 512 px under 0.5 m, else 1024.
  - Output: `game/assets/models/polyhaven/<id>.gltf` and `.bin`, `sources/<id>.json`, check render `work/props/<id>.png`.
  - Afterwards run `write_export_presets.py` (its exclusions depend on which textures the processed files reference) and `import.sh`.
- Guns and gear: `tools/blender/process_items.py` reads `tools/cache/sketchfab/<src>/<src>.glb` and writes `game/assets/models/items/<id>.glb` and `sources/<id>.json`. Its orientation logic is gun-specific.
- **No script exists for Sketchfab scenery such as cars.** The owner's Sleep project processed its street and nature models with its own Blender scripts (`A:/3rd Harmonik/interior/tools/blender/`).
- Textures need no processing: a folder `thirdparty/polyhaven/textures/<id>/` with albedo/normal/roughness[/ao] jpg or png, plus a `SURFACES` entry in `materials.gd:10-79`: `{tex, tile (m per repeat), phys, metal, grime, flake}`.
  - An unknown surface name silently falls back to plywood (`:146`).
  - The `phys` value must be one of the materials in `data/ballistics.json`: concrete, default, dirt, fabric, flesh, foliage, glass, hollow_block, plaster, plastic, plywood, sand, sheet_metal, steel, water, wood. There is no brick or tile material.

**Licence records**
- Each downloaded folder gets a `source.json` (`write_source`, `:65`): source, title, url, authors, license, license_url, attribution_required, kind, resolution, modifications, retrieved, and `files` as `{relative path: sha256}`.
- Processed models get `<folder>/sources/<id>.json` with `processed_from` and `modifications`.
- `fetch_assets.py --manifest` builds the table in `docs/ASSET_MANIFEST.md` (`collect_records`, `:271`) from everything under `game/assets/thirdparty`, `game/assets` and `game/addons`.
- **Every `fetch_assets.py` run calls `write_manifest()` at the end (`:349`), and it rewrites the whole file (`:301-316`).** That wipes the hand-kept sections from line 442 on: the r3/r4 "made in this project" table and the r6 sound credits, about 170 lines. The note in the file that says otherwise is wrong. Back the file up and re-append the hand sections, or fix the function.
- Licences currently in the manifest:
  - CC0-1.0: 384 rows (Poly Haven, Kenney, OpenGameArt) plus 121 Freesound sounds.
  - CC-BY-4.0: 31 rows (Sketchfab guns and gear, Sleep nature and street) plus Commons Gravity Sound (CC BY 4.0).
  - Freesound CC-BY 3.0/4.0: 12 sounds, which need an in-game credits screen (none exists yet).
  - Also: CC BY-SA in the Sleep audio entry, MIT (sky_3d, particle_scene_compositor, profesor_shader), SIL OFL 1.1 (fonts), public domain (NASA moon), owner's own or project-owned work.

**Build effects of new assets**
- All of `game/` ships (`export_filter="all_resources"`). Only raw Poly Haven model glTF/bin files and their unreferenced textures are excluded (`write_export_presets.py:28-41`). Every new texture set makes the EXE (1.29 GB) and APK (416 MB) bigger.
- `build_android.py:34-36` caps imported textures at 512 px (skies 1024) only under `assets/thirdparty/` and `assets/models/`.
- Android versionCode is the minor version number (`write_export_presets.py:46`): 0.8.0 gives 8.
- The network version is the project version (`config/version="0.7.0"`). The map fingerprint must match between PC and phone.

## (d) Assets on disk a suburban map could reuse

**Folder sizes**
- `game/assets/thirdparty` (1.1 G): `polyhaven/textures` 346 M (109 sets), `polyhaven/models` 736 M (152 raw), `polyhaven/hdri` 16 M (qwantani_night_puresky, kloppenheim_02_puresky, qwantani_moonrise_puresky), `profesor_shader` 13 K.
- `tools/cache` (1.4 G):
  - `sketchfab` 358 M: 74 models, guns, gear, arms, plus `parachute` and `aircraft_c130`. **No cars, furniture or scenery.**
  - `audio_libs` 526 M; `addons` 263 M and `addons_disabled` 169 M (zip archives).
  - `kenney` 47 M: impact, interface and rpg audio packs, particle and smoke packs.
  - `objaverse` 19 M (the index); `freesound` 11 M; `announcer` 3.9 M; `loot_tex` 2.3 M; `commons` 1.6 M; `oga` 964 K.
- Processed models in `game/assets/models`: `polyhaven` 38 M (120 .gltf), `items` 97 M, `loot` 13 M, `gear` 5.7 M, `fp_arms` 1.5 M, `sleep` 111 M.
- `game/assets/textures` is empty.

**Textures in `thirdparty/polyhaven/textures/`**

| Kind | Sets |
|---|---|
| Asphalt and pavement | road_damaged (2k), asphalt_02, worn_asphalt, cracked_concrete |
| Concrete | rough_concrete, concrete_wall_008, dirty_concrete, cracked_concrete_wall, rebar_reinforced_concrete, hacked_concrete, concrete_debris, concrete_block_wall / _02 / _03 |
| Concrete floors | damaged_concrete_floor, concrete_floor_02, concrete_floor_painted, worn_concrete_floor, garage_floor, scuffed_cement |
| Plaster and paint | rough_plaster_broken, damaged_plaster, worn_cracked_plaster, peeling_painted_wall, painted_plaster_wall, white_plaster_02, beige_wall_001, blue_plaster_weathered, red_plaster_weathered, yellow_plaster, worn_mossy_plasterwall, plastered_wall_04 |
| Wood floors | old_wood_floor, worn_planks, dark_wooden_planks, weathered_planks |
| Tiles and linoleum | dirty_tiles, worn_tile_floor, floor_tiles_06, blue_floor_tiles_01, terrazzo_tiles, square_tiled_wall, old_linoleum_flooring_01, linoleum_brown |
| Siding and boards | weathered_plank_siding, plywood, oriented_strand_board, raw_plank_wall, various painted planks |
| Doors and shutters | rough_pine_door, wood_shutter, worn_shutter, rusty_metal_shutter, rusted_shutter, painted_metal_shutter |
| Factory metal | box_profile_metal_sheet, container_side, rusty_metal_grid, metal_grate_rusty, corrugated_iron sets, rusty_metal_* |
| Interiors | dirty_carpet, decrepit_wallpaper, ceiling_interior, polystyrene, assorted fabrics |
| Ground | sparse_grass, leafy_grass, withered_grass, dry_decay_leaves, forest_floor, dirt, dirt_floor, stony_dirt_path, gravel_road, gravel_floor, brown_mud_*, muddy_tracks, rubble |
| Canal | mud_cracked_dry_riverbed_002, coast_sand_01, damp_beach_sand, low_tide_rocks |
| Bark | palm_tree_bark, bark_brown_01 |

**Not in the project:** brick, roof tiles, lawn-quality grass, and wooden or picket fences.

**Models already processed** (`models/polyhaven/`)

| Kind | Models |
|---|---|
| Furniture | painted_wooden_chair_01/02, painted_wooden_table, painted_wooden_cabinet / _02, painted_wooden_shelves, painted_wooden_sofa, painted_wooden_nightstand, painted_wooden_stool, painted_wooden_bench, WoodenTable_01, wooden_stool_01, folding_wooden_stool, small_wooden_table_01, round_wooden_table_01, old_bed_frame, vintage_day_bed, drawer_cabinet, vintage_wooden_drawer_01, wooden_bookshelf_worn, metal_office_desk, SchoolChair_01, SchoolDesk_01, standing_chalkboard_01, wooden_picnic_table, plastic_monobloc_chair_01, metal_stool_01 |
| Store | Shelf_01, steel_frame_shelves_01/02, CashRegister_01 |
| Appliances | Television_01, television_02, ceiling_fan, electric_stove, vintage_microwave, wall_clock, classic_laptop, exterior_aircon_unit, portable_generator |
| Kitchen clutter | pot_enamel_01, brass_pot_01, jug_01, wooden_bowl_01, wooden_cutting_board, wine_bottles_01, plastic_bottle_gallon, plastic_container, small_lpg_tank, propane_tank |
| Industrial | metal_tool_chest, metal_toolbox, drill_press_01, portable_welding_cart, hand_truck, tire_pump, modular_industrial_pipes_01, hanging_industrial_lamp, mounted_fluorescent_lights, Barrel_01, barrel_03, wooden_barrels_01, wooden_crate_01/02, plastic_crate_01/02/03, cardboard_box_01, cement_bag, compost_bags, old_tyre, rusted_wheel_rim_01, ladder_sectioned_01, wooden_ladder, plus hand tools |
| Street | street_lamp_01/02, security_light, fire_hydrant, water_manhole_cover, concrete_road_barrier, utility_box_01/02, power_box_01, metal_trash_can, trashbag, covered_car |
| Canal | ship_pinnace, lifebuoy, ocean_buoy |
| Plants | island_tree_01/02, tree_small_02, shrub_02, grass_medium_01, weed_plant_02 |
| Medical | medical_box, wheelchair_01, vintage_crutches_01, korean_fire_extinguisher_01 |

**Downloaded but not yet processed:** modular_chainlink_fence (fences), rollershutter_door and rollershutter_window_01 (store fronts), modular_electricity_poles, modular_electric_cables, modular_wooden_pier (canals), outdoor_table_chair_set_01, WoodenChair_01, tool_cart, bench_vice_01, caged_hanging_light, lightbulb_01, island_tree_03, shrub_01/03/04, fern_02, grass_medium_02, grass_bermuda_01, nettle_plant, pachira_aquatica_01, tree_stump_01, dead_tree_trunk, boulder_01, coast_rocks_01, coast_land_rocks_02, root_cluster_01.

**Other sets already in the game**
- `models/sleep/street` (CC-BY): jeepney, tricycle_a/b, food_cart_a/b, food_stall_c, oil_drum. These are the only vehicles besides covered_car; there are **no normal cars, vans or trucks**.
- `models/sleep/nature`: palm_coconut_a/b, banana_*, bamboo_clump, cattails, reeds.
- `models/sleep/kit` (owner's own): heap_*, litter_a/b, rubble_a/b, floating_a/b/c, mattress.
- `models/loot`: 8 loot box kinds, each with an open model.

**More Poly Haven assets on disk in the owner's Sleep project** (CC0; add the ids to `asset_sources.json` and fetch them properly rather than copying)
- `A:/3rd Harmonik/interior/game/assets/outdoor/textures/` has albedo/normal/roughness sets in the same layout:
  - brick: brick_wall_02, red_brick, mossy_brick, rough_plaster_brick_04
  - roofs: clay_roof_tiles_02, grey_roof_tiles, roof_slates_02
  - other: concrete_pavement, marble_tiles, mossy_cobblestone, old_stone_wall, rustic_stone_wall_02, dark_paneled_wood, wood_floor_worn, wood_cabinet_worn_long, floral_jacquard, velour_velvet
- `A:/3rd Harmonik/interior/.local/downloads/polyhaven/models/` (151 raw models) includes ArmChair_01, Sofa_01, sofa_02, CoffeeTable_01, side_table_01, dining_table, dining_chair_02, ClassicConsole_01, ClassicNightstand_01, GreenChair_01, Ottoman_01, Rockingchair_01, potted_plant_01/02/04, modern_ceiling_lamp_01, desk_lamp_arm_01, throw_pillows_01, book_encyclopedia_set_01, vintage_cabinet_01, wooden_display_shelves_01, worn_metal_rack, jacaranda_tree, searsia_lucida, large_iron_gate and Lantern_01.

**Not found anywhere:** fridges, washing machines, forklifts, playgrounds, or real road vehicles.