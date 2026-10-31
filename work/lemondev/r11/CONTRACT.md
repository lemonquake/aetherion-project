# r11 contract — Deathmatch (Lawless Sub) hard QA and fixes

User request (2026-10-29, via @work/lemondev): hard QA of the Deathmatch map; 3 teams max, 7 players max per team;
answer: ship-ready or AI slop, does the map make sense, walkability (elevated sidewalks), textures on theme, fun
spots (3-storey houses with interiors and stairs, rooftops, a small mall with a real interior), readable assets and
per-weapon ammo colours, bot quality, unreachable spots, a visible metal cage round the whole map with big speakers
carrying a realistic radio/PA announcer with reverb/delay, convincing bullet impacts with lingering dust/smoke.

Engine: Godot 4.7.2, Forward+ (RTX 4060 dev PC). Baseline: git 430ea9e (clean tree at start).

## Components and gates

| ID | Component | Gate (frozen before building) |
|---|---|---|
| C1 | Teams 2-3, up to 7 each (default 3x7) | headless 21-bot match starts 3 teams of 7 at 3 spawns >= 300 m apart; `r11_three_teams`; `dm_teams` |
| C2 | Steel cage perimeter + speaker stacks | captures show the cage from inside and from the air; `r11_cage_holds` (player stops inside the wall line, chest ray stops on it) |
| C3 | Cage announcer (radio + PA + arena) | `r11_cage_pa` (start line played from cage stacks, 3 nearest stacks on the cage); spectrum band-limited (< 2 % energy under 300 Hz and over 4.5 kHz), tail present |
| C4 | Impact after-dust | `r11_impact_haze`: centre luma change still > 1.2 at 1.5 s and lower at 4 s |
| C5 | Walkability | `r11_sidewalks_walkable` (every sidewalk in 30 m legs, real time) and `r11_kerbs_step_up` (24 approaches) |
| C6 | Landmarks: mall, 3-storey houses, roof decks | captures of exterior, concourse, upper floor, roof; script compile; no build errors |
| C7 | Ammo readability | ammo drawn at 1.9x box size; 9 calibre colours (data) |
| C8 | Visual slop fixes | blind A/B (baseline vs candidate, same cameras) |
| C9 | Bots with 3 teams | headless matches finish with a winner; stuck/zone deaths reported |

Commercial benchmark: none on disk for this map (only the user's top-down reference, not a commercial capture). The
commercial A/B gate stays UNVERIFIED; the blind review compares baseline vs candidate only.
Budget: 8 passes per component (none needed more than 3).
