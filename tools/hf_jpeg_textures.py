"""Makes the Hidden Forest models' opaque PNG textures JPEGs (quality 90) and points their .gltf files at them; cut-out
textures (with a real alpha channel) stay PNG. The Sketchfab sources export their textures as lossless PNG, about
1.6 MB each; Godot compresses them for the GPU anyway, so the files only weigh on the repository and the download.

    python -I tools/hf_jpeg_textures.py          # after tools/blender/process_hf.py

Large JPEGs (over 400 KB, re-saved by Blender from Poly Haven's) are written again at quality 85.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

HF = Path(__file__).resolve().parent.parent / "game" / "assets" / "models" / "hf"


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
    print("%d textures to JPEG, %.1f MB saved" % (len(renamed), saved / 1e6))


if __name__ == "__main__":
    main()
