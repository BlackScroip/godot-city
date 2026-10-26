"""Recover loose item sprites from the supplied APK without running it."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


def digest(data):
    return hashlib.sha256(data).hexdigest()


def recover(apk, output, report):
    output.mkdir(parents=True, exist_ok=True)
    records = {}
    bundle_sources = []
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest_data = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest_data)
        selected = {asset["address"]: asset for asset in assets if re.fullmatch(
            r"sprite_(?:abilityitem|material)icon_\d+", asset["address"])}
        for index in sorted({asset["bundle"] for asset in selected.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            bundle_sources.append({"member": member, "sha256": digest(payload)})
            objects = list(UnityPy.load(payload).objects)
            # Sprite images carry the source atlas crop and alpha treatment.
            objects.sort(key=lambda obj: obj.type.name != "Sprite")
            for obj in objects:
                if obj.type.name not in ("Sprite", "Texture2D"):
                    continue
                name = obj.peek_name()
                if name not in selected or name in records:
                    continue
                image = obj.read().image
                path = output / (name + ".png")
                image.save(path)
                records[name] = {"id": int(name.rsplit("_", 1)[1]),
                    "kind": "material" if name.startswith("sprite_material") else "loot", "resource":
                    "res://assets/ui/pickup/" + path.name, "source_asset": selected[name]["path"],
                    "source_bundle": member, "source_type": obj.type.name,
                    "source_path_id": str(obj.path_id), "dimensions": list(image.size),
                    "png_sha256": digest(path.read_bytes())}
    missing = sorted(set(selected) - set(records))
    result = {"schema": 1, "apk": str(apk), "apk_sha256":
        hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
        "evidence_type": "static Unity Sprite/Texture2D extraction; no APK execution",
        "manifest": {"member": manifest_name, "sha256": digest(manifest_data)},
        "bundles": bundle_sources, "sprites": records, "missing": missing,
        "limitations": ["Source images establish artwork only, not runtime drop probabilities or effects."]}
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"count": len(records), "missing": missing, "report": str(report)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    recover(args.apk, args.output, args.report)
