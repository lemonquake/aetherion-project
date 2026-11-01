#!/usr/bin/env bash
# Regression run: bash work/r25/reg.sh <name> <port> <args...>   (results in work/r25/<name>/)
cd "$(dirname "$0")/../../game"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
F="$(cd .. && pwd -W)/work/r25"
name=$1; port=$2; shift 2
mkdir -p $F/$name
timeout 1500 "$GODOT" --path . -- --host --autostart=1 "$@" --shots=$F/$name --size=1280x720 --port=$port --autotest_timeout=1400 > $F/$name/run.log 2>&1
echo "$name exit $?"
grep -h '\] PASS\|\] FAIL\|SCRIPT ERROR' $F/$name/run.log | cut -c1-400 | head -40
