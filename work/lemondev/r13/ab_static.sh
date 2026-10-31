#!/usr/bin/env bash
# Does the radio static change what bots do in the r12 field checks and the r13 voice checks? Each runs with
# rules.json radio.static on and off (restored afterwards), REPS times. Also reruns dm once. Results:
# work/lemondev/r13/ab/<static>_<test>_<rep>/.
cd "$(dirname "$0")/../../../game"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
F=A:/Python/aetherion-project/work/lemondev/r13/ab
REPS=${REPS:-2}
cp data/rules.json ../work/lemondev/r13/rules_backup.json
trap 'cp ../work/lemondev/r13/rules_backup.json data/rules.json' EXIT
set_static() {
    python -I - "$1" <<'EOF'
import sys
p = 'data/rules.json'
s = open(p, 'rb').read().decode('utf-8')
a, b = ('"static": false', '"static": true') if sys.argv[1] == 'on' else ('"static": true', '"static": false')
s = s.replace(a, b, 1)
open(p, 'wb').write(s.encode('utf-8'))
EOF
}
run() {
    local name=$1 port=$2; shift 2
    mkdir -p $F/$name
    timeout 600 "$GODOT" --path . -- --host --game_mode=deathmatch --bots=20 --autostart=1 "$@" --shots=$F/$name --size=1280x720 \
        --port=$port --autotest_timeout=500 --matchlog --radiolog > $F/$name/run.log 2>&1
    echo "$name: $(grep -h '\] PASS\|\] FAIL' $F/$name/run.log | sed 's/\[autotest\] //' | cut -c1-150 | tr '\n' '|')"
}
port=27700
for rep in $(seq 1 $REPS); do
    for st in on off; do
        set_static $st
        port=$((port + 1)); run ${st}_field_$rep $port --autotest=r12 --r12_only=field,fieldhouse
        port=$((port + 1)); run ${st}_voice_$rep $port --autotest=r13 --r13_only=voice
    done
done
set_static on
port=$((port + 1)); run dm_rerun $port --autotest=dm
echo "ab done"
