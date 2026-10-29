#!/usr/bin/env python3
"""Inspect serialized particle and trail objects in APK Boss prefab bundles."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from recover_chest_effects import package_manifest


PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parent
CANDIDATES = {33002: "myenemy_jianchihu.prefab"}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audit(apk):
    actors = json.loads((PROJECT / "assets/catalog.json").read_text())["enemies"]
    combat = json.loads((PROJECT / "assets/data/combat.json").read_text())
    bosses = [int(row["id"]) for row in combat["enemies"] if row.get("rank") == "Boss"]
    result = {
        "apk_sha256": sha256(apk),
        "scope": "Serialized ParticleSystem and TrailRenderer objects in exact matched actor prefab bundles; excludes external dependencies, aliases and remote resources.",
        "bosses": [],
    }
    with zipfile.ZipFile(apk) as archive:
        names = [name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes")]
        if len(names) != 1:
            raise ValueError("Expected exactly one default package manifest")
        manifest = package_manifest(archive.read(names[0]))
        for boss in bosses:
            actor = actors.get(str(boss), {})
            source = actor.get("source", "")
            candidate = Path(source).name or CANDIDATES.get(boss, "")
            matches = [row for row in manifest["assets"] if Path(row["path"]).name.lower() == candidate.lower()] if candidate else []
            entry = {"id": boss, "candidate": candidate, "candidate_from_imported_actor": bool(source), "manifest_matches": len(matches)}
            result["bosses"].append(entry)
            if len(matches) != 1:
                entry["status"] = "unavailable_or_ambiguous"
                continue
            asset = matches[0]
            bundle = manifest["bundles"][asset["bundle"]]
            member = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            try:
                payload = archive.read(member)
                counts = Counter(obj.type.name for obj in UnityPy.load(payload).objects)
            except (KeyError, OSError, ValueError) as error:
                entry.update({"status": "bundle_unreadable", "member": member, "error": str(error)})
                continue
            entry.update({"status": "inspected", "asset": asset["path"], "member": member,
                          "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                          "particle_systems": counts["ParticleSystem"], "trail_renderers": counts["TrailRenderer"]})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    text = json.dumps(audit(args.apk), indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.write_text(text)
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
