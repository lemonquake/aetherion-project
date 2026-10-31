# r16 component contract (frozen 2026-10-30, before candidate review)

Run / component: r16 Malasugue Mall after the outbreak (lighting, wreckage, department store, Level 3 restrooms).
User outcome: much more detail; darker overall with dark spots, flickering and faulty lights; a huge department store
with its own dark spots; zombie-apocalypse destruction and mess, blood stains, drags and splatters; real restrooms on
Level 3. Exclusions: no zombies/NPC changes, no gameplay rule changes, mall escalators and stairs keep working.
Engine: Godot 4.7.2, Forward+ (PC), Mobile renderer unverified. Owned files: game/src/world/maps/malasugue_mall/*,
src/world/lighting.gd (indoor profile, down/shaft lights), materials.gd, surface.gdshader, tools/make_mall_apoc.py,
game/assets/mall/apoc.*, src/debug/autotest_mall.gd.
Baseline: commit 430ea9e + r15 working tree (work/r16/before/ captures).
Benchmark: no commercial reference available on this machine -> benchmark gate UNVERIFIED. Blind review compares
the r15 build (baseline) with the r16 build from the same ten viewpoints (work/r16/cams.txt, map_preview, t=450).
Frozen criterion: which capture set better shows a shopping mall that a zombie outbreak has just swept through -
dim, uneven light with dark spots and failing fittings, destruction, mess and blood, detailed, objects that fit the
lighting - while staying readable enough to move through (not uniformly black).
Mandatory invariants: --autotest=mall build/ride_up/ride_down/stairs/glass/door/bot pass; new dept stairs, dark,
flicker, restroom checks pass; mall fingerprint identical on a headless server and a client; frame rate measured at
the five perf spots (r15: 90-102 fps avg, p99 15.9-18.6 ms, 20 bots).
Max passes: 8.
