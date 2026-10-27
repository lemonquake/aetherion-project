#!/usr/bin/env bash
# Imports new or changed assets into the Godot project (retries: the headless editor sometimes crashes on exit or
# while loading its layout, after or before the import step).
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../game"
for i in 1 2 3 4 5; do
  "$GODOT" --headless --path . --import > ../tools/cache/import.log 2>&1
  missing=$(find assets \( -name "*.png" -o -name "*.jpg" -o -name "*.glb" -o -name "*.wav" -o -name "*.ogg" \) | while read f; do [ -f "$f.import" ] || echo "$f"; done | wc -l)
  if [ "$missing" = "0" ]; then
    # Textures loaded from scripts are never auto-detected as 3D: give them VRAM compression and mipmaps
    # (fresh downloads arrive with the editor's lossless, mipmap-less defaults), then import those again.
    fixed=$(python -I ../tools/fix_texture_imports.py | awk '{print $2}')
    [ "$fixed" = "0" ] && { echo "import ok"; exit 0; }
    echo "texture settings fixed on $fixed files, importing them again"
    continue
  fi
  echo "attempt $i: $missing files still unimported"
done
exit 1
