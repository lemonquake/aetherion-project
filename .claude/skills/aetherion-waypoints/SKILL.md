---
name: aetherion-waypoints
description: How Aetherion Project makes, edits, bakes and proves the bot waypoint graph on a map (game/src/ai/waypoints.gd, game/data/waypoints/<map>.json). Use when adding a new map, changing a map's geometry, fixing bots that get stuck, walk into walls, miss a bridge or a floor, or when the user asks about bot pathing, waypoints, bot routes, hiding or sniping spots.
---

# Bot waypoints in Aetherion Project

Bots walk a **waypoint graph** on every map. They go node to node along **edges that were proven** by sweeping a
body-sized cylinder through the real collision. A bot that keeps to its edge cannot touch a wall. The full reference
is `docs/WAYPOINTS.md`; this skill is the working procedure.

## The pieces

| Path | What |
|---|---|
| `game/src/ai/waypoints.gd` | The graph: generation, proof of each edge, routes (AStar3D with priority weights), edges closed when bots get stuck, the file |
| `game/src/ai/bot_nav.gd` | BotNav: the walk check of the layout's walk grids and the hiding and sniping spot survey the graph starts from |
| `game/src/ai/nav_levels.gd` / `nav_grid.gd` | Walk grids: per level on storeyed maps (layout has `nav_open`), one 2 m grid on flat maps |
| `game/data/waypoints/<map>.json` | The shipped graph (`source` auto or edited) |
| `game/data/botnav/<map>.json` | The shipped BotNav bake (walk check, spots) |
| `game/src/debug/waypoint_qa.gd` | `--wpqa=<dir>`: the strict check and a picture per level |
| `game/addons/aetherion_waypoints/` | The Godot waypoint editor (a `Waypoints` node in any map editor scene) |
| `tools/bake_botnav.sh` | Bakes BotNav and the waypoints for one map or all |

## What a good graph has

- **Ids**: `<CODE><level>-<number>` such as `MM3-0412`. The code comes from `CODES` in `waypoints.gd` for the built-in maps,
  or from the map file's `"code"` for a map made in the map editor (two capital letters). Hand-made waypoints are
  numbered from 9001.
- **Kinds**: road (middle line of a corridor or street), junction, plaza, bridge, area, corner, door (1.1 m either side
  of a door, on its centre line), stair, escalator, and the held places hide, snipe, cover (with a facing).
- **Priority**: 1 main road, 2 secondary, 3 side way or dead end. Generated from 400 sample routes. Routes cost 15% more
  through priority 2 and 35% more through priority 3, so bots keep to main roads the way players do.
- **Edges**: walk (sweep radius 0.40 m passed), tight (only 0.31 m passed, costs more), door (straight through the
  middle of the leaf, the bot opens it), stair, escalator (one way), wade (shallow water, 4x cost).
- Coverage: no walkable cell far from a waypoint it can see. 500 of 500 sample routes found. Zero edges failing a fresh
  sweep. Those are the r23 numbers every map reached; a new map must reach them too.

## Making the graph for a map

1. **The map must give the bots what they need** before any waypoint work:
   - Storeyed maps: a walk grid per level (`nav_open`) and the stairs as links (`nav_links`). Maps from the map
     editor get both from their pieces: every `stairs` piece is a link, every level in `"levels"` is a grid.
   - Team spawns on open floor (the walk grid is flood-filled from the spawns and stair ends; floor nobody can reach
     is dropped, which is right for roofs and container tops).
   - Designated spots: `designated_spots()` on the layout, or `spot` pieces in a map-editor map (kind hide or snipe,
     a `face` point to watch, a name).
2. **Bake**: `bash tools/bake_botnav.sh <map_id>` (Git Bash, from the repo root). It runs a headless server with two bots,
   writes `game/data/botnav/<map>.json` and `game/data/waypoints/<map>.json`, and logs to `tools/cache/botnav_<map>.log`.
   Two bakes at once need different `BAKE_PORT`s. Kalinaw's edge generation alone takes about 130 s.
3. **Strict check** (must pass before saying the graph works):
   ```bash
   godot --headless --path game -- --server --game_mode=deathmatch --map=<map_id> --bots=2 --autostart=1 --expect_players=0 --wpqa=work/<run>/wpqa_<map_id>
   ```
   Read `<map_id>_qa.json` in that folder: coverage of walkable cells, routes found out of 500, edges failing the fresh
   sweep, unjoined sets. Look at the per-level pictures, do not trust the numbers alone.
4. **Watch bots** on the map: a 10-minute headless match with `--navwatch` (stall share of walking time, stall events per
   bot-minute, share on graph edges). Compare with `--waypoints_off` for an A/B. Match-to-match noise is large: run twice
   before claiming a gain.

`godot` above means `A:\Installer\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe`.

## Editing waypoints by hand

Any map editor scene can hold a `Waypoints` node (`addons/aetherion_waypoints/waypoint_set.gd`): the mall has
`res://editor/malasugue_mall_editor.tscn`, maps made in the map editor get one in `res://editor/maps/<map_id>.tscn`.

- Select **Waypoints** > **Load the game's waypoints**. Set **Show Level** to the floor you edit.
- **Shift + click** a floor: new waypoint joined to the selected one (a chain). Move with the gizmo, Ctrl+D copies with
  joins, Delete removes.
- Toolbar **Link** / **Unlink**. Inspector: Kind, Priority, Place Name, Faces (turn the node; the blue arrow is where
  a hide / snipe / cover bot looks).
- **Save for the game** writes `game/data/waypoints/<map>.json` as `source: edited`. An edited graph is never
  regenerated. When it has not been checked against the current geometry, the game proves every edge on load, drops the
  ones that fail and says which.
- **Check in game** saves, runs the game headless with `--wpcheck` and prints dropped joins (red), waypoints where a body
  does not fit, and waypoints not joined to the rest. About 20 seconds.
- **Generate again** replaces everything (edits lost; it asks).

Line colours: white walk, orange tight, cyan door, magenta stairs and escalators, blue wade, red dropped by the last
check.

## After any geometry change

The file's `key` is the map's geometry (map id, fingerprint, walk grids), not the game version.

- An **auto** graph is made again when the key changes, so re-bake and ship the new file:
  `bash tools/bake_botnav.sh <map_id>`, then the strict check.
- An **edited** graph is kept, and the game re-proves it on load. Still run Check in game (or the strict check) and fix
  what it drops: a wall moved across a join, a doorway narrowed, a stair moved.
- For maps made in the map editor, the map file's content hash is part of the fingerprint, so any saved edit changes the key.

## Diagnosing stuck bots

1. Reproduce with `--navwatch` or `--bottrace=first` on a headless match and find where the stall events cluster.
2. Check the graph there: is there a waypoint? Is the edge tight? Did the strict check drop an edge nearby?
3. Typical causes found before: a crossing not on the walk grid (Kalinaw's bridges), a door edge off the leaf's centre,
   waypoint spacing blocked by a wall in the next aisle, a stuck edge closed with no other way (bridges and single
   doorways are never closed now), a start check wider than the body.
4. Fix the map or the graph, not the symptom. Re-bake, strict check, then a match with `--navwatch` before and after.

## Gotchas

- `tools/check.sh` does not compile `addons/` scripts. Test the editor scripts with
  `godot --headless --path game -s res://tools/waypoint_editor_test.gd`.
- `bot_brain.gd` has CRLF line endings. Patch it with a Python script that keeps them (see `tools/patches/`).
- Opening the Godot editor rewrites many `.import` files. That is Godot's own churn: do not commit it.
- Props that move each match (Kalinaw) make a few edges fail a fresh sweep. That is expected; the game blocks those
  edges when bots get stuck on them.
- A graph is only as good as the collision. If bots walk through something, the thing has no collision; if they refuse
  a gap, the gap is narrower than 0.62 m at body height.
