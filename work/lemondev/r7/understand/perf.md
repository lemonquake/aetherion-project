# Rendering performance in Aetherion: findings for the Deathmatch mode and the "Lawless Sub" map

All file references are relative to `A:/Python/aetherion-project`. I read code, docs and saved logs only. I edited nothing and ran no benchmark. Every figure below comes from `docs/PERFORMANCE.md` or from the logs in `work/lemondev/r3` and `work/lemondev/r4`.

## (a) Measured numbers and where the frame time goes

**Test machine.** RTX 4060, 1600×900 window, vsync forced off. The PC preset is High: 2-cascade moon shadow out to 90 m, 8 lamp shadows, SSAO, volumetric fog, TAA. Every run after 2026-10-26 was taken while other work held 40–100 % of the CPU, so treat absolute fps as pessimistic. Nothing has ever been measured on a real phone.

**PC, 19 bots, closest to a 20-player match** (r4, editor build, loaded machine; `work/lemondev/r4/final/perf.log`):

| Phase | Avg ms (fps) | Render CPU / GPU ms | Draw calls | Triangles |
|---|---|---|---|---|
| Aircraft (plane) | 2.27 (440) | 0.65 / 1.35 | 102 | 0.10 M |
| Free fall | 6.08 (165) | 2.02 / 2.14 | 619 | 0.75 M |
| Canopy high / low | 8.64 / 10.92 (116 / 92) | 3.3–4.3 / 2.5–3.2 | 1,249 / 1,653 | 1.4–1.8 M |
| Just landed | 13.09 (76) | 5.10 / 4.10 | 2,201 | 2.27 M |
| Market | 13.73 (73) | 5.25 / 4.21 | 2,091 | 2.15 M |
| Dense looban | 15.55 (64) | 5.98 / 3.93 | 2,580 | 3.09 M |
| Densest spot (looban_east) | 20.16 (50) | 8.33 / 5.63 | 4,043 | 5.54 M |
| Rail | 13.35 (75) | 5.60 / 4.05 | 2,359 | 2.57 M |
| Indoors with flashlight | 14.77 (68) | 5.93 / 4.32 | 2,513 | 2.74 M |
| Roofed lane | 19.39 (52) | 8.10 / 5.44 | 3,440 | 3.60 M |
| Densest spot / market by day | 19.13 / 14.60 | about 8.2 / 6.2 | 3,926 / 2,178 | about 5.6 M / 2.2 M |

- **49 bots, release EXE** (`work/lemondev/r3/perf_new49b.log`): ground phases 13.7–25.5 ms (39–73 fps).
- **First pass, idle machine** (11 bots, unfurnished full-size map): ground 117–253 fps, aircraft 528 fps (`docs/PERFORMANCE.md:28-42`).

**Phone profile run on the PC** (Mobile renderer, mobile preset, 20 bots, release EXE; `work/lemondev/r3/perf_mob_new20b.log`; settings were shadows 0, no AO, no fog, render scale 0.70):

| Phase | Avg ms (fps) | Render CPU / GPU ms | Draw calls | Triangles |
|---|---|---|---|---|
| Plane | 1.99 (504) | — | 123 | — |
| Free fall | 4.45 (225) | — | 640 | — |
| Canopy high / low | 5.03 / 5.78 | — | — | — |
| Landed | 6.82 (147) | — | — | — |
| Market | 6.15 (163) | 1.98 / 1.87 | 641 | 0.56 M |
| Dense looban | 7.55 (132) | — | 680 | — |
| Densest spot | 7.41 (135) | 2.66 / 2.38 | 926 | 1.05 M |
| Rail | 5.86 | — | 526 | — |
| Indoors | 6.57 | — | — | — |
| Roofed lane | 7.62 | — | — | — |
| Densest spot / market by day | 8.61 / 7.18 | — | — | — |

- One isolated 159.7 ms hitch happened at the densest spot.
- `docs/PERFORMANCE.md:190` estimates 30–60 fps on a mid-range phone until someone measures one.
- **OpenGL (Compatibility) renderer:** 6–83 fps with long stalls from multi-pass lights and shader compiles (`docs/PERFORMANCE.md:193-194`).

**Where the time goes:**
- **Draw submission on the CPU.** Rendering is CPU-bound: about 2–3 µs per draw call on this CPU (5.25 ms / 2,091 draws; 8.33 ms / 4,043; 2.66 ms / 926 on the Mobile renderer). The densest spots issue 2,000–4,100 draws because each chunk mesh × material × render pass is one call. The suggested fix, folding the ~70 wall and floor materials into texture arrays, is not done (`docs/PERFORMANCE.md:208-209`).
- **The GPU** takes 4–8.7 ms on High, mostly the moon shadow cascades, the depth pre-pass and opaque pass, SSAO and volumetric fog. The only per-feature breakdown on record is `--attrib` for loot: 0.9 ms and 110–200 draws (`docs/PERFORMANCE.md:167-171`). No other attrib logs were kept.
- **Host simulation** of bots runs on the main thread:
  - 31 bots: server scripts 9.0 ms at the densest spot, 5.0 ms at the market.
  - 49 bots: world tick 7–12 ms, up to 40 ms in daytime firefights, bullets alone up to 11 ms (`docs/PERFORMANCE.md:132, 240-242`).
  - Per character: about 0.15 ms per tick for movement.
- **Jolt physics step:** 0.50–0.83 ms average per step, 0.14–1.7 steps per frame (r3 logs).

## (b) Speed measures already in the code

**Occlusion culling**
- Turned on in `game/project.godot:129` (`occlusion_culling/use_occlusion_culling=true`).
- Occluders are built only from boxes flagged `occlude`. They become one `ArrayOccluder3D` per 48 m chunk, shrunk to 97 % (`game/src/world/geo_sink.gd:190-191, 367-381, 473-479`).
- Flagged boxes: house walls at least 0.1 m thick and more than 1.5 m tall (`game/src/world/shanty.gd:440`), plus five spots in `game/src/world/sites.gd` (lines 342, 426, 502, 507, 555). Thin plywood and corrugated-iron walls never occlude.

**Chunking and merged meshes** (`game/src/world/geo_sink.gd`)
- One mesh per (chunk, material, layer). The `ext` and `inner` layers use 96 m chunks (`WIDE`, line 15); `int`, `mid` and the rest use 48 m chunks (`CHUNK`, line 11; key built in `_acc`, 108-119).
- One trimesh collider per (48 m chunk, physics material), lines 456-472.
- No LODs are generated for sink meshes.

**Visibility ranges** (all use FADE_SELF)

| What | Range | Where |
|---|---|---|
| `ext` exteriors | end 220 m, margin 30 | `geo_sink.gd:426-430` |
| `inner` (inside faces of shells, Interior layer) | 220 m | `geo_sink.gd:413-420` |
| `int` (partitions, interior detail, Interior layer) | 60 m, margin 8 | `geo_sink.gd:421-425`; `draw_int` at line 85 |
| `mid` (wires, decals; decals and puddles cast no shadow) | 140 m, margin 15 | `geo_sink.gd:407-412` |
| Terrain chunks (64 m, no shadow) | 900 m | `map_builder.gd:388-390` |
| Lamp emitters | 110 m | `lighting.gd:298-300` |
| Ground items | 24/15 m outdoors (gun/other), 14/9 m indoors, × draw distance, no shadow | `dynamics.gd:875-882` |

**Far stand-ins (HLOD)**
- `far_block()` builds flat-coloured boxes with no bottom face, one shared vertex-colour material, one mesh per 96 m chunk, shown from 220 m to 1,900 m, no shadow (`geo_sink.gd:292-313, 433-455`).
- Only `MapBuilder.shanty()` emits them (`game/src/world/map_builder.gd:297`).

**Altitude tiers** (`game/src/world/view_lod.gd`)
- Re-evaluated every 0.1 s from `MapBuilder.physics_tick` (`map_builder.gd:646-650`), with hysteresis: low air from 24 m (leave at 18 m), high air above moon-shadow distance + 12 m (lines 11-14, 38-62).
- Above the ground tier: the Interior and InteriorProps layers leave the camera mask, mesh LOD becomes 1.6× / 3× coarser, the exterior/far switch moves to 300 m (on the ground it is 220 m × draw distance clamped 0.6–1.3), and SSAO and local shadows go off; high air also drops the moon shadow (lines 65-81; `lighting.gd:167, 174, 551`).

**Moon / sun shadow** (`game/src/world/lighting.gd`)
- Distance by shadow setting: [60, 60, 90, 150] m (line 196). Ultra uses 4 splits with split_1 0.1; everything else 2 splits with split_1 0.25 (lines 178-180).
- Off when shadows = 0 or in high air (174). Furniture is excluded from its shadow passes (`shadow_caster_mask`, 173).
- Without shadows the moon also skips the Interior layers and loses a quarter of its energy (177, 439-442).
- Shadow maps: 4096 on PC, 2048 on mobile; soft filter quality 2; positional atlas 4096 / 2048 with quadrant subdivisions 1/2/3/3, i.e. 1/4/16/16 slots (`project.godot:109-124`).

**Lamp budget** (`lighting.gd`)
- The light manager files fixtures in 32 m grid cells, and 64 m cells for street lamps, floods and beacons (43-56, 306-324).
- Four times a second it shows only fixtures within fade distance + 16 m (542-590).
- Fade begins at 140 m for big lights, 38 + 3 × range for small ones, × `light_distance` (0.5–1.0, read at build); fade lengths 30 / 15 m; shadow fade 32 m (280-287).
- Shadows go to the nearest 0 / 4 / 8 / 12 lamps (by shadow setting) within 40 m, or 80 m for big lights, ground tier only, never for `no_shadow` fixtures (551, 583, 591-602).
- Lamp shadows exclude furniture (276). Faults animate only near the camera and send only changed levels (481-499, 585-586).
- Street lamps go off by day (570-571). Far light glints are one MultiMesh, shown at night only (398-422, 476-477).
- Muzzle flashes come from a pool of 6 unshadowed lights (`game/src/fx/effects.gd:71-77`).

**Sky and environment** (`lighting.gd`)
- Sky radiance 128, incremental processing (81-82).
- Volumetric fog only at night (166); froxel volume 96×96 (`project.godot:126-127`).
- SSAO only on the ground tier and only if enabled (167).
- The sky-fill light always stays in the scene, at zero energy by night, so the Mobile renderer never recompiles shaders at sunrise (140-145).

**Props** (`game/src/world/dynamics.gd`)
- Instanced as MultiMesh cells (393-430); the placement rules are in `_policy` (523-573):
  - cheap models (triangles × surfaces ≤ 300) go in 64 m cells, others in 32 m cells;
  - default range 80 m;
  - trees: 96 m cells, 200 m, cast shadows;
  - plants: 45 m, no shadow;
  - vehicles, or anything over 3 m: 140 m, cast shadows;
  - interior furniture: 15 m (under 0.7 m) or 25 m;
  - small outdoor clutter: 45 m, no shadow;
  - models with 6 or more surfaces: at most 35 m, no shadow;
  - loot boxes never cast shadows;
  - all ranges × draw distance; the effective range is want + 0.7 × cell.
- Doors, shutters, glass and curtains share MultiMesh "leaves" per 96 m cell, range +67 m (484-494). Only swinging doors are ticked (`door_started` at 1216, `tick` at 1255).
- Imported models: surfaces merged by material, LODs generated with `generate_lods(25, 60)` (`game/src/world/model_lib.gd:286-363`).

**Characters**
- Animation LOD: skeleton posed every 2nd frame beyond 30 m, every 4th beyond 70 m, every 8th beyond 140 m; IK only within 30 m (`game/src/player/character_visual.gd:37-38, 255-302`).
- Outfits are 2 surfaces with no mesh LOD (`game/src/player/outfit.gd:275-295`).

**Bot LOD** (`game/src/match/world.gd:518-551`)
- A bot runs every tick if it is fighting, has a target, is in the plane, or is on a team whose human is dead or spectating. Otherwise: every tick within 60 m of a living human, every 2nd tick within 150 m, every 4th beyond; `move_body` scales the missed time.
- `--bot_lod_off` disables it (line 534). Lag-compensation history is a ring of plain Arrays (498-515).

**Anti-aliasing, render scale and renderer** (`game/src/core/settings.gd:323-341`)
- Render scale is clamped 0.5–1.0. On Forward+ it uses FSR2 when that upscaler is picked, FSR1 whenever scale < 1, bilinear otherwise.
- TAA only on Forward+ (and not with FSR2); FXAA or 2× MSAA by option.
- Project defaults: TAA on, TAA off on mobile (`project.godot:113-116`); mesh LOD threshold 2.0 px, 4.0 on mobile (111, 130); anisotropic filtering 8× on PC, 2× on mobile (108, 112); clustered elements raised to 1,024 (131).
- Renderer: Forward+ on PC, Mobile on phones, OpenGL fallback (104-106).
- Physics: 60 Hz, at most 6 catch-up steps per frame, 4 on mobile (85-87).

**Textures**
- PC: BC1/BC3/BC5 compression with mipmaps (`tools/fix_texture_imports.py`, run by `tools/import.sh`).
- Android: 512 px cap (skies 1024) on `assets/thirdparty/` and `assets/models/`, ETC2/ASTC only (`tools/build_android.py:34-36, 92-126`).

**Quality presets** (`settings.gd:38-48`)

| Preset | Shadows | SSAO | Fog volumes | Draw distance | Other |
|---|---|---|---|---|---|
| mobile | 0 | off | off | 0.6 | render scale 0.7, MSAA, no flashlight shadows, lamp distance 0.6, **max_fps 60** |
| low | 0 | off | off | 0.8 | no flashlight shadows, lamp distance 0.8 |
| medium | 1 | off | on | 0.9 | |
| high | 2 | on | on | 1.0 | |
| ultra | 3 | on | on | 1.2 | |

- Defaults: vsync on, max_fps 0, TAA, flashlight shadows on (16-21). Phones get the mobile preset plus vsync (71-74, 117-125).
- The frame-rate menu offers 0/30/60/90/120/144 only (`game/src/ui/settings_ui.gd:153`).

**Shader warm-up** (`map_builder.gd:208-253`)
- Draws every material in `mats._cache`, every model in `models._cache` and every lamp emitter material once behind the loading screen. Particles and holes warm themselves (`effects.gd:60-66`).

**Not present anywhere:** room or portal culling on the ground (interiors are culled only by range and occluders), LODs on sink meshes, a texture array or atlas for walls (decals do use one atlas), reflection probes, GI or SSR. The `ssil` setting exists in DEFAULTS but nothing reads it.

## (c) What a new map must do, and the risks of Lawless Sub

**Budgets.** None is written down in the project; these are derived from the numbers above.
- **PC at 200 fps (5 ms a frame):** about 2.5 ms of render CPU, which is roughly 1,000–1,300 draws per frame across all passes at the busiest ground spot. Today: 2,100–4,100.
- **Phones at 100 fps:** an estimated ≤ 300–500 draws and ≤ 300–500 k triangles per frame, assuming a phone CPU is 2–3× slower per draw than this PC. Today the phone profile is 526–933 draws and 0.53–1.05 M triangles.
- **Per chunk:** each distinct material in a 96 m exterior chunk costs one draw per pass. Forward+ passes are depth pre-pass + opaque + each moon cascade + 2 per shadowed omni light (`OmniLight3D.SHADOW_DUAL_PARABOLOID` at `lighting.gd:269`). The Mobile preset has about 1 pass.
- **Materials:** aim for ≤ ~10 materials per chunk per layer. Vary colour with the free per-vertex `tint`/`paint` options of `sink.box()` (`geo_sink.gd:152-153`) instead of adding materials. Each surface material loads 4 textures plus noise (`materials.gd:146-175`).
- **Furniture:** draws = cells × distinct models × surfaces. Keep the number of distinct furniture models per 32 m cell small. Furniture added +195 draws at the densest spot (`docs/PERFORMANCE.md:115`).

**Lights**
- The Mobile renderer lights each mesh with at most 8 omni and 8 spot lights (comment at `lighting.gd:281-283`). Exterior and inner meshes span 96 m and interior meshes 48 m, so a suburban block with more than 8 lit rooms or porches in reach of one chunk mesh will drop lights or pop on phones.
- Forward+ caps clustered lights plus decals at 1,024 (`project.godot:131`); there are 220 pooled decals (`effects.gd:13`).
- Street lamps are generated every 38–55 m on every road at least 6 m wide, 55 % alive (`lighting.gd:206-231`). A suburb's road grid will produce many of them.

**Rules a new builder must follow**
- Route geometry through `GeoSink` with the right layers: shell outside on `ext`, shell inside faces via `inner_faces`, partitions and fixtures on `int`, small detail on `mid`.
- Flag thick walls `occlude: true`.
- Emit a `far_block` per building. Only `shanty()` does this today, so big hand-built structures like the factory and store vanish past about 250 m.
- Create materials only through `Materials.get_material` and models only through `ModelLib`, or the warm-up misses them and phones stall 100–380 ms.
- Leave the sky-fill directional light in the scene and add no other directional lights.

**Concrete risks**
1. **Every frame is a ground frame.** Deathmatch has no aircraft, free-fall or canopy phases, so play sits in the expensive ground tier: 50–76 fps on High with 19 bots on the loaded PC. The cheap airborne tiers never apply.
2. **Remote flashlights have no budget.** Each other player gets a SpotLight3D that casts shadows when `flashlight_shadows` is on (the PC default), with no distance fade and no nearest-N cap (`character_visual.gd:79-89, 320-355`). Up to 19 shadowed spot lights in a close-quarters night match is a large cost.
3. **Low suburban houses occlude less than the slum.** Open parks, parking lots, canals and roads give long sight lines, so more 96 m chunks are visible. Occlusion culls whole bounding boxes, and 96 m exterior meshes are rarely fully hidden; it mostly culls characters, items and some 48 m interior chunks.
4. **Real interiors in every house.** The `int` layer draws to 60 m with no per-building culling. Richer suburban furniture means more models per 32 m cell. Glass is alpha-transparent (`materials.gd:98-113`), drawn as one draw per 96 m leaf cell, so reuse the shared leaves.
5. **Bot LOD helps less in Deathmatch.** On a compact map most bots are within 60–150 m of a human. As soon as one human on a team dies, `watching` makes all of that team's bots run every tick (`world.gd:529-530, 541`).
6. **Host-side map limits** (`game/src/world/map_builder.gd`, `game/src/world/layout.gd`):
   - The water tile grid is hard-coded to ±576 m (`range(-6, 6)` × 96 m, `map_builder.gd:469-470`).
   - The terrain is a 2 m heightfield over `Layout.HALF` = 560 × `MAP_SCALE` 0.65 = 364 m (`layout.gd:11-13`); a bigger map grows the terrain chunks and the splat map.
   - The perf tool `_perf_toggles` does `get_node("TerrainMesh")` and `get_node("Water")` (`game/src/debug/autotest.gd:1291`), so a new map needs both nodes or `--attrib` breaks.
7. **Day/night needs the plane clock.** `Lighting.match_time()` counts from `match_info.plane.t0` and returns 0 without a plane (`lighting.gd:425-436`). Deathmatch must supply a t0, or it stays night forever. Fog volumes, street lamps and glints all switch on daylight.
8. **Mid layer ignores draw distance on phones.** `mid` (140 m), `int` (60 m) and emitters (110 m) are fixed, while phone exteriors end at 132 m (220 × 0.6). Prop, light and ground-item ranges read draw and lamp distance once, at build.
9. **Character triangle count adds up.** Outfits are 9–19 k triangles with no mesh LOD. Armour and a full helmet must merge into the outfit's 2 surfaces, or each costs one draw per character per pass.

## (d) How to measure

- **PC benchmark:** `godot --path game -- --host --bots=19 --autostart=1 --autotest=perf --shots=<dir> [--size=1600x900] [--attrib] [--autotest_timeout=420]`.
  - It forces vsync off and `Engine.max_fps = 0` and measures render time (`autotest.gd:1166-1173`).
  - Godot console exe: `A:\Installer\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe`.
- **Release EXE:** `powershell -ExecutionPolicy Bypass -File tools/perf_exe.ps1 -Exe builds\windows\Aetherion.exe -Tag <t> -Bots 19 [-Pre "<engine args>"] [-Extra "<game args>"] [-OutDir work\...] [-Seconds 700]`.
  - Log at `<OutDir>\perf_<Tag>.log`, results at `<OutDir>\perf_<Tag>\perf.json`; the default OutDir is `work\lemondev\r3`.
- **Phone profile:** `godot --path game --rendering-method mobile -- --mobile --host --bots=19 --autostart=1 --autotest=perf --shots=<dir>`, or via the EXE script with `-Pre "--rendering-method mobile" -Extra "--mobile"`.
  - `--mobile` neither loads nor saves the PC's settings (`settings.gd:131, 162`).
- **OpenGL check:**
  - Desktop run: `--rendering-method gl_compatibility -- --mobile ...` with the same game arguments.
  - Android build: `python -I tools/build_android.py --gl --out builds/android/Aetherion-opengl.apk`.
  - `--args "..."` bakes launch options into an APK, since Android apps take no command line. A perf run baked this way would write `perf.json` to `user://` on the device; that is untested.
- **Other tools:**
  - `godot --path game res://tools/map_preview.tscn -- --mmstats` lists instanced models by triangles, cells and LODs.
  - `godot --path game --gpu-profile res://tools/map_preview.tscn -- --perf=<view>` gives a feature-toggle A/B. Its views are hard-coded for the current map.
  - `python -I tools/prof_instrument.py apply|revert` adds or strips `##PROF` section timers. It needs `bash tools/import.sh` once; always revert before committing.
  - `--print-fps` is an engine flag; `--bot_lod_off` disables bot LOD for comparison.

**What gets reported** (`autotest.gd:1046-1157`): `[perf] <phase>` lines with frames, average ms, fps, p50/p95/p99/max, frames over 16.7 ms, render CPU and GPU, process and physics time, draw calls, objects, triangles and height above ground. Each phase then adds lines for physics steps per frame, Jolt step average/max, Prof sections, worst single calls and bot path searches. Hitches over 25 ms and tier changes are printed as they happen. `perf.json` keys are `phase, frames, avg_ms, fps, p50, p95, p99, max, over_16ms, cpu, gpu, proc, phys, draws, objs, prims, phys_steps, jolt_step, sec.*`. The `perf_recorded` check requires at least 5 phases.

**Measurement gotchas**
- **Process/physics columns overstate.** "process" and "physics" are `Performance.TIME_*` monitors, which are per-second maxima, not averages.
- **Body counts read 0.** The active-bodies, pairs and islands counts always show 0 under Jolt.
- **The benchmark only works on the current Battle Royale map.**
  - It waits on `match_server.plane` (lines 1176-1178).
  - Its ground spots are coordinates on the current map (1206, 1237).
  - It needs `map.tunnels` and `map.rooms` (1213-1235).
  - `--attrib` sorts chunk meshes into layers by their exact range values: interior ≤ 60.5, mid == 140, exterior > 200, far begin > 0 (1286-1289).
  - A Deathmatch / Lawless Sub version needs its own spots and no airborne phases.
- **`--attrib` has a fixed spot list.** It runs at the densest spot plus two hard-coded camera views from the air (1245-1247, 1345-1362).

## (e) Recommendations for 20-player team matches

**Phones, 100+ fps**
- **Raise the frame cap.** `PRESETS.mobile.max_fps` is 60 and vsync is on (`settings.gd:42, 72`). Use 0 or 120 on 90/120 Hz screens. Saved phone settings keep 60, so bump `Settings.VERSION` and add a `_migrate` step (`settings.gd:9, 146-158`).
- **Lower the render scale to 0.6–0.65** and keep 2× MSAA (cheap on mobile GPUs). Godot's docs say FSR1 also runs on the Mobile renderer, but `_apply_viewport` forces bilinear outside Forward+ (`settings.gd:330-336`). Test FSR1 there before relying on it.
- **Keep phones within the per-mesh light limit.** Either build interior and inner geometry in smaller chunks (for example 24–32 m) or cap lit rooms and porches so that no chunk mesh has more than about 6–8 lights in reach. Scale `mid` and `int` ranges with draw distance.
- **Target ≤ 400 draws per frame** and ~0.5 M triangles at the busiest spot.
- **Don't host bots on a phone.** Use a dedicated server, or limit a phone host to a few bots.

**High-end PC, 200+ fps**
- **Get ground spots to ≤ 1,200 draws.** Wall and floor texture arrays are the documented lever; use a small material palette and tints.
- **Budget remote flashlight shadows.** Keep the nearest 2–4 remote beams shadowed, put a distance fade on all of them, and re-run the shadow choice inside the existing 4 Hz `_shadow_budget`.
- **Trim shadows for Deathmatch.** High: 2 cascades over 60–70 m instead of 90 (`moon_shadow_distance`, `lighting.gd:196`), and 4 lamp shadows instead of 8.
- **Shorten the ground exterior range** to about 160–180 m, with far blocks behind it, including the big buildings.
- **Add explicit full-height occluder boxes** for the factory, the store and house shells.
- **Try multi-threaded rendering.** `rendering/driver/threads/thread_model` is not set in `project.godot`, so the engine default applies. Moving render CPU off the main thread might overlap it with the 5–12 ms of scripts. This is unmeasured here.
- **Run bots on a dedicated server.**
- **Give PC players higher caps.** Add 165/240 frame-rate options to the menu (it stops at 144) and leave vsync off for testing.
- **Re-measure on an idle machine** with `tools/perf_exe.ps1` before quoting any number.