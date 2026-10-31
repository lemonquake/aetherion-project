# r22: bots on the LimboAI-style mind, and the firefight lag (2026-11-01)

## The mind against the reference brain (A/B)

Headless Deathmatch on Freight Delight, 12 bots, 2 teams, field off, Normal skill. `new` is `bot_mind.gd`, `r22a` is the
r22 reference brain (`--brain=r22a`, `src/debug/legacy/bot_brain_r22a.gd`, commit fc3522c). Script:
`work/r22/ai/ab_matches.ps1`, analysis `work/r22/round_stats.py`, `work/r22/ai/gaps.py`. Logs in `work/r22/ai/ab/`
(not committed, 45 MB).

First version (a hold cut short counted as held until then):

| seeds | rounds new / r22a | kills new / r22a |
|---|---|---|
| 414243, 42, 43, 44 (11 min) | 32 / 39 | 316 / 374 |
| 51, 52 (8 min) | 11 / 12 | |
| 61, 62, 63 (8 min) | 19 / 20 | 192 / 198 |

Activity shares (`[botstates]`) showed one systematic difference: camping about 1.5% of bot time on the new mind
against 3.2% on the reference. The branches of the trees match the old if-chain; the difference was the one deliberate
tweak (a hold cut short marked as held until then, which kept bots away from nearby spots longer). It was removed.

After removing it (seeds 71-74, 10 min): rounds 30 / 32, kills 285 / 302, camp 4% / 3.5%: parity within the noise
(single seeds swing from 3 to 11 rounds on either brain).

Other checks on the new mind: r13 on Lawless Sub all pass (as the reference); canal bots 4/4 out; r12 field push, crush
and bot escape pass, fieldhouse passes (one flaky run under load: house 5 took 13.9 s); Freight routes 26/26 with 2
stalls; mall navtour (see navtour_mall2.log). No script errors in any match. Object counts steady across rounds (the
mind's trees add about 1,500 objects for 12 bots; no climb), server tick average the same as the reference.

## The firefight lag (Freight Delight)

`--autotest=firefight` (src/debug/autotest_firefight.gd): ten frozen bots fire their real guns in front of the camera
on Freight's plaza. RTX 4060, 1080p, shadows 2.

| | before | bullet fix | + rounds past the map dropped | + flash shadows limited (vsync off) |
|---|---|---|---|---|
| firing frame | 116-150 ms (7-9 fps) | 24-36 ms | ~17 ms (vsync-capped 60) | ~15-18 ms, quiet 9.5 ms |
| physics steps/frame | 6 | 1.46 | 1.0 | 1.0 |
| w.projectiles ms/frame | 78-101 | 8-14 | ~2 | |
| draw calls firing | 3,900-4,900 | | | ~2,340 (quiet 2,170) |

Cause: every round in flight tested every character every tick (`_test_characters` rewound each character's history,
`_flybys` asked each character for its eyes), and a miss flew on for 4 s / 1.6 km although Freight is 70 m to the edge.
Lights were not the cause (no muzzle-flash light at all: still 109-123 ms); muzzle-flash cube shadows cost ~1,450 draw
calls and ~1-2 ms GPU. Fix: projectile_server.gd gathers once per tick the characters with the box of their rewound
positions and their eyes (exact broad phase), drops rounds 40 m past the map's edge heading out, and effects.gd gives
flash shadows only to your own flash and at most two others within 14 m of the camera. Hit rate in bot matches unchanged
(19-23%). An xcopy outside this session was using four cores during the later runs, so their timings are noisy.

## Bot skill on the new mind (Freight, seed 91, 6 min each, `work/r22/ai/skill/`)

| skill | rounds fired | hits | hit rate | reaction avg | damage | rounds ended |
|---|---|---|---|---|---|---|
| easy | 2084 | 142 | 6.8% | 0.82 s | 3078 | 2 |
| normal | 1142 | 235 | 20.6% | 0.44 s | 5584 | 4 |
| hard | 1161 | 353 | 30.4% | 0.28 s | 7170 | 6 |
| pro | 1171 | 306 | 26.1% | 0.22 s | 7894 | 6 |
