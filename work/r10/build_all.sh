#!/usr/bin/env bash
# r10 builds: Windows EXE and both Android APKs from the current revision (0.10.0). The 0.9.0 EXE is kept for A/B.
cd "$(dirname "$0")/../.."
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
L=work/r10/build
mkdir -p $L
[ -f builds/windows/Aetherion-0.9.0.exe ] || mv builds/windows/Aetherion.exe builds/windows/Aetherion-0.9.0.exe
python -I tools/write_export_presets.py > $L/presets.log 2>&1
echo "presets: $?"
t0=$(date +%s)
(cd game && "$GODOT" --headless --path . --export-release "Windows Desktop" ../builds/windows/Aetherion.exe) > $L/exe.log 2>&1
echo "exe: $? in $(( $(date +%s) - t0 )) s, $(stat -c %s builds/windows/Aetherion.exe 2>/dev/null) bytes"
t0=$(date +%s)
python -I tools/build_android.py > $L/apk.log 2>&1
echo "apk: $? in $(( $(date +%s) - t0 )) s, $(stat -c %s builds/android/Aetherion.apk 2>/dev/null) bytes"
t0=$(date +%s)
python -I tools/build_android.py --gl --out builds/android/Aetherion-opengl.apk > $L/apk_gl.log 2>&1
echo "apk_gl: $? in $(( $(date +%s) - t0 )) s, $(stat -c %s builds/android/Aetherion-opengl.apk 2>/dev/null) bytes"
echo "builds done"
