"""Recover the APK's complete semantic keyword table and inline artwork."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/ui/talent_view"


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main(apk):
    with zipfile.ZipFile(apk) as archive:
        manifest = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest))
        table = next(item for item in assets if item["address"] == "LocalizationData_SingleKeyword")
        member = "assets/yoo/DefaultPackage/" + bundles[table["bundle"]]["hash"] + ".bundle"
        payload = archive.read(member)
        table_objects = [obj for obj in UnityPy.load(payload).objects if obj.type.name == "TextAsset"]
        source = next(obj for obj in table_objects if obj.read().m_Name == table["address"])
        rows = json.loads(source.read().m_Script)
        table_source = {"member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                        "path_id": str(source.path_id), "rows": len(rows)}
        write_json(OUTPUT / "specinfo.json", rows)
        names = set(re.findall(r'<sprite\s+name="([^"]+)"', " ".join(
            str(value) for row in rows for value in row.values())))
        mapping, sources = {}, []
        bundle_cache = {}
        for asset in assets:
            if asset["address"] not in names:
                continue
            name = asset["address"]
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            if member not in bundle_cache:
                payload = archive.read(member)
                sprites = {obj.read().m_Name: obj for obj in UnityPy.load(payload).objects
                           if obj.type.name == "Sprite"}
                bundle_cache[member] = (hashlib.sha256(payload).hexdigest(), sprites)
            bundle_sha256, sprites = bundle_cache[member]
            if name not in sprites:
                continue
            obj = sprites[name]
            existing = next((ROOT / "assets").rglob(name + ".png"), None)
            if existing is None:
                existing = OUTPUT / "inline" / (name + ".png")
                existing.parent.mkdir(exist_ok=True)
                obj.read().image.save(existing)
            mapping[name] = "res://" + str(existing.relative_to(ROOT))
            sources.append({"name": name, "member": member, "bundle_sha256": bundle_sha256,
                            "path_id": str(obj.path_id), "output": mapping[name]})
        for name in sorted(names - mapping.keys()):
            for member, (bundle_sha256, sprites) in bundle_cache.items():
                if name not in sprites:
                    continue
                obj = sprites[name]
                destination = OUTPUT / "inline" / (name + ".png")
                obj.read().image.save(destination)
                mapping[name] = "res://" + str(destination.relative_to(ROOT))
                sources.append({"name": name, "member": member, "bundle_sha256": bundle_sha256,
                                "path_id": str(obj.path_id), "output": mapping[name]})
                break
        report = {"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
                  "evidence_type": "Static serialized TextAsset and Sprite; no APK runtime executed",
                  "keyword_table": table_source, "sprites": sources,
                  "unresolved": sorted(names - mapping.keys())}
        write_json(OUTPUT / "inline_map.json", mapping)
        write_json(OUTPUT / "inline-provenance.json", report)
        print(json.dumps({"terms": len(rows), "sprites": len(mapping), "unresolved": report["unresolved"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    main(parser.parse_args().apk)
