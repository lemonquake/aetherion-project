# Living checklist

Status of every requirement in the brief, with the evidence behind it. **Tested** means an automated run or an
inspected capture on this machine exercised it; **Implemented** means the code exists but no run has verified it
yet; **Incomplete** and **Blocked** say what is missing. Updated 2026-10-26 (furnished rooms, 30–40 player map,
bot level of detail; loot, loot boxes, weapon attachments and scopes, bot looting — version 0.3.0).

Test machine: Windows 10 Pro, RTX 4060, Godot 4.7.2, 1600×900 window unless noted.
Evidence folders (not committed, regenerate with the commands in the README): `work/screens/t9/` (host
play-through), `work/screens/net/` (two clients), `work/screens/L1`, `L2` (lighting previews), `work/items/`
(model checks), bot-match logs from `--matchlog`, `work/scale/` (map size, benchmarks, 40-bot matches).

## 2026-10-27 polish run (version 0.5.0)

Evidence: `work/lemondev/r3/` (contract, final captures, logs). All on the final revision unless noted.

| Requirement (owner, 2026-10-27) | Status | Evidence / notes |
|---|---|---|
| Artificial sun: night for 5 min, then 5 min of daylight, looping | Tested | `day_cycle_schedule`; same courtyard view luma 32 at night → 99 at noon (PC), 34 → 96 (phone profile); `sun_ignites` (31 → 99 within 12 s); notices 30 s and 5 s ahead, siren, ignition and dusk hums. Driven by the server tick, so every machine changes at the same moment |
| Roofed inner lanes stay dark by day; little lights in them; flashlight needed | Tested | `tunnel_dark_at_noon`: 7–27 luma inside vs 99 outside, flashlight adds 6–16; also on the phone profile (no shadow maps): 17–23 vs 96. 97 roofed lanes and estero walks (1.5 km), 210 bulbs (19 dead, the first of every lane always lit), 20 candle shrines |
| Richer, intentional map (pathways, 3rd floors, rooftops, ladders, vault boxes and windows, vandalism, dirt, rust, eerie) | Tested (counts, captures, blind review) | `map_*` checks: 16% of houses three storeys, 178 roof decks, 85 ladders, 25 courtyards, 88 crate stacks, 291 low walls, 18 sandbag rows, 9 junk barricades, 80 vacant-lot ruins, 2,646 glassless windows sized to vault, crawl-through holes between neighbours, 5,389 decals. A fresh-context reviewer shown only anonymised captures picked the new map over the owner's Sleep captures for this criterion, with a clear advantage (`work/lemondev/r3/critic/`) |
| Ladders | Tested | `ladder_climb` (2.6–5.1 m up and back down, PC and phone profile, exported EXE); network `ladder_predicted`: 0 corrections |
| Vault on crates | Tested | `crate_vault` (vaulted over 0.9–1.4 m crates); kiosk-side steps are 1.2 m deep so you climb on to them |
| 20 bots by default; 40–50 player matches | Tested (lobby, benchmarks) | Lobby shows 20 bots and a 50-player cap (PC and Android emulator); 49-bot host benchmarks in [PERFORMANCE.md](PERFORMANCE.md). Not run with 50 human clients |
| Compass under the minimap with numbers | Tested | `compass_bearing` reads back 0/90/120/225/330 exactly; visible at 1600×900 and on the phone profile (1800×810) and the emulator |
| Radio voice heard by eavesdroppers; key clicks | Tested (routing, playback; not by ear) | `radio_eavesdrop`: near a teammate's radio → speech from that radio; near the speaker → their voice; 45 m away → nothing; overheard frames play positionally on the Radio bus. Network: teammate receives voice packets over the new protocol. Key-up click and squelch tail from every radio. No microphone test |
| Builds | Tested | `builds/windows/Aetherion.exe` (0.5.0): r3 checks 19/19, clean exit. `builds/android/Aetherion.apk` and `-opengl.apk` (366 MB each): OpenGL APK installed on the emulator, practice match started, map fingerprint #1375a694 identical to the PC |
| Regressions | Tested | `--autotest=fixes` 26/26 (stairs 24/24 after fixing two causes found here), network test 17/17 |

## Automated checks

| Run | Result |
|---|---|
| `tools/check.sh` (compile all scripts) | 67 scripts, 0 failed |
| Loot play-through `--autotest=loot` (11 bots; editor loot4 and the exported EXE loot_exe2, version 0.3.0) | 29 checks, 0 failed on both: model census, loot boxes and floor loot counts, items resting on surfaces, ten attachment-effect checks, pickups, a loot box opening, sights on the bullet line, scope views, another player's attachments and laser |
| Host play-through `--autotest=tour` (t23, 31 bots, after the loot work) | 26 checks, 0 failed (includes `flashlight_lights_room`: the same view must get clearly brighter when the flashlight comes on) |
| Same play-through on the exported EXE (31 bots, version 0.3.0, t26_exe) | 26 checks, 0 failed, clean exit. One run (t25_exe, with a second game running on the machine) failed `team_cluster`: a bot teammate 73.5 m away under canopy against a 60 m limit; five other runs 31–41 m |
| Same play-through on the phone profile (`--mobile --rendering-method mobile`, 15 bots, 1800×810) | 29 checks, 0 failed (adds three touch-control checks driven by screen touches) |
| Frame-rate benchmark `--autotest=perf` (deploy + six ground spots, 1600×900, vsync off) | Measured under 40–70% background CPU load from other work: 54–372 fps by phase with 11 bots, 29–227 fps with 31 bots; frames over 16.7 ms at the busy ground spots. First pass (idle machine, full map, 11 bots): 117–528 fps. See [PERFORMANCE.md](PERFORMANCE.md) |
| Two-client network test `tools/net_test.sh` | 14 checks, 0 failed (dedicated server + two separate client processes, same PC), rerun after the loot work (ground items are now physics/render resources without scene nodes) |
| Bot-only match, 40 bots, `--zone_speed=2` | Reaches a valid winner ("winner team 2 after 472 s"); see Bots below |
| Door swing check `map_preview --doorcheck` | 7 of 2,272 outer doors jammed by a heavy prop (was 187 before the fixes below) |

## Phones, PCs and cross-play

| Requirement | Status | Evidence / notes |
|---|---|---|
| Android build | Tested (emulator) | `builds/android/Aetherion.apk`, 333 MB, Android 7+ (arm64, x86_64), Mobile renderer. Installed and started on an Android 16 emulator; that emulator cannot present Vulkan frames, so the in-game checks below ran on the OpenGL variant (`Aetherion-opengl.apk`, same build otherwise) |
| Windows build | Tested | `builds/windows/Aetherion.exe` (1.1 GB, single file): exported EXE passes the host play-through (26 checks, 0 failed); steady 60 fps (vsync) through aircraft and free fall with `--print-fps` |
| Phone joins a PC match | Tested | Android app joined a PC dedicated server (6 bots): lobby shows "Phone · Mobile", match started, the phone's player jumped with its squad and landed (server log) |
| Same map on phone and PC | Tested (x86 Android) | Fingerprint #3aa3e7d7 on the PC server and on the Android client (2,240 buildings, 4,736 doors, 5,768 containers, 15,451 props); the server compares every client's and warns on a mismatch. Not yet compared on an ARM phone |
| Version check | Implemented | Version from `project.godot` (now 0.2.0, since the map changed); other versions are turned away at join |
| Phone hosts a practice match | Tested (emulator) | Practice with bots from the phone's menu: lobby, map built in 32.6 s, match played |
| Touch controls | Tested | Play-through on the mobile profile injects screen touches: stick moved 2.4–5.5 m, a drag turned the view 0.60 rad, the Light button toggled the flashlight; on the emulator, adb touches moved, turned and lit the flashlight |
| Phone UI | Tested | UI drawn 1.5× on phones; captures of menu, Play panel, lobby and HUD at 2400×1080; fullscreen (Android immersive); microphone permission asked at the menu |
| Phone frame rate | Not measured on a phone | No phone was available. Mobile profile on this PC (Mobile renderer, 15 bots, under 60% background load): 94–114 fps on the ground, 520–980 draw calls, render CPU 2.3–3.3 ms. See [PERFORMANCE.md](PERFORMANCE.md) |

## Match flow and deployment

| Requirement | Status | Evidence / notes |
|---|---|---|
| Main menu with the title, settings, lobby, teams, ready | Implemented | Menu and lobby screens exist; not re-captured this session |
| Loading, synchronised start | Tested | Host and dedicated-server runs; loading waits for every client |
| Aircraft pass, team jumps together | Tested | `jump` check; match log shows each team leaving at its own point; an aircraft (built in code, with navigation lights) and an engine drone during the pass |
| Teammates start their descent close together | Tested | Under canopy, farthest teammate 12.9–36.7 m; bots land as squads 3–60 m apart |
| Steering, braking, flare, landing consequences | Tested (landing) | Landing at full forward speed costs 15 health; canopy snags no longer cut away high up |
| Jumping only over the play area | Fixed | The flight path runs past the map edge and a team forced out at its end fell forever; jumps now open over land and the last team leaves before the aircraft crosses out; free fall opens by altitude with no ground below; anyone outside the world is put back on land |
| Restricted zone with warnings | Tested | Zone phases shrink on schedule; damage outside; warnings at 60/30/10 s |
| Winner, results | Tested | Bot-only match ended "winner team 2 after 139 s" |
| Rematch and full world reset | Implemented | `--rematch` path exists; not run this session |

## Darkness, lighting, flashlights

| Requirement | Status | Evidence / notes |
|---|---|---|
| Very few, dim practical lights; faulty ones | Tested | ~500 lane bulbs, ~570 doorway lights, ~1,040 of 2,240 houses lit in 1–2 rooms (bulb, tube, battery lantern, candle); flicker, dying, failing-starter, brownout faults; lit houses change per match, same for every player |
| Interiors darker than lanes | Tested | Screenshots (t22): unlit rooms dark, bulb-lit rooms lit, lanes under bulbs |
| Flashlight lights the scene | Fixed | It never did: unlit room 0.0 → 32.6 and 20.1 → 40.6 in the centre of the view now (0–255). Three causes: (1) every wall in the map was wound inside out (box side faces in `GeoSink.FACES`), so you saw each wall's far face, lit from the wrong side: no lamp or flashlight inside a room lit its walls, and the moon lit them through the wall; (2) the beam pattern was an RGB8 image, which projected black; (3) the pattern kept full strength only in a small hot centre. Also: your own body no longer shadows your beam |
| Shadow budget (no light through walls nearby) | Implemented | Nearest 4/8/12 lights cast shadows by quality; the light manager keeps only lamps within their fade distance in the scene; no lamp shadows above the rooftops |
| Battery drain, low-charge warning, death, swap with a window of vulnerability | Tested | `low_battery_flag`, `battery_dies`, `battery_swap_started` (2.25 s), `battery_replaced` |
| Batteries looted from a dead player | Tested | `corpse_battery_looted`: 0 → 2 |
| Other players' lights visible | Tested | Observer capture shows the lit lens; host now draws bots' flags |
| Weapon-mounted vs handheld light handling | Implemented | Rules in code; not captured |

## Weapons and projectiles

| Requirement | Status | Evidence / notes |
|---|---|---|
| Real weapon models | Tested | Processed CC-BY models (1911, revolver, 870, MP5, Uzi, M16, AK) plus CC0 pistol and bolt rifle; first-person captures |
| Bullets travel with drop | Tested | 5.56 at 940 m/s: 310 m in 0.383 s, 0.66 m drop, 702 m/s left |
| Recoil moves the actual aim | Tested | View climbed 1.15° after a shot |
| Draw / fire | Tested | `draw_rifle`, `rifle_fired` |
| Penetration, ricochet, arm-injury sway, headshots, helmets | Implemented | Server code and data exist; not exercised by a test yet |
| Attachments shown on weapons | Tested | 27 attachments over six mounts, drawn on the first-person and third-person gun at mount points found from each model's shape (captures loot3/loot4); other players see them (`observer_attachments`: 5 of 5 drawn from the replicated mask) |
| Attachment effects | Tested | `att_*` checks: 4x zoom, aim time x1.06 with 4x + angled grip, vertical kick 1.68 -> 1.34 (compensator) -> 1.14 deg (+ vertical grip), hip spread 2.40 -> 1.56 deg (laser), magazine 30 -> 40, reload 2.50 -> 1.75 s, suppressor loudness x0.30 / flash x0.10 / suppressed sound, choke pattern x0.65 |
| Scopes like PUBG (1x, 2x, 3x, 4x, 6x, 8x) | Tested | Red dot 0.4 px and holographic 0.9 px from where the bullets go while aiming; 4x and 6x scope views with field of view 20.0 / 13.3 deg and the gun hidden; reticles: dot, holo ring, 2x circle-dot, 3x chevron, 4x ACOG ladder, 6x mil-dot, 8x duplex |
| More guns | Tested (captures) | Double-barrel shotgun (break action, both barrels reload together: `break_action_reload`), the sumpak (improvised 12-gauge) and a .308 marksman rifle, modelled in code |
| Guns held the right way | Fixed | The Poly Haven 9 mm pistol and bolt rifle are modelled along x: the pistol was held sideways and the rifle stood on end on the ground; both now point forward (t23 `gun_pistol_9`, loot lineup) |

## Health, bodies, looting

| Requirement | Status | Evidence / notes |
|---|---|---|
| Every drop has a real model | Tested | `loot_models_census`: 59 droppable ids, no placeholder boxes. New models made in code (tools/blender/make_loot_models.py): 25 attachments, battery, bandage, painkillers, splint, two backpacks, eight calibre-labelled ammunition boxes, three guns, eight loot boxes with open lids |
| Loot scattered across the map | Tested | 6,574–6,641 items on the ground at the start (about 1,100 guns, 2,500 ammunition stacks, 1,200 attachments); a gun found loose usually has its ammunition beside it |
| Loot boxes, many, mostly in houses | Tested | 3,832 loot boxes (3,737 inside buildings, for 2,072 houses, shops and apartments): balikbayan boxes, storage bins, footlockers, rifle cases, iceboxes, toolboxes, ammo cans, first aid cases; Use opens the contents on the SmarTab and the lid opens for everyone; late joiners get the opened lids |
| Items rest on what is under them | Tested | `floor_items_rest`: 941 of 941 sampled items 0-5 cm above a surface (each item settles on the surface under it when the match is set up; spots with nothing solid under them get no loot) |
| Picking up fits attachments; ammunition named for your gun | Tested | `pickup_fits_scope`, `pickup_ammo_named`, `gun_takes_bag_attachments`; SmarTab Weapons page with Fit / Off per mount |
| Ragdoll corpse, lootable, persists | Tested | `corpse_spawned`, `corpse_opened`, `corpse_persists` |
| Downed and revive for squads | Partly tested | A squad member goes down before dying (corpse test); revive not exercised |
| Blood on surfaces and characters | Implemented | Blood decal textures now imported; not captured |

## SmarTab and UI

| Requirement | Status | Evidence / notes |
|---|---|---|
| Hold TAB: weapon lowered, device raised in the left hand, readable | Tested | `smartab_raised` / `smartab_lowered`; captures of the status, items and map pages |
| No minimap or permanent HUD | Tested | Captures show only a small reticle and context prompts |
| Master volume: 100 plays at 75 %, debug unlock for full | Tested | `master_volume_cap`: slider 100 → 0.750 of full output on the Master bus; 1.000 with Settings → Debug → "Unlock master volume" |

## Sound

| Requirement | Status | Evidence / notes |
|---|---|---|
| Sound set built (guns near/far, impacts, doors, foley, footsteps, radio, synthesised cues) | Tested | 108 sound ids from CC0/CC-BY libraries and synthesis (`tools/build_audio.py`) |
| Room-and-opening propagation | Implemented | Acoustic routing rewritten to stay fast indoors (it froze the game before); not listened to |
| Night ambience reacting to gunfire | Implemented | Insects, frogs, dogs, geckos, owl/nightjar; not listened to |
| Reload sounds heard by others | Implemented | Server events on magazine out / in |
| Radio cue when a teammate transmits | See Multiplayer | |

Nothing in this table has been checked by ear: the test runs cannot capture audio.

## Multiplayer

| Requirement | Status | Evidence / notes |
|---|---|---|
| Clients survive the 40 s map build | Fixed | ENet's default timeout dropped every client while it built the map, so dedicated-server matches started without them; peer timeout raised to 90–180 s |
| Floor loot identical on every client | Tested | Rolled from the match seed on every machine (was a 1,300-item reliable message that arrived a minute late and held up every other reliable event) |
| A door opened by one client is open for the other | Tested | `door_open_local`, `door_open_seen_by_other` (target 1.65 rad on both) |
| A window broken by one client is broken for the other | Tested | `window_broken_local`, `window_broken_seen_by_other` |
| Flashlight state visible to others | Tested | `flashlight_seen_by_other` |
| Radio cue: a teammate's transmission shows on the transmitting character, packets reach teammates | Tested | `radio_cue_seen_by_teammate`: flag seen, 25 packets (synthetic frames, no microphone) |
| Two players cannot claim the same item | Tested | Both clients press Use on one item at the same moment; server log: Alpha took it, Bravo's press in the same tick found nothing |
| Quick taps are never lost | Fixed | Taps of Use, fire, reload, heal, jump, flashlight are latched from input events; at under 20 fps a tap could fall between two input samples and vanish |
| Client prediction stays close to the server | Tested | Whole match on one client: 4 corrections (3 are the test's own teleports), none while running. Fixed: the server invented movement when a packet was late; it dropped inputs beyond 12 queued; and replays ran outside the physics step, where `move_and_slide` uses the render delta (free fall and canopy were corrected ~460 times by up to 16 m) |
| Reconnect / late join | Implemented | Not run this session. Late joiners now get only the floor-item changes (items taken, items dropped) and the opened loot-box lids |
| Clean exit | Fixed | The exported game crashed on quitting (heap corruption, exit code 0xC0000374) after ground items became server-side render instances; the map now frees its bodies and render instances when it leaves the tree (on quit and on return to the menu). EXE runs loot_exe2 and t26_exe exit 0 |

## Bots

| Requirement | Status | Evidence / notes |
|---|---|---|
| Deploy as squads near their flight path; follow a human teammate's jump | Tested | Match logs |
| Enter houses through doors and search containers | Partly working | 40-bot match: bots opened up to 178 containers at once in play (17–18 per 16-bot match before); many approaches still fail |
| Loot what they need | Tested | `[lootstats]` (run5, 40 bots): 89-95% of armed bots carry ammunition for their gun (18 of 19 at 120 s), 0 rounds of unusable ammunition carried, attachments fitted by bots, 60+ loose items picked up on detours. Bots value a gun first, then its ammunition, attachments that improve it, armour, a bigger bag, medicine and batteries |
| Arm themselves and fight | Incomplete | About half of 40 bots are armed after 2-4 minutes; 5-8 bots at a time are stuck in river channels and many door approaches fail (bot navigation, not loot); bot-only matches mostly end in the zone (run5: 34 shots in 389 s) |
| Server cost | Tested | 40 bots on a dedicated server: tick average 4–6 ms, p99 6–10 ms, worst 16 ms (without bot level of detail 9–12 ms, p99 12–17 ms, worst 24 ms). Bots far from every human think and move every 2nd or 4th tick; the same-seed comparison shows no loss in looting or fighting |

## Map

| Requirement | Status | Evidence / notes |
|---|---|---|
| Raised front doors reachable on foot | Fixed | Entrance steps built for every outer door above the lane (houses on slopes and stilts) |
| First map sized for 30–40 players | Tested | `Layout.MAP_SCALE` 0.65: ~650 m of play area, 2,239 buildings (was 5,007), build 21–26 s (was ~44 s). Matches fill to 32 players (one human + 31 bots), up to 40. River, bridges and districts kept; sites checked for overlaps with roads, water and each other |
| Furnished rooms | Tested | Poly Haven furniture and plants load from decimated single-material copies (trees ~12k triangles, from up to 2.1 million); captures show furniture in dark rooms |
| Doors not jammed by clutter | Fixed | Doors swing toward whoever opens them, into lanes 1.2–2 m wide: 8% of outer doors were jammed by a bottle, bucket, drum or bench. Doors now shove light resting props aside, and heavy props are not placed in a door's swing (lane clutter, drums by the door, room furniture) |
| Map review from player viewpoints, collision snags, floating objects | Incomplete | Only the views captured so far |

## Known limitations

- The loot models are made in code: clean but simple next to the processed photo-scanned guns. There is no PUBG
  capture on this machine to compare the scope views or attachments against, so that comparison is not done.
- Frame cost of the loot: on the PC (RTX 4060, 1600x900, 11 bots, ~100% background CPU load) the densest ground spot takes 10.4-10.7 ms with loot and 9.7 ms with every ground item and loot box hidden (about 0.9 ms; 110-200 of ~3,300 draw calls); fixed ground spots against the same morning's baseline: market 7.27 -> 7.36 ms, looban 7.12 -> 7.55 ms, looban_east 10.65 -> 9.83 ms, rail 7.09 -> 6.88 ms. Not measured on a phone.

- First-person arms are simple procedural sleeves and gloves; the handguns read as dark shapes from behind.
- The red dot and holographic sights are now made in code (the downloaded holographic sight carried a
  manufacturer's logo and is no longer used); the 4x prism scope is still the processed download.
- The C-130 and parachute models are downloaded but not yet used (the aircraft and canopy are built in code).
- Frame rate measured with the scripted benchmark only (one machine, RTX 4060). Draw calls still dominate at the
  densest spots (2,000–3,500); see [PERFORMANCE.md](PERFORMANCE.md).
- Nothing has run on a real phone: the Android checks used an x86_64 emulator, and its Vulkan could not present,
  so the in-game phone checks used the OpenGL variant. Frame rate on phones, the Vulkan build's picture on Android,
  and map agreement on ARM are unverified. No iOS build.
- The APK is signed with the Android SDK's debug key; a store release needs your own key (README).
- On the emulator, Android's microphone indicator was lit at the main menu right after the permission was granted
  (audio input is enabled in the project for the radio); not investigated further.
- With 31 bots on a host, the busiest ground spots run below 60 fps on this machine (measured under heavy
  background load); a dedicated server takes the server half of the frame off the player's machine.
- Many verification scenarios in the brief (bottle distraction, furniture noise and barricades, arm and leg
  injuries, helmets, headshots, concurrent destruction under latency) have no automated test yet.
