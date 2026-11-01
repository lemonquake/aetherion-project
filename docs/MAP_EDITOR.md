# The map editor (r26)

Aetherion maps are now **map files** you open and edit in Godot: `game/maps/<id>/map.json`. Every wall, floor, stair,
light, spawn and prop is one piece you can see, select, move, resize and set. The game builds the map from the same
file, with the same materials, collision, lamps, doors and bot navigation as the other maps. QA notes you pin on the
map are saved next to it for Claude to read, fix and answer.

The first map made this way is **San Roque Covered Court** (`covered_court`): a barangay's covered basketball court,
the two-storey Barangay Hall with a balcony over the court, a sari-sari store, the kapilya, the tricycle terminal and
an eskinita of small houses. West Team spawns at the terminal, East Team behind the kapilya.

## Open a map

1. Open the project in Godot 4.7 (`game/`). The **Aetherion Map Editor** plugin is on.
2. In the **Maps** dock (top left, beside Scene and Import) double-click a map. Its scene opens with every piece under
   its layer (Ground, Court, Barangay Hall, Eskinita, Lights, Spawns...). Lamps light the view; tick **Night Preview**
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
godot --path game -- --host --game_mode=deathmatch --map=covered_court --bots=11 --autostart=1
```

Editor maps are Deathmatch maps (the file's `modes`). Hosts pick them in the lobby like the others.

## The bots

After geometry changes, the bots' waypoints are baked again (the root node's **Bake the bots' waypoints**, or
`bash tools/bake_botnav.sh covered_court`) and checked. The editor scene's **Waypoints** node edits the graph by hand
(see `docs/WAYPOINTS.md`).

## For Claude

The procedure, the format and the checks are in the `aetherion-map-editor` skill (`.claude/skills/`); the format's
full spec is the doc comment at the top of `game/src/world/maps/authored/map_doc.gd`. Plan pictures:
`python -I tools/map_plan.py <id>` writes `work/maps/<id>/plan.png` (every piece's id, spawns, lights, notes).

## Checks (r26)

| Check | Result |
|---|---|
| `map_doc_test` (format, build, survey; a self-made two-storey map with a door, stacked openings, stairs) | 13 / 13 |
| `map_doc_test --map=covered_court` (443 pieces: 655 brushes, 39 lamps, 20 doors, 40 props) | 8 / 8, built in about 0.5 s |
| Editor self-test in the real Godot editor (open, save unchanged, move, turn, scale, wall length, click picking, QA note) | 8 / 8 |
| Bots' waypoints on Covered Court (`--wpqa`) | 638 waypoints, 100% of 19,231 walkable cells, 498 / 498 routes, 0 edges failing, 0 blocked, 0 orphans |
| 5-minute Deathmatch, 12 bots (`--navwatch`) | 6 rounds, no script errors, 95% of walking on proven edges; 8 stalls (6.7% of moving time), in the lane south of the bleachers and at house doors: still to look at |
| Freight Delight after its layout moved into the shared one | its shipped graph still matches (not regenerated), 100% of 34,218 cells |
| `tools/check.sh` | 196 scripts, 0 failed |
