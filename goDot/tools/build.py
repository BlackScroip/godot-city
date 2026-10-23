#!/usr/bin/env python3
"""Reproducible debug exports; signing and connected-device tests are separate gates."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2.stable.official.ed1daf0bf"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=["macOS", "Android", "iOS", "all"])
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot"))
    parser.add_argument("--skip-import", action="store_true")
    parser.add_argument("--ads-godot-source", type=Path, default=os.environ.get("GODOT_SOURCE"), help="Matching engine source headers for the iOS advertising plugin")
    args = parser.parse_args()
    version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    if version != VERSION:
        raise SystemExit(f"Expected {VERSION}, found {version}")
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    if not args.skip_import:
        with (reports / "build-import-console.log").open("w") as output:
            subprocess.run([args.godot, "--headless", "--path", str(ROOT), "--import", "--log-file", str(reports / "build-import.log")], stdout=output, stderr=subprocess.STDOUT, check=True)
    selected = ["macOS", "Android", "iOS"] if args.platform == "all" else [args.platform]
    report_path = reports / "builds.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {"engine": version, "exports": {}}
    report["engine"] = version
    targets = {"macOS": ("macos", "DungeonChasers.app", "macos.zip"), "Android": ("android", "DungeonChasers-debug.apk", "android_debug.apk"), "iOS": ("ios", "DungeonChasers.zip", "ios.zip")}
    for platform in selected:
        folder, name, template = targets[platform]
        destination = ROOT / "builds" / folder
        destination.mkdir(parents=True, exist_ok=True)
        source = ROOT / ".local/templates" / template
        if not source.exists():
            report["exports"][platform] = {"status": "blocked", "reason": f"Missing pinned template: {source}"}
            continue
        if platform == "iOS":
            if not args.ads_godot_source:
                report["exports"][platform] = {"status": "blocked", "reason": "Supply --ads-godot-source to include the advertising plugin"}
                continue
            result = subprocess.run([sys.executable, str(ROOT / "tools/export_ios_unsigned.py"), "--godot", args.godot, "--ads-godot-source", str(args.ads_godot_source), "--build"])
            ios_report = json.loads((reports / "ios-unsigned.json").read_text())
            report["exports"][platform] = {"status": "exported_unsigned" if result.returncode == 0 else "failed", "exit_code": result.returncode, "artifact": ios_report.get("project"), "unsigned_app": ios_report.get("unsigned_app"), "device_verified": False}
            print(f"{platform}: {report['exports'][platform]['status']}", flush=True)
            continue
        if platform == "Android":
            keystore = ROOT / ".local/debug.keystore"
            if not keystore.exists():
                existing = Path.home() / ".android/debug.keystore"
                if existing.exists():
                    shutil.copy2(existing, keystore)
                else:
                    report["exports"][platform] = {"status": "blocked", "reason": "Debug keystore missing; create androiddebugkey with keytool"}
                    continue
        console = reports / f"export-{folder}-console.log"
        with console.open("w") as output:
            result = subprocess.run([args.godot, "--headless", "--path", str(ROOT), "--export-debug", platform, str(destination / name), "--log-file", str(reports / f"export-{folder}.log")], stdout=output, stderr=subprocess.STDOUT)
        exists = (destination / name).exists()
        report["exports"][platform] = {"status": "exported" if result.returncode == 0 and exists else "failed", "exit_code": result.returncode, "artifact": str(destination / name), "log": str(console), "device_verified": False}
        print(f"{platform}: {report['exports'][platform]['status']}", flush=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    if any(report["exports"][name]["status"] not in ["exported", "exported_unsigned"] for name in selected):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
