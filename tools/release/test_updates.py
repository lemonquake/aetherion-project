"""End-to-end checks of the launcher's install and update engine against a local copy of the update server.

    python -I tools/release/test_updates.py [--keep]

Serves builds/release/store like the VPS does (release.json, chunk store, a fake /api/status), then with the built
Windows launcher (builds/release/launcher/AetherionLauncher.exe --selftest):
  1. installs the staged Windows release into an empty folder (everything downloaded);
  2. publishes a test release whose .pck has bytes inserted and overwritten (re-chunked and signed with the real key)
     and updates to it: only the chunks around the edits may be downloaded, the rest is copied from the installed file;
  3. damages the installed .pck and runs --verify: only the damaged chunk is downloaded again;
  4. checks a release with a bad signature is refused and leaves the install alone.
Nothing touches the real server or the user's installed game. Work files go to builds/release/test/.
"""
import base64
import hashlib
import http.server
import json
import os
import shutil
import subprocess
import sys
import threading
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chunker  # noqa: E402
import publish  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
STORE = ROOT / "builds" / "release" / "store"
TEST = ROOT / "builds" / "release" / "test"
EXE = ROOT / "builds" / "release" / "launcher" / "AetherionLauncher.exe"
PORT = 8765
releases = {}  # platform -> bytes of release.json being served


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        p = self.path.split("?")[0]
        body = None
        if p.startswith("/updates/") and p.endswith("/release.json"):
            body = releases.get(p.split("/")[2])
        elif p.startswith("/updates/chunks/"):
            rel = p[len("/updates/chunks/"):]
            for base in (TEST / "chunks", STORE / "chunks"):
                f = base / rel
                if f.is_file():
                    body = f.read_bytes()
                    break
        elif p == "/api/status":
            body = json.dumps({"ok": True, "online": 3, "servers": [
                {"name": "Official Classic", "game_mode": "classic", "map": "kalinaw", "players": 3, "max": 28, "state": "lobby", "region": "Singapore"},
                {"name": "Official Deathmatch", "game_mode": "deathmatch", "map": "lawless_sub", "players": 0, "max": 21, "state": "match", "region": "Singapore"}]}).encode()
        if body is None:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def selftest(install_dir, *extra):
    report = TEST / "report.json"
    if report.exists():
        report.unlink()
    cmd = [str(EXE), "--selftest", "--portable", "--install-dir=%s" % install_dir, "--base-url=http://127.0.0.1:%d" % PORT,
           "--report=%s" % report] + list(extra)
    r = subprocess.run(cmd, capture_output=True, timeout=1800)
    out = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {"ok": False, "error": "no report", "exit": r.returncode}
    out["exit"] = r.returncode
    return out


def make_release(platform, files_root, version, sign=True):
    """A signed release of the files in files_root (chunks into TEST/chunks)."""
    files = []
    total = stored = 0
    for path in sorted(Path(files_root).iterdir()):
        chunks, digest = chunker.chunk_file(str(path))
        entry = {"path": path.name, "size": path.stat().st_size, "sha256": digest, "chunks": []}
        with open(path, "rb") as f:
            for off, size, h in chunks:
                f.seek(off)
                data = f.read(size)
                dest = TEST / "chunks" / h[:2] / h
                if not dest.exists() and not (STORE / "chunks" / h[:2] / h).exists():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    c = zlib.compressobj(6, zlib.DEFLATED, -15)
                    dest.write_bytes(c.compress(data) + c.flush())
                z = (dest if dest.exists() else STORE / "chunks" / h[:2] / h).stat().st_size
                entry["chunks"].append([h, size, z])
                stored += z
        total += entry["size"]
        files.append(entry)
    man = {"format": 1, "platform": platform, "version": version, "net_version": "aetherion-" + version, "published": "test",
           "launch": "Aetherion.exe", "notes": ["test release"], "chunks": "../chunks/", "size": total, "download_size": stored, "files": files}
    data = json.dumps(man, separators=(",", ":"), sort_keys=True).encode()
    sig = publish.sign(data) if sign else base64.b64encode(b"\0" * 384).decode()
    return json.dumps({"manifest": base64.b64encode(data).decode(), "sig": sig}).encode(), man


def check(name, ok, detail=""):
    print("%s %s %s" % ("PASS" if ok else "FAIL", name, detail))
    return ok


def main():
    keep = "--keep" in sys.argv
    if TEST.exists():
        shutil.rmtree(TEST)
    TEST.mkdir(parents=True)
    releases["windows"] = (STORE / "staged" / "windows" / "release.json").read_bytes()
    base_man = json.loads((STORE / "staged" / "windows" / "manifest.json").read_text(encoding="utf-8"))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    inst = TEST / "install"
    ok = True

    # 1. Fresh install.
    r = selftest(inst)
    ok &= check("fresh install", r.get("ok") and r.get("after") == base_man["version"], json.dumps(r))
    ok &= check("fresh install downloads everything", r.get("reused", -1) == 0 and r.get("downloaded", 0) >= base_man["download_size"] * 0.99)

    # 2. A changed release: bytes inserted at 40% and overwritten at 70% of the .pck.
    src = ROOT / "builds" / "release" / "windows"
    mod = TEST / "release_b"
    mod.mkdir()
    shutil.copy2(src / "Aetherion.exe", mod / "Aetherion.exe")
    data = bytearray((src / "Aetherion.pck").read_bytes())
    n = len(data)
    data[int(n * 0.4):int(n * 0.4)] = os.urandom(1000)
    data[int(n * 0.7):int(n * 0.7) + 3_000_000] = os.urandom(3_000_000)
    (mod / "Aetherion.pck").write_bytes(bytes(data))
    del data
    rel_b, man_b = make_release("windows", mod, "9.9.9")
    releases["windows"] = rel_b
    r = selftest(inst)
    pck_b = next(f for f in man_b["files"] if f["path"] == "Aetherion.pck")
    got = hashlib.sha256((inst / "Aetherion.pck").read_bytes()).hexdigest()
    ok &= check("update applies", r.get("ok") and r.get("after") == "9.9.9" and got == pck_b["sha256"], json.dumps(r))
    ok &= check("update downloads only the changed parts", 0 < r.get("downloaded", 0) < 40_000_000,
                "%.1f MB downloaded, %.2f GB reused" % (r.get("downloaded", 0) / 1e6, r.get("reused", 0) / 1e9))

    # 3. Damage the installed file; Verify repairs it from one chunk.
    with open(inst / "Aetherion.pck", "r+b") as f:
        f.seek(n // 2)
        f.write(b"\xff" * 4096)
    r = selftest(inst, "--verify")
    got = hashlib.sha256((inst / "Aetherion.pck").read_bytes()).hexdigest()
    ok &= check("verify repairs a damaged file", r.get("ok") and got == pck_b["sha256"] and 0 < r.get("downloaded", 0) < 12_000_000,
                "%.1f MB downloaded" % (r.get("downloaded", 0) / 1e6))

    # 4. A bad signature is refused.
    bad, _ = make_release("windows", mod, "9.9.10", sign=False)
    releases["windows"] = bad
    r = selftest(inst)
    ok &= check("unsigned release refused", not r.get("ok") and "signed" in r.get("error", ""), r.get("error", ""))
    state = json.loads((inst / ".launcher" / "state.json").read_text(encoding="utf-8"))
    ok &= check("install untouched after refusal", state.get("version") == "9.9.9")

    srv.shutdown()
    if not keep:
        shutil.rmtree(TEST, ignore_errors=True)
    print("ALL PASS" if ok else "SOME CHECKS FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
