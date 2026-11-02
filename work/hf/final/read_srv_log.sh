#!/bin/bash
f="/tmp/aeth_srv_test/data/godot/app_userdata/Aetherion Project by Aljay Leodones/logs/godot.log"
wc -l "$f"
grep -v "^\[loadout\]" "$f" | grep -v "^   at:" | head -${1:-80}
