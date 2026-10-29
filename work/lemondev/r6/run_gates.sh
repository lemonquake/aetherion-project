#!/usr/bin/env bash
# r6 integration gate: every earlier run's regression suite plus r6, one after another on this revision.
cd "$(dirname "$0")/../../.."
G=work/lemondev/r6/gates
mkdir -p $G
run() {  # name, seconds, args
  powershell -ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds $2 -Log $G/$1.log -ArgLine "$3"
  echo "== $1: $(grep -c 'autotest\] PASS' $G/$1.log) pass, $(grep -c 'autotest\] FAIL' $G/$1.log) fail"
}
A=A:/Python/aetherion-project/$G
run r6 600 "--path game -- --host --bots=11 --autostart=1 --autotest=r6 --shots=$A/r6 --port=27515"
run tour 900 "--path game -- --host --bots=11 --autostart=1 --autotest=tour --shots=$A/tour --port=27516"
run fixes 1200 "--path game -- --host --bots=11 --autostart=1 --autotest=fixes --shots=$A/fixes --port=27517"
run r3 900 "--path game -- --host --bots=11 --autostart=1 --autotest=r3 --shots=$A/r3 --port=27518"
run r4 900 "--path game -- --host --bots=11 --autostart=1 --autotest=r4 --shots=$A/r4 --port=27519"
run r5 900 "--path game -- --host --bots=11 --autostart=1 --autotest=r5 --r5_fast=1 --shots=$A/r5 --port=27520"
bash tools/net_test.sh > $G/net.log 2>&1
echo "== net: $(grep -c 'PASS' $G/net.log) pass, $(grep -c 'FAIL' $G/net.log) fail"
echo "gates done"
