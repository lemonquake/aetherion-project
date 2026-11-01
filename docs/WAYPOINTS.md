# Bot waypoints (r23, 0.23.0)

Bots walk a **waypoint graph** on every map: they go from waypoint to waypoint along **edges that were proven** by
sweeping a body-sized cylinder along them through the real collision. A bot that keeps to its edge cannot touch a wall.
Before this, bots walked straight lines that the walk grid merely allowed (`NavLevels` / `NavGrid`), and the grid did
not know every wall, shelf or bridge.

| File | What it is |
|---|---|
| `game/src/ai/waypoints.gd` | The graph: generation, the proof of each edge, routes, edges closed when bots get stuck, the file |
| `game/src/ai/bot_brain.gd` | Bots ask `Waypoints.route()` for their path, steer along the edge, open doors on door edges, report stuck edges |
| `game/data/waypoints/<map>.json` | The shipped graph of each map (made by `tools/bake_botnav.sh`, or saved by a map editor) |
| `game/src/debug/waypoint_qa.gd` | `--wpqa=<dir>`: the strict check (coverage, edges, routes) and a picture per level |
| `game/addons/aetherion_waypoints/` | The Godot editor plugin: waypoints as nodes, Shift+click to add, Link / Unlink, Save, Check in game |
| `game/editor/malasugue_mall_editor.tscn` | **Malasugue Mall's map editor** (open it in Godot) |
| `game/tools/mall_preview_export.tscn` | Makes the mall geometry the editor shows (`editor/malasugue_mall/mall_preview.scn`) |
| `game/tools/waypoint_editor_test.gd` | Round trip of the editor scripts (load, edit, save, the game reads it) |

## Waypoints

Every waypoint has an **id** (`MM3-0412`: map code, level, number; MM mall, FD Freight Delight, LS Lawless Sub, SK
Sitio Kalinaw), a **kind**, a **priority** and a **place name** (the shop or landmark it is in, with the level).

| Kind | Where |
|---|---|
| road | the middle line of a corridor, lane or street (the cells farthest from any wall): every 3.5 m indoors, 8 m outdoors |
| junction | a road where three or more roads meet |
| plaza | a road in an open court (5 m or more from every wall) |
| bridge | along every crossing's deck (Sitio Kalinaw's river bridges, estero planks, the culvert) |
| area / corner | filling the rest so no open cell is far from a waypoint it can see (corner: beside a wall) |
| door | 1.1 m either side of a door, on its centre line |
| stair / escalator | the ends and points of every stair flight and escalator |
| hide / snipe / cover | the map's designated places and the best hiding and sniping spots, each with the way it watches |

**Priority** 1 = main road, 2 = secondary, 3 = side way or dead end. It comes from traffic: 400 sample routes across
the map, the most used 15% are main roads, the next 35% secondary. Routes prefer high priorities (crossing a priority-2
waypoint costs 15% more, priority 3 35% more), so bots keep to the main roads the way players do. The map editor can
set any waypoint's priority by hand.

## Edges (the proof)

An edge joins two waypoints a body can walk between in a straight line:

- storeyed maps (mall, Freight): the walk grid's cells under a body-wide band are open (or, in a 1 m aisle between
  shelves, the cells on the line), and a cylinder of radius **0.40 m** (body 0.30 m + 0.10 m margin) from step height
  to head height swept from one to the other meets nothing; where only the body itself fits (radius 0.31 m), the edge
  is **tight** and costs more;
- flat maps (Kalinaw, Lawless Sub): the same sweep, following the ground (a floor every metre, no step over 0.5 m, no
  deep water; shallow water makes a **wade** edge, four times the cost);
- an edge crossing a doorway must go straight through the middle of the leaf (a **door** edge: the bot opens it);
- stairs and escalators are joined in their order (escalators one way).

Each waypoint joins its nearest proven neighbour in each of 12 directions (up to 8 m indoors, 16 m outdoors). Sets of
waypoints left apart from the main graph are joined by threading waypoints along the walk grid's own path to it; what
still cannot join is too narrow for a body (the grid's mistake, not a way in).

## How bots use it

1. `_set_goal` keeps the goal where it is (the grid's region test used to pull goals across Kalinaw's river back to
   the near bank).
2. `Waypoints.route(from, goal)`: the nearest waypoint the bot can walk straight to (swept), A* over the graph
   (`AStar3D`, priority weights), to a waypoint the goal is in plain sight of, then the goal. Goal out of sight of every
   waypoint: the route ends at the nearest one (the bot stops there instead of pushing at a wall). Bot somewhere no
   waypoint is in plain sight (pushed into a corner): a grid path to the nearest waypoint first.
3. `_move`: the bot steers for a point a metre ahead of itself **on the edge**, not for the edge's end, so it keeps to
   the swept line. A waypoint counts as reached at 0.45 m, or at 1.2 m when the sweep to the next one is clear. Pushed
   more than 1.8 m off the edge (a crowd, a fight) for a second, it plans again from where it is.
4. A door edge: the bot faces the door, opens it from outside its swing and waits for it; a locked door closes that
   edge for two minutes and the bot routes round it.
5. Stuck on an edge for 3.2 s: the edge closes for every bot for 45 s (the third report in a match: for the rest of
   it) and is remembered (`user://waypoints/<map>_learn.json`: such edges cost more next match, fading by a fifth a load).

`--waypoints_off` turns the graph off (bots walk the grid paths as in 0.22.0) for A/B tests.

## The file

`res://data/waypoints/<map>.json`: `{format, map, key, source, verified, nodes: [{id, p, lv, k, pri, n?, d?, via?}],
edges: [[a, b, code]]}` (`a`, `b`: node indices, or ids in an edited file; code `w` walk, `t` tight, `d<door>` door,
`s` stair, `e` escalator, `v` wade).

- `key` is the map's geometry (map id, fingerprint, walk grids), not the game version: version bumps keep the file.
- `source` **auto** (made by the generator): made again when the geometry changes.
  **edited** (saved by a map editor): always kept; when it has not been checked against today's geometry (`verified`),
  the game proves every edge when it loads it, drops the ones that fail (and says which and why), and keeps a checked
  copy in `user://waypoints/`.

```bash
bash tools/bake_botnav.sh                     # every map: BotNav + waypoints (an edited graph is kept, re-checked)
bash tools/bake_botnav.sh malasugue_mall      # one map
# the strict check: coverage, edges swept again, 500 routes, pictures per level (in <dir>)
godot --headless --path game -- --server --game_mode=deathmatch --map=malasugue_mall --bots=2 --autostart=1 \
  --expect_players=0 --wpqa=<dir>
```

## Editing Malasugue Mall in Godot

1. Open the project in Godot 4.7 (`game/`). The **Aetherion Waypoints** plugin is on (Project > Project Settings >
   Plugins).
2. Open **`res://editor/malasugue_mall_editor.tscn`**. The mall is shown as the game builds it.
3. Select **Waypoints**, press **Load the game's waypoints** in the Inspector (6,100 waypoints, a few seconds). Set
   **Level** on the root node (or **Show Level** on Waypoints) to the floor you edit: the floors above it hide.
4. Edit:
   - **Shift + click** on the floor: a new waypoint, joined to the waypoint selected (select it, Shift+click the next
     place, Shift+click the next: a chain);
   - move waypoints with the gizmo; **Ctrl+D** copies one (with its joins), **Delete** removes one;
   - **Link** / **Unlink** in the 3D toolbar join or part the selected waypoints;
   - in the Inspector: **Kind**, **Priority** (1 main road, 2 secondary, 3 side), **Place Name**; for hide / snipe /
     cover places tick **Faces** and turn the waypoint (its blue arrow) the way bots should watch.
5. **Save for the game** (toolbar or Inspector) writes `game/data/waypoints/malasugue_mall.json`.
6. **Check in game** saves, runs the game headless on the mall, proves every join with its physics and prints what
   failed in the Output panel (dropped joins show red, waypoints where a body does not fit, waypoints not joined to
   the rest). About 20 seconds.
7. **Extras**: anything put under the **Extras** node (a wall, crates, cover, lights; any node or scene, with collision
   where people should bump into it) is added to the mall in the game. It is saved with Save for the game (or the
   root's **Save extras for the game**) to `game/assets/maps/malasugue_mall_extras.scn`. After changing extras, run
   `bash tools/bake_botnav.sh malasugue_mall` so the bots' walk check and waypoints see them.
8. **Generate again** replaces the whole graph with a fresh one from the map (your edits are lost; it asks first).

Lines: white walk, orange tight, cyan door, magenta stairs and escalators, blue wade, red a join the last check dropped.
Waypoint colours: yellow road, orange junction, green area, dark green corner, cyan door, magenta stair / escalator,
violet hide, red snipe, pink cover; bigger = higher priority.

After a change to the mall's builder, run `godot --path game res://tools/mall_preview_export.tscn` so the editor shows
the new mall (the game itself never loads the preview).

## QA results (r23)

| Map | Waypoints | Edges | Walkable cells covered | Routes found | Edges failing a fresh sweep |
|---|---|---|---|---|---|
| Malasugue Mall | 6,107 | 23,338 | 99.88% of 49,484 | 500 / 500 | 0 |
| Freight Delight | 1,237 | 3,923 | 100.00% of 34,218 | 500 / 500 | 0 |
| Lawless Sub | 3,193 | 10,383 | 99.75% of 33,875 | 500 / 500 | 0 |
| Sitio Kalinaw | 7,035 | 21,165 | 98.78% of 69,497 (was 50.47%) | 500 / 500 | 5 (props moved per match) |

Bots in real matches (`--navwatch`, 10-minute Deathmatch with 21 bots; Sitio Kalinaw: Classic with 40 bots), share of
the time bots wanted to go somewhere but were stuck (under 0.25 m/s for 2 s or more):

| Map | 0.22.0 | 0.23.0 | Stall events per bot-minute | On graph edges | Within 0.8 m of the swept line |
|---|---|---|---|---|---|
| Malasugue Mall | 4.7% | 1.3% | 0.3 -> 0.1 | 90% | 83% |
| Freight Delight | 4.2% | 1.7% | 0.2 -> 0.1 | 97% | 88% |
| Lawless Sub | 2.1% | 0.5% | 0.1 -> 0.1 | 97% | 94% |
| Sitio Kalinaw | 23.7% | 7.8% | 1.2 -> 0.7 | 64% | 77% |

Still open: on Sitio Kalinaw most stalls left are inside houses, on the house plans (door to room to container), which
are not on the graph. Match-to-match noise is large (the same build gave the mall 3.0% and 4.2% in two runs).

Found in matches and fixed:

- A bot sent to a spot it cannot reach in plain sight (an order, a ping) stopped at the nearest waypoint but was sent
  there again every tick; it now counts as arrived.
- A helper that reached a teammate stood still when the teammate moved on; it now follows again.
- A locked door on a door edge made the bot close that edge, plan the same route and come back for ever (the edge was
  the only way into the fire-stair core). Bots now force a locked door (hold Use, as in house plans), and an edge that is
  the only way between its ends is never closed (bridges, single doorways): a queue on a bridge is not a blocked edge.
- A bot standing against a wall was checked with a cylinder wider than its body, so it never saw a waypoint (a quarter
  of the mall's routes started with a grid path); the check from a bot's own feet is now thinner than the body.
- Sitio Kalinaw's house plans: the walk to a door off every road ends with the grid's way from the last waypoint.

Found by the strict QA on the way:

- **Sitio Kalinaw's bridges were not on the bots' walk grid**: the river (and the estero) split the map, and no bot
  could plan a way across; every goal on the far bank was pulled back to the near one. Bridge waypoints now run along
  all 14 crossings.
- Entrance doors are rows of leaves; the doorway check took the neighbouring leaf and called every straight crossing
  "off centre" (92 door edges). It now takes the leaf the line passes nearest the middle of.
- Waypoint spacing ignored walls: a waypoint in one shop aisle stopped one being placed in the next aisle, which left
  whole shelving areas (the supermart, the botika, the sari-sari mart) unjoined. Spacing now counts only waypoints in
  sight on the walk grid, and unjoined sets are threaded along the grid's own path.
- The walk grid calls some shelf gaps passable that a body is too wide for (60 waypoints in the mall's Level 1 shops
  stay unjoined: bots never route there).
