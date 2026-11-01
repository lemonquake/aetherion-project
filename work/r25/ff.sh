#!/usr/bin/env bash
# Mall firefight benchmark: bash work/r25/ff.sh <name> [port] [extra args...]
cd "$(dirname "$0")/../../game"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
F="$(cd .. && pwd -W)/work/r25"
name=${1:-ff}
port=${2:-28260}
shift 2 2>/dev/null
mkdir -p $F/$name
timeout 600 "$GODOT" --path . -- --host --game_mode=deathmatch --map=malasugue_mall --autostart=1 --bots=11 --autotest=firefight \
  --ff_at=18,0,-10 --ff_look=-8,1.2,4 "$@" --shots=$F/$name --size=1280x720 --port=$port --autotest_timeout=500 > $F/$name/run.log 2>&1
echo "$name exit $?"
grep -h '\[firefight\]\|\] PASS\|\] FAIL\|SCRIPT ERROR' $F/$name/run.log | cut -c1-300
