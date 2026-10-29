# Rifle and SMG firing modes

Implemented, awaiting independent and integrated visual/network acceptance.

- All 10 rifle/SMG definitions use the same Auto → Single → Burst selector. Newly created weapons, acquired dropped weapons, and fresh character equipment start at mode index 0 (Auto). Other weapon classes retain their original modes.
- B was already the default configurable fire_mode key. The existing input action and command bit are reused.
- Single fires once per press. Burst fires three rounds at the weapon's RPM after a tap, with no repeat while held and no extension from a repress during an active burst. Exhausted magazines truncate the burst.
- Reload, weapon switch, holster, selector changes, or blocked hands cancel outstanding burst rounds. Local forced mode changes and death cancel them as well. The integration owner is adding cancellation to authoritative world.server_set_mode for non-ground states.
- The mobile Mode button displays Auto, Single, or Burst and is shown for equipped rifles/SMGs. The desktop HUD displays the current mode and its actual bound key.
- Pending burst rounds and queued reload state use unused bits of the existing snapshot flag byte. Packet length does not increase. Reconciliation checks selector, pending rounds and trigger flags. Inventory updates preserve the predicted equipped mode until authoritative snapshot correction.

Production paths: weapon_state.gd, snapshot.gd, interaction.gd, inventory.gd, player_controller.gd, hud.gd, touch_controls.gd, settings_ui.gd. No changes to weapon definitions or default key binding were needed.

## Checks run

Godot 4.7.2 stable on Windows, headless:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tests/fire_modes.tscn
```

20218 checks, 0 failed. Two deterministic simulation replicas each ran 10000 fixed steps at 60 Hz with seed 1729, yielding 640 shots each and identical events/state. The combined workload took 508.69 ms during concurrent compile checking; this is simulation timing, not rendered frame-rate evidence. Additional checks cover every eligible gun, sustained Auto, press-gated Single, tap/held/repressed Burst, RPM spacing, partial/empty magazines, cancellation, packet roundtrip and resumed pending burst, acquisition default, inventory synchronization, actual quick touch tap latching, B binding and 20 fresh resets.

```
Godot_v4.7.2-stable_win64_console.exe --headless --path game res://tools/check_scripts.tscn
```

118 scripts checked, 0 failed. git diff --check for owned paths passed. Raw outputs: fire_modes_tests.log and fire_modes_compile.log in this directory.

During development, fixed a HUD type-inference compile error and the test harness's initial incorrect expectation of 11 eligible weapons (the data contains 10). Final evidence above is after both fixes and after the active-burst repress guard.

## Remaining integration checks

Real rendered desktop/mobile HUD layout, live host/client firing under network delay and authoritative cancellation in world.server_set_mode. Headless codec tests do not establish a physical phone's frame rate or a live network play-through. No commercial firing-behavior benchmark was supplied; independent benchmark comparison remains unverified.
