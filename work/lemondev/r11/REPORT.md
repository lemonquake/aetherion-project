# r11 — Deathmatch map (Lawless Sub): hard QA and fixes

Status: **IMPLEMENTED — UNVERIFIED** for "ship-ready". All r11 functional gates pass on the final tree (one
sidewalk-sweep run had 4 stalls, explained below). A blind review prefers the new build over the old one. The
commercial-benchmark gate, real-phone performance, hearing the announcer by ear and a full EXE/APK build were not
done. Nothing is committed (base 430ea9e).

## QA verdict (before the fixes)

| Question | Finding at the start of the run |
|---|---|
| Ship-ready, or low-quality AI slop? | **Not ship-ready.** It read as a procedural prototype: large empty brown lots, rows of repeated boxy houses, dark blotches across every ceiling and the office tower, flat-colour box skyline, mostly empty rooms (the clubhouse hall had nothing in it). |
| Does the map make sense? | Yes, as a layout: an avenue and a boulevard crossing at the centre, two canals, walled subdivision blocks, a factory and a mart. It is big for 21 players (440 m square). |
| Walkable paths / elevated sidewalks? | Mostly. Kerb step-ups work. The overpass stairs stand on the avenue sidewalks, and walking under their low end trapped the player. Bots' saved stuck spots cluster along the estero fence, which is closed by design except at the three crossings. |
| Textures suitable / on theme? | Poly Haven photo textures, on theme for a Philippine subdivision. Defects: paint-flake blotches on ceilings and the tower; sand-like roof decks; a wavy repeating crack pattern on the avenue asphalt. |
| Fun spots (3-storey houses, rooftops, mall)? | None of it existed. No house had more than 2 floors: Canal Row's 3-floor setting was ignored. Roofs could only be reached by ladder. The "Lawless Mart" was a one-room convenience store, not a mall. |
| Assets readable; ammo colours by weapon? | Nine calibre colours exist (9 mm yellow, .45 blue, 5.56 green, 7.62 red, .308 purple, buckshot orange, ...). The boxes were real size (10-13 cm), too small to read on the ground. |
| AI smart / objective / cooperation? | Yes, within limits. Bots have roles (looter, rusher, sniper, stalker), states (hunt, overwatch, follow, fight, investigate), squads and radio callouts, and they move with the zone. Only 1 of 21 died to the zone. |
| Spots you can't get through, and why? | The overpass stair wedge. The estero fence (by design: cross at the bridges). Everything else is walkable (see the sweep below). |
| Cage walls and speakers? | Not there. The edge was a 3.4 m concrete wall, and the announcer spoke from small horns on street poles, with lines naming the other map ("Sitio Kalinaw"). |
| Bullet impacts with after-smoke? | There was a puff, chips and sparks, gone within about 1.5 s. Nothing lingered. |

## What changed

- **3 teams of up to 7 each** (default 3 x 7; the host can pick 2 or 3 teams and 1-7 players per team). The teams
  are North, East and South, and they spawn at the flats parking, a new East Yard and a new South Yard, 326, 353 and
  343 m apart. The first zone centres on the middle of the three spawns. The lobby, HUD team bar, kill feed colours,
  results screen and bots all handle a third team. Files: rules.json, net.gd, lobby_ui.gd, ui_theme.gd, hud.gd,
  match_server.gd, bot_brain.gd, sub_layout.gd and the plan.
- **Steel cage** round the whole arena (sub_works._perimeter):
  - 10 m galvanised steel panels on I-section posts, with rails, a yellow hazard band, an inward-leaning mesh
    overhang and wire along its edge.
  - Welded, chained gates where roads meet it, and bar grilles over the canal outlets.
  - It also draws at long range, so it rings the map from anywhere.
- **Big speakers**: 28 stacks on frames above the wall top (two 2.4 m black cabinets with grilles and woofer rings,
  two horns with 1.6 m mouths, a work lamp and a red beacon) and a horn tower in each corner. These are the map's PA.
- **Cage announcer** (tools/make_cage_announcer.py, 27 lines plus the chime and siren):
  - The voice is offline Windows TTS (David), slowed and dropped about a semitone.
  - It goes through a radio link (key-up click, 300-3400 Hz band, presence peak, clipping, hiss, squelch tail),
    then an overdriven speaker stack, then the arena (flutter echo between steel walls, slap-back delays from
    0.18 to 1.3 s, and a 3 s tail). A duller "far" version plays for distant listeners.
  - In game, the 3 nearest stacks speak at once and each is delayed by its distance, so the line rolls across the
    arena.
  - Lines: day/night 60 s and 30 s warnings, a 10-1 countdown and the siren; trial start, containment closing,
    final phase, team eliminated, trial over; and an ambient line about every 100 s ("Remain calm. You are being
    observed.", "Do not approach the perimeter wall.", ...). Each shows as a subtitle.
- **Lawless Mall** (big_plans._mall, on the block south-east of the central intersection):
  - Two floors round an open atrium with a glass balustrade, and a 2 m grand stair in the concourse.
  - 13 shop units with full-width storefronts, a food court, a supermarket, an arcade hall, a management office
    and toilets.
  - A service stair core that carries on up to the roof deck, and entrances on three sides.
  - Named shop signs and a "Lawless Mall" sign on the roof edge.
  - New building-kit features: floor voids, storefront links, the concourse and boutique room types, and stairs
    up through flat roofs.
- **3-storey houses with roof decks**:
  - A third of the full-size houses, and every Canal Row shophouse whose row asks for 3 floors, get a third floor
    (family room, bedroom, bath).
  - It is reached by a switchback flight, and a third flight goes up through a flat roof deck with a parapet.
  - The tower and the flats' stair cores now also reach their roofs. Roof decks are concrete instead of sand.
- **Impact after-dust**: hits now leave a slow cloud that hangs 3-4 s and drifts up. Each material has its own
  colour: grey dust on concrete and plaster, brown on soil, sawdust on wood, and a thin wisp off metal.
- **Ammo** lies on the ground at 1.9x a single box's size, in the same calibre colours.
- **Texture slop fixes**:
  - No paint-flake blotches on ceilings; fewer on the tower facade and steel plate.
  - Large halls now get rows of tables and chairs, a buffet line and clutter.
- **Walkability**: the overpass stairs moved 0.3 m outward (the bypass is now 1.4 m) and got a solid base under the
  low end, so nobody wedges under them.

## Evidence (final tree)

| Gate | Result |
|---|---|
| `--autotest=r11` three teams | PASS: 7 / 7 / 7, spawns 326+ m apart |
| `--autotest=r11` cage PA | PASS: 28 cage stacks + 4 towers; start line played; the 3 nearest stacks are on the cage |
| `--autotest=r11` cage holds | PASS: a player sprinting and jumping into the wall stops 0.4-0.7 m inside its line; a chest-height ray stops on it |
| `--autotest=r11` impact haze | PASS (at5): luma change 2.92 at 0.15 s, 2.29 at 1.5 s, 0.32 at 4 s, against 0.35 with no hit. It failed in at4 (0.99 at 1.5 s), before the cloud was strengthened |
| `--autotest=r11` kerbs | PASS: 24/24 kerb approaches (square and at 35 degrees) step up without jumping |
| `--autotest=r11` sidewalk sweep | at4: 182 legs of 30 m (5.4 km), 4 stalled. 1 = a wrecked bus on the boulevard where the Acacia leg crosses the road. 3 = Molave St, which did not reproduce: a rerun of all 18 Molave legs (at6) had 0 stalls |
| `--autotest=r11` upper stairs | PASS: 24 upper flights (third floors and roof decks, 12 ending above 8.5 m) climbed |
| `--autotest=dm` (updated for 3 x 7) | PASS 7/7 (map, teams 7/7/7, kit, spawn, own body, arms, haze) |
| Headless 21-bot matches | seed 1729: North Team won at 320 s, 598 shots, 1 zone death. Seed 4242: East Team won at 361 s, 1,571 shots, 0 zone deaths. No script errors |
| Classic regression smoke | Kalinaw builds the same map (#49929ca0) and plays (11 bots, 2 min), no script errors |
| Announcer audio | After processing: 1.1 % of energy under 300 Hz and 0.06 % over 4.5 kHz (the raw TTS had 27.8 % and 2.7 %). Tail 3.2 s. Spectrograms in qa/announcer_spectrogram.png. **Not checked by ear.** |
| Blind review 1 (critic1) | UNVERIFIED. The baseline captures came after the overhead plan view, which forces full detail for the rest of the run, so they were not comparable; the intersection camera now sits inside the mall |
| Blind review 2 (critic2, same capture order) | The new build won 5 of 6 views, 2 clearly (tower facade, clubhouse hall). The old build won 1 narrowly (a street with the new flat-roof houses) |

Captures: qa/ (base = before, after2 = after with the same capture order), r11_showcase.png. Logs: at1-at7,
dm_gate, qa/dm3_match1.log, qa/dm3_match2.log, qa/classic_smoke.log.

## Not done / remaining largest gaps

1. **Interior walls still read as greybox** (blind reviewer's largest gap): cloudy plaster, no skirting boards and
   nothing mounted on the walls.
2. **Big empty brown lots** and flat lawn colour, especially seen from the air. The avenue asphalt has a wavy
   repeating crack pattern. The distant skyline is plain boxes.
3. The map is large for 21 players (440 m). A smaller arena would raise the encounter rate; it was not changed.
4. Not measured: commercial benchmark comparison (none on disk), frame rate on this build, phones, the announcer by
   ear, a full EXE/APK build. The licence of the TTS voice for commercial release is still unchecked.
5. The test sweep runs at 1x time scale. At 3x, `_try_step` popped the player 0.8 m (a test artefact, not seen at
   1x).

## Builds (0.11.0, 2026-10-29)

`bash work/lemondev/r11/build_all.sh` (version bumped 0.10.0 -> 0.11.0 because the map, rules and netcode changed;
phones and PCs must run the same version):

| Build | Result |
|---|---|
| builds/windows/Aetherion.exe | exit 0, 60 s, 1.81 GB |
| builds/android/Aetherion.apk (Vulkan) | exit 0, 118 s, 561 MB |
| builds/android/Aetherion-opengl.apk | exit 0, 58 s, 561 MB |
| Kept for A/B | builds/android/Aetherion-0.10.0.apk, Aetherion-opengl-0.10.0.apk; builds/windows/Aetherion-0.9.0.exe |

EXE smoke test (`work/lemondev/r11/exe_test.ps1`, the exported EXE as a listen host on Deathmatch, 20 bots):
`--autotest=dm` 7/7 PASS, exit 0; `--autotest=r11` (teams, pa, cage, haze, kerbs, stairs) 6/6 PASS, exit 0. Map
fingerprint in the EXE: #b1fba961. Not run: the APKs on the emulator or a phone (map fingerprint match with the PC
is unchecked for 0.11.0).
