#!/usr/bin/env bash
# r15 (0.16.0): the release exports the launcher installs and the official server runs, then both Android APKs.
cd "$(dirname "$0")/../../.."
L=work/r15/build
python -I tools/write_export_presets.py > $L/presets.log 2>&1
echo "presets: $? $(tail -1 $L/presets.log)"
t0=$(date +%s)
bash tools/release/export_all.sh linux windows macos > $L/export.log 2>&1
echo "exports: $? in $(( $(date +%s) - t0 )) s"
grep "exit" $L/export.log
t0=$(date +%s)
python -I tools/build_android.py > $L/apk.log 2>&1
echo "apk: $? in $(( $(date +%s) - t0 )) s, $(stat -c %s builds/android/Aetherion.apk 2>/dev/null) bytes"
t0=$(date +%s)
python -I tools/build_android.py --gl --out builds/android/Aetherion-opengl.apk > $L/apk_gl.log 2>&1
echo "apk_gl: $? in $(( $(date +%s) - t0 )) s, $(stat -c %s builds/android/Aetherion-opengl.apk 2>/dev/null) bytes"
ls -la builds/release/windows builds/release/linux builds/release/macos builds/android
echo "builds done"
