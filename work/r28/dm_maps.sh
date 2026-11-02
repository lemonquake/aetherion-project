#!/usr/bin/env bash
# r28: a Deathmatch bot match on every DM map (headless dedicated server), for the grenade pickups' log lines.
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../../game"
SECS=${SECS:-300}
p=7801
for m in ${MAPS:-malasugue_mall freight_delight lawless_sub hidden_forest}; do
  timeout $((SECS + 400)) "$GODOT" --headless --path . -- --server --port=$p --game_mode=deathmatch --map=$m --bots=${BOTS:-20} \
    --autostart=1 --expect_players=0 --matchlog --match_seed=${SEED:-28} --end_after=$SECS --quit_after_results \
    > ../work/r28/${TAG:-}$m.log 2>&1 &
  p=$((p + 1))
done
wait
