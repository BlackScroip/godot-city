"""Recover the adventure-event panel and dynamic illustrations from the supplied APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records
from recover_camp_developer_ui import recover


def main(apk, output):
    recover(apk, output, "ATPanel_AdventureEvent", "panel")
    for filename in ("resource_map.json", "provenance.json", "panel/prefab-layout.json"):
        path = output / filename
        value = json.loads(path.read_text())
        serialized = json.dumps(value, ensure_ascii=False, indent=2)
        path.write_text(serialized.replace("res://assets/ui/camp/panel/", "res://assets/ui/adventure_events/panel/") + "\n")
    mapping = json.loads((output / "resource_map.json").read_text())
    events = json.loads((output.parents[1] / "data/AdvantureEventData.json").read_text())
    names = {row["Icon"] for row in events}
    records = []
    target = output / "icons"
    target.mkdir(exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        manifest = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest))
        for asset in assets:
            if asset["address"] not in names:
                continue
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "Sprite" or obj.peek_name() != asset["address"]:
                    continue
                path = target / (asset["address"] + ".png")
                obj.read().image.save(path)
                mapping[asset["address"]] = "res://assets/ui/adventure_events/icons/" + path.name
                records.append({"name": asset["address"], "member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(), "path_id": str(obj.path_id), "png_sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (output / "resource_map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
    missing = sorted(names - mapping.keys())
    (output / "icons-provenance.json").write_text(json.dumps({"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(), "icons": records, "missing": missing, "limitations": ["Serialized artwork only; original Android runtime not observed."]}, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"icons": len(records), "missing": missing, "output": str(output)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    main(args.apk, args.output)
