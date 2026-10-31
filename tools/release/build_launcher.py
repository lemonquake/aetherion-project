"""Builds the Windows launcher (launcher/windows) into builds/release/launcher/ with its metadata (docs/HOSTING.md).

    python -I tools/release/build_launcher.py

The macOS launcher is built on a Mac (GitHub Actions: .github/workflows/mac-launcher.yml) and its zip copied to the same
folder. tools/release/publish.py stage puts both launchers' versions and hashes into the signed releases, so an older
launcher updates itself.
"""
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJ = ROOT / "launcher" / "windows" / "AetherionLauncher.csproj"
OUT = ROOT / "builds" / "release" / "launcher"


def main() -> None:
    version = re.search(r"<Version>([^<]+)</Version>", PROJ.read_text(encoding="utf-8")).group(1)
    subprocess.run(["dotnet", "build", str(PROJ), "-c", "Release", "-nologo", "-v", "q"], check=True)
    exe = PROJ.parent / "bin" / "Release" / "net48" / "AetherionLauncher.exe"
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copy2(exe, OUT / "AetherionLauncher.exe")
    meta = {"platform": "windows", "name": "Aetherion Launcher for Windows", "version": version,
            "requires": "Windows 10 or 11, 64-bit"}
    (OUT / "AetherionLauncher.exe.json").write_text(json.dumps(meta, indent=1) + "\n", encoding="utf-8", newline="\n")
    print("launcher %s: %s (%d KB)" % (version, OUT / "AetherionLauncher.exe", (OUT / "AetherionLauncher.exe").stat().st_size // 1024))


if __name__ == "__main__":
    main()
