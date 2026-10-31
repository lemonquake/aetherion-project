#!/usr/bin/env bash
# r14 spectator A/B: the r13 bot LOD rule (--bot_lod_r13) against the r14 one, same seed and test.
cd "$(dirname "$0")/../../game"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
F=A:/Python/aetherion-project/work/r14
run() {
    local name=$1 port=$2; shift 2
    mkdir -p $F/$name
    timeout 900 "$GODOT" --path . -- --host --game_mode=deathmatch --autostart=1 --bots=20 "$@" --shots=$F/$name --size=1280x720 \
        --port=$port --autotest_timeout=800 > $F/$name/run.log 2>&1
    echo "$name exit $?"
    grep -h '\] PASS\|\] FAIL\|SCRIPT ERROR' $F/$name/run.log | cut -c1-700
    grep -h '^\[perf\] [a-z]' $F/$name/run.log | cut -c1-200
}
run spec_r13 28113 --autotest=r14 --r14_only=zone,spectate --bot_lod_r13
run spec_r14 28114 --autotest=r14 --r14_only=zone,spectate
