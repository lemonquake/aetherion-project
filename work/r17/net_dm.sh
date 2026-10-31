#!/usr/bin/env bash
# r17: a real client in a Deathmatch respawn round on Malasugue Mall (dedicated server): floor spawn, death, countdown,
# respawn into a new body it controls, kill scored for the killer's team (game/src/debug/autotest_net.gd, role "dm").
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../../game"
OUT=A:/Python/aetherion-project/work/r17/net_dm
rm -rf ../work/r17/net_dm; mkdir -p ../work/r17/net_dm
PORT=${PORT:-24641}
timeout 300 "$GODOT" --headless --path . -- --server --port=$PORT --game_mode=deathmatch --map=malasugue_mall --teams=3 --bots=8 \
  --dm_win=score --dm_score=50 --day_len=120 --autostart=2 --expect_players=1 --testcheats --matchlog --match_seed=5 > ../work/r17/net_dm/server.log 2>&1 &
SRV=$!
sleep 3
timeout 240 "$GODOT" --path . -- --join=127.0.0.1 --port=$PORT --name=Delta --autotest=net_dm --shots=$OUT --size=1280x720 > ../work/r17/net_dm/client.log 2>&1
RC=$?
kill $SRV 2>/dev/null
grep -h "autotest-\|\[autotest\]" ../work/r17/net_dm/client.log
grep -h "respawned\|killed by\|deathmatch start" ../work/r17/net_dm/server.log | head -12
echo "client exit $RC"
