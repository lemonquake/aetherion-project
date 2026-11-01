#!/usr/bin/env bash
# r23: bake one map's nav + waypoints, then the strict waypoint QA (pictures + json in work/r23/qa)
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
m="$1"; port="${2:-27750}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" && BAKE_PORT=$((port - 40)) bash tools/bake_botnav.sh "$m" > /dev/null 2>&1
grep -E "\[waypoints\] (baked|.*generated)|SCRIPT ERROR" tools/cache/botnav_$m.log | cut -c1-400
cd "$root/game"
mode=deathmatch; [ "$m" = "kalinaw" ] && mode=classic
qa="$(cd "$root/work/r23/qa" && pwd -W)"
timeout 1200 "$GODOT" --headless --path . -- --server --game_mode=$mode --map=$m --bots=2 --autostart=1 --expect_players=0 --wpqa="$qa" --port=$port > "$root/work/r23/qa/$m.log" 2>&1
grep -E "\[wpqa\]|SCRIPT ERROR" "$root/work/r23/qa/$m.log"
