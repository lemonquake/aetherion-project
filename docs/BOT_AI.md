# Bot AI (r22): LimboAI-style state machines and behaviour trees

The bots' decisions run on the architecture of [LimboAI](https://github.com/limbonaut/limboai) (the user's
`A:\Python\fps_ai` is LimboAI 1.8.1's source): hierarchical state machines (HSM), behaviour trees (BT) and a blackboard
with scopes. It is written in GDScript (`game/src/ai/limbo/`), with LimboAI's names and semantics, so it runs on the
Windows, macOS and Linux builds, the Linux servers and Android without a native plugin. Moving to the real plugin later
is mostly renaming base classes (`BT.Sequence` -> `BTSequence`, `LimboHSM`, `BTState`, `Blackboard`).

| File | What it is |
|---|---|
| `src/ai/limbo/blackboard.gd` | Variables with a parent scope. A bot's blackboard has its team's as parent. |
| `src/ai/limbo/bt_task.gd` | The task base: `execute(delta)` -> RUNNING / SUCCESS / FAILURE, `abort()`, `running_path()`. |
| `src/ai/limbo/bt.gd` | Composites (Sequence, Selector, DynamicSequence, DynamicSelector, Parallel), decorators (Invert, AlwaysSucceed, AlwaysFail, Cooldown, TimeLimit, Repeat, RepeatUntilFailure, Probability, Delay), leaves (Condition, Action, Wait, SetVar, CheckVar). |
| `src/ai/limbo/limbo_state.gd` | A state: enter / exit / update, callables, guard, event handlers, `dispatch()`. |
| `src/ai/limbo/limbo_hsm.gd` | The machine: child states, one transition per (from, event), ANYSTATE, guards, nesting, deferred changes. |
| `src/ai/limbo/bt_state.gd` | A state that runs a behaviour tree and dispatches an event when the tree ends. |
| `src/ai/bot_mind.gd` | The bot's three machines and all its trees. |
| `src/ai/bot_brain.gd` | The senses and skills the trees call (perception, paths, doors, unsticking, house search, holds, aim, trigger). |
| `src/ai/bot_team.gd` | What a team shares, now with its blackboard (`BotTeam.board(team)`): `intel`, `endgame`. |
| `tools/limbo_selftest.gd` | 29 checks of the framework, including that a dropped machine and its owner are freed. |

Self-test: `godot --headless --path game -s res://tools/limbo_selftest.gd`.

## The three machines

```
 server tick (60 Hz)                                  brain.think(dt) -> mind.update(dt)
 ─────────────────────────────────────────────────────────────────────────────────────
 BODY (every tick, event = the character's mode)
   idle ........ plane, dead, spectating            nothing
   airborne .... freefall, canopy                   _deploy (follow a human's lead, steer the canopy)
   downed ...... downed                             _crawl (away from the field)
   survive ..... in a walled canal for 1.5 s        _escape_water (ladder, else over the wall to dry ground)
   play ........ on its feet                        ┐
                                                    │ every 0.25 s: perceive, squad, endgame clock,
                                                    │   then MIND thinks
                                                    │ replies on the radio
                                                    │ MOTOR runs the activity
                                                    ┘ light, field escape, edges, traces

 MIND (4 Hz, while playing). One ordered table of guards picks the mode; the first that holds wins:
   1 directed   a fall-back order and no enemy within 12 m
   2 evacuate   an enemy in sight, but the haze is on us and the enemy is more than 15 m off
   3 combat     an enemy in sight
   4 recover    bleeding, or hurt with a first aid kit or a bandage
   5 evacuate   on the way out of a house
   6 evacuate   the haze says leave now for the next circle
   7 directed   a radio order (help, go, check)
   8 ready      Deathmatch: the first seconds of a round, not following anyone
   9 directed   a teammate's ping, a leader to follow, or a noise to look into
  10 objective  everything else
 Each mode is a BTState: its tree is ticked at the same 4 Hz and makes the decisions. Its leaves set the activity
 (the brain's `state` label). A mode whose tree finds nothing to do hands over to objective in the same think.

 MOTOR (every tick): the activity the label names
   fight ....... "fight"                 the combat tree (below), ticked every frame
   hold ........ "camp", "overwatch"     _hold_step + upkeep
   order ....... "order"                 _order_step + upkeep
   follow ...... "follow"                _follow_step + upkeep
   fetch ....... "fetch"                 _fetch_step
   heal ........ "heal"                  treat + walk slowly
   move ........ anything else           detour to loose loot, or walk the path (pro: pre-aimed), loot actions
               (roam, hunt, loot, zone, investigate)
```

## The mind's trees

Guarded branches are `DynamicSequence[Condition, action]`, so a branch stops the moment its condition fails, and the
`DynamicSelector`s above them re-check from the top every think (a higher branch pre-empts a lower one that was
running).

```
evacuate  DynamicSelector
├─ out of the house  DynamicSequence
│  ├─ Selector [ already leaving? | find the door (find_exit + leave_house) ]
│  └─ walk out ......................... RUNNING while the exit plan lasts
└─ run for the circle .................. goal in the next circle (new when far off), "haze" on the radio, state zone

directed  DynamicSelector
├─ order ........ an order? -> carry it out (state order)
├─ ping ......... a ping? -> answer it (_ping_step: go / flank / watch / look)
├─ follow ....... a leader? -> keep up (state follow)
└─ investigate .. a noise? -> go and look (holding a spot far from it: only look)

objective  DynamicSelector
├─ fetching .......... fetching loot? -> keep at it
├─ searching a house . a house plan under way? -> keep at it
├─ holding ........... camp / overwatch time left? -> keep at it
├─ out of the house .. indoors with a door to leave by? -> walk out
├─ gear up ........... (Classic, or out of rounds) loot in sight within a short walk? -> fetch it
├─ arm yourself ...... (Classic, unarmed) -> the next house with loot, or roam
└─ role  DynamicSequence [ rethink clock, DynamicSelector ]
   ├─ endgame (Deathmatch: a side down to a few, or no contact for a while)
   │  ├─ on the way ........ a sweep or hunt leg under way (a sweep leg gives way to word of an enemy)
   │  ├─ short hold ........ sniper / ambusher at a spot of its kind the sweep brought it to, a hold due
   │  ├─ (leg over) ........ always fails: ends the sweep leg's claim
   │  ├─ word of an enemy .. a callout or the team's hint more than 10 m off -> hunt it
   │  └─ sweep ............. the stalest cell of the map nobody of the team is sweeping
   ├─ ambusher (Deathmatch looter)
   │  ├─ (hold over: a finished camp clears the objective)
   │  ├─ in place .......... at its hiding spot -> camp (25-50 s x patience x skill)
   │  ├─ (walk ended short: pick again)
   │  ├─ on the way
   │  └─ take a hiding spot  (never one held in the last 3 min, nor within 20 m of the last)
   ├─ looter (Classic)  on the way | next house
   ├─ sniper            hunting | in position -> overwatch (40-80 s ...) | on the way | take a sniping spot
   ├─ rusher            on the way | pick a hunt (across the open, at a sprint)
   └─ stalker           on the way | pick a hunt (cover waypoints to one side: a flank)
```

## The combat tree (motor, every tick)

```
combat  DynamicSequence
├─ aim ......................... on the target (pro: the head at range), the skill's error settling; fails if gone
└─ act  DynamicSelector
   ├─ unarmed ................. no gun -> get away
   └─ armed  DynamicSequence
      ├─ trigger .............. aim down sights close or scoped; reload when empty; fire once reacted and on target
      └─ footwork  DynamicSelector
         ├─ pro (skill Pro)  DynamicSequence
         │  ├─ read the fight . rounds left, an opening (target reloading, hurt, looking away, or outnumbered)
         │  └─ tactics  DynamicSelector
         │     ├─ reloading ... reloading within 40 m -> out of the line of fire
         │     ├─ rush ........ out of rounds or down to a handgun -> close in
         │     ├─ long gun .... marksman / bolt -> crouched and scoped at range, back off when close
         │     ├─ opening ..... smg / rifle / shotgun / lmg and an opening -> push
         │     └─ strafe
         └─ by temperament .... rusher closes in, sniper keeps still, looter sways, others strafe; hurt or
                                reloading close: back off (not the fearless)
```

## Debugging

- `--bottrace=first` (or a name) prints each second, after the old line, `| body/play mind/objective [objective/role/
  sniper/on the way] motor/move`: the body's path, the mind's mode with the running branch, the motor's activity.
- `--mindlog` with `--matchlog` writes `[mind] <bot> <from> -> <to> (<guard>)` on every mode change.
- The `[hold]`, `[sweep]`, `[endgame]`, `[hint]` and `[botskill]` lines are as in r22's first version.

## Adding a behaviour

1. A new decision: a branch in the mode's tree in `bot_mind.gd`, usually `_when(condition, BT.Action.new(leaf), "name")`
   placed by priority. Conditions and leaves are methods of the mind (no lambdas: a lambda that captures the mind
   keeps it alive forever).
2. A new mode: a `BTState` in `_build_mind()`, an ANYSTATE transition to it, a `[guard, event]` row in `_rank` at its
   priority, and a `&"done"` transition back to objective.
3. A new activity: a state label, an `ACT_OF` entry and a motor state whose update calls the brain's skill.
4. The skill itself (movement, aim, the use of the world) belongs in `bot_brain.gd`.

Things outside read the brain's fields as before (`state`, `role`, `order`, `goal`, `path`, `target_eid`, `_dm_hold`,
`test_idle`, `test_blind`, ...) and call its hooks (`take_order`, `hear`, `on_team_ping`, `on_laser`, `on_damaged`,
`_start_hold` in tests), so the match server and the autotests did not change.
