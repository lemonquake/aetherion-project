"""Makes the Hidden Forest models' opaque PNG textures JPEGs (quality 90) and points their .gltf files at them; cut-out
textures (with a real alpha channel) stay PNG. The Sketchfab sources export their textures as lossless PNG, about
1.6 MB each; Godot compresses them for the GPU anyway, so the files only weigh on the repository and the download.

    python -I tools/hf_jpeg_textures.py          # after tools/blender/process_hf.py

Large JPEGs (over 400 KB, re-saved by Blender from Poly Haven's) are written again at quality 85.
"""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

HF = Path(__file__).resolve().parent.parent / "game" / "assets" / "models" / "hf"
# Colour grades for textures that read wrong at night: the ceiba's bark came out pale, its trunk a white obelisk
# between the dark trees. Applied once to each fresh export (textures/graded.json keeps the graded files' hashes).
GRADE = {"ceiba_atlas_diff.jpg": (0.42, 0.46, 0.38)}


def main():
    tex = HF / "textures"
    renamed = {}
    saved = 0
    for png in sorted(tex.glob("*.png")):
        im = Image.open(png)
        if im.mode in ("RGBA", "LA") or "transparency" in im.info:
            a = np.asarray(im.convert("RGBA"))[..., 3]
            if a.min() < 250:
                continue          # a real cut-out: keep it
        jpg = png.with_suffix(".jpg")
        im.convert("RGB").save(jpg, quality=90, optimize=True)
        saved += png.stat().st_size - jpg.stat().st_size
        renamed[png.name] = jpg.name
        png.unlink()
        imp = png.with_name(png.name + ".import")
        if imp.exists():
            imp.unlink()
    for g in HF.glob("*.gltf"):
        js = json.loads(g.read_text(encoding="utf-8"))
        changed = False
        for img in js.get("images", []):
            uri = img.get("uri", "")
            name = uri.split("/")[-1]
            if name in renamed:
                img["uri"] = uri[: len(uri) - len(name)] + renamed[name]
                img["mimeType"] = "image/jpeg"
                changed = True
        if changed:
            g.write_text(json.dumps(js, indent=1), encoding="utf-8")
    # the JPEGs Blender re-saved from Poly Haven's at about 1 MB each: quality 85 is plenty under GPU compression
    for jpg in tex.glob("*.jpg"):
        if jpg.stat().st_size > 400 * 1024:
            s0 = jpg.stat().st_size
            im = Image.open(jpg)
            im.load()
            im.convert("RGB").save(jpg, quality=85, optimize=True)
            saved += s0 - jpg.stat().st_size
    done_path = tex / "graded.json"
    done = json.loads(done_path.read_text()) if done_path.exists() else {}
    for name, k in GRADE.items():
        f = tex / name
        if not f.exists() or done.get(name) == hashlib.sha256(f.read_bytes()).hexdigest():
            continue
        a = np.asarray(Image.open(f).convert("RGB")).astype(np.float32) / 255.0 * np.array(k, np.float32)
        Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(f, quality=88)
        done[name] = hashlib.sha256(f.read_bytes()).hexdigest()
    done_path.write_text(json.dumps(done, indent=1))
    print("%d textures to JPEG, %.1f MB saved" % (len(renamed), saved / 1e6))


if __name__ == "__main__":
    main()
