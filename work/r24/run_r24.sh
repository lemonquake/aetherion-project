#!/usr/bin/env bash
# r24 checks on a Deathmatch listen host: bash work/r24/run_r24.sh <name> [port] [extra args...]
# (e.g. --r24_only=round). Captures and results go to work/r24/<name>/.
cd "$(dirname "$0")/../../game"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
F="$(cd .. && pwd -W)/work/r24"
name=${1:-run}
port=${2:-28240}
shift 2 2>/dev/null
mkdir -p $F/$name
rm -f $F/$name/*.png
timeout 900 "$GODOT" --path . -- --host --game_mode=deathmatch --autostart=1 --bots=20 --autotest=r24 --matchlog "$@" --shots=$F/$name --size=1280x720 \
    --port=$port --autotest_timeout=800 > $F/$name/run.log 2>&1
echo "$name exit $?"
grep -h '\] PASS\|\] FAIL\|SCRIPT ERROR\|ERROR:' $F/$name/run.log | cut -c1-700 | head -60
