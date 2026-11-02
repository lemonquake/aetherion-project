#!/bin/bash
# Runs the exported Linux server on a map with bots for a while (WSL): bash linux_server_test.sh <map> <seconds> <log>
B=/mnt/a/Python/aetherion-project/builds/release/linux/aetherion_server.x86_64
export HOME=/tmp/aeth_srv_test XDG_DATA_HOME=/tmp/aeth_srv_test/data
mkdir -p $XDG_DATA_HOME
timeout -s INT "$2" stdbuf -oL -eL "$B" --headless -- --server --port=27991 --game_mode=deathmatch --map="$1" --teams=3 --team_size=7 --bots=21 --autostart=1 --expect_players=0 --matchlog > "$3" 2>&1
echo "exit $?" >> "$3"
