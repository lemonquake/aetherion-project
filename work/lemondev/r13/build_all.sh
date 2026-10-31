#!/usr/bin/env bash
# r13 builds (r12 and r13 ship together): Windows EXE and both Android APKs at 0.13.0 from the current tree. As the
# user asked in r12, old builds go: the 0.9.0 EXE, the 0.10.0 APKs and the r8 preview folder; the 0.11.0 EXE/APKs are
# overwritten. builds/_android_stage is the APK build's working copy, not a build: kept.
cd "$(dirname "$0")/../../.."
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
L=work/lemondev/r13/build
mkdir -p $L builds/windows builds/android
rm -f builds/windows/Aetherion-0.9.0.exe builds/android/Aetherion-0.10.0.apk builds/android/Aetherion-opengl-0.10.0.apk builds/android/*.idsig
rm -rf builds/r8-preview
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
