# Deathmatch map and resource audit

Inspection and headless validation: Godot 4.7.2 stable on Windows, seed 1729. Local render hardware is an NVIDIA GeForce RTX 4060 (driver 32.0.15.9636) and AMD Ryzen 7 5700X. Headless geometry checks do not measure rendered frame rate. `adb devices -l` found no connected device; four local AVD definitions exist. Desktop mobile-profile rendering cannot certify a physical phone.

## Map census

The Lawless Sub plan has 12 road segments, four crossing types, four parking lots, a walled canal and basin, an estero, subdivision walls and a perimeter with a city backdrop. The 256 lots include 216 houses, 20 shophouses, two apartment buildings, three tanks, and one each of office tower, guard booth, guardhouse, clubhouse, chapel, store, strip shops, factory, warehouse, gas station, pool, covered court, playground, water tower and container yard.

Existing streets already had lane markings, zebra crossings, traffic signals, lamps, a waiting shed, bus/jeepney wrecks, parked cars, canal trees and shrubs. The new static street module adds a covered pedestrian overpass with two usable stair flights, deck/bridge structural details, service covers, drainage, repairs, utility cabinets and bollards. New sidewalk ramps replace their former flat surface rather than adding an overlapping layer.

Imported and procedural objects include household furniture, appliances, fixtures, cabinets, shelves, loot boxes, cars and vans, jeepneys, wrecks, machinery, conveyors, forklifts, control pedestals, containers, rubble, trees, plants and utility furniture. See `collision_categories` in the JSON for all recorded categories and counts.

## Validation evidence

Run:

```powershell
& 'A:/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe' --headless --path game res://tests/deathmatch_design.tscn -- --out=A:/Python/aetherion-project/work/lemondev/r8/final-design.json --cycles=3
```

`final-design.json` and `final-design.log`: 75,400 checks, zero failures, no engine errors or exit resource-leak warnings. This includes the final facade and median-planting geometry. The JSON records SHA256 hashes of all world scripts/shaders and checks those files remained unchanged during validation. Later changes to these sources require a new run. The combined sorted world hash manifest SHA256 is `d9158b634f66b584724f98864f65f7e8fac685f477cb3129047b9f003909e2f1`; full per-file hashes are in `final-validation-hashes.json`.

- Layout lots and masks match a second independent construction from the same seed. Three full scene constructions have the same fingerprint: `256 buildings, 1970 doors, 2518 containers, 2480 props, #f9b648fc`.
- All 28 team spawn locations have physical floor support and clear standing capsules.
- All 63 samples across the two road bridges and the Narra Footbridge have continuous physical deck support. The pipe route has no standing-capsule requirement.
- All 528 samples on 176 registered stair flights have physical support. Stair sampling follows each registered flight centre line; the approach/side-exit points are not mistaken for that line.
- The overpass provides at least 5.3 m vehicle clearance (recorded geometry: 5.56 m), clear road lanes below, and clear standing capsules and rail openings at both stair landings.
- Every scene transform/collision box is finite and collision-box sizes are positive. Every render mesh has a surface. Shared urban-array surfaces have matching vertex/custom/normal/tangent/color/UV channel counts and bounded texture-layer/material attributes.
- Built scene: 5,199 nodes, 651 ordinary mesh instances, 2,901 MultiMesh instances containing 8,847 model instances, 617 CollisionShape nodes and 136 occluders. Stored ordinary mesh triangles: 995,520. Model triangles drawn per frame are separate.
- Architecture material cache: 17 logical materials and 46 directly cached source textures. Texture arrays and imported model textures are additional resources; these numbers are not total GPU texture counts.
- Each teardown returns to 91 scene nodes, zero orphan nodes and 1,989 ObjectDB objects. Static allocated memory after the three cycles: 99,653,735; 99,680,175; 99,712,199 bytes. This small allocator growth does not establish unlimited-duration leak freedom.

The earlier `design-pass1.json` checked pre-array geometry and detected no physical invariant failures. An intermediate `design-cleanup.json` run overlapped the initial custom-channel implementation and emitted invalid-surface errors. Its JSON verdict predates the mandatory nonempty-mesh gate and must not be used as rendering acceptance. That error was fixed in `design-arrays` evidence; `final-design` is the final revision with later visual work included.

## Resource lifecycle correction

Before the correction, repeated map removal leaked MapBuilder and its RefCounted helpers through backreferences and Settings listeners. Door records also referenced their Door objects, whose `spec` pointed back to the records and whose `dyn` pointed to Dynamics. Two map builds left 14,602 ObjectDB instances and 1,205 resources in use at process exit.

The map root now owns its lights/environment as well as geometry. Its exit invokes an idempotent MapBuilder dispose path: release Dynamics server RIDs, break Door/spec/Dynamics references, disconnect Lighting and ViewLod Settings listeners, break helper/map backreferences, and release map-held geometry/material/texture registries. Weak-reference assertions verify MapBuilder, Dynamics, Lighting and ViewLod are released after each teardown.

## Remaining performance evidence

The parent integration runner owns rendered 60-second frame traces, desktop/mobile-profile and 1080p/4K screenshots, final source revision hashes and independent visual review. Target: p95 frame time at or below 16.67 ms, while reporting p99, maximum and frames over 33 ms. Actual phone testing remains unavailable with no connected device.

The existing `map_preview --perf=<view>` performs useful attribution by disabling shadows, volumetric fog, SSAO, MultiMesh props and chunk geometry separately. The old full-map material split produced 2,033 ordinary meshes in this headless scene; the shared architecture array plus all later facade/median additions uses 651. Actual visible draws depend on camera and renderer and require the parent's rendered measurements.

## Independent firing-mode source review

Packet encoding carries selector mode, pending burst rounds, trigger edges and queued reload state; reconciliation compares the new state. Auto acquisition is applied to both human and bot pickup paths and fresh loadouts. Single/Burst trigger-edge behavior and reload/switch/death cancellation look coherent in the reviewed source.

Two issues were reported and corrected by the integration owner: Pause/results now sends `Motor.B_ACTION_BLOCKED`, which server and prediction consume, and a held-Fire release gate prevents firing on menu closure. Application version is now 0.9.0 so older exports are rejected by the version handshake.

The extended `fire_modes.tscn` test ran 20,620 checks with zero failures (`final-fire.log`). It now exercises actual controller commands for both Pause and Match Results in all three modes, codec preservation of the blocker, cancellation after the first burst round, 60 ticks holding Fire across resume without firing, and restoration of Auto/Single/Burst behavior on a fresh trigger press. The existing two-client `tools/net_test.sh` is a live ENet test but follows the Kalinaw aircraft flow and does not exercise firing modes; the parent owns current live input/network evidence.
