#!/usr/bin/env bash
# r4 regression sequence (one game process at a time: they share the default port).
cd /a/Python/aetherion-project
R=work/lemondev/r4/final
mkdir -p $R
run() { # name seconds args
  powershell -ExecutionPolicy Bypass -File tools/run_timed.ps1 -Seconds $2 -Log $R/$1.log -ArgLine "$3"
  echo "== $1: $(grep -a -c 'autotest\] PASS' $R/$1.log) pass, $(grep -a -c 'autotest\] FAIL' $R/$1.log) fail"
}
run r4 1100 "--path game -- --host --bots=11 --autostart=1 --autotest=r4 --shots=A:/Python/aetherion-project/$R/r4 --autotest_timeout=1080"
run fixes 1100 "--path game -- --host --bots=3 --autostart=1 --autotest=fixes --autotest_timeout=1050 --shots=A:/Python/aetherion-project/$R/fixes"
run r3 700 "--path game -- --host --bots=11 --autostart=1 --autotest=r3 --autotest_timeout=680 --shots=A:/Python/aetherion-project/$R/r3"
run tour 700 "--path game -- --host --bots=11 --autostart=1 --matchlog --autotest=tour --autotest_timeout=680 --shots=A:/Python/aetherion-project/$R/tour"
bash tools/net_test.sh > $R/net.log 2>&1; echo "== net: $(grep -a -c 'PASS' $R/net.log) pass, $(grep -a -c 'FAIL' $R/net.log) fail"
bash tools/online_test.sh > $R/online.log 2>&1; tail -1 $R/online.log
run perf 700 "--path game -- --host --bots=19 --autostart=1 --autotest=perf --autotest_timeout=680 --shots=A:/Python/aetherion-project/$R/perf"
echo "== all done"
