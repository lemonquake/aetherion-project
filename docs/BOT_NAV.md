# How bots know a map (BotNav, 0.21.0)

> **0.23.0:** bots now walk a proven **waypoint graph** on every map (`docs/WAYPOINTS.md`, `src/ai/waypoints.gd`). The
> walk grids below still decide where the waypoints go and carry a bot back onto the graph; the routes themselves are
> the graph's. Malasugue Mall's waypoints can be edited in Godot (`game/editor/malasugue_mall_editor.tscn`).

One system for every map (Sitio Kalinaw, Lawless Sub, Malasugue Mall, Freight Delight, and any map added later). It
replaces the old per-map waypoint survey and fixes bots standing stuck against walls, mostly on the mall.

## Why bots got stuck (measured on Malasugue Mall before the change)

**After** (same match, same seed): 48 stalls (0.24 per bot-minute) and 121 s facing a wall (was 330 s); Freight
Delight's route test 26 of 26 legs (was 23); the mall route test 22 of 24 waypoints before the last stair fixes.

A 10-minute 21-bot match with `--navwatch` counted **160 stalls** (a bot that wanted to go somewhere and covered under
0.25 m/s for 2 s), 0.8 per bot-minute, 4.2% of all walking time, and 17 bots standing still facing a wall. The causes:

1. **The walk grid only knew the walls the builder drew.** Kiosks, wreckage, planters, shelving and counter ends were
   open floor to the bots. The physics check closed 1,424 such cells on the mall.
2. **Unreachable goals.** A goal in a sealed pocket, outside the building or on a floor with no way there got a partial
   path, and at its end the bot walked straight at the goal, into the wall, until it gave up 10 s later.
3. **Corner cutting.** Straightened paths were checked along a one-cell line, so they clipped wall corners and pillar
   edges. Paths also hugged walls.
4. **Follow slots inside walls.** A follower's place beside its leader could be inside a shop wall; it walked to the
   nearest open cell and stood there, facing the wall. This was the worst spot on the map (south-east ground floor).
5. **Walls on whole-metre lines.** On the mall's 1 m grid a wall standing exactly between two rows of cell centres
   (the fire-stair cores' fronts, many shop fronts) closed no cell at all, so paths ran straight through it. The link
   check below cut 4,148 such links.
6. **Waypoints counted as reached too early.** Anything within 1.2 m counted, so the point just past a doorway was
   "reached" from inside the room and the bot set off for the next one along the inside of the wall, into a corner,
   over and over (the fire stairs' top landings).

## The parts

| File | What it does |
| --- | --- |
| `src/ai/bot_nav.gd` | The analysis: walk check, waypoints and hiding spots, the saved file |
| `src/ai/nav_levels.gd` | Paths on storeyed maps: bake applied, pockets dropped, wall weights, band + sweep straightening |
| `src/ai/nav_grid.gd` | Paths on flat maps (unchanged) |
| `src/ai/bot_team.gd` | What bots share: spots in use, popularity, learned spots, claims, stuck cells, the memory file |
| `src/ai/bot_brain.gd` | Each bot: goals put on the walk, path ends, whiskers, facing, ambushers |
| `src/debug/nav_watch.gd` | `--navwatch[=file.json]`: stalls and wall-facing counted in any match |
| `src/debug/autotest_navtour.gd` | `--autotest=navtour`: one bot walks waypoint to waypoint across any map |
| `src/debug/nav_probe.gd` | `--navprobe=a;b[;...]`: path, band and sweep checks and ray hits between points; `--navgrid` prints the grid |
| `tools/bake_botnav.sh` | Makes the shipped files `game/data/botnav/<map>.json` |

## 1. The walk check (storeyed maps)

For every open cell of each level's walk grid (`layout.nav_open`):

- a ray down from 1 m above the level to 0.8 m below it must hit floor no higher than 0.55 m above the level (a raised
  container floor counts, a counter top does not);
- a cylinder of radius 0.32 m (the body is 0.30 m) from 0.40 m above that floor (over step height, 0.36 m, so sills and
  thresholds are walked) to 1.75 m must touch nothing in `Defs.MOVE_MASK` (world, props, glass, blockers). Doors are left
  out: bots open them.

Cells that fail are removed from the graph. Then the **link check**: every link between two open neighbours (straight
and diagonal) gets a ray between the cell centres at 0.9 m over the floor (doors left out); a hit cuts the link. On the
mall that took 2.2 s and cut 4,148 links. The landing cells of escalators and stairs are always kept (and re-joined to
the floor round them if their neighbours failed). Then `NavLevels.finish()`:

- **clearance**: cells to the nearest closed cell; a cell whose centre is under 0.6 m from one costs 3 times as much to
  cross, under 1.0 m 1.6 times, so paths run down the middle of corridors;
- **components**: a flood over every connection (escalators and stairs both ways); everything outside the largest set
  is a pocket and is disabled (`--navdebug` prints where the pockets are);
- **straightening** (`_smooth`) skips points only where a body-wide band (0.36 m each side) of open cells runs the whole
  way **and** a body-sized cylinder swept through the real collision meets nothing;
- **start point**: the nearest open cell the bot can walk to in a straight line (the nearest one can be behind a thin
  wall); on a stair, its half landing or an escalator, the nearest point of that stair or escalator; somewhere the walk
  does not go (the dead end under a fire stair on the ground floor), the nearest cell within 8 m it can walk to (the
  nearest cells there were outside the building's back wall);
- **doorways**: a step of the path that crosses a door is bent through the middle of it, 1.4 m before the door on its
  centre line and 0.8 m past it (a 1.2 m door rarely lines up with 1 m cells).

On flat maps (Kalinaw, Lawless Sub) the 2 m grid and its region logic stay as they were; the spots, the learning, the
goal and path-end rules, the whiskers and the facing apply there too.

## 2. Waypoints and hiding spots

Candidates: along walls every 2 m (corners and recesses are where hiding spots are), in the open every 4 m, on every
floor (flat maps: every 8 m of open ground), plus the map's designated spots (`layout.designated_spots()`, each
`{p, kind, face?, name}`). Each is looked round from crouching eye height (1.05 m) in 16 directions (45 m on storeyed
maps, 70 m outdoors):

| Kind | Rule |
| --- | --- |
| hide | at most 30% of directions open past 6 m, at least 3 closed within 1.3 m, a view of 6 m or more |
| snipe | a view of 35 m (storeyed) or 60 m (outdoors), something beside it, at most 60% open |
| cover | at least 2 directions closed within 1.3 m |
| open | none of those |

Each spot keeps `dir`, the way it watches: its longest view, or the designated facing. Spots are thinned (one hiding
spot per 2.5 m, sniping and cover per 4 m, open per 8 m; designated spots always kept).

Designated spots so far:

- **Malasugue Mall** (`mall_layout.gd`): the back corner of every shop deep and wide enough, watching its front
  (hide); inside each restroom block (hide); the top of every escalator, watching the people riding up (cover); the
  balconies round the Grand Atrium, the East Court and the West Court on Levels 2 to 5 (snipe).
- **Freight Delight** (`freight_layout.gd`): Bodega mezzanine, deck west/middle/east, crane platform, Taas balcony,
  the container stack by the Talyer (snipe); Taas corridor and east room, container home, through-homes, Talyer office,
  sari-sari store (hide).

To add designated spots to a map, give its layout a `designated_spots()` returning that list, then rebake.

## 3. The files

- `game/data/botnav/<map>.json` ships with the game: `{key, map, closed: [[cell indices] per level], spots: [...]}`.
  `key` is `map|fingerprint|game version|format version`, so a file from another build is ignored.
- `user://botnav/<map>.json`: the same, made by a game or server whose build the shipped file does not match. The walk
  check runs at once when a match starts (0.8 s on the mall); the spot analysis runs 2.5 ms a server tick (about 0.7 s
  of work on the mall, spread over the first seconds) and bots use a quick grid survey until it is done.

Make the shipped files after any map geometry change and on every version bump:

```bash
bash tools/bake_botnav.sh                  # all maps
bash tools/bake_botnav.sh malasugue_mall   # one map
```

## 4. What bots learn from play

Saved per map in `user://bot_memory_<map>.json` after every match (Settings > Gameplay > Bots learn), version 2:

- `cells`: per 8 m cell, kills scored from it (good), long kills (snipe), time unhurt (safe), deaths (danger);
- `spot_stats`: per waypoint (keyed by its rounded position): uses (held by a bot, camped by a player), seconds held,
  kills scored from it, deaths in it. `popularity = uses x 0.6 + held/45 + kills x 2 - deaths x 1.5`;
- `learned`: spots learned from human players: where a player stayed within 1.2 m for 8 s (camping) or scored a kill
  from, more than 2.2 m from every known spot, looked round like the others (kept only if it is hiding, sniping or
  cover), up to 150 per map;
- `stuck`: cells bots kept getting stuck on (per floor on storeyed maps); three reports from two bots close a cell, at
  most 60 per map. They are forgotten when the map's build changes (`key`).

Everything fades by a fifth each time it is loaded, so old lessons give way to new ones. Bots pick spots by kind, cover,
view, exposure, the 8 m cell lessons, popularity, a bonus for designated spots and distance, and skip a spot another bot
has claimed (or one within 3 m of it).

## 5. Behaviour on the move

- `_set_goal`: a goal is put on the walk (`reachable_near`); still off it, it becomes the nearest waypoint.
- `_move` (storeyed maps): a path walked to its end with the goal still behind something ends the walk (the goal was as
  near as the walk gets) instead of pushing straight at it. Not on the flat maps: there a long search stops early on
  purpose and the next one carries on from its end. A waypoint counts as reached at 0.45 m, or at 1.2 m only when the next
  one is in plain sight (stair and escalator points, off the floor grid, keep 1.2 m).
- While on a stair or an escalator a bot does not re-plan its path (a new path from mid-flight could start at a point
  behind it and walk it back down), and it never hops or vaults from there (the grid "ahead" is the floor below).
- `_order_step`: an order is done only on the goal's floor (within 0.6 m of its height), not part way up the stairs.
- `_feel_walls` (whiskers): two 1.1 m rays at knee height, 30 degrees either side of the walking direction; a wall
  closing on one side pushes the bot to the other (they cancel in a doorway).
- `_start_hold` and following: never face a wall within 2.5 m (3 m beside a leader); the most open direction near the
  wanted one instead (`_open_yaw`). The same when arriving where an order sent it, and whenever a bot stands with
  nowhere to go (between objectives, the start of a round): a wall within 1.5 m in front turns it to open floor
  (`_idle_face`). Holding a spot, its look-round sweep shrinks while it swings onto a wall beside it (corners).
- `_follow_slot`: the place beside the leader must be open floor the leader can walk to in a straight line (its own
  offset, the mirror of it, straight behind, or the leader's own spot).
- Deathmatch looters are ambushers (`_ambush`): a hiding spot (cover if none), held 25 to 50 s crouching, then another.

## 6. Measuring

`--navdebug` prints the pockets the walk dropped; `--botnav_nobake` skips the walk and link checks (A/B).

```bash
# stalls and wall-facing in a real bot match (prints [navwatch] every minute and the worst places at the end)
godot --headless --path game -- --server --game_mode=deathmatch --map=malasugue_mall --bots=21 --autostart=1 \
  --expect_players=0 --dm_win=time --dm_time=10 --matchlog --radiolog --navwatch=<file.json> --quit_after_results=1
# one bot through the whole map, waypoint to waypoint (any map)
godot --headless --path game -- --host --game_mode=deathmatch --map=malasugue_mall --bots=11 --autostart=1 \
  --dm_win=time --dm_time=30 --autotest=navtour --shots=<dir> [--navtour_legs=24 --navtour_seed=7 --navdebug]
# replay one leg with a trace of the bot every second
...  --autotest=navtour --navtour_from=x,y,z --navtour_to=x,y,z --bottrace=first
# what is between two points (quits when done)
godot --headless --path game -- --server --game_mode=deathmatch --map=malasugue_mall --bots=2 --autostart=1   --expect_players=0 "--navprobe=x,y,z;x,y,z" ["--navgrid=x0,z0,x1,z1,level"]
```
