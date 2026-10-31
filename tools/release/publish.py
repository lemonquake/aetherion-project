"""Publishes a game release: the launchers' updates and the official server, from one revision (docs/HOSTING.md).

    bash tools/release/export_all.sh                       # builds/release/{windows,macos,linux}
    python -I tools/release/publish.py stage --notes tools/release/notes/0.15.0.md
    python -I tools/release/publish.py upload              # new chunks and the staged releases (players see nothing yet)
    python -I tools/release/publish.py activate            # the VPS installs the server, then switches all platforms at once
    python -I tools/release/publish.py apk                 # builds/android APKs to /downloads (after tools/build_android.py)
    python -I tools/release/publish.py site                # website/ to the site root (make_site_assets.py first)
    python -I tools/release/publish.py status | gc [--keep 3] | keygen | launchers

Every file is cut into content-defined chunks (chunker.py), stored once by SHA-256, raw-deflated, under
/updates/chunks/<2 hex>/<sha256>. Each platform has /updates/<platform>/release.json: {"manifest": base64 of the
manifest JSON, "sig": base64 RSA PKCS#1 v1.5 SHA-256 signature of those bytes}. Launchers pin the public key
(tools/release/update-public-key.json) and check every chunk's hash and every file's hash. The private key is outside
the repository (KEY below); losing it means shipping new launchers.
"""
import argparse
import base64
import datetime
import hashlib
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import zipfile
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chunker  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
REL = ROOT / "builds" / "release"
STORE = REL / "store"
LAUNCHERS = REL / "launcher"
KEY = Path(os.environ.get("AETHERION_SIGNING_KEY", Path.home() / ".aetherion-private" / "update-signing-key.pem"))
PUBLIC = Path(__file__).resolve().parent / "update-public-key.json"
SSH_KEY = Path.home() / ".ssh" / "bh_ovh_testers"
HOST = os.environ.get("AETHERION_VPS", "ubuntu@15.235.246.87")
REMOTE = "/srv/aetherion"
SITE_URL = "https://aetherion.15-235-246-87.sslip.io"
PLATFORMS = {
    "windows": {"launch": "Aetherion.exe", "launcher": "AetherionLauncher.exe"},
    "macos": {"launch": "Aetherion.app", "launcher": "Aetherion-Launcher-macOS.zip"},
    "linux": {"launch": "aetherion_server.x86_64", "launcher": None},
}
SITE = ROOT / "website"
ANDROID = ROOT / "builds" / "android"
# Android has no launcher: phones download the APK again for each release. Listed in downloads/index.json by platform.
APKS = {
    "Aetherion.apk": {"platform": "android", "name": "Aetherion for Android"},
    "Aetherion-opengl.apk": {"platform": "android-opengl", "name": "Aetherion for Android (OpenGL compatibility build)"},
}


def project_version() -> str:
    for line in (ROOT / "game" / "project.godot").read_text(encoding="utf-8").splitlines():
        if line.startswith("config/version="):
            return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("no config/version in project.godot")


def ssh(cmd: str, stdin=None, capture=True, check=True):
    args = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-i", str(SSH_KEY), HOST, cmd]
    r = subprocess.run(args, input=stdin, capture_output=capture, check=False)
    if check and r.returncode != 0:
        raise SystemExit("ssh failed (%d): %s\n%s" % (r.returncode, cmd, (r.stderr or b"").decode(errors="replace")))
    return r


# ------------------------------------------------------------------ keys

def load_private():
    from cryptography.hazmat.primitives import serialization
    if not KEY.exists():
        raise SystemExit("signing key missing: %s (run keygen once)" % KEY)
    return serialization.load_pem_private_key(KEY.read_bytes(), password=None)


def sign(data: bytes) -> str:
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import padding
    return base64.b64encode(load_private().sign(data, padding.PKCS1v15(), hashes.SHA256())).decode()


def cmd_keygen(_a) -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    if KEY.exists():
        print("signing key already exists at %s; not replacing it" % KEY)
    else:
        KEY.parent.mkdir(parents=True, exist_ok=True)
        k = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        KEY.write_bytes(k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                        serialization.NoEncryption()))
        print("new signing key at %s: back it up; launchers trust only this key" % KEY)
    pub = load_private().public_key()
    n = pub.public_numbers()
    der = pub.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.PKCS1)
    out = {"_doc": "Public half of the Aetherion update signing key (tools/release/publish.py). Pinned in both launchers.",
           "modulus": base64.b64encode(n.n.to_bytes((n.n.bit_length() + 7) // 8, "big")).decode(),
           "exponent": base64.b64encode(n.e.to_bytes(3, "big")).decode(),
           "pkcs1_der": base64.b64encode(der).decode(),
           "sha256": hashlib.sha256(der).hexdigest()}
    PUBLIC.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("public key written to %s (%s)" % (PUBLIC, out["sha256"][:16]))


# ------------------------------------------------------------------ staging

def platform_files(platform: str):
    """[(relative path, absolute file, executable, link target or None)] for one exported build."""
    base = REL / platform
    out = []
    if platform == "macos":
        z = base / "Aetherion.zip"
        if not z.exists():
            raise SystemExit("missing %s: export it first" % z)
        app = base / "unpacked"
        if app.exists():
            shutil.rmtree(app)
        with zipfile.ZipFile(z) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                mode = info.external_attr >> 16
                rel = info.filename
                dest = app / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                data = zf.read(info)
                if stat.S_ISLNK(mode):
                    out.append((rel, None, False, data.decode("utf-8")))
                    continue
                dest.write_bytes(data)
                execu = bool(mode & 0o111) or "/Contents/MacOS/" in "/" + rel
                out.append((rel, dest, execu, None))
        return out
    for p in sorted(base.iterdir()):
        if p.is_file() and not p.name.endswith((".log", ".tmp")):
            out.append((p.name, p, p.suffix in (".x86_64", ".sh"), None))
    if not out:
        raise SystemExit("nothing exported in %s" % base)
    return out


def chunk_cached(path: Path):
    """chunker.chunk_file with a cache by whole-file hash: the platforms share their .pck byte for byte."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(16 * 1024 * 1024), b""):
            h.update(block)
    digest = h.hexdigest()
    cache_f = STORE / "chunk_cache.json"
    cache = json.loads(cache_f.read_text(encoding="utf-8")) if cache_f.exists() else {}
    key = "%s:%d:%d:%d" % (digest, path.stat().st_size, chunker.CUT_BITS, chunker.MIN_SIZE)
    if key in cache:
        return [tuple(c) for c in cache[key]], digest
    chunks, d2 = chunker.chunk_file(str(path))
    assert d2 == digest
    cache[key] = chunks
    STORE.mkdir(parents=True, exist_ok=True)
    cache_f.write_text(json.dumps(cache), encoding="utf-8")
    return chunks, digest


def store_chunk(path: Path, off: int, size: int, digest: str) -> int:
    dest = STORE / "chunks" / digest[:2] / digest
    if dest.exists():
        return dest.stat().st_size
    with open(path, "rb") as f:
        f.seek(off)
        data = f.read(size)
    assert hashlib.sha256(data).hexdigest() == digest
    c = zlib.compressobj(6, zlib.DEFLATED, -15)
    z = c.compress(data) + c.flush()
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".tmp")
    tmp.write_bytes(z)
    os.replace(tmp, dest)
    return len(z)


def launcher_info(platform: str):
    name = PLATFORMS[platform]["launcher"]
    if not name:
        return None
    f = LAUNCHERS / name
    meta = LAUNCHERS / (name + ".json")
    if not f.exists() or not meta.exists():
        print("  (no launcher build for %s yet: %s)" % (platform, f))
        return None
    m = json.loads(meta.read_text(encoding="utf-8"))
    return {"version": m["version"], "url": "../../downloads/" + name, "size": f.stat().st_size,
            "sha256": hashlib.sha256(f.read_bytes()).hexdigest()}


def cmd_stage(a) -> None:
    version = a.version or project_version()
    notes = []
    if a.notes:
        notes = [l.strip().lstrip("-*").strip() for l in Path(a.notes).read_text(encoding="utf-8").splitlines()
                 if l.strip() and not l.startswith("#")]
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    for platform in a.platforms or list(PLATFORMS):
        print("[stage] %s %s" % (platform, version))
        files = []
        total = stored = 0
        for rel, path, execu, link in platform_files(platform):
            if link is not None:
                files.append({"path": rel, "link": link})
                continue
            chunks, digest = chunk_cached(path)
            entry = {"path": rel, "size": path.stat().st_size, "sha256": digest, "chunks": []}
            if execu:
                entry["exec"] = True
            for off, size, h in chunks:
                z = store_chunk(path, off, size, h)
                entry["chunks"].append([h, size, z])
                stored += z
            total += entry["size"]
            files.append(entry)
            print("  %-60s %10d bytes, %4d chunks" % (rel[:60], entry["size"], len(chunks)))
        launch = PLATFORMS[platform]["launch"]
        if platform == "macos":
            launch = next(f["path"].split("/")[0] for f in files if f["path"].split("/")[0].endswith(".app"))
        man = {"format": 1, "game": "Aetherion Project", "author": "Aljay Leodones", "studio": "AzAz Games",
               "platform": platform, "version": version, "net_version": "aetherion-" + version, "published": now,
               "launch": launch, "notes": notes, "chunks": "../chunks/",
               "size": total, "download_size": stored, "files": files}
        li = launcher_info(platform)
        if li:
            man["launcher"] = li
        data = json.dumps(man, separators=(",", ":"), sort_keys=True).encode("utf-8")
        rel_doc = {"manifest": base64.b64encode(data).decode(), "sig": sign(data)}
        d = STORE / "staged" / platform
        d.mkdir(parents=True, exist_ok=True)
        (d / "release.json").write_text(json.dumps(rel_doc), encoding="utf-8", newline="\n")
        (d / "manifest.json").write_bytes(data)  # readable copy for humans and tests; not published
        print("  -> %d files, %.2f GB, %.2f GB compressed" % (len(files), total / 1e9, stored / 1e9))


# ------------------------------------------------------------------ upload / activate

def staged_manifests():
    out = {}
    for platform in PLATFORMS:
        f = STORE / "staged" / platform / "manifest.json"
        if f.exists():
            out[platform] = json.loads(f.read_text(encoding="utf-8"))
    return out


def tar_stream(entries):
    """entries: [(arcname, local path)] -> bytes of an uncompressed tar."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as t:
        for arc, path in entries:
            ti = t.gettarinfo(str(path), arcname=arc)
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = ""
            ti.mode = 0o644
            with open(path, "rb") as f:
                t.addfile(ti, f)
    return buf.getvalue()


def cmd_upload(a) -> None:
    mans = staged_manifests()
    if not mans:
        raise SystemExit("nothing staged")
    have = set(ssh("mkdir -p %s/updates/chunks && cd %s/updates/chunks && find . -type f -printf '%%P\\n'" % (REMOTE, REMOTE))
               .stdout.decode().split())
    need = {}
    for m in mans.values():
        for f in m["files"]:
            for h, _size, _z in f.get("chunks", []):
                key = "%s/%s" % (h[:2], h)
                if key not in have:
                    need[key] = STORE / "chunks" / h[:2] / h
    print("[upload] %d chunks already on the server, %d to send (%.2f GB)" % (
        len(have), len(need), sum(p.stat().st_size for p in need.values()) / 1e9))
    batch, size = [], 0
    keys = sorted(need)
    for i, k in enumerate(keys):
        batch.append(("chunks/" + k, need[k]))
        size += need[k].stat().st_size
        if size > 256 * 1024 * 1024 or i == len(keys) - 1:
            # Into a temporary name first, so a half-sent chunk is never served.
            ssh("cd %s/updates && mkdir -p .incoming && tar -x -C .incoming && cd .incoming/chunks && "
                "find . -type f -printf '%%P\\n' | while read f; do mkdir -p ../../chunks/$(dirname $f); mv -f $f ../../chunks/$f; done"
                % REMOTE, stdin=tar_stream(batch))
            print("  sent %d/%d" % (i + 1, len(keys)))
            batch, size = [], 0
    staged = [("next/%s/release.json" % p, STORE / "staged" / p / "release.json") for p in mans]
    for name in {PLATFORMS[p]["launcher"] for p in mans if PLATFORMS[p]["launcher"]}:
        if (LAUNCHERS / name).exists():
            staged.append(("next/downloads/" + name, LAUNCHERS / name))
            staged.append(("next/downloads/%s.json" % name, LAUNCHERS / (name + ".json")))
    ssh("rm -rf %s/updates/next && mkdir -p %s/updates && tar -x -C %s/updates" % (REMOTE, REMOTE, REMOTE),
        stdin=tar_stream(staged))
    # The server reassembles its own build from the chunks: a check that the store is complete before players see it.
    v = mans.get("linux", {}).get("version")
    if v:
        r = ssh("sudo /opt/aetherion/bin/aetherion-admin prepare %s" % v, capture=True, check=False)
        sys.stdout.write(r.stdout.decode(errors="replace"))
        if r.returncode != 0:
            raise SystemExit("the server could not prepare %s:\n%s" % (v, r.stderr.decode(errors="replace")))
    print("[upload] staged %s; players still get the current release until activate" % ", ".join(sorted(mans)))


def cmd_activate(_a) -> None:
    mans = staged_manifests()
    v = mans["linux"]["version"]
    r = ssh("sudo /opt/aetherion/bin/aetherion-admin activate %s" % v, check=False)
    sys.stdout.write(r.stdout.decode(errors="replace"))
    if r.returncode != 0:
        raise SystemExit("activate failed:\n%s" % r.stderr.decode(errors="replace"))


def cmd_launchers(_a) -> None:
    """Publish only the launcher downloads (and their metadata) without a new game release."""
    entries = []
    for p in PLATFORMS.values():
        name = p["launcher"]
        if name and (LAUNCHERS / name).exists():
            entries += [("downloads/" + name, LAUNCHERS / name), ("downloads/%s.json" % name, LAUNCHERS / (name + ".json"))]
    ssh("mkdir -p %s/downloads.new && tar -x -C %s/downloads.new && cp -f %s/downloads.new/downloads/* %s/downloads/ && rm -rf %s/downloads.new"
        % ((REMOTE,) * 5), stdin=tar_stream(entries))
    ssh("sudo /opt/aetherion/bin/aetherion-admin downloads-index")
    print("[launchers] published %s" % ", ".join(e[0] for e in entries))


def apk_version(apk: Path) -> str:
    """versionName from the APK's manifest (the SDK's aapt), so a stale APK is never listed as the current game."""
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or str(Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk")
    tools = sorted((Path(sdk) / "build-tools").glob("*/aapt*"))
    if not tools:
        raise SystemExit("aapt not found under %s/build-tools: set ANDROID_HOME" % sdk)
    out = subprocess.run([str(tools[-1]), "dump", "badging", str(apk)], capture_output=True, text=True, check=True).stdout
    for part in out.splitlines()[0].split():
        if part.startswith("versionName="):
            return part.split("=", 1)[1].strip("'")
    raise SystemExit("no versionName in %s" % apk)


def cmd_apk(a) -> None:
    """Upload the Android APKs (only those that changed) with their metadata, then refresh the website's index."""
    game = project_version()
    staged = bool(getattr(a, "stage", False))
    folder = REMOTE + ("/updates/next/downloads" if staged else "/downloads")
    ssh("mkdir -p %s" % folder)
    for name, meta in APKS.items():
        apk = ANDROID / name
        if not apk.exists():
            print("[apk] %s not built; skipped" % name)
            continue
        v = apk_version(apk)
        if v != game:
            raise SystemExit("%s is %s but the game is %s: run tools/build_android.py first" % (name, v, game))
        h = hashlib.sha256()
        with open(apk, "rb") as f:
            for block in iter(lambda: f.read(16 * 1024 * 1024), b""):
                h.update(block)
        digest = h.hexdigest()
        dest = "%s/%s" % (folder, name)
        remote = ssh("sha256sum %s 2>/dev/null || true" % dest).stdout.decode().split()
        if remote and remote[0] == digest:
            print("[apk] %s %s already on the server" % (name, v))
        else:
            print("[apk] sending %s %s (%.0f MB)" % (name, v, apk.stat().st_size / 1e6))
            with open(apk, "rb") as f:
                r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-i", str(SSH_KEY), HOST,
                                    "cat > %s.part && echo '%s  %s.part' | sha256sum -c --quiet && mv -f %s.part %s"
                                    % (dest, digest, dest, dest, dest)], stdin=f, capture_output=True)
            if r.returncode != 0:
                raise SystemExit("upload of %s failed: %s" % (name, r.stderr.decode(errors="replace")))
        info = dict(meta, version=v, requires="Android 7.0 or newer, 64-bit")
        ssh("cat > %s.json" % dest, stdin=(json.dumps(info, indent=1) + "\n").encode())
    if staged:
        print("[apk] staged with the next game release; activate switches Android and desktop downloads together")
    else:
        ssh("sudo /opt/aetherion/bin/aetherion-admin downloads-index")
        print("[apk] published; %s/downloads/index.json updated" % SITE_URL)


def cmd_site(_a) -> None:
    """Replace the website (website/ -> /srv/aetherion/site) in one rename, so nobody gets half a site."""
    files = [p for p in sorted(SITE.rglob("*")) if p.is_file()]
    if not (SITE / "index.html").exists():
        raise SystemExit("no %s" % (SITE / "index.html"))
    entries = [(p.relative_to(SITE).as_posix(), p) for p in files]
    ssh("rm -rf {r}/site.new && mkdir -p {r}/site.new && tar -x -C {r}/site.new && find {r}/site.new -type d -exec chmod 755 {{}} + && "
        "rm -rf {r}/site.old && mv {r}/site {r}/site.old && mv {r}/site.new {r}/site && rm -rf {r}/site.old".format(r=REMOTE),
        stdin=tar_stream(entries))
    print("[site] %d files published to %s/" % (len(entries), SITE_URL))


def cmd_status(_a) -> None:
    r = ssh("sudo /opt/aetherion/bin/aetherion-admin status", check=False)
    sys.stdout.write(r.stdout.decode(errors="replace") + r.stderr.decode(errors="replace"))


def cmd_gc(a) -> None:
    r = ssh("sudo /opt/aetherion/bin/aetherion-admin gc %d" % a.keep, check=False)
    sys.stdout.write(r.stdout.decode(errors="replace") + r.stderr.decode(errors="replace"))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("keygen")
    s = sub.add_parser("stage")
    s.add_argument("--version")
    s.add_argument("--notes")
    s.add_argument("--platforms", nargs="*")
    sub.add_parser("upload")
    sub.add_parser("activate")
    sub.add_parser("launchers")
    a_apk = sub.add_parser("apk")
    a_apk.add_argument("--stage", action="store_true", help="upload to the next release; run after upload and before activate")
    sub.add_parser("site")
    sub.add_parser("status")
    g = sub.add_parser("gc")
    g.add_argument("--keep", type=int, default=3)
    a = ap.parse_args()
    {"keygen": cmd_keygen, "stage": cmd_stage, "upload": cmd_upload, "activate": cmd_activate, "launchers": cmd_launchers,
     "apk": cmd_apk, "site": cmd_site, "status": cmd_status, "gc": cmd_gc}[a.cmd](a)


if __name__ == "__main__":
    main()
