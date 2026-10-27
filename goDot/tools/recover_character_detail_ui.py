"""Recover character detail, fashion and upgrade presentation from the APK."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import UnityPy
from inspect_camp_progression import manifest_records
from recover_camp_developer_ui import recover


def main(apk, output):
    for address, folder in [("ATPanel_AttributeDetail", "attribute_detail"),
                            ("ATPanel_SelectCharaFashion", "fashion"),
                            ("ATPanel_CharaLevelUp", "upgrade")]:
        if not (output / folder / "prefab-layout.json").exists():
            recover(apk, output, address, folder)
        for path in [output / folder / "prefab-layout.json", output / "resource_map.json", output / "provenance.json"]:
            text = path.read_text().replace("res://assets/ui/camp/" + folder + "/", "res://assets/ui/role_character/" + folder + "/")
            path.write_text(text)
    mapping_path = output / "resource_map.json"
    mapping = json.loads(mapping_path.read_text())
    rows = json.loads((output / "CharaFashionConfigData.json").read_text())
    names = {row["slot_icon_path"] for row in rows}
    names.add("FashionSuitConfigData")
    sources = []
    with zipfile.ZipFile(apk) as archive:
        manifest = next(n for n in archive.namelist() if n.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest))
        for asset in assets:
            if asset["address"] not in names:
                continue
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name == "TextAsset" and obj.peek_name() == "FashionSuitConfigData":
                    (output / "FashionSuitConfigData.json").write_text(obj.read().m_Script)
                    continue
                if obj.type.name != "Sprite":
                    continue
                sprite = obj.read()
                if sprite.m_Name != asset["address"]:
                    continue
                path = output / "fashion" / (re.sub(r"[^A-Za-z0-9_.-]", "_", sprite.m_Name) + ".png")
                sprite.image.save(path)
                mapping[sprite.m_Name] = "res://assets/ui/role_character/fashion/" + path.name
                sources.append({"name": sprite.m_Name, "member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(), "path_id": obj.path_id, "png_sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    mapping_path.write_text(json.dumps(mapping, indent=2) + "\n")
    (output / "detail-art-provenance.json").write_text(json.dumps({"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(), "slot_icons": sources, "limitations": ["Static serialized prefabs and sprites; original APK not executed."]}, indent=2) + "\n")
    print(json.dumps({"slot_icons": len(sources), "missing": sorted(names - mapping.keys() - {"FashionSuitConfigData"})}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    main(args.apk, args.output)
