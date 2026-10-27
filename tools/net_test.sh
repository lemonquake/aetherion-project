#!/usr/bin/env bash
# Two real clients on a local dedicated server (see game/src/debug/autotest_net.gd). Results: work/screens/net/.
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../game"
OUT=A:/Python/aetherion-project/work/screens/net
rm -rf ../work/screens/net; mkdir -p ../work/screens/net
PORT=${PORT:-24631}
timeout 600 "$GODOT" --headless --path . -- --server --port=$PORT --bots=6 --autostart=2 --expect_players=2 --testcheats --netdebug --match_seed=11 > ../work/screens/net/server.log 2>&1 &
SRV=$!
sleep 3
timeout 560 "$GODOT" --path . -- --join=127.0.0.1 --port=$PORT --name=Alpha --netdebug --autotest=net_a --shots=$OUT > ../work/screens/net/alpha.log 2>&1 &
A=$!
sleep 1
timeout 560 "$GODOT" --path . -- --join=127.0.0.1 --port=$PORT --name=Bravo --autotest=net_b --shots=$OUT > ../work/screens/net/bravo.log 2>&1 &
B=$!
wait $A; RA=$?
wait $B; RB=$?
kill $SRV 2>/dev/null
grep -h "autotest-" ../work/screens/net/alpha.log ../work/screens/net/bravo.log
echo "alpha exit $RA, bravo exit $RB"
