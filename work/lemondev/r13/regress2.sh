#!/usr/bin/env bash
# r13 final-tree regression, after the radio static, canal haul-out, step-up and bot field-path fixes:
# r13 all, r12 all, dm, r11 subset, canal, bursts, the kerb step lab, the net test. Results: work/lemondev/r13/final2/.
cd "$(dirname "$0")/../../../game"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
F=A:/Python/aetherion-project/work/lemondev/r13/final2
mkdir -p $F
run() {
    local name=$1 port=$2; shift 2
    mkdir -p $F/$name
    timeout 1500 "$GODOT" --path . -- --host --game_mode=deathmatch --autostart=1 "$@" --shots=$F/$name --size=1280x720 \
        --port=$port --autotest_timeout=1400 > $F/$name/run.log 2>&1
    echo "$name exit $?: $(grep -c '\] PASS' $F/$name/run.log) pass, $(grep -c '\] FAIL' $F/$name/run.log) fail"
    grep -h '\] FAIL\|SCRIPT ERROR' $F/$name/run.log | cut -c1-400
}
run r13 27901 --bots=20 --autotest=r13
run r12 27902 --bots=20 --autotest=r12
run dm 27903 --bots=20 --autotest=dm
run r11 27904 --bots=20 --autotest=r11 --r11_only=teams,pa,cage,haze,kerbs,stairs
run canal 27905 --bots=4 --autotest=canal
run bursts 27906 --bots=4 --autotest=bursts
timeout 600 "$GODOT" --headless --path . res://tools/step_lab.tscn > $F/step_lab.log 2>&1
echo "step lab: $(grep -o ':ok' $F/step_lab.log | wc -l) ok, $(grep -o ':BLOCKED' $F/step_lab.log | wc -l) blocked (baseline 132 ok, 24 blocked at 0.50/0.55 m)"
PORT=27907 bash ../tools/net_test.sh > $F/net_test.log 2>&1
mkdir -p $F/net && cp -r ../work/screens/net/* $F/net/ 2>/dev/null
grep -h "FAIL" $F/net_test.log
tail -1 $F/net_test.log
echo "regression done"
