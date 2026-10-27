"""Recover the player-state prefab, character backgrounds and fashion artwork."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records
from recover_camp_developer_ui import recover


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/ui/role_character"


def normalize(value):
    if isinstance(value, dict):
        return {key: normalize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize(item) for item in value]
    if isinstance(value, str):
        return value.replace("res://assets/ui/camp/panel/", "res://assets/ui/role_character/panel/").replace(
            "res://assets/ui/camp/select_character/", "res://assets/ui/role_character/select_character/")
    return value


def main(apk):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for address, folder in [("Panel_PlayerStateMenu", "panel"), ("ATPanel_SelectChara", "select_character")]:
        if not (OUTPUT / folder / "prefab-layout.json").exists():
            recover(apk, OUTPUT, address, folder)
    for filename in [OUTPUT / "resource_map.json", OUTPUT / "provenance.json", *OUTPUT.glob("*/prefab-layout.json")]:
        data = normalize(json.loads(filename.read_text()))
        filename.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    mapping = json.loads((OUTPUT / "resource_map.json").read_text())
    extracted = []
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest_name))
        selected = [asset for asset in assets if asset["address"].startswith(("CharaFashion_", "charamenumask_", "CharaFashionCard_", "sprite_illustration_", "sprite_cardicon_square_bg_", "Adventure_Level_"))
                    or asset["address"] == "CharaFashionConfigData"]
        for asset in selected:
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            env = UnityPy.load(payload)
            for obj in env.objects:
                if obj.type.name not in ("Sprite", "TextAsset"):
                    continue
                item = obj.read()
                if item.m_Name != asset["address"]:
                    continue
                if obj.type.name == "Sprite":
                    path = OUTPUT / (re.sub(r"[^A-Za-z0-9_.-]", "_", item.m_Name) + ".png")
                    item.image.save(path)
                    mapping[item.m_Name] = "res://" + str(path.relative_to(ROOT))
                else:
                    path = OUTPUT / (item.m_Name + ".json")
                    path.write_text(item.m_Script)
                extracted.append({"address": asset["address"], "source": member,
                                  "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                                  "path_id": str(obj.path_id), "output": str(path.relative_to(ROOT)),
                                  "output_sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (OUTPUT / "resource_map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
    report = {"apk": str(apk), "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
              "extracted": extracted, "limit": "Static serialized prefab and sprite evidence; no APK execution."}
    (OUTPUT / "character-art-provenance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"sprites": len(mapping), "addressed_assets": len(extracted)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    main(parser.parse_args().apk)
