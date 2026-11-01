#!/usr/bin/env bash
# r23: one bot match per map with --navwatch (stalls, wall-facing). Usage: navwatch_all.sh <outdir> [extra args...]
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
out="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; shift
mkdir -p "$out"
cd "$(dirname "$0")/../../game"
port=27810
for m in malasugue_mall freight_delight lawless_sub kalinaw; do
  port=$((port + 1))
  if [ "$m" = "kalinaw" ]; then
    timeout 900 "$GODOT" --headless --path . -- --server --game_mode=classic --map=$m --bots=40 --autostart=1 --expect_players=0 \
      --matchlog --navwatch="$out/$m.json" --quit_after_results=1 --port=$port "$@" > "$out/$m.log" 2>&1 &
  else
    timeout 900 "$GODOT" --headless --path . -- --server --game_mode=deathmatch --map=$m --bots=21 --autostart=1 --expect_players=0 \
      --dm_win=time --dm_time=10 --matchlog --navwatch="$out/$m.json" --quit_after_results=1 --port=$port "$@" > "$out/$m.log" 2>&1 &
  fi
done
wait
for m in malasugue_mall freight_delight lawless_sub kalinaw; do echo "== $m"; grep -E "\[navwatch\]" "$out/$m.log" | tail -3; grep -c "SCRIPT ERROR" "$out/$m.log"; done
