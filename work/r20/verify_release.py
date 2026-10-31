"""Verify the public 0.20.0 release against the built and signed local artifacts."""
import base64
import datetime
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BASE = "https://aetherion.15-235-246-87.sslip.io"
VERSION = "0.20.0"


def fetch(path, method="GET"):
    req = urllib.request.Request(BASE + path, method=method, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=45) as response:
        return response.read() if method == "GET" else dict(response.headers)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    report = {"version": VERSION, "verified_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "url": BASE}
    page = fetch("/?release=" + VERSION)
    assert hashlib.sha256(page).hexdigest() == digest(ROOT / "website/index.html"), "public website differs"
    assert b"Team Wipe is the default" in page
    index = json.loads(fetch("/downloads/index.json?release=" + VERSION))
    assert index["game"]["version"] == VERSION
    expected_notes = [line[2:] for line in (ROOT / "tools/release/notes/0.20.0.md").read_text(encoding="utf-8").splitlines() if line.startswith("- ")]
    assert index["game"]["notes"] == expected_notes
    report["website_sha256"] = hashlib.sha256(page).hexdigest()
    report["manifests"] = {}
    for platform in ["windows", "linux", "macos"]:
        public = json.loads(fetch("/updates/" + platform + "/release.json?release=" + VERSION))
        local = json.loads((ROOT / "builds/release/store/staged" / platform / "release.json").read_text())
        assert public == local, platform + " signed manifest differs"
        manifest = json.loads(base64.b64decode(public["manifest"]))
        assert manifest["version"] == VERSION and index["platforms"][platform]["version"] == VERSION
        report["manifests"][platform] = {"version": manifest["version"], "files": len(manifest["files"]), "notes": len(manifest["notes"])}
    report["downloads"] = {}
    for platform, path in [("windows", "builds/release/launcher/AetherionLauncher.exe"), ("android", "builds/android/Aetherion.apk"), ("android-opengl", "builds/android/Aetherion-opengl.apk")]:
        local = ROOT / path
        meta = index["launchers"][platform]
        assert meta["version"] == ("1.2.0" if platform == "windows" else VERSION)
        assert meta["sha256"] == digest(local)
        assert meta["size"] == local.stat().st_size
        headers = fetch("/downloads/" + meta["file"], "HEAD")
        assert int(headers["Content-Length"]) == meta["size"]
        report["downloads"][platform] = meta
    status = json.loads(fetch("/api/status?release=" + VERSION))
    assert status["version"] == "aetherion-" + VERSION
    assert {s["game_mode"] for s in status["servers"]} == {"classic", "deathmatch"}
    assert all(s["version"] == "aetherion-" + VERSION for s in status["servers"])
    report["servers"] = status["servers"]
    sources = json.loads((ROOT / "work/r20/source_sha256.json").read_text())
    assert all(digest(ROOT / path) == sha for path, sha in sources.items()), "source changed after export"
    report["source_files_verified"] = len(sources)
    assert "ALL PASS" in (ROOT / "builds/release/test_updates_0.20.0.log").read_text(), "updater tests incomplete"
    report["standalone_windows"] = {"path": "builds/windows/Aetherion.exe", "size": (ROOT / "builds/windows/Aetherion.exe").stat().st_size,
                                     "sha256": digest(ROOT / "builds/windows/Aetherion.exe")}
    report["ok"] = True
    (ROOT / "work/r20/release_verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "version": VERSION, "downloads": list(report["downloads"]), "servers": len(report["servers"]), "source_files": len(sources)}))


if __name__ == "__main__":
    main()
