#!/usr/bin/env bash
# r13 final-tree regression (after the radio static and follow_me recordings): r13 all, r12 all, dm, r11 subset, net.
# Results: work/lemondev/r13/final/<test>/ (run.log, results.json, captures).
cd "$(dirname "$0")/../../../game"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
F=A:/Python/aetherion-project/work/lemondev/r13/final
run() {
    local name=$1 port=$2; shift 2
    mkdir -p $F/$name
    timeout 900 "$GODOT" --path . -- --host --game_mode=deathmatch --bots=20 --autostart=1 "$@" --shots=$F/$name --size=1280x720 \
        --port=$port --autotest_timeout=800 > $F/$name/run.log 2>&1
    echo "$name exit $?: $(grep -c '\] PASS' $F/$name/run.log) pass, $(grep -c '\] FAIL' $F/$name/run.log) fail"
    grep -h '\] FAIL' $F/$name/run.log
}
run r13 27621 --autotest=r13
run r12 27622 --autotest=r12
run dm 27623 --autotest=dm
run r11 27624 --autotest=r11 --r11_only=teams,pa,cage,haze,kerbs,stairs
PORT=27625 bash ../tools/net_test.sh > $F/net_test.log 2>&1
mkdir -p $F/net && cp -r ../work/screens/net/* $F/net/ 2>/dev/null
tail -1 $F/net_test.log
grep -h "FAIL" $F/net_test.log
echo "regression done"
