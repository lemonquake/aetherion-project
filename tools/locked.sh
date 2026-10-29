#!/usr/bin/env bash
# Runs a command while holding a named lock (an atomic mkdir), so parallel builders never run the Godot import or the
# script check at the same time (both rewrite shared files).
#   bash tools/locked.sh import bash tools/import.sh
#   bash tools/locked.sh check bash tools/check.sh
name="$1"; shift
dir="$(dirname "$0")/cache/$name.lockdir"
mkdir -p "$(dirname "$0")/cache"
n=0
until mkdir "$dir" 2>/dev/null; do
  sleep 3
  n=$((n+1))
  if [ $n -gt 400 ]; then echo "[locked] $name: stale lock? removing"; rmdir "$dir" 2>/dev/null; fi
done
trap 'rmdir "$dir" 2>/dev/null' EXIT
"$@"
