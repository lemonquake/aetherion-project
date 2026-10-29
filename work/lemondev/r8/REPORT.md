# r8 verification record

This run implements the requested Deathmatch overhaul and select-fire controls on the existing Godot project. The previous working source was copied to baseline/ before changes. Existing user changes were retained.

## Implementation
- Static covered pedestrian overpass with two stair flights, railings, drainage and 5.56m road clearance; detailed canal crossings, road repairs, drains, manholes, utility cabinets and actual curb ramps.
- Weathered PBR arrays derived from the project's credited Poly Haven sources: 99 independently mipmapped512px slices for base colour, normals and packed AO/roughness. Opaque architecture is batched across surface types. No runtime texture baking.
- Building drainage, utility services, shop awnings/signs, industrial and skyline detail; no per-building update scripts or extra lights.
- Auto -> Single -> Burst for rifles/SMGs, defaultAuto on fresh/acquired weapons, configurable defaultB, mobile state button. Three-round trigger bursts, authoritative/predicted state, cancellation for menus/reload/switch/death; held fire must be released after Resume.
- Map teardown releases subsystem cycles and listeners; network build version0.9.0 rejects older incompatible peers.

## Evidence already observed
- Source compile120 scripts/0failed (prior to final relief trim refinement).
- Independent headless physics/resource suite75,400 checks/0failed over3build/freecycles. All28spawns,63bridge samples,528stair samples supported; steady object/node counts after teardown and no leak errors.
- Firing suite20,620 checks/0failed;10,000 fixed steps per replica, serialization, defaults, held/tap behavior, interruption and menu regressions.
- Real desktop host input11checks/0failed; live client/dedicatedserver11checks/0failed with231snapshots, mode agreement and burst/pause behavior.
- Desktop stage1: realForward+ on RTX4060/Ryzen75700X at1920x1080, High settings,19bots,9eight-second recorded phases. Worst phase avg6.69ms. Full traces/per-phase percentiles are in perf_desktop/. A later relevant visual change requires final rerun.

## Quality review and remaining gates
Official Valve Counter-Strike2 Overpass images from https://www.counter-strike.net/cs2 are reference only, not production assets. Context-isolated review1 chose the reference, identifying architectural relief as the single largest gap. A bounded second trim pass addresses that gap; independent recheck pending. Critic isolation is instruction-enforced on a shared filesystem; review1 lists only authorized packet reads.

Physical mobile target unavailable: adb reports no connected device. Mobile renderer/profile checks on the desktop can validate compatibility and touch layout but cannot certify phone performance, temperature or frame-time spikes. No universal zero-spike or commercial-quality claim is made.

Artifacts under builds/r8-preview/ are review builds, kept separate from previously exported releases until all requested target and quality gates can be verified.
