#!/usr/bin/env bash
# r12 C5: headless Deathmatch bot matches (3 teams x 7 bots, field at double speed), match log on. Prints the field
# deaths and the "field watch" lines (bots indoors in the field's path when it started closing) per match.
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../../../game"
OUT=../work/lemondev/r12/bots${1:+_$1}
mkdir -p "$OUT"
for seed in ${SEEDS:-11 12}; do
  timeout 900 "$GODOT" --headless --path . -- --server --game_mode=deathmatch --bots=21 --autostart=1 --expect_players=0 \
    --match_seed=$seed --zone_speed=2 --matchlog --quit_after_results=1 --port=$((27600 + seed)) > "$OUT/match_$seed.log" 2>&1
  echo "== seed $seed exit $?"
  grep -E "zone [0-9]+ shrinking|crushed by the field|\[field death\]|\[field watch\]|match over|SCRIPT ERROR" "$OUT/match_$seed.log"
done
