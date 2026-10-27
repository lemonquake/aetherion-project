#!/usr/bin/env bash
# Compile-checks every GDScript in the project, auto-fixing ":=" inference errors, and prints failures.
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/../game"
for i in 1 2 3 4; do
  "$GODOT" --headless --path . res://tools/check_scripts.tscn > ../tools/cache/check.txt 2>&1
  r=$(python -I ../tools/fix_infer.py ../tools/cache/check.txt)
  [ "$r" = "fixed 0" ] && break
done
grep -A1 "Parse Error\|Compile Error\|SCRIPT ERROR" ../tools/cache/check.txt | grep -v "Preload file\|Cannot infer the type of \"[A-Z][A-Za-z]*\" constant\|Failed to compile depended\|^--$\|backtrace\|_ready (res://tools/check_scripts" | paste - - | sed 's/SCRIPT ERROR: //; s/   at: GDScript::reload //' | sort -u | head -30
grep "checked\|^FAIL" ../tools/cache/check.txt
