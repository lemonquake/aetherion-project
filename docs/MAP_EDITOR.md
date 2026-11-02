# The map editor (r26)

Aetherion maps are now **map files** you open and edit in Godot: `game/maps/<id>/map.json`. Every wall, floor, stair,
light, spawn and prop is one piece you can see, select, move, resize and set. The game builds the map from the same
file, with the same materials, collision, lamps, doors and bot navigation as the other maps. QA notes you pin on the
map are saved next to it for Claude to read, fix and answer.

The first map made this way is **Hidden Forest** (`hidden_forest`, r27, below).

## Open a map

1. Open the project in Godot 4.7 (`game/`). The **Aetherion Map Editor** plugin is on.
2. In the **Maps** dock (top left, beside Scene and Import) double-click a map. Its scene opens with every piece under
   its layer (Ground, Temple, Heart, Lights, Spawns...). Lamps light the view; tick **Night Preview**
   on the root node to see it at night.
3. **Show Level** on the root hides everything above a floor so you can work inside a building.

## Edit

- **Click** a wall, floor or anything else to select its piece. The outline turns orange.
- **Move / turn** with Godot's gizmo (W / E). Only the turn about the vertical is kept (tilt a box with its Tilt field).
  **Scaling** a box, floor or wall changes its size.
- **Orange handles** on the selected piece: a wall's two ends and its height; a box's width, height, depth; a floor's
  width and depth; the rise of stairs and ramps. 5 cm steps, Shift for 1 cm.
- **Inspector**: everything else, such as textures (pick from the list), thickness, openings in walls (doors and
  windows: where along the wall, width, height, sill, a door leaf), a light's colour, brightness, reach and fault, a
  spawn's team, a prop's model.
- **3D toolbar**: **Add piece** (where the middle of the view points), **Draw walls** (click where a wall starts, click
  where it ends, keep clicking for the next one; right click or Esc ends), **Save map**, **Play**.
- Ctrl+D copies a piece, Delete removes it, Ctrl+Z undoes, as anywhere in Godot.
- **Save**: Save map, or Ctrl+S. Both write `map.json`.

If the file changes on disk while the map is open (Claude working on it), the editor reloads it by itself, unless you
have unsaved edits. Then it warns you instead: **Save map** keeps yours, **Reload from file** takes the file's.

## Pin QA notes

1. **Pin a note** in the 3D toolbar, then click the exact spot.
2. Write what is wrong or what should change in the Inspector's **Text**. Be as exact as you like: "this step is too
   high", "the doorway should face the court", "the bulb here is too bright".
3. Save. Notes go to `game/maps/<id>/qa.json`. Red: open, amber: a question, green: fixed, grey: won't fix.
4. Claude fixes them, sets the status and writes a **Reply** saying what changed. The Maps dock lists the open map's
   notes: click one to select it, then F in the 3D view to go to it.

## Play it

**Play** (toolbar or root node) saves the map and starts the game on it as host with bots. From a terminal:

```bash
godot --path game -- --host --game_mode=deathmatch --map=hidden_forest --bots=11 --autostart=1
```

Editor maps are Deathmatch maps (the file's `modes`). Hosts pick them in the lobby like the others.

## The bots

After geometry changes, the bots' waypoints are baked again (the root node's **Bake the bots' waypoints**, or
`bash tools/bake_botnav.sh hidden_forest`) and checked. The editor scene's **Waypoints** node edits the graph by hand
(see `docs/WAYPOINTS.md`).

## For Claude

The procedure, the format and the checks are in the `aetherion-map-editor` skill (`.claude/skills/`); the format's
full spec is the doc comment at the top of `game/src/world/maps/authored/map_doc.gd`. Plan pictures:
`python -I tools/map_plan.py <id>` writes `work/maps/<id>/plan.png` (every piece's id, spawns, lights, notes).

## Checks (r26)

| Check | Result |
|---|---|
| `map_doc_test` (format, build, survey; a self-made two-storey map with a door, stacked openings, stairs) | 13 / 13 |
| Editor self-test in the real Godot editor (open, save unchanged, move, turn, scale, wall length, click picking, QA note) | 8 / 8 |
| Freight Delight after its layout moved into the shared one | its shipped graph still matches (not regenerated), 100% of 34,218 cells |
| `tools/check.sh` | 196 scripts, 0 failed |

## Uneven ground: Terrain3D (r27)

From 2026-11-02 every map with uneven ground uses **Terrain3D** (`game/addons/terrain_3d/`, built from the source kept
at `A:\Python\terrain`), together with the map editor. The map file names the ground in its header (`"terrain"`: data
folder, vertex spacing, region size); the pieces stand on it.

- **Sculpt, paint and plant it in Godot**: open the map's editor scene, select the **Terrain3D** node; Terrain3D's own
  toolbar (raise, lower, smooth, flatten, paint textures, spray ground cover) and its asset dock appear. The texture
  sets and ground-cover meshes are in `game/maps/<id>/terrain/assets.tres`.
- **Save map** (or Ctrl+S) also writes the Terrain3D regions and **bakes the heights** (`terrain/heights.res`). The
  game collides with that heightfield on every machine (a dedicated server needs no extension), the bots survey it
  and `ground_height()` reads it. After sculpting, bake the bots' waypoints again.
- Keep the floor people walk on within about 0.3 m of a level's height and no steeper than about 39 degrees: that is
  what the bots' walk grid takes as floor. Steeper ground (banks, cliffs) is a wall to them.
- In the game the ground and its plants are drawn on the render layer lamps leave out of their shadow maps; on
  phones Terrain3D's lightweight shader is used and the ground cover is drawn 60% as far.

## New pieces and fields (r27)

| Piece / field | What |
|---|---|
| `vines` | Hanging strands along a line: from, to (x, y, z), drop (longest strand), density (a metre), sag, w, seed. The game merges them into one mesh per 32 m |
| light kind `torch` / `brazier` | An open fire: a drawn, animated flame and glow, a fire flicker. `mount` pole / wall / stand / bowl / none is what it burns on, `pole` the flame's height on a pole |
| light `minor` | On phones only the flame, no light (the Mobile renderer lights a mesh with at most 8 lights) |
| prop `foot`, `foot_h` | An invisible collider round a prop's base (a radius, or [w, d]), seen by the bots' walk grid: trees, rocks and statues keep no collision of their own |
| header `fireflies` | How many fireflies drift over every landmark (half on phones) |

## Hidden Forest (r27)

The first map made this way: an ancient city swallowed by the jungle, always at night (`hidden_forest`, code HF,
three teams of up to seven). The jungle floor is carved into clearings and trails between steep earth banks; temple
tops, terraces, the ball court's platforms and a rope bridge are the upper level (4 m).

- **Temple of the Sun** (north): a four-tier pyramid, twin red and white shrines on top, serpent heads at the stair.
  Team 3 waits behind it.
- **Serpent Wall** (north-west): ruined rooms behind a wall of carved scales. **Moon Well** (north-east): a sinkhole
  in a ring of shrines, vines hanging into it.
- **Heart of the Forest** (centre): a pyramid with a tunnel and a crypt through its base, the sun stone on top, a
  rope bridge to a lookout over the east trail.
- **Ball Court** (east), **Observatory** (west, a round tower), **Temazcal** (south-west, steam-bath huts),
  **Court of Skulls** (south: a plaza under terraces, the skull rack), **Jade Shrine** (south-east).
- **Eagle Gate** (Team 1, west) and **Jaguar Gate** (Team 2, east). Narrow hidden paths cut between the areas, two
  under giant strangler-fig roots.

Made with: `work/hf/build_hidden_forest.py` (the first draft of the map file, the ground's heights, texture map and
ground cover), `game/tools/terrain_import.gd` (writes the draft into Terrain3D), `tools/make_jungle_textures.py`,
`tools/blender/process_hf.py` + `tools/hf_jpeg_textures.py` (models: Sketchfab CC-BY statues and trees, Poly Haven
rocks and plants). Evidence: `work/hf/`.
