#!/usr/bin/env bash
# r6 gate, second batch: what failed in the first batch, rerun on the current revision, plus the phone layout.
cd "$(dirname "$0")/../../.."
G=work/lemondev/r6/gates2
mkdir -p $G
run() {  # name, seconds, args
  powershell -ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds $2 -Log $G/$1.log -ArgLine "$3"
  echo "== $1: $(grep -c 'autotest\] PASS' $G/$1.log) pass, $(grep -c 'autotest\] FAIL' $G/$1.log) fail"
}
A=A:/Python/aetherion-project/$G
run r6 700 "--path game -- --host --bots=11 --autostart=1 --autotest=r6 --shots=$A/r6 --port=27515"
run r6_phone 400 "--path game -- --mobile --rendering-method mobile --host --bots=11 --autostart=1 --autotest=r6 --r6_only=smartab,blood --r6_fast=1 --shots=$A/r6_phone --port=27521"
run tour 900 "--path game -- --host --bots=11 --autostart=1 --autotest=tour --shots=$A/tour --port=27516"
run fixes_grab 600 "--path game -- --host --bots=11 --autostart=1 --autotest=fixes --fixes_only=grab,sounds --shots=$A/fixes_grab --port=27517"
run r4 700 "--path game -- --host --bots=11 --autostart=1 --autotest=r4 --r4_only=holes,chunks,realism --shots=$A/r4 --port=27519"
echo "gates2 done"
