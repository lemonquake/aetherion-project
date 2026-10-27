# Fix run 2026-10-27 — handoff

Revision: working tree on `master` (uncommitted), game version 0.4.0. Patches applied in order: `tools/patches/p70`–`p91`.

## State

**IMPLEMENTED — UNVERIFIED** overall: all listed fixes are in and pass their automated checks on PC, but there is no
PUBG reference capture (visual parity not graded), no real-phone run, and PC frame time is within noise of yesterday's
build except possibly +1 ms indoors.

| Item | Evidence (final revision) |
|---|---|
| Guns on house floors, in boxes | `floor_guns_in_houses` 90% of 2,072 houses (5,518 guns); balikbayan rolls 32% guns |
| Loot readable at night | `floor_gun_visible` 1,725 px of gun in an unlit room, no flashlight (faint self-glow, no extra pass) |
| Stairs | `stairs_climbable` 24/24 real flights climbed and stepped off upstairs |
| Tab beside a box | `tab_opens_box` balikbayan: 2 of 2 entries listed, lid opens |
| T grabs, E takes items | `grab_with_t`, `use_takes_items` |
| Lite minimap, V ping | `ping_minimap` (green, gone after 5 s); net: `ping_seen_by_teammate` |
| Doors | opens forward, walk-through (1 unexplained stuck doorway in 7 runs), push swings on, latches shut with sound |
| Vaulting | 5/6 windows (6th: no room outside), gun lowered and restored; net `vault_predicted` 0 corrections |
| Trash | bag blocks neither movement nor bullets; 601 heaps without collision |
| Weapons | 24 guns fire/kick/reload; calibre groups (5.56: AR-15, SCAR-L, M416, M249, Mini 14); frag grenade |
| Sounds | 46/46 work/sounds files used; doors -4.4 dB (60%), ambience default 60% |
| Network | 16/16 two-client checks |
| Perf (RTX 4060, 1600x900 High, release EXE) | medians old vs new at fixed spots: market 8.8/9.5, looban 9.7/11.4, looban_east 12.4/13.5, rail 8.6/8.6, indoor 9.2/10.9 ms; identical builds vary up to 2.7 ms on this (loaded) machine |
| Phone profile on PC (mobile renderer) | 140–170 fps; 1 crash (0xC0000005 at the first ground-tier shader compile) on the build before the final one, 3 clean runs on the final build, old build 1 clean run |

Independent review (fresh-context critic) found: weak captures, a Tab test on an empty icebox, a cartoon Vector model,
an untested E pickup, S686/Sumpak test threshold, perf regression. All but performance were fixed and rechecked.

## Largest remaining gap

Performance on real phones is unmeasured, and the one phone-profile crash is not explained. Recheck: install
`builds/android/Aetherion.apk` on a low-end phone, play a full match from the plane to the ground in a dense block;
pass if no crash and p95 frame time ≤ 33 ms.

## Smallest next actions

1. Real-phone run (above). 2. If a doorway stalls again, the `door_walk_through` failure now prints slide collisions
and threshold heights. 3. Optional: MultiMesh ground items if draw calls matter on phones.

## Commands

    godot --path game -- --host --bots=3 --autostart=1 --autotest=fixes --autotest_timeout=950 --shots=<dir>
    bash tools/net_test.sh
    powershell -ExecutionPolicy Bypass -File tools/perf_exe.ps1 -Exe builds\windows\Aetherion.exe -Tag <tag>
