#!/usr/bin/env bash
# r11 builds: Windows EXE and both Android APKs from the current revision (0.11.0). The 0.10.0 APKs are kept for A/B.
cd "$(dirname "$0")/../../.."
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
L=work/lemondev/r11/build
mkdir -p $L builds/windows
[ -f builds/android/Aetherion-0.10.0.apk ] || mv builds/android/Aetherion.apk builds/android/Aetherion-0.10.0.apk
[ -f builds/android/Aetherion-opengl-0.10.0.apk ] || mv builds/android/Aetherion-opengl.apk builds/android/Aetherion-opengl-0.10.0.apk
rm -f builds/android/*.idsig
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
