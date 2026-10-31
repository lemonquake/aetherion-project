# Freight Delight

A Deathmatch map for two teams of up to 12: a squatter settlement that grew inside an old container yard by the
port, always at night. It is the first Aetherion map made with a mapping tool instead of generated from code, so it can
be edited by hand in TrenchBroom and in Godot.

The original `work/custom_map.bsp` was a copy of Valve's `de_dust.bsp` (byte for byte). Freight Delight does not reuse
its geometry or textures: the layout, the pathways and every texture are new.

## The map

About 124 x 84 m of play area (x east, z south; metres).

- **West Team** spawns on the fish pier (Pantalan 3) under the fish-landing shed. **East Team** spawns at the truck
  gate, round the weighbridge and the trailer. The two are about 110 m apart.
- **North lane: the Container Canyon.** It runs between the yard's three-high perimeter stack and the inner row. Single
  containers jut out from both sides and turn it into a zig-zag. Two of them are open homes you can walk into.
- **Middle lane.** The **Bodega** (warehouse: racks, sacks, a mezzanine) opens on the pier side. Next comes the
  **plaza** under the old gantry crane: a sari-sari store, the videoke shack, a basketball ring, the Sto. Niño shrine,
  containers and sandbags as cover. Then the **Talyer** (repair shop, open to the plaza), which opens on the gate side.
- **South lane: the Eskinita.** Three rows of shanties with alleys between them (Alley A by the Bodega and Talyer,
  Alley B behind the Taas, Alley C by the estero). Some shanties are walk-throughs. There is a courtyard with a hand pump.
- **Between the lanes.** There are two ground passages under the inner row, plus a walk-through home that cuts across
  it. The transition yards north of the Bodega and the Talyer also connect the lanes. So do the Taas's two covered
  passages (lagusan) and the shanty doors onto the plaza.
- **The second floor (3.2 m)** is one connected network:
  - the inner row's roof deck, with rooftop shacks, parapets, laundry and balconies over the canyon
  - Bridge A from the deck to the Bodega mezzanine
  - the plaza bridges to the crane's platform and on to the **Taas**, the two-storey row house whose windows look over
    the plaza
  - the container leg by the Talyer
- **Three stairs reach the second floor:**
  - **Stair A** (west) is inside the Bodega, up its west wall to the mezzanine.
  - **Stair B** (east) is a steel stair up the container leg north of the Talyer.
  - **Stair C** (south) is a timber stair in Alley B, up to the Taas's back balcony.
- Night only. The moon is thin and the haze is thick (`night_grade` in the layout). The light comes from the lamps:
  sodium floodlights on the poles and the crane, bare bulbs on wires (some flicker, some are dying), fluorescent tubes
  with bad starters, neon at the videoke, and candles at the shrines.
- The Deathmatch field is off by default. The host can turn it on, and it then stops at half its radius, as in the mall.
  Picking the map sets 12 players per team. Teams are fixed at 2.

## Files

| Path | What |
|---|---|
| `game/assets/maps/freight_delight.map` | **The map source** (TrenchBroom, Valve 220 format, 32 units per metre), organised in TrenchBroom layers and groups |
| `game/assets/maps/freight_delight.tscn` | The Godot scene the game loads: the imported map, an `Extras` node for anything you add in Godot, and an editor-only night preview |
| `game/assets/maps/textures/freight/*.png` | Albedo textures (what TrenchBroom shows); `normals/` and `roughness/` hold the matching maps |
| `game/assets/maps/surfaces.json` | Per texture: physical surface (bullets, footsteps), roughness, metal, emission, alpha, size |
| `game/addons/aetherion_map/` | The Godot importer: `.map` to scene |
| `game/src/world/maps/freight_delight/freight_layout.gd` | The game side: spawns, landmarks, stairs, the bots' walk grids, the minimap |
| `tools/trenchbroom/Aetherion/` | TrenchBroom game configuration (`GameConfig.cfg`, `Aetherion.fgd`, icon) |
| `tools/make_freight_textures.py` | Draws every texture (noise and shapes; nothing downloaded) |
| `tools/make_freight_map.py` | Wrote the first version of the map. It refuses to overwrite a map edited since (`--force` starts over) |

## Editing in TrenchBroom

1. Install TrenchBroom (2024.1 or later) from https://trenchbroom.github.io.
2. Install the game configuration:
   ```
   powershell -ExecutionPolicy Bypass -File tools\trenchbroom\install.ps1
   ```
3. In TrenchBroom go to Preferences > Aetherion and set the **Game Path** to `game\assets\maps` (the folder that holds
   `textures`).
4. Open `game/assets/maps/freight_delight.map`. Use the layers (Ground, Perimeter, Clip, each district, Inner row and
   deck, Lights, Spawns, Landmarks) to hide what you are not working on. Each building is a group.
5. Save. When Godot gets focus again it re-imports the map. Every scene that uses it, and the next match, shows the
   change.

Conventions:

- **Grid and floors.** 32 units = 1 m, and the ground is at z = 0. The second floor is at **102 units (3.2 m)**. Keep
  walkable second-floor surfaces at that height, because the bots' second-floor grid is surveyed there. Risers up to
  11 units (0.36 m) are walked up without a jump. Keep sloped roofs off the 86 to 117 unit band (2.7 to 3.65 m), or they
  count as floor.
- **Brush entities.** `func_detail` is drawn and solid, like the world. `func_illusionary` is drawn but has no collision
  (wires, laundry, scenery past the clip). `func_stairs` holds the steps of a stair flight: the game finds its foot and
  top and links the two floors there for the bots. Any new stair to the second floor should be a `func_stairs`.
- **Stair ramps.** A `func_stairs` is drawn only: feet would snag on every riser. The game's own stairs work the same
  way. What bodies walk on is a sloped brush over the step nosings, outside the `func_stairs`, textured
  `freight/clip_concrete`, `clip_wood` or `clip_steel`. It is invisible but solid, and footsteps and bullets match the
  steps. It runs from one tread before the first riser, at the floor, to the landing's edge (about 35°). A new stair
  needs one.
- **Tool textures.** `freight/clip` is invisible and stops bodies but not bullets; the play-area bounds use it.
  `freight/clip_<surface>` is invisible and fully solid (stair ramps).
  `freight/skip` is not drawn and not solid; use it for faces nobody sees.
- **Lights.** Use a `light` entity with a kind (bulb, tube, lamp, flood, street, candle), colour, energy, range and fault
  (flicker, dying, starter, sag, candle). Tubes lie along their yaw. Floods aim with yaw, pitch and cone. In a match the
  game takes them over: faults animate, distant lamps switch off, and shadows go to the nearest.
- **Spawns.** Use `info_team_spawn` with team 1 (West Team) or 2 (East Team). Put at least 12 per team, about 2 m
  apart, on open floor.
- **Landmarks.** An `info_landmark` names a place on the SmarTab map.
- **New textures.** Add a PNG under `game/assets/maps/textures/freight/`, and an entry in `surfaces.json` for its physical
  surface and size (otherwise it counts as concrete, 2 m). Then run `tools/import.sh`.

## Editing in Godot

Open `res://assets/maps/freight_delight.tscn`. The brushes come from the `.map`, so change their shape in TrenchBroom.
Anything you add under `Extras` is part of the map in a match:

- a `Light3D` becomes a game lamp. Give it the metadata `kind` and `fault` if you want a fitting or a fault.
- a `Marker3D` with the metadata `team` (1 or 2) is a spawn point.
- a `Marker3D` with the metadata `landmark` names a place on the SmarTab map.
- meshes and `StaticBody3D` collision are used as they are. A body needs collision layer 1 (World) and metadata
  `mat` (concrete, steel, wood...) for footsteps and bullets.

The `EditorPreview` node (night sky, moon) is only for looking at the map in the editor. The game removes it and uses
its own lighting.

To replace a generated material, save a material as `res://assets/maps/materials/freight/<name>.tres` and re-import the
map (FileSystem dock > `freight_delight.map` > Reimport).

## Testing

`--autotest=freight` checks the build (spawns, stair links, walk grids, the bots' waypoints on both floors, the
lamps). It walks the player up each stair. Then it sends one bot on a tour of 26 places across both floors: every
stair top, the deck, the crane platform, the Taas rooms and balcony, the container homes, the Bodega, the Talyer, the
canyon, the alleys and both spawns. Each leg must arrive in time without the bot stalling against a wall. Results go to
`<shots>/freight_routes.json`.

```bash
godot --path game -- --host --game_mode=deathmatch --map=freight_delight --bots=23 --autostart=1 --autotest=freight --shots=work/freight_test
godot --path game -- --host --game_mode=deathmatch --map=freight_delight --bots=23 --autostart=1
godot --headless --path game -- --server --game_mode=deathmatch --map=freight_delight --team_size=12 --bots=24 --expect_players=0 --autostart=1 --matchlog --end_after=300 --quit_after_results
godot --headless --path game res://tools/map_preview.tscn -- --map=freight_delight --mmstats --mapimg=work/freight_mapimg.png
godot --path game res://tools/map_preview.tscn -- --map=freight_delight --out=work/freight_shots --cams="plaza:-14,1.7,-9,0,3.5,2"
python -I tools/make_freight_textures.py --sheet          # redraw the textures (and a contact sheet in work/)
```
