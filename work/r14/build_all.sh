#!/usr/bin/env bash
# r14 builds: Windows EXE and both Android APKs at 0.14.0 from the current tree (version from project.godot). The
# 0.13.0 builds are overwritten (same file names). builds/_android_stage is the APK build's working copy: kept.
cd "$(dirname "$0")/../.."
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
L=work/r14/build
mkdir -p $L builds/windows builds/android
python -I tools/write_export_presets.py > $L/presets.log 2>&1
echo "presets: $? $(tail -1 $L/presets.log)"
t0=$(date +%s)
(cd game && "$GODOT" --headless --path . --export-release "Windows Desktop" ../builds/windows/Aetherion.exe) > $L/exe.log 2>&1
echo "exe: $? in $(( $(date +%s) - t0 )) s, $(stat -c %s builds/windows/Aetherion.exe 2>/dev/null) bytes"
t0=$(date +%s)
python -I tools/build_android.py > $L/apk.log 2>&1
echo "apk: $? in $(( $(date +%s) - t0 )) s, $(stat -c %s builds/android/Aetherion.apk 2>/dev/null) bytes"
t0=$(date +%s)
python -I tools/build_android.py --gl --out builds/android/Aetherion-opengl.apk > $L/apk_gl.log 2>&1
echo "apk_gl: $? in $(( $(date +%s) - t0 )) s, $(stat -c %s builds/android/Aetherion-opengl.apk 2>/dev/null) bytes"
ls -la builds/windows builds/android
echo "builds done"
