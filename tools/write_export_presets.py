"""Writes game/export_presets.cfg: a Windows build and an Android build of the same game (cross-play needs both
built from one revision), plus the release builds the launcher installs and the official server runs
(tools/release/publish.py, docs/HOSTING.md): Windows with its .pck beside the .exe (updates download only the parts of
it that changed), macOS (universal, ad-hoc signed) and the headless Linux server.

    python -I tools/write_export_presets.py

Both exports leave out what the game never loads: the original Poly Haven models (the game uses the decimated
copies in assets/models/polyhaven/, made by tools/blender/process_props.py) and the original textures those copies do
not point at. Re-run after re-processing models. Builds go to builds/windows/ and builds/android/.
"""
import glob
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
VERSION = "0.2.0"
VERSION_CODE = 2


def project_version() -> str:
    for line in (GAME / "project.godot").read_text(encoding="utf-8").splitlines():
        if line.startswith("config/version="):
            return line.split("=", 1)[1].strip('"')
    return VERSION


def excluded() -> list:
    os.chdir(GAME)
    used = set()
    for g in glob.glob("assets/models/polyhaven/*.gltf"):
        d = json.loads(Path(g).read_text(encoding="utf-8"))
        for im in d.get("images", []):
            if im.get("uri"):
                used.add(os.path.normpath(os.path.join(os.path.dirname(g), im["uri"])).replace("\\", "/"))
    # r23: the map editors (editor/: the mall's preview geometry and editor scene) are for the Godot editor only
    out = ["assets/thirdparty/polyhaven/models/*/*.gltf", "assets/thirdparty/polyhaven/models/*/*.bin", "editor/*"]
    for t in sorted(glob.glob("assets/thirdparty/polyhaven/models/*/textures/*")):
        t = t.replace("\\", "/")
        if t not in used and not t.endswith(".import"):
            out.append(t)
    return out


# (r27) The Linux server draws nothing, and Terrain3D has no Linux build here: the server collides with each map's baked
# heights (maps/<id>/terrain/heights.res), so the addon and the maps' Terrain3D drawing data stay out of it (Godot
# refuses to export an extension whose library is missing for the platform).
SERVER_EXCLUDED = ["addons/terrain_3d/*", "maps/*/terrain/terrain3d*.res", "maps/*/terrain/assets.tres",
                   "maps/*/terrain/material*.tres", "maps/*/terrain/tex/*"]


def main() -> None:
    ver = project_version()
    # Android version code: minor * 100 + patch (0.17.1 -> 1701), so a patch release installs over the one before it.
    code = int(ver.split(".")[1]) * 100 + int(ver.split(".")[2]) if ver.count(".") == 2 else VERSION_CODE
    ex = ", ".join(excluded())
    common = f'''export_filter="all_resources"
include_filter=""
exclude_filter="{ex}"
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2'''
    server_common = common.replace(f'exclude_filter="{ex}"', 'exclude_filter="%s"' % ", ".join([ex] + SERVER_EXCLUDED))
    text = f'''[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
{common}
export_path="../builds/windows/Aetherion.exe"

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
application/file_version="{ver}.0"
application/product_version="{ver}.0"
application/company_name="Aljay Leodones"
application/product_name="Aetherion Project"
application/file_description="Aetherion Project"
application/copyright="Aljay Leodones"

[preset.1]

name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
{common}
export_path="../builds/android/Aetherion.apk"

[preset.1.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/export_format=0
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=true
version/code={code}
version/name="{ver}"
package/unique_name="com.lemonquake.aetherion"
package/name="Aetherion"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_android_tv=false
package/show_in_app_library=true
package/show_as_launcher_app=false
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
graphics/opengl_debug=false
permissions/custom_permissions=PackedStringArray()
permissions/access_network_state=true
permissions/access_wifi_state=true
permissions/internet=true
permissions/record_audio=true
permissions/vibrate=true

[preset.2]

name="Windows Release"
platform="Windows Desktop"
runnable=false
advanced_options=false
dedicated_server=false
custom_features=""
{common}
export_path="../builds/release/windows/Aetherion.exe"

[preset.2.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
application/file_version="{ver}.0"
application/product_version="{ver}.0"
application/company_name="Aljay Leodones"
application/product_name="Aetherion Project"
application/file_description="Aetherion Project"
application/copyright="Aljay Leodones"

[preset.3]

name="macOS"
platform="macOS"
runnable=false
advanced_options=false
dedicated_server=false
custom_features=""
{common}
export_path="../builds/release/macos/Aetherion.zip"

[preset.3.options]

export/distribution_type=1
binary_format/architecture="universal"
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
application/bundle_identifier="com.lemonquake.aetherion"
application/signature="AETH"
application/app_category="Games"
application/short_version="{ver}"
application/version="{ver}"
application/copyright="Aljay Leodones · AzAz Games"
application/min_macos_version_x86_64="10.15"
application/min_macos_version_arm64="11.00"
display/high_res=true
codesign/codesign=1
codesign/entitlements/audio_input=true
notarization/notarization=0
privacy/microphone_usage_description="Team radio: talk to your squad while you hold the radio key."
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false

[preset.4]

name="Linux Server"
platform="Linux"
runnable=false
advanced_options=false
dedicated_server=false
custom_features=""
{server_common}
export_path="../builds/release/linux/aetherion_server.x86_64"

[preset.4.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
'''
    dest = GAME / "export_presets.cfg"
    # Godot may hold this file open while exporting another platform. Reuse an
    # identical preset instead of attempting an unnecessary shared-file write.
    if not dest.exists() or dest.read_text(encoding="utf-8") != text:
        dest.write_text(text, encoding="utf-8", newline="\n")
    print("export_presets.cfg written: version %s (code %d), %d exclusions" % (ver, code, ex.count(",") + 1))


if __name__ == "__main__":
    main()
