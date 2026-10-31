#!/usr/bin/env bash
# Exports the release builds the launcher installs and the official server runs (tools/write_export_presets.py):
#   bash tools/release/export_all.sh [linux] [windows] [macos]     (no arguments: all three)
# Output in builds/release/<platform>/, logs in builds/release/export_<platform>.log.
GODOT="${GODOT:-/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/../../game" || exit 1
want="${*:-linux windows macos}"
status=0
for p in $want; do
  case "$p" in
    linux)   preset="Linux Server"; out="../builds/release/linux/aetherion_server.x86_64" ;;
    windows) preset="Windows Release"; out="../builds/release/windows/Aetherion.exe" ;;
    macos)   preset="macOS"; out="../builds/release/macos/Aetherion.zip" ;;
    *) echo "unknown platform $p"; exit 2 ;;
  esac
  mkdir -p "$(dirname "$out")"
  rm -rf "$(dirname "$out")"/*
  echo "[export] $preset -> $out"
  start=$(date +%s)
  "$GODOT" --headless --path . --export-release "$preset" "$out" > "../builds/release/export_$p.log" 2>&1
  rc=$?
  echo "[export] $preset exit $rc in $(( $(date +%s) - start )) s"
  grep -i "error" "../builds/release/export_$p.log" | grep -v "^ERROR: Condition \"!FileAccess::exists" | head -5
  ls -la "$(dirname "$out")"
  [ $rc -ne 0 ] && status=$rc
done
exit $status
