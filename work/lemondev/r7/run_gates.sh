#!/usr/bin/env bash
# r7 gate: Deathmatch on Lawless Sub (PC and phone profile) plus the Classic regression suites on Sitio Kalinaw,
# all on the current revision. Logs and captures in work/lemondev/r7/gates/.
cd "$(dirname "$0")/../../.."
G=work/lemondev/r7/gates
mkdir -p $G
run() {  # name, seconds, args
  powershell -ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds $2 -Log $G/$1.log -ArgLine "$3"
  echo "== $1: $(grep -c 'autotest\] PASS' $G/$1.log) pass, $(grep -c 'autotest\] FAIL' $G/$1.log) fail, $(grep -c 'SCRIPT ERROR' $G/$1.log) script errors"
}
A=A:/Python/aetherion-project/$G
run dm 400 "--path game -- --host --game_mode=deathmatch --bots=19 --autostart=1 --autotest=dm --shots=$A/dm --port=27701 --autotest_timeout=300"
run dm_phone 400 "--path game -- --mobile --rendering-method mobile --host --game_mode=deathmatch --bots=19 --autostart=1 --autotest=dm --shots=$A/dm_phone --port=27702 --autotest_timeout=300"
run tour 900 "--path game -- --host --bots=11 --autostart=1 --autotest=tour --shots=$A/tour --port=27703"
run fixes 900 "--path game -- --host --bots=11 --autostart=1 --autotest=fixes --shots=$A/fixes --port=27704"
run r6 700 "--path game -- --host --bots=11 --autostart=1 --autotest=r6 --shots=$A/r6 --port=27705"
run r3 700 "--path game -- --host --bots=11 --autostart=1 --autotest=r3 --shots=$A/r3 --port=27706"
echo "r7 gates done"
