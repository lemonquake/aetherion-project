#!/usr/bin/env bash
# r25 checks on a Malasugue Mall Deathmatch listen host: bash work/r25/run.sh <name> <autotest> [port] [extra args...]
# Captures and results go to work/r25/<name>/.
cd "$(dirname "$0")/../../game"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
F="$(cd .. && pwd -W)/work/r25"
name=${1:-run}
test=${2:-bursts}
port=${3:-28250}
shift 3 2>/dev/null
mkdir -p $F/$name
rm -f $F/$name/*.png
timeout 900 "$GODOT" --path . -- --host --game_mode=deathmatch --map=malasugue_mall --autostart=1 --bots=4 --autotest=$test "$@" --shots=$F/$name --size=1280x720 \
    --port=$port --autotest_timeout=800 > $F/$name/run.log 2>&1
echo "$name exit $?"
grep -h '\] PASS\|\] FAIL\|SCRIPT ERROR\|ERROR:' $F/$name/run.log | cut -c1-700 | head -60
