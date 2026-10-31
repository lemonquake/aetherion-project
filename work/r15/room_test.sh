#!/usr/bin/env bash
# r15: lobby host rights on an official (dedicated) server: alpha joins first and hosts, bravo joins second.
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../../game"
OUT=../work/r15/room; rm -rf $OUT; mkdir -p $OUT
P=${PORT:-27497}
"$GODOT" --headless --path . -- --server --official --game_mode=deathmatch --port=$P --bots=4 --stats_server=127.0.0.1:9 > $OUT/server.log 2>&1 &
S=$!
sleep 4
"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$P --name=Alpha --room_test=alpha > $OUT/alpha.log 2>&1 &
A=$!
sleep 4
"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$P --name=Bravo --room_test=bravo > $OUT/bravo.log 2>&1 &
B=$!
wait $A; wait $B
kill $S 2>/dev/null
"$GODOT" --headless --path . -- --server --official --game_mode=classic --port=$((P+1)) --bots=4 --stats_server=127.0.0.1:9 > $OUT/server_solo.log 2>&1 &
S2=$!
sleep 4
timeout 60 "$GODOT" --headless --path . -- --join=127.0.0.1 --port=$((P+1)) --name=Solo --room_test=solo > $OUT/solo.log 2>&1
kill $S2 2>/dev/null
grep -h "\[roomtest\]" $OUT/alpha.log $OUT/bravo.log $OUT/solo.log
grep -h "started the match\|start refused" $OUT/server.log $OUT/server_solo.log
