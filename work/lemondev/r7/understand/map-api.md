The second map can reuse the whole stack below the geography layer: Shanty, Dynamics, Acoustics, Dresser, PracticalLights, Lighting, ViewLod, Entrances and GeoSink are map-agnostic. They read only the shared registries on `map` and a small set of `layout` members. What is tied to Sitio Kalinaw is `layout.gd`, `districts.gd`, `sites.gd`, `street_dress.gd`, the terrain skirts, the splat map, the water tiling and the railway. Below: what consumers query, the shanty spec, big buildings, GeoSink, terrain, and how to plug in a second map. Everything comes from reading the code; nothing was run.

## Gotchas to read first

1. **Street lamp poles are probably never drawn.** `map_builder.gd:124` calls `sink.finish()`, then `:127` calls `lighting.build()`. That runs `lighting.gd:149 _street_lamps` → `_lamp_pole` (`lighting.gd:234-240`), which adds `sink.cylinder/box` after the flush. That geometry is never turned into meshes or colliders, so only the floating Light3D and its emitter show. The new map must build any lamp geometry before `sink.finish()`. This is from code order only, not checked in a render.
2. **Bot navigation reads private layout fields.** `ai/nav_grid.gd:32-41` reads `L._n`, `L.HALF`, `L.GRID`, `L._reserved` and `L._water`. A cell is walkable when `_water==0` and `_reserved` is not 2 (site) or 3 (lot). Building footprints must therefore be reserved with value 2 or 3, or bots walk into walls.
3. **The day/night cycle needs a plane.** `lighting.gd:425-437 match_time()` counts from `match_info.plane.t0`. Without a plane it stays 0 and the match never leaves night.
4. **Phones are capped at 60 fps.** `settings.gd:42` sets `max_fps: 60` in the mobile preset, which conflicts with "100+ fps on phones". The cost that matters is CPU-side draw calls (`docs/PERFORMANCE.md:41`): Kalinaw draws 630–880 calls at ground spots on the Mobile renderer.
5. **Acoustic zones are axis-aligned boxes** (`acoustics.gd:46`), built from the AABB of a rotated rectangle (`shanty.gd:342`). Houses rotated 0/90/180/270° get exact zones; other angles leak "indoor" past the corners. Axis-aligned houses also avoid the ARM float drift that the fingerprint comment warns about (`map_builder.gd:192-195`).
6. **Only shanty buildings get far-distance blocks** (`map_builder.gd:297`). All other "ext" geometry stops drawing at 220–300 m: towers, the crane, warehouse walls, the highway. Big buildings and landmarks on the new map need their own `sink.far_block`.
7. **The warehouse is not an interior.** `sites.gd:382` adds no acoustic zone, no door and no Interior-layer faces. Bots (`bot_brain.gd:310, 902`) and ambience (`ambience.gd:85`) treat it as outdoors, and the sky fill lights it.
8. **Narrow canals can be missed by the water tiles.** `_water` (`map_builder.gd:469-479`) only places a 96 m tile if one of 9×9 samples, 12 m apart, is water. A canal under 12 m wide can lose its tile. The tile loop is also fixed at -6..5 × 96 m (±576 m).
9. **Big buildings are dots on the minimap.** `_make_map_image` (`map_builder.gd:605-616`) fills footprints with a 7×7 point grid, so anything larger than about 8 m shows as dots.

## (a) What other systems query on `map` and `map.layout`

### `layout` members used outside `world/`
| Member | Used by (file:line) |
|---|---|
| `HALF` (const, 364) | `match/world.gd:560` (off-world edge); `ui/minimap.gd:58`; `ui/smartab_ui.gd:402`; `ai/nav_grid.gd:35`; `debug/autotest_map.gd:550`; `autotest_r5.gd:266,624` |
| `PLAY_HALF` (325) | `match/world.gd:570` (rescue clamp); `match/match_server.gd:83` (first zone r0 = PLAY_HALF×1.25), `:196` (next radius = phase.radius × PLAY_HALF × 1.6) |
| `MAP_SCALE` (0.65) | `match_server.gd:47` (flight path); `ai/bot_brain.gd:136`; `autotest.gd:1205,1351` |
| `WATER_Y` (-0.6), `LAND_Y` (0.9) | `autotest_map.gd:704`; `autotest_net.gd:92` |
| `GRID` (2.0), `_n`, `_water`, `_reserved` | `ai/nav_grid.gd:34-41` |
| `in_play_area(p: Vector2) -> bool` | `match_server.gd:62,205`; `world.gd:575`; `bot_brain.gd:144` |
| `is_water(x, z) -> bool` | `match_server.gd:62,205`; `world.gd:575`; `audio/ambience.gd:116`; autotests |
| `ground_height(x, z) -> float` | `world.gd:581`; `nav_grid.gd:284`; autotests |
| `landmarks: [{name, pos: Vector2}]` | `ui/smartab_ui.gd:408` |
| Object identity | `bot_brain.gd:80-88`: static `nav` and the building index rebuild when `world.map.layout` changes |

Inside `world/`, the slum geography is also read: `rng` (seed base: districts +101, sites +211, dresser +307, lighting +401, street_dress +509, lagusan +733, looban +911, vandal +1201, map_builder +77), `roads [{name, pts: PackedVector2Array, w, mat, curb}]`, `districts`, `sites`, `crossings`, `railway`, `river`, `estero`, `coast_z(x)`, `dump_c`, `dump_r`, `highway_x`, `rail_z`, `estero_z`, `river_x`, `river_hw`, `rect_free(center, half, ang, allow_water=false, margin=0.3)`, `reserve_rect(center, half, ang, value, margin=0, only_free=false)`, and the static `seg_dist` and `poly_dist`. Nothing accesses Layout constants at class level (only `map_builder.gd:5` preloads it), so another layout object can provide them as plain `var`s.

### `map` (MapBuilder) members used outside `world/`
- **Construction:** `match/world.gd:73-80` does `MapBuilder.new()`, `map.build(self, cfg.map_seed, match_seed)`, sets `map.acoustics.space`, then calls `SoundSys.set_acoustics(map.acoustics)` and `map.warm_up(self)`. `tools/map_preview.gd:52-53` does the same.
- **Query methods:**
  - `ground_height(x, z)`: `props/corpse.gd:713`, autotests.
  - `water_height(x, z)` (returns WATER_Y or -INF): `world.gd:139` → `player/character.gd:160`, `weapons/projectile_server.gd:89`, `ambience.gd:117`.
  - `ladders_near(p)`, checked with `has_method`: `player/ladder.gd:17-20`. Ladder records are `{base, top_y, n, w}`.
  - `item_visual(id)`: `viewmodel.gd`, `character_visual.gd:273`, `weapons/attach_visual.gd:21-184`, `grenades.gd:48`.
- **Runtime facade (all generic, `map_builder.gd:646-798`):** `physics_tick(dt)`, `server_tick`, `awake_props_near`, `client_prop_snapshot`, `client_interpolate`, `server_spawn_corpse`, `server_break_glass`, `server_prop_hit`, `server_blast` (also `grenades.gd:139`), `server_corpse_hit`, `server_push_prop`, `server_sync_peer`. Callers are in `world.gd` at 354, 407, 757, 784, 815, 1025-1041, 1123, 1144.
- **Fields read:**
  - `fingerprint`: `core/game.gd:231-246`. A mismatch only shows a toast; the client is not kicked.
  - `map_image`: `ui/minimap.gd:20-21`, `ui/smartab_ui.gd:41-42`. Must be a square image covering [-HALF, HALF]².
  - `buildings [{id, xf, w, d, kind, district, style, floors, covered, deck, top, front_open, h0}]`: `bot_brain.gd:92-153, 379-422` (xf, id); `ambience.gd:37`.
  - `dyn.doors / windows / items / containers / loot_boxes / props / corpses / floor_count` and `dyn` methods: `world.gd:1053-1334`, `interaction.gd:498`, `hud.gd:444-474`, `effects.gd:255-440`, `match_server.gd`. Bots need `doors[].outer`, `.bid`, `.outward`, `.node` and `containers[].bid` (-1 means a site box).
  - `acoustics.zone_at(p)`, where a non-zero result means indoors: `bot_brain.gd:310, 673, 687, 752, 902`; `ambience.gd:85`.
  - `cover.covered(p)` (null-checked): `bot_brain.gd:310`.
  - `lighting`: `match_time()` in `bot_brain.gd:304` and `announcer.gd:25`; `forced_time`, `env`, `moon`, `_shadowed`, `air_tier` in autotests.
  - `pa_speakers [{pos, along}]`: `announcer.gd:79`. It falls back to local playback when empty (`:69`).
  - `models.spec/get_model`, `mats.get_material`: `hud.gd:474`, `interaction.gd`, `effects.gd:396-440`.
  - Autotests only: `rooms`, `stairs`, `ladders`, `alleys`, `tunnels`, `loobans`, `vault_spots`, `sink` (`rec` for mapscan), `root`, `view_lod`, `stats`.
- **Map RPCs on `world` used by the facade:** `map_window_broken`, `map_door_ev`, `server_door_panel`, `map_prop_*`, `map_corpse_spawn`, `_box_opened`, `server_send_items`, `server_sound`. All generic.

## (b) The Shanty spec and what it produces

**Entry point:** `MapBuilder.shanty(spec) -> Dictionary` (`map_builder.gd:282-302`). It:
1. sets `spec.id = new_building_id()`;
2. calls `Shanty.new({sink, mats, acoustics, dyn}).build(spec)`;
3. appends `s.flights` to `stairs` and `s.ladders` to `ladders`;
4. appends a `buildings` record;
5. adds a far block of size (w+0.6, top+0.4, d+0.6), body colour by style, roof colour from `sink.rng`;
6. calls `dresser.dress_room(r, spec)` for every room, appends to `rooms`, and calls `practical.house(spec, rooms)`.

**Keys `shanty.build` reads** (`shanty.gd:40-318`; the canonical producer is `Districts.place`, `districts.gd:68-112`):
- **Required:** `seed`, `id` (set by map_builder), `xf: Transform3D`, `w`, `d`.
  - `xf.origin` = footprint centre at ground-floor level.
  - Local -Z is the front and +X is the right side looking out of the front door (`basis_facing(front2d)`, `districts.gd:60`).
- **`floors`** (default 1). It drops to 1 if the house is too shallow for a stair (`:99-103`). 2 floors adds one stair; 3 adds a second flight on the other wall.
- **`style`**: one of `chb`, `wood`, `yero`, `bamboo`, `concrete`, `patch` (`STYLES`, `:15-22`). It picks the ground and upper wall materials, the paint chance, a gable roof for concrete (60%), and the far-block colour.
- **`kind`**, default "house". The comfort room exists only when `kind == "house"`. The dresser and the lights branch on it (store, workshop, classroom, clinic, chapel, church, hall, police, outpost, pump, apartment, shop, chapel).
- **`front`**: "door" (door plus maybe a window), "store" (door plus a barred shop window), or "open" (whole front open as a workshop).
- **Other keys:**
  - `stilts` and `ground_y`
  - `covered`: the front wall's faces go on the Interior layer
  - `roof_deck`, `ladder` (only with a deck and front "door"), `parapet` (default true)
  - `can_overhang`: upper floor leans out 0.5–1.0 m, clamped by `front_lane_w/2 - 0.2`
  - `front_lane_w` (default 9)
  - `back_blocked`: no back door, and vault windows become bars
  - `side_holes: [Vector2 world points]`: crawl holes into the neighbour
  - `front_gy`: ground height in front, used for the ladder foot and door drums
- **Read only by `map_builder.shanty`:** `district`.

There are no `doors`, `windows`, `rooms` or `stairs` keys. The floor plan and every opening come from the building's own `rng`:
- **Ground floor:** a front room (`sala`, `store` or `workshop`). An optional back room (`kitchen` or `bed`) when d ≥ 5.4 (80%), with a partition that is a curtain, door or opening. A comfort room in a back corner (1.2×1.4 m, door 0.76 m).
- **Stair:** steep, 0.78 m wide, along a side wall rising to the back.
- **Upper floors:** one `bed` room each.
- **Wall height:** h0 2.35–2.6 and h1 2.15–2.4, both random and not settable through the spec.

**Output** (`:70, :307-318`): `{id, rooms, doors: [] (always empty), top, deck, front_open: [Vector4(x, w, y, h)], h0, zone_front}`.

**Room record:** `{type, xf (floor centre, house basis), size: Vector2 (usable), h, bid, zone, avoid / avoid2 / avoid3: Rect2 (house-local, the dresser subtracts local_z), door_x (front room only), local_z, cr}`.

**Side effects through `ctx`:**

**Openings in walls:** `_walls(xf, w, d, y, h, mat, openings: {front, back, left, right: [{type: door|window|opening, x, w, y, h, win, vault, hole}]}, painted, paint, dirt, bid, zones, split, z_split, zf, zb, covered)` (`:359`). Opening `x` is the house-local x on front/back walls and the house-local z on left/right walls; the function flips signs itself.

Per opening, `_opening` (`:447-483`) does:
- **Door:** `acoustics.add_portal(zone, 0, pos, "door", 0)` and `dyn.add_door({xf: hinge at bottom-left, w, h, t: 0.035, mat, portal, bid, outer: true, outward, seed, role})`.
- **Window:** `add_portal(zone, 0, pos, kind)`, where glass→window, shutter→shutter, bars/open/store→opening, plastic→curtain. Then `dyn.add_window({xf at the centre, w, h, type, portal, bid, outward, t, seed, vault, hole, sill_y})`.
- **Opening:** a portal plus `dyn.add_doorway({c, u, n, w, h, kind: "front_open", bid})`.

**Interior partitions, comfort room and stairs:**
- **Partition:** `_partition_x(...)` (`:486`) runs across x only; there is no partition along z. The comfort room is `:522`.
- **Stair:** `_stair` (`:546`) appends `{foot, top, dir, start, run, rise, w, side}` to `flights`, adds the clearances "stair_foot" and "stair_top", and an invisible `col_box` ramp ("stair_ramp").

**Acoustic zones and portals:**
- **Zones:** `add_zone(aabb, bid, floor, reverb, floor_mat)`. Ground rooms use "small" if w×d < 14, else "medium". Floor material is "wood" on stilts, else "concrete". AABBs shrink by 0.08 m.
- **Portals between floors:** "stair" (`:272`).

**Roof, deck and ladder:**
- **Roof:** `_roof` (`:629`) makes corrugated sheets with a footprint-only collider and roof infill. It adds 0–4 tyres, blocks or stones with `add_static_prop`.
- **Deck:** `_deck` (`:697`) makes a slab and parapet. It adds a drum on a stand, a monobloc (both `add_prop_spec`), plants, and a 45% `add_loot_spot(..., "floor_street", bid)`.
- **Ladder:** `_ladder` (`:785`) adds a `{base, top_y, n, w}` ladder and a "ladder" clearance.

**How windows become vaultable.** Vaulting is purely physical (`player/vault.gd:10-14, 19-120`). With rays on `Defs.MOVE_MASK`, it needs:
- something in front within 0.75 m whose top is 0.45–1.5 m above the feet;
- at least 0.62 m of clear opening above that top;
- a landing spot past the obstacle where a crouching capsule fits.

By window type:
| Window type | Vaultable? | Why |
|---|---|---|
| `"open"` | Yes | A 5 cm timber "sill" box (`shanty.gd:470-475`) and nothing in the opening. |
| `"glass"` | Once shot out | PHYS_GLASS body with `window_id` meta (`dynamics.gd:663-685`). `break_window` (`:1332`) frees it and turns the portal into "opening". |
| `"shutter"` | When open or destroyed | A Door with panels. |
| `"bars"`, `"store"` | Never | PHYS_BLOCKER `col_box`. |
| `"plastic"` | Yes, and shot through | Frosted quad only, no collider at all. |

`_ground_window` (`:321-326`) makes 36% of ground windows `{win: "open", vault: true, w: 0.95–1.2, y: 0.78–0.9, h: 1.1–1.24}`. The `vault` flag only chooses those sizes. It is stored on the window record and read only by `autotest_fixes.gd:500`. No clearance is added under vault windows, even though the comment at `dynamics.gd:90` says so; the dresser can place furniture in the landing spot.

**Doors.** `door.gd` gives every leaf a kinematic body (PHYS_WORLD|PHYS_INTERACT) plus one instance in a shared MultiMesh.
- **Panels:** `server_damage` / `lose_panel` / `destroy`, through `Destruct.door_panels`. Panel strength is 170 for metal, 45 for plywood, 70 otherwise (`door.gd:386-406`).
- **Grenades:** `server_blast` damages doors and shutters within radius + 1 m.
- **Per match:** 22% of outer doors are locked, and start angles are randomised (`dynamics.gd:723-735`).
- **Shutter ids:** 1000000 + window id.

**Furniture and loot (`dresser.gd`).** `dress_room(r, house)` (`:37`) sets `dyn.interior_scope = true`, so props go on RENDER_INTERIOR_PROPS with 15–25 m ranges (`dynamics.gd:557-560`).
- **Kind overrides first** (`:72-87`): classroom, clinic, chapel/church, hall/police/outpost/pump. Then by room type: sala, kitchen, bed, cr, store, workshop.
- **Placement:** `_put` and `_wall_slot` check room bounds, the `occ` rects and `dyn.spot_clear`. Spot_clear covers door swings and all clearances, so any door or doorway registered through dyn is protected automatically.
- **Containers:** inside cabinets, with tables drawer, kitchen, wardrobe, under_bed, bathroom, store_counter, store_shelf, toolbox, clinic.
- **Loot boxes:** from `BOXES` (`:13-27`), `[model, box_* table, chance]`.
- **Floor loot:** floor_household, clinic, toolbox.
- **Weapons:** `_weapon_spots` (`:44-57`) rolls floor_weapon with 0.72 chance and up to 2 spots, police/outpost 1.0 and up to 3, a comfort room 0.2 and 1. These chances are hard-coded, not data.
- **Unknown room types** get only weapon spots.
- **Contents:** tables are in `game/data/loot.json` → `tables`. Floor spots are rolled on every machine from the match seed, so ground items 1..floor_count are deterministic. Containers are rolled on the server only (`dynamics.gd:741-771`).

**Lights.** `practical.house(spec, rooms)` (`practical_lights.gd:111`) lights about 45% of houses (stores 75%; clinic, church, hall, police 60%), one or two rooms, using a bulb, tube, lamp or candle and the match seed.

## (c) Big buildings in `sites.gd`

Most sites are `mb.shanty` called with large sizes through `_house(p, ang, w, d, floors, style, kind, front)` (`sites.gd:181-186`; it sets `district: "site"`, `can_overhang: false`, ground +0.1).

| Site | Size | Floors | Style / kind | Extras |
|---|---|---|---|---|
| Chapel | 9×13 | 1 | concrete, chapel, front "open" | — |
| School | 8 classrooms, 13×8 | 1–2 | concrete, classroom | — |
| Hall | 15×11 | 2 | concrete, hall | — |
| Clinic | 13×9 | 1 | concrete, clinic | emergency light |
| Outpost | 6×5 | 1 | chb, outpost | weapon_locker |
| Pump | 16×12 | 2 | concrete, pump | — |
| Church | 18×30 | 1 | concrete, church | bespoke tower |
| Shophouses | w × 10 | 2–3 | concrete, shop, front "store" | store_counter |
| Gas station | 8×5 | 1 | concrete, store | — |
| Apartment | 4 houses of 5.8×8 | 3 | concrete, apartment | — |
| Police | 12×9 | 2 | concrete, police | 2 weapon_lockers |

Even an 18×30 church gets at most front/back rooms and one room per upper floor.

The bespoke structures are geometry plus props with no zones or doors:
- **Warehouse** (`:382`): corrugated walls, `col_box` walls, `_posts_roof`.
- **Market** (`:313`) and covered court: posts, roof, stalls.
- **Container yard and crane** (`:413`), fish port, towers, scrapyard, highway (`:494`).

**There is no generic big-building builder.** The reusable helpers are:
- `_reserve(p, half, ang, margin)`: reserves value 2 and records a footprint check.
- `_free(p, r)`: spot_clear and not inside any building.
- `_boxes(xf, n, half, y, choices)`
- `_slab`
- `_posts_roof(xf, w, d, h, mat, post_mat, spacing)`: an open shed with a collider.
- `_sign`
- `_check_footprints`

## (d) GeoSink (`geo_sink.gd`)

- **Batching:** one mesh per (chunk, material, layer) (`_acc`, `:108`). Layers:
  - "ext" and "inner" use 96 m chunks (`WIDE`, key `w%d,%d`).
  - "int" and "mid" use 48 m chunks (`CHUNK`).
  - Vertex colour carries tint plus paint alpha; UV2 carries (dirt, base_y). A tint does not add a draw call; a new material name does, for every chunk and pass.
- **Ranges and render layers** (`finish`, `:385-483`):
  - **ext:** RENDER_WORLD, ends at 220 m (`draw_ext`). ViewLod sets 220/300/300 by altitude tier, times `view_distance` on the ground (`view_lod.gd:17, 67-81`).
  - **inner:** RENDER_INTERIOR (16), 220 m. Used for inward faces of outer walls, floors and roof undersides, through the `inner_faces` bitmask in `box()`.
  - **int:** RENDER_INTERIOR, 60 m. Partitions, stairs, interior detail.
  - **mid:** RENDER_WORLD, 140 m. Decals cast no shadow.
  - The sky fill skips both Interior layers (`lighting.gd:140`), and ViewLod removes them from the camera in the air.
- **Far blocks:** `far_block(xf, size, col, top_col)` (`:292`) makes a 5-face vertex-coloured box drawn from 220 m to 1900 m, in the same 96 m chunks, crossfading.
- **Collision:** one ConcavePolygonShape3D per (48 m chunk, physical material), backface collision on, StaticBody meta `"mat"` = the physical material. The layer is PHYS_BLOCKER if the material is "blocker", else PHYS_WORLD.
- **Occluders:** one ArrayOccluder3D per 48 m chunk, from boxes with `occlude: true`. Shanty sets it only for walls at least 0.1 m thick and over 1.5 m tall (chb, plaster, concrete).
- **Primitives:**
  - `box(xf, size, mat, opt)`; opts are tint, paint, dirt, base_y, collide (default true), occlude, layer, faces, inner_faces, phys, uv_off, tile, what.
  - `quad(p0..p3, mat, opt)`; opts include facing, double, collide (default false), phys.
  - `corrugated`, `cylinder` (collide default false), `atlas_quad`.
  - `col_box(xf, size, phys, what)`: invisible collision.
- **Mapscan record:** `record` keeps `[xf, size, what]` per collider for the mapscan test.
- **Stats:** `{boxes, tris, meshes, colliders, far_tris}`.
- **Seeded rng:** `sink.rng` (map_seed) is drawn twice per `box()` call without `uv_off`. Order matters, but it is visual only and not part of the fingerprint.

## (e) Terrain, water, roads and textures

- **Terrain** (`map_builder.gd:315-406`):
  - Heights come from `layout.ground_height` on a 2 m grid with `n = HALF·2/2 + 1`. HALF should be a multiple of 2 m.
  - Collision is one HeightMapShape3D with `meta mat = "dirt"`.
  - The mesh is built in 64 m SurfaceTool chunks with no shadows and draws to 900 m.
  - The skirts beyond the edge use `coast_z`, which is slum-specific.
- **Splat map** (`_splat_map`, `:409-432`): 560×560 RGBA8 over 2·HALF. R = mud (near water height), G = grass, B = sand (coast), A = path.
  - The grass rules are hard-coded in Kalinaw's unscaled coordinates, plus the dump.
  - `_paint_lanes` (`:146-189`, skipped on headless) adds noise and paints `alleys` into A (0.85).
  - Ground textures (`:349-351`): dirt=`dirt_floor`, mud=`brown_mud_02`, grass=`sparse_grass`, sand=`coast_sand_01`, path=`stony_dirt_path`.
  - Shader: `ground.gdshader`, with `splat_origin`/`splat_size` set from HALF.
- **Water** (`:441-499`): `water.gdshader` planes at WATER_Y in 96 m tiles. A tile is sea or river depending on `coast_z`. There is also a far sea plane.
  - Water is not a physics surface. Swimming and bullets use `water_height`.
  - The water mask is `layout._water`, rasterised where ground < WATER_Y + 0.05 near the river, estero or sea (`layout.gd:375-384`).
- **Roads** (`:504-537`): `layout.roads[{name, pts, w, mat: asphalt|pavement|gravel, curb}]`.
  - Quads in 6 m steps at `max(ground, WATER_Y+1.2) + 0.06`, colliding as concrete, plus 0.16 m slab edges of `concrete_dirty`. Segments over water are skipped; bridges come from `crossings`.
  - `curb` does nothing (`:536`).
  - Crossing roads sit at the same height, so junctions probably z-fight. This was not checked.
  - The road mask reserves w/2 + 1 m as value 1, walkable for bots.
  - `lighting._street_lamps` puts lamps on roads 6 m or wider, every 38–55 m (see gotcha 1).
- **Materials** (`materials.gd`): `SURFACES[name] = {tex, tile (m), phys, metal, grime, flake}` → `surface.gdshader` loading `res://assets/thirdparty/polyhaven/textures/<tex>/{albedo, normal, roughness, ao}.jpg`.
  - Downloads are done by `python -I tools/fetch_assets.py polyhaven_textures` from `tools/asset_sources.json` (109 sets).
  - Downloaded but not yet in SURFACES, and useful for a suburb: `leafy_grass`, `forest_floor`, `withered_grass`, `beige_wall_001`, `painted_plaster_wall`, `plastered_wall_04`, `floor_tiles_06`, `worn_concrete_floor`, `rough_concrete`, `asphalt_02`, `gravel_floor`, `rough_pine_door`, `wood_shutter`, `box_profile_metal_sheet`, `rusty_metal_grid`, `concrete_block_wall_03`, `raw_plank_wall`, `black_painted_planks`.
  - There is no roof-tile texture.
  - `PAINTS` holds 14 tints.
- **Models** (`model_lib.gd`): `PROPS[name] = {model | path | prim, mass, mat, hp, kind, static, no_collide, trunk, glass, throwable}`. They load from processed copies (`assets/models/polyhaven/<id>.gltf`) and are merged by material with LODs generated.
  - Loot boxes need both `name` and `name_open`.
  - There are no suburban props: no cars (only `covered_car`), mailboxes, fences, hedges or playground items.

## (f) Plugging in a second map

**Slum-specific in `build()`** (`map_builder.gd:63-138`):
- `Layout.new` (the whole geography).
- `_terrain` skirts, `_splat_map`, `_water` (tile range and sea test), `_railway`.
- `Sites.build_all` / `build_crossings` / `_highway`, and `Districts.build_all`.
- `StreetDress` (washing, wires, trash, tricycles and jeepneys; `_water_rubbish` and `_vegetation` use `coast_z` and Kalinaw coordinates).
- `Vandal` (Filipino tags).
- `Looban._vacant_lots`, which runs on any map and places random ruins.

**Generic:**
- Creating mats, models, acoustics, sink, dyn, dresser, lighting and practical.
- `dyn.place_deferred`; `Lagusan` and `Looban` (driven by the `tunnels`, `loobans`, `barricades` and `yard_walls` lists; empty is fine).
- `Entrances` (steps for every raised outer door).
- `PaSystem` (speakers from `pole_tops [[top, along]]`), `practical.porch_lights`.
- `_index_ladders`, `sink.finish`, `dyn.instantiate`, `lighting.build`, `ViewLod`.
- `stats`, `_fingerprint`, `dyn.randomize_for_match`, `_make_map_image`, plus `shanty()`, `warm_up` and the whole facade.

**Fingerprint** (`:192-205`): `"%d buildings, %d doors, %d containers, %d props, #%08x"`, a hash of building, door and prop `xf.origin` and container `pos`, in whole centimetres. Doors, windows, containers and props are referenced by array index over the network, so build order must be deterministic.

**Map image** (`:576-641`): 512×512 over 2·HALF. Land is (0.13, 0.15, 0.13), water (0.07, 0.11, 0.15), roads grey, buildings shown as point grids, tunnels dark, loobans lighter.

**Build stats:**
- Keys: `layout_ms`, `terrain_ms`, `towns_ms`, `finish_ms`, `tunnels`, `looban`, `entrances`, `decals`, `ladders`, `lights`, `buildings`, `sink{}`, `doors`, `windows`, `props`, `zones`, `containers`, `warmed`.
- Printed by `world.gd:75` and `map_preview.gd:55`.
- Kalinaw at scale 0.65 builds in 21–26 s on PC (`PERFORMANCE.md:103`; 2,239 buildings) and 32.6–33.7 s on the phone emulator.
- `opts` accepts `{districts, only: [names], dress, record}`.

## Recommended way to add Lawless Sub

1. **Map selection.** Add `Net.config.map` (e.g. "kalinaw" or "lawless_sub") and switch on it in `world.gd:73` and `tools/map_preview.gd:52`. Put the map id into the fingerprint string.
2. **`world/maps/lawless_sub/sub_layout.gd`**, a RefCounted with the same members as plain `var`s:
   - Values: `MAP_SCALE = 1.0`, `HALF` (a multiple of 2), `PLAY_HALF`, `WATER_Y`, `LAND_Y`, `GRID = 2.0`, `rng`, `roads`, `landmarks`.
   - Empty lists: `districts`, `sites`, `crossings`, `railway`.
   - The arrays `_n`, `_water`, `_reserved`.
   - Methods: `ground_height`, `is_water`, `water_height`, `in_play_area`, `coast_z` (return a value far off-map), `rect_free`, `reserve_rect`, and static `seg_dist`/`poly_dist` (copy them from layout.gd or move them to a shared base).
   - Carve canals in `ground_height` and rasterise them into `_water`.
   - Author the plan as data (for example `game/data/maps/lawless_sub.json`): road polylines, canals, lots, big buildings, parks, parking lots.
3. **`sub_builder.gd extends "res://src/world/map_builder.gd"`.** It inherits every registry, `shanty()`, the facade, `warm_up`, `ladders_near`, `_paint_lanes`, `_fingerprint` and the map image. Override `build()` with the same pipeline order:
   1. terrain and water;
   2. roads, then big buildings (reserve value 2), then houses (reserve value 3);
   3. `dyn.place_deferred()`;
   4. Entrances, then a suburban street dressing (append to `pole_tops` for the PA, build lamp geometry here, before finish);
   5. `sink.finish()`, `dyn.instantiate()`, `lighting.build()`, `ViewLod`;
   6. fingerprint, randomize, map image.

   Also override `_splat_map` (lawns in G, driveways in A), `_terrain` (no coast skirts), `_water` (sample the mask per cell) and `_make_map_image` (filled footprints). Name constants differently from the parent's; Godot 4 refuses to shadow them. Kalinaw's code, and so its fingerprint, stays untouched.
4. **Houses.** Placing through `Districts.new(self).place(center, front2d, w, d, opts)` gives plinths, a validated lot and a lot reservation for free. Hand-placed lots need about 1 m of margin from roads, because the road mask is w/2 + 1.

   Shanty is a Filipino informal-house generator, though: 2–4 rooms, patchwork walls, tyres on the roof. For real suburban interiors, extract `_walls`, `_wall_piece`, `_opening`, a generalised partition (any segment, with openings), `_stair`, `_upper_floor`, `_roof_infill`, `_ladder` and `_aabb` into a `building_kit.gd`. Pass the per-building rng in and keep the call order, so Kalinaw stays identical. Then write `house_plan.gd`, which takes explicit room rectangles per floor, interior walls with doors, exterior windows (with `vault: true` sizes), a stair and a roof. It returns the same `out` dictionary and is registered through a split-out `MapBuilder._register_building(spec, out)` that does the buildings record, far block, dresser, rooms and lights.

   With axis-aligned houses and concrete or plaster walls (≥ 0.1 m thick, so they occlude), the dresser, practical lights, bots and mapscan all work unchanged. The dresser needs new routines for garage, office, convenience-store aisles (rows of `steel_shelves` with `store_shelf` containers) and the factory floor.
5. **Big buildings** (convenience store, factory) go through the same kit with several zones and doors. Give them Interior-layer inner faces, a `sink.far_block`, at least one door with `outer: true` and `outward` set (bots need it), and their containers' `bid` set.
6. **Performance.** Keep a small palette per chunk (about 10–12 surfaces) and vary colour with `tint`/`paint`. Put interiors on `int`/`inner`. Use thick occluding walls. Keep MultiMesh-friendly props (one material each). Validate with `--autotest=mapscan` and `map_preview --perf`. Any 100 fps target on phones also means lifting the 60 fps cap.