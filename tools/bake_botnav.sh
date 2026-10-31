#!/usr/bin/env bash
# r21: makes the bot navigation files the game ships with (game/data/botnav/<map>.json): for each map, a headless
# server with one bot builds the map, runs BotNav's walk check and its waypoint / hiding-spot analysis at once, writes
# the file and quits. Run after any change to a map's geometry and on every version bump (the files are keyed to the map
# build and the game version; a stale file is ignored and the analysis runs in the match instead).
#   bash tools/bake_botnav.sh                 # every map
#   bash tools/bake_botnav.sh malasugue_mall  # one
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../game"
mkdir -p data/botnav ../tools/cache
MAPS="${*:-malasugue_mall freight_delight lawless_sub kalinaw}"
port=27700
for m in $MAPS; do
  port=$((port + 1))
  mode=deathmatch
  [ "$m" = "kalinaw" ] && mode=classic
  timeout 900 "$GODOT" --headless --path . -- --server --game_mode=$mode --map=$m --bots=2 --autostart=1 --expect_players=0 \
    --botnav_bake --port=$port > ../tools/cache/botnav_$m.log 2>&1
  echo "== $m exit $?"
  grep -E "\[botnav\]|\[nav\]|SCRIPT ERROR" ../tools/cache/botnav_$m.log | head -8
done
ls -la data/botnav
