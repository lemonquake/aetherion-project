#!/usr/bin/env bash
# Multiplayer on the exported build: a dedicated server and two clients, all builds/windows/Aetherion.exe, running the
# net test (game/src/debug/autotest_net.gd: Alpha and Bravo on one team, 6 bots). MIX=1 runs Bravo from the source
# tree instead (another build of the same version must join the same match: the cross-build check phones rely on).
# Results: work/lemondev/r13/exe_net[_mix]/.
cd "$(dirname "$0")/../../.."
EXE="$PWD/builds/windows/Aetherion.exe"
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
NAME=exe_net$([ "$MIX" = 1 ] && echo _mix)
OUT=A:/Python/aetherion-project/work/lemondev/r13/$NAME
D=work/lemondev/r13/$NAME
rm -rf $D; mkdir -p $D
PORT=${PORT:-24731}
timeout 600 "$EXE" --headless -- --server --port=$PORT --bots=6 --autostart=2 --expect_players=2 --testcheats --netdebug --match_seed=11 > $D/server.log 2>&1 &
SRV=$!
sleep 4
timeout 560 "$EXE" -- --join=127.0.0.1 --port=$PORT --name=Alpha --netdebug --autotest=net_a --shots=$OUT > $D/alpha.log 2>&1 &
A=$!
sleep 1
if [ "$MIX" = 1 ]; then
    (cd game && timeout 560 "$GODOT" --path . -- --join=127.0.0.1 --port=$PORT --name=Bravo --autotest=net_b --shots=$OUT) > $D/bravo.log 2>&1 &
else
    timeout 560 "$EXE" -- --join=127.0.0.1 --port=$PORT --name=Bravo --autotest=net_b --shots=$OUT > $D/bravo.log 2>&1 &
fi
B=$!
wait $A; RA=$?
wait $B; RB=$?
kill $SRV 2>/dev/null
grep -h "autotest-" $D/alpha.log $D/bravo.log
grep -h "\[map\]\|version" $D/server.log | head -5
echo "alpha exit $RA, bravo exit $RB"
