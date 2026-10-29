#!/usr/bin/env bash
# Online flow, end to end on one PC: a stats server (--master), a host (Alpha) and a client (Bravo) with their own
# profiles. Checks presence, the open-game list, joining, a finished match reported to the stats server, the
# leaderboard and both profiles' XP. Results and logs: work/lemondev/r4/online/.
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../game"
OUT=../work/lemondev/r4/online
rm -rf $OUT; mkdir -p $OUT/data
MP=27431
GP=24641
pass=0; fail=0
check() { if [ "$2" = "1" ]; then echo "[online] PASS $1: $3"; pass=$((pass+1)); else echo "[online] FAIL $1: $3"; fail=$((fail+1)); fi; }
APPDATA_DIR="$APPDATA/Godot/app_userdata/Aetherion Project by Aljay Leodones"
rm -f "$APPDATA_DIR/profile_alpha.json" "$APPDATA_DIR/profile_bravo.json"

"$GODOT" --headless --path . -- --master --master_port=$MP --data=$(cd $OUT/data && pwd -W) > $OUT/master.log 2>&1 &
M=$!
sleep 3
"$GODOT" --path . --resolution 960x540 -- --host --port=$GP --bots=2 --autostart=1 --expect_players=2 --name=Alpha --profile=alpha \
  --stats_server=127.0.0.1:$MP --end_after=25 --quit_after_results --match_seed=5 > $OUT/alpha.log 2>&1 &
A=$!
sleep 6
# Presence and the game list while Alpha waits for Bravo.
G=$(curl -s http://127.0.0.1:$MP/games)
echo "$G" > $OUT/games.json
check open_game "$(echo "$G" | grep -c '"host":"Alpha"' | tr -d ' ' | sed 's/^[1-9][0-9]*$/1/')" "$(echo "$G" | head -c 300)"
"$GODOT" --path . --resolution 960x540 -- --join=127.0.0.1 --port=$GP --name=Bravo --profile=bravo --stats_server=127.0.0.1:$MP --quit_after_results > $OUT/bravo.log 2>&1 &
B=$!
sleep 8
O=$(curl -s http://127.0.0.1:$MP/online)
echo "$O" > $OUT/online.json
both=0; echo "$O" | grep -q '"name":"Alpha"' && echo "$O" | grep -q '"name":"Bravo"' && both=1
check presence $both "$(echo "$O" | head -c 400)"
wait $A; RA=$?
wait $B; RB=$?
sleep 3
L=$(curl -s "http://127.0.0.1:$MP/leaderboard?by=xp")
echo "$L" > $OUT/leaderboard.json
lb=0; echo "$L" | grep -q '"name":"Alpha"' && echo "$L" | grep -q '"name":"Bravo"' && lb=1
check leaderboard $lb "$(echo "$L" | head -c 500)"
xa=$(python -c "import json;print(json.load(open(r'$APPDATA_DIR/profile_alpha.json'))['xp'])" 2>/dev/null || echo 0)
xb=$(python -c "import json;print(json.load(open(r'$APPDATA_DIR/profile_bravo.json'))['xp'])" 2>/dev/null || echo 0)
ok=0; [ "${xa:-0}" -gt 0 ] && [ "${xb:-0}" -gt 0 ] && ok=1
check profiles_xp $ok "Alpha $xa XP, Bravo $xb XP"
grep -h "\[game\] results" $OUT/alpha.log $OUT/bravo.log
kill $M 2>/dev/null
sleep 1
saved=0; [ -f $OUT/data/stats.json ] && grep -q Bravo $OUT/data/stats.json && saved=1
check saved $saved "stats.json on disk"
echo "[online] $pass passed, $fail failed (alpha exit $RA, bravo exit $RB)"
