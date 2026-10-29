"""Switches the textures used on 3D surfaces to VRAM compression with mipmaps.

The world, prop and decal textures are loaded from scripts, so Godot's "detect 3D" never upgraded them: they were
imported lossless (uncompressed in VRAM) without mipmaps, which is slow to sample at a distance and shimmers.
Normal maps get BC5 (RGTC). UI, sky and HDRI images are left alone. Deletes the old imported files so the next
`tools/import.sh` run rebuilds them.

    python -I tools/fix_texture_imports.py [--dry]
"""
import re
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parent.parent / "game"
INCLUDE = ["assets/thirdparty/polyhaven/textures", "assets/thirdparty/polyhaven/models", "assets/models", "assets/fx"]
NORMAL = re.compile(r"(normal|_nor_gl|_nor_dx|_nrm)", re.I)
# Kept lossless (block compression would show in smooth noise); it only needs mipmaps, set when it was added.
SKIP = {"noise_rgba.png.import", "holes_normal.png.import", "blood_normal.png.import"}  # holes_normal and blood_normal keep roughness in alpha


def set_param(text: str, key: str, value: str) -> str:
    pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
    if pat.search(text):
        return pat.sub("%s=%s" % (key, value), text)
    return text.replace("[params]\n", "[params]\n\n%s=%s\n" % (key, value), 1)


def main() -> None:
    dry = "--dry" in sys.argv
    changed = 0
    removed = 0
    for inc in INCLUDE:
        for imp in sorted((GAME / inc).rglob("*.import")):
            if imp.name in SKIP:
                continue
            raw = imp.read_bytes().decode("utf-8")
            nl = "\r\n" if "\r\n" in raw else "\n"
            text = raw.replace("\r\n", "\n")
            if 'importer="texture"' not in text:
                continue
            new = set_param(text, "compress/mode", "2")
            new = set_param(new, "mipmaps/generate", "true")
            if NORMAL.search(imp.name):
                new = set_param(new, "compress/normal_map", "1")
            if new == text:
                continue
            changed += 1
            if dry:
                continue
            # Old outputs: delete so the importer rebuilds them with the new settings.
            for dest in re.findall(r'"(res://\.godot/imported/[^"]+)"', text):
                p = GAME / dest.replace("res://", "")
                for f in [p, Path(str(p).rsplit(".", 1)[0] + ".md5")]:
                    if f.exists():
                        f.unlink()
                        removed += 1
            imp.write_bytes(new.replace("\n", nl).encode("utf-8"))
    print("%s %d texture imports, removed %d imported files" % ("would change" if dry else "changed", changed, removed))


if __name__ == "__main__":
    main()
