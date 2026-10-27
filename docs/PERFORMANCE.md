# Performance

How Aetherion stays fast, how to measure it, and what each system costs. Measured 2026-10-26 on the test machine
(Windows 10, RTX 4060, 1600×900 window, High preset: shadows High, ambient occlusion on, volumetric fog on, TAA,
vsync off), host with 11 bots.

## Measuring

```bash
# A real deploy (aircraft, free fall, canopy, landing) and six ground spots, vsync off. Prints per-phase frame
# time (avg/p50/p95/p99/max, frames over 16.7 ms), the renderer's CPU and GPU time, draw calls, objects,
# triangles, the engine's physics step, bot path-search times, and any frame over 25 ms.
godot --path game -- --host --bots=11 --autostart=1 --autotest=perf --shots=<folder>
# Same, then switches each rendering feature off in turn at a busy ground spot, under a canopy and in free fall.
godot --path game -- --host --bots=11 --autostart=1 --autotest=perf --attrib --shots=<folder>
# Per-system script timings (adds `##PROF` timers to the per-frame callbacks; strip them before committing).
python -I tools/prof_instrument.py apply   # ... run the perf test ...   python -I tools/prof_instrument.py revert
# Instanced models by triangle count, cells and LOD levels.
godot --path game res://tools/map_preview.tscn -- --mmstats
# GPU time per render pass.
godot --path game --gpu-profile res://tools/map_preview.tscn -- --perf=looban_east
```

Results go to `<folder>/perf.json`.

## Results

| Phase | Before (start of this pass) | After (final run) | p99 frame | After, range over 5 runs |
|---|---|---|---|---|
| Aircraft (320 m) | 9 fps | 528 fps | 3.3 ms | 459–528 fps |
| Free fall | 9 fps | 308 fps | 5.8 ms | 289–408 fps |
| Canopy, high | 8 fps | 377 fps | 4.1 ms | 160–377 fps |
| Canopy, low | 8 fps | 298 fps | 5.9 ms | 186–298 fps |
| Just landed | 8 fps | 253 fps | 8.2 ms | 167–253 fps |
| Market | 8 fps | 185 fps | 8.0 ms | 144–185 fps |
| Dense looban | 7 fps | 153 fps | 10.3 ms | 132–156 fps |
| Densest spot (looban east) | 7 fps | 117 fps | 12.0 ms | 105–117 fps |
| Rail line / indoors with flashlight | 8 fps | 199 / 197 fps | 8.1 / 8.3 ms | 184–205 fps |

Final run: no frame over 16.7 ms in any phase (longest 15.6 ms). Ranges are across runs, each of which lands in a
different place. GPU time is 1.4–4.8 ms everywhere; frames are bound by the CPU side of rendering (draw calls).
Dedicated server with 16 bots: tick average ~3 ms, p99 4.1–4.6 ms (was p99 ~27 ms).

## What changed and why

| Cost found | Fix |
|---|---|
| Every physics tick looped over all ~27,000 doors and window shutters to find the moving ones (15 ms a tick; at 8 fps six ticks ran per frame) | Only swinging doors are ticked (`Dynamics.door_started`) |
| 1,217 world, prop and decal textures imported uncompressed and mostly without mipmaps (they are loaded from scripts, so Godot never detected 3D use) | VRAM-compressed (BC1/BC3, BC5 normal maps) with mipmaps: `tools/fix_texture_imports.py`. Map load also fell from 33 s to ~26 s |
| Merged prop models lost their LODs; each surface is a draw call per MultiMesh cell and pass; 96 m cells drew every prop in shadow passes | `ModelLib` merges surfaces by material and generates LODs; `Dynamics._policy` picks cell size, range and shadow casting per model (small clutter casts no shadow, many-material litter is drawn to 35 m, trees to 200 m); static box props are baked into chunk geometry |
| Wall shader evaluated three 4-octave value-noise fbm per pixel, also in the depth pre-pass (SSAO needs normals) | Baked into `assets/fx/noise_rgba.png` (`tools/make_noise.py`); terrain and water likewise |
| Moon shadow: 4 cascades over 140 m, terrain and furniture as casters | 2 cascades over 90 m on High (4 on Ultra), terrain and indoor furniture left out (`RENDER_INTERIOR_PROPS`), positional shadow atlas 4096 |
| ~3,300 lamps and emitters always in the scene, culled every frame even when faded out | Light manager in `lighting.gd`: grid of fixtures, 4×/s shows only those within their fade distance; lamp flicker only sends changed levels |
| Exterior geometry in 48 m chunks of ~20 materials, drawn to 270 m | 96 m chunks (shared with the far blocks, so each chunk is near or far, never both); 220 m on the ground |
| Bot A* in GDScript: up to 18–50 ms on the main thread | `AStarGrid2D` (jump point search) inside precomputed connected regions, on a worker thread, one search at a time (`NavGrid.request/take`) |
| SmarTab screen re-rendered every frame | Renders only while the device is up |
| First play of each sound read the file from disk | All sounds load during the map build (`SoundSys.warm`) |
| Every death printed 10 Jolt warnings with backtraces | Unsupported joint softness no longer set |
| Player camera, remote players, client props and corpses were placed per frame but still physics-interpolated | Interpolation off for those nodes (it lagged them and stepped at the 60 Hz tick) |

## Altitude tiers (`src/world/view_lod.gd`)

A jumper sees roofs, not rooms. The camera's height above ground picks a tier (10× a second, with hysteresis):

| Tier | Height | Changes |
|---|---|---|
| Ground | below 18–24 m | Everything as the settings say |
| Low air (canopy) | 24 m up to the moon-shadow range + 12 m | Interiors and indoor furniture leave the camera; no flashlight/lamp shadows; no ambient occlusion; mesh LOD 1.6× coarser; buildings keep full detail to 300 m (headroom is large up here) |
| High air (aircraft, free fall) | above ~102 m | Also no moon shadow (its 90 m range no longer reaches the ground); mesh LOD 3× coarser |

The scripted play-through checks the tier, interior culling, AO and local shadows in free fall and after landing.

## Settings that matter

- **Quality preset** now applies its settings when picked (Low: no shadows, AO or volumetric fog, shorter
  draw distance; Medium: 2-cascade moon shadow, 4 lamp shadows, no AO; High; Ultra: 4 cascades, 12 lamp
  shadows, longer draw distance). Options can still be changed one by one afterwards.
- **Draw distance** (0.8–1.3) scales where buildings switch to their far blocks on the ground.
- **Vertical sync** is on by default, so the frame rate is capped at the monitor's refresh rate.

## Second pass: furnished rooms, a 30–40 player map, bot level of detail (2026-10-26)

The results table above is the first pass (full-size map, unfurnished rooms, 11 bots). Since then the map was
shrunk for 30–40 players, rooms are furnished, and matches fill to 32 players by default.

**Machine load.** Every run in this section was taken while other work held 40–70% of the CPU (a long `xcopy`,
Windows Defender scanning it, a QEMU virtual machine). Absolute frame rates are therefore lower than the first
pass and not comparable with it; comparisons below are between runs taken back to back under the same load.
Re-run the benchmark on an idle machine before quoting fps. The runs also predate two later fixes: walls wound the
right way round (`GeoSink.FACES`; the same triangles, but lamps and flashlights now light the walls they face) and
heavy props kept out of door swings (~100 fewer props).

### Map size (`Layout.MAP_SCALE`)

The geography in `layout.gd` is written at its original size and scaled on load. At 0.65 (~650 m of play area):

| | Full size | 0.65 |
|---|---|---|
| Buildings | 5,007 | 2,239 |
| Loot containers (furnished) | 14,948 | 6,578 |
| Movable props (furnished) | 35,831 | 16,338 |
| Instanced model cells | 22,811 | 10,986 |
| Map build | ~44 s | 21–26 s |

Positions, district extents, the coastline, the expressway and the dump scale; river, road and alley widths,
buildings and bridge spans do not. Sites check their footprint after placement (`Sites._check_footprints`) and
warn when one lands on a road, the railway, water or another site.

### Furniture and plants

The Poly Haven models load from processed copies (`tools/blender/process_props.py`, `game/assets/models/polyhaven/`):
one material each, 1,000–4,000 triangles by size (900 for the roof tyres, of which there are thousands), trees
~12,000 (from 1.6–2.1 million). Interior furniture is drawn to 15–25 m (rooms are dark and walled in), and lamps do
not take furniture as shadow casters (`shadow_caster_mask`); flashlights still do. Fixed-view A/B at Looban East
(`map_preview --perf`, same build, furniture on/off): 4.79 → 5.57 ms, +195 draw calls. Before the lamp mask and
the short interior range it cost +2.1 ms.

### Bot level of detail (`World._bot_lod`) and the lag-compensation history

Profiling a host with 31 bots showed the server half of the frame dominating: every character's movement step
(Jolt `move_and_slide` plus the movement script, ~0.15 ms per character per tick), bot thinking, and recording
the lag-compensation history. When a frame ran long, two or three ticks ran in the next one, which made it worse.

- A bot within 60 m of a living human, fighting, chasing a target, or in a squad a dead human is watching runs
  every tick; within 150 m every 2nd tick; farther every 4th, its step covering the ticks it missed
  (`Character.move_body` scales the velocity for `move_and_slide`). `--bot_lod_off` turns it off.
- The history was a packed array inside a Dictionary (copied on every append) re-sliced every tick for every
  character; it is now a ring of plain Arrays.

| Measure | Before | After |
|---|---|---|
| Host, 31 bots, server scripts per frame at Looban East / market (profiled) | 26.9 / 17.2 ms | 9.0 / 5.0 ms |
| Dedicated server, 40 bots: tick average | 9–12 ms | 4–6 ms |
| Dedicated server, 40 bots: tick p99 / worst | 12–17 / 24 ms | 6–10 / 16 ms |

### Current frame rates (host, 1600×900, High, vsync off, under the load above)

| Phase | 11 bots | 31 bots | 31 bots, Mobile renderer |
|---|---|---|---|
| Aircraft | 372 | 227 | 302 |
| Free fall | 142 | 99 | 101 |
| Canopy, high / low | 98 / 103 | 63 / 61 | 59 / 62 |
| Just landed | 70 | 51 | 50 |
| Market | 78 | 53 | 43 |
| Dense looban | 75 | 47 | 45 |
| Looban east | 54 | 29 | 35 |
| Rail line / indoors | 54 / 79 | 50 / 49 | 57 / 54 |

`--rendering-method mobile` is the renderer a phone export uses (no SSAO or volumetric fog). On this PC it draws a
third to a half of the draw calls but is no faster, because the frame is CPU-bound; it says little about a real
phone, which has to be measured on the device.

## Loot: ground items and loot boxes (2026-10-26)

The map now starts with ~6,600 items on the ground and ~3,800 loot boxes. How they stay cheap:

- **Ground items have no scene nodes**: each is a static physics body (for the Use ray) and a render instance made
  directly on the servers, with a short draw distance (12 m; 22 m for guns and packs, scaled by the draw-distance
  setting), no shadow, and the interior layer indoors (hidden from the air). Freed when the match is torn down.
- **Loot boxes are MultiMesh instances** like the furniture, with no shadows. A box's open model is a render instance
  of its own, created only when the box is first opened: registering the open models in every cell cost a draw
  call per cell, model and surface even while hidden (the first version: +300 to +480 draw calls at the ground
  spots).
- Hidden MultiMesh instances (picked-up props, broken windows, opened boxes) are scaled to nothing where they stand;
  they used to be moved 1 km below the map, which stretched their whole cell's bounds.

Measured with `--autotest=perf --attrib` (new `loot` toggle: every ground item and box hidden, same view), RTX 4060,
1600x900, 11 bots, under ~100% background CPU load: densest ground spot 10.4-10.7 ms with loot, 9.7 ms without
(about 0.9 ms; 110-200 of ~3,300 draw calls). The fixed ground spots against the same day's baseline before the loot
work: market 7.27 -> 7.36 ms, looban 7.12 -> 7.55 ms, looban_east 10.65 -> 9.83 ms, rail 7.09 -> 6.88 ms (the new
placement also shifted furniture, so spots do not hold identical scenes). Not measured on a phone.

## Phones (the Mobile profile)

What a phone gets (`Settings.PRESETS.mobile`, `.mobile` overrides in `project.godot`): the Mobile renderer, 3D drawn at
70 % and scaled up bilinearly, 2× MSAA, no shadow maps (flashlight shadows off too), no AO or fog volumes, draw
distance 0.6 (chunks and instanced props), lamps culled at 60 % of their PC distance, a 60 fps cap, 2048 shadow
atlases, coarser mesh LOD switching, at most 4 physics catch-up steps a frame, and textures capped at 512 px in the
APK (`tools/build_android.py`). Rooms stay dark without moon shadows: the inside faces of buildings are on the
Interior render layer, which the moon skips when it casts no shadow.

Measured on this PC with `--mobile --rendering-method mobile`, 15 bots (no phone was available; ~60 % background
CPU load from other work):

| Phase | fps | Draw calls | Render CPU |
|---|---|---|---|
| Free fall / canopy | 83–132 | 520–970 | 2.3 ms |
| Ground spots (market, looban, looban east, rail, indoors) | 94–114 | 630–880 | 2.6–3.3 ms |

A mid-range phone's CPU is several times slower than this one, so expect roughly 30–60 fps there until measured.
The first mobile run (before props followed the draw distance) had 1,021 draw calls at Looban East; now ~880.

- **Compatibility (OpenGL) renderer:** 6–83 fps on the same benchmark with long stalls (multi-pass lights, shader
  compiles), so Android uses the Mobile (Vulkan) renderer and falls back to OpenGL only where Vulkan is missing.
- **Benchmark caveat:** in runs taken while two Android emulators shared the GPU, the aircraft phase read 13–14 fps.
  The benchmark's own per-frame renderer queries were waiting on the render thread; the exported EXE without the
  benchmark held 60 fps (vsync) through the same phase (`--print-fps`).
- **Package size:** the APK was 1,048 MB with the PC's textures (ETC2: 931 MB); 333 MB with textures capped at
  512 px (skies 1024).
- **Map build on a phone:** 32.6–33.7 s on the 4-core x86_64 emulator; a real phone may be slower. The server waits
  for every client (`loading_timeout_s`, 90 s).

## Known remaining costs

- With 31 bots on a host, frames still miss 60 fps at the densest spots on this (loaded) machine: rendering CPU
  time (draw calls), the remaining per-character server work and the bots' visuals. A dedicated server takes the
  server half off the player's machine.
- Draw calls dominate (2,000–3,500 at the densest spots). Folding the ~70 wall/floor materials into texture
  arrays would make each chunk one draw call per layer; not done.
- Nothing has been measured on a phone. A mobile build needs an Android/iOS export preset, a mobile quality preset
  (the Mobile renderer drops SSAO and volumetric fog, which the lighting leans on) and touch controls.

## 2026-10-27: fix run (0.4.0) against 0.3.0, release EXEs on the same PC

Ground loot more than doubled (15,849 items), more and larger windows, door push physics, lite minimap. Ground items
lost their physics bodies (Use finds them through the item grid) and draw to 24 m / 15 m outdoors and 14 m / 9 m
indoors with a faint self-glow (no overlay pass). Medians of 4 (old) and 2 (new) runs at the fixed spots, average
frame ms at 1600x900 High on the RTX 4060: market 8.8 -> 9.5, looban 9.7 -> 11.4, looban_east 12.4 -> 13.5,
rail 8.6 -> 8.6, indoor_light 9.2 -> 10.9. The machine was loaded by other work: two runs of the same build differed by
up to 2.7 ms, so only the indoor difference is likely real. Phone profile on this PC (`--rendering-method mobile --
--mobile`, release EXE): 140-170 fps at the indoor spot; one crash (0xC0000005) at the first ground-tier shader
compile on an intermediate build, three clean runs on the final one. No real phone measured.

## 2026-10-27 (r3, 0.5.0): 50-player matches, the artificial sun, the richer map

Release EXEs on the same PC (RTX 4060, 1600×900, High, vsync off; another process held about one core), `--autotest=perf`
with **49 bots on the host** (a full 50-player match simulated on the player's own machine — the worst case; a
dedicated server takes all of the bots' work off the players). Average frame time in ms (fps):

| Phase | 0.4.0 | 0.5.0 | Notes |
|---|---|---|---|
| Aircraft | 1.89 (530) | 2.25 (444) | |
| Free fall | 3.45 (290) | 6.40 (156) | airborne frames cost 1–3 ms more (more geometry and decals in view; script time also higher, not resolved) |
| Canopy high / low | 6.11 / 7.12 | 9.90 / 11.61 | |
| Market / dense looban / densest spot | 12.97 / 13.06 / 18.57 | 13.73 / 16.29 / 19.75 | |
| Rail / indoors with flashlight | 13.58 / 14.11 | 15.34 / 19.26 | indoor p95 is noisy run to run (bots fighting nearby) |
| Inside a roofed lane (flashlight on) | — | 23.53 (43) | was 25.85 before tunnel bulbs were kept out of the lamp shadow budget |
| Densest spot / market at noon | — | 25.53 / 21.06 | the day phases run last, when most bots are fighting |

With 49 bots, the host's own simulation of them is the largest cost (profiled: the world tick 7–12 ms a frame on
the ground, up to 40 ms in the heaviest daytime firefights, bullets alone up to 11 ms). Bots therefore see at most
75 m by day (not the 110 m first tried, which started constant long-range fights).

**Phone profile** (`--rendering-method mobile -- --mobile`: Mobile renderer, phone preset, 20 bots — the default
practice match a phone hosts), release EXEs on the PC:

| Phase | 0.4.0 | 0.5.0 |
|---|---|---|
| Free fall / canopy low | 3.23 / 4.42 | 4.45 / 5.78 |
| Landed / market / looban / densest spot | 6.71 / 6.20 / 7.14 / 7.06 | 6.82 / 6.15 / 7.55 / 7.41 |
| Rail / indoors | 7.12 / 7.67 | 5.86 / 6.57 |
| Roofed lane / densest spot at noon / market at noon | — | 7.62 / 8.61 / 7.18 |

Every phone-profile ground phase stays above 115 fps on this PC. Not measured on a real phone.

What this pass changed for speed:
- **Other players' animation level of detail** (`character_visual.gd`): skeletons beyond 30 m are posed every 2nd
  frame, beyond 70 m every 4th, beyond 140 m every 8th; hand IK only within 30 m.
- **Tunnel bulbs and candles never cast shadows** (`no_shadow` light spec): each shadowed omni light redraws the
  scene around it twice, and a lane has one every 7–11 m.
- **No fog volumes by day** (they are a night effect).
- **No shader stalls at sunrise**: the sky-fill light stays in the scene at zero energy by night, because switching a
  directional light on changes the light count the Mobile renderer's shaders are specialised for (the first tries
  stalled 100–350 ms at sunrise on the phone profile). A **warm-up** (`MapBuilder.warm_up`) draws every map material
  and model once behind the loading screen.
- One draw call per chunk for all wall and ground decals (`assets/fx/vandal_atlas.png`); the old per-texture decals
  are gone. Tunnel dressing shares materials (cloth, timber, wire).

Remaining: one isolated 160 ms frame in one phone-profile phase (not reproduced; probably a first-time effect such
as a nearby fight's particles, which the warm-up does not cover).
