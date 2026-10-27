"""Builds the Android APK from a staging copy of the project whose textures are capped for phones.

    python -I tools/build_android.py
    python -I tools/build_android.py --gl --args "--join=10.0.2.2 --name=Phone" --out builds/android/Aetherion-test.apk

--gl builds with the Compatibility (OpenGL) renderer, for emulators whose Vulkan cannot present; --args bakes launch
options into the APK (an Android app takes no command line). The stage is shared: build the store APK last.

The PC build keeps full-resolution textures; Godot has no per-platform texture size, so the APK is exported from
builds/_android_stage/game: a copy of game/ (scripts, data and scenes unchanged, so phones and PCs run the same game
and generate the same map) whose texture imports are capped at 512 px (skies 1024), with the desktop texture formats
switched off. Later runs only copy what changed and re-import what that touches.

Output: builds/android/Aetherion.apk, release template, signed with GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER /
_PASSWORD when set, otherwise with the Android SDK's debug key (fine to install and test; not for a store listing).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import write_export_presets  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
STAGE = ROOT / "builds" / "_android_stage" / "game"
APK = ROOT / "builds" / "android" / "Aetherion.apk"
GODOT = Path("A:/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe")
DEBUG_KEYSTORE = Path(os.environ.get("APPDATA", "")) / "Godot" / "keystores" / "debug.keystore"
CAP = 512
CAP_SKY = 1024
CAPPED_DIRS = ("assets/thirdparty/", "assets/models/")  # UI, fonts and the baked noise keep their size
SIZE_LINE = re.compile(r"^process/size_limit=(\d+)$", re.M)


def skipped() -> set:
    """Files the export leaves out (write_export_presets), as paths relative to game/."""
    cwd = os.getcwd()
    patterns = write_export_presets.excluded()
    os.chdir(cwd)
    out = set()
    for pat in patterns:
        for p in GAME.glob(pat):
            out.add(p.relative_to(GAME).as_posix())
    return out


IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp", ".hdr", ".exr", ".svg", ".tga", ".bmp")


def desktop_only(rel: str) -> bool:
    """Not copied to the stage: desktop texture formats, editor state, and every imported image (the stage imports
    its own at phone size; copying the PC's, with their checksums, would hide the size caps from the importer)."""
    if not rel.startswith(".godot/"):
        return False
    if rel.startswith(".godot/editor/") or rel.startswith(".godot/shader_cache/"):
        return True
    if rel.startswith(".godot/imported/"):
        name = rel.rsplit("/", 1)[1]
        return name.rsplit("-", 1)[0].lower().endswith(IMAGE_EXT)
    return False


def sync() -> int:
    skip = skipped()
    copied = 0
    seen = set()
    for src in GAME.rglob("*"):
        rel = src.relative_to(GAME).as_posix()
        if src.is_dir() or rel in skip or rel.removesuffix(".import") in skip or desktop_only(rel):
            continue
        seen.add(rel)
        if rel.endswith(".import") or rel == "project.godot":
            continue  # written by cap_imports / stage_project
        dst = STAGE / rel
        if dst.exists() and dst.stat().st_size == src.stat().st_size and dst.stat().st_mtime >= src.stat().st_mtime:
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1
    for dst in list(STAGE.rglob("*")):
        rel = dst.relative_to(STAGE).as_posix()
        if dst.is_file() and not rel.startswith(".godot/") and rel not in seen:
            dst.unlink()
    return copied


def cap_for(rel: str, text: str) -> int:
    if 'importer="texture"' not in text or not rel.startswith(CAPPED_DIRS):
        return 0
    return CAP_SKY if rel.lower().endswith((".hdr.import", ".exr.import")) else CAP


def cap_imports() -> int:
    changed = 0
    for src in GAME.rglob("*.import"):
        rel = src.relative_to(GAME).as_posix()
        if not (STAGE / rel.removesuffix(".import")).exists():
            continue
        dst = STAGE / rel
        text = src.read_text(encoding="utf-8")
        cap = cap_for(rel, text)
        # Godot rewrites an .import file after importing it: leave the stage copy alone unless the source changed.
        if dst.exists() and dst.stat().st_mtime >= src.stat().st_mtime:
            m = SIZE_LINE.search(dst.read_text(encoding="utf-8"))
            if cap == 0 or (m and int(m.group(1)) == cap):
                continue
        if cap:
            if SIZE_LINE.search(text):
                text = SIZE_LINE.sub("process/size_limit=%d" % cap, text)
            else:
                text = text.replace("[params]\n", "[params]\n\nprocess/size_limit=%d\n" % cap, 1)
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(text, encoding="utf-8", newline="\n")
        changed += 1
    return changed


def stage_project(gl: bool, extra_args: str) -> None:
    text = (GAME / "project.godot").read_text(encoding="utf-8")
    # Phones read ETC2/ASTC only: skip the desktop formats in the stage (faster import, half the cache).
    text = text.replace("[rendering]\n", "[rendering]\n\ntextures/vram_compression/import_s3tc_bptc=false\n", 1)
    if gl:
        text = text.replace('renderer/rendering_method.mobile="mobile"', 'renderer/rendering_method.mobile="gl_compatibility"')
    presets = STAGE / "export_presets.cfg"
    pt = re.sub(r"^command_line/extra_args=.*\n", "", presets.read_text(encoding="utf-8"), flags=re.M)
    if extra_args:
        pt = pt.replace("[preset.1.options]\n", '[preset.1.options]\n\ncommand_line/extra_args="%s"\n' % extra_args, 1)
    presets.write_text(pt, encoding="utf-8", newline="\n")
    dst = STAGE / "project.godot"
    if not dst.exists() or dst.read_text(encoding="utf-8") != text:
        dst.write_text(text, encoding="utf-8", newline="\n")


def missing_imports() -> int:
    """Texture imports whose phone-format file is not there yet."""
    n = 0
    for imp in STAGE.rglob("*.import"):
        text = imp.read_text(encoding="utf-8")
        if 'importer="texture"' not in text or '"vram_texture": true' not in text:
            continue
        m = re.search(r'^path\.(etc2|astc)="res://(.+?)"', text, re.M)
        if m is None or not (STAGE / m.group(2)).exists():
            n += 1
    return n


def godot(*args, env=None) -> int:
    return subprocess.call([str(GODOT), "--headless", "--path", str(STAGE), *args], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gl", action="store_true", help="Compatibility (OpenGL) renderer, for emulators")
    ap.add_argument("--args", default="", help="launch options baked into the APK")
    ap.add_argument("--out", default=str(APK))
    opt = ap.parse_args()
    apk = Path(opt.out).resolve()
    write_export_presets.main()
    STAGE.mkdir(parents=True, exist_ok=True)
    print("synced %d files" % sync())
    stage_project(opt.gl, opt.args)
    print("import settings written for %d files" % cap_imports())
    for attempt in range(4):  # the headless editor sometimes crashes on exit; importing again finishes the job
        godot("--import")
        left = missing_imports()
        print("import pass %d: %d textures still to import" % (attempt + 1, left))
        if left == 0:
            break
    env = dict(os.environ)
    env.setdefault("GODOT_ANDROID_KEYSTORE_RELEASE_PATH", str(DEBUG_KEYSTORE))
    env.setdefault("GODOT_ANDROID_KEYSTORE_RELEASE_USER", "androiddebugkey")
    env.setdefault("GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD", "android")
    apk.parent.mkdir(parents=True, exist_ok=True)
    if apk.exists():
        apk.unlink()
    rc = godot("--export-release", "Android", str(apk), env=env)
    if rc != 0 or not apk.exists():
        sys.exit("export failed (%d)" % rc)
    print("%s: %.0f MB" % (apk, apk.stat().st_size / 1e6))


if __name__ == "__main__":
    main()
