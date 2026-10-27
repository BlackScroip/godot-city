"""Recover the original weapon selector and normalize its isolated resource paths."""

import argparse
import json
from pathlib import Path
import shutil

from recover_camp_developer_ui import recover


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/ui/role_weapon"


def normalize(value):
    if isinstance(value, dict):
        return {key: normalize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize(item) for item in value]
    if isinstance(value, str):
        return value.replace("res://assets/ui/camp/select_weapon/", "res://assets/ui/role_weapon/select_weapon/")
    return value


def main(apk, existing):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if existing:
        shutil.copytree(existing / "select_weapon", OUTPUT / "select_weapon", dirs_exist_ok=True)
        for filename in ["resource_map.json", "provenance.json"]:
            shutil.copy2(existing / filename, OUTPUT / filename)
    else:
        recover(apk, OUTPUT, "ATPanel_SelectWeapon", "select_weapon")
    for filename in [OUTPUT / "resource_map.json", OUTPUT / "provenance.json", OUTPUT / "select_weapon/prefab-layout.json"]:
        filename.write_text(json.dumps(normalize(json.loads(filename.read_text())), ensure_ascii=False, indent=2) + "\n")
    layout = json.loads((OUTPUT / "select_weapon/prefab-layout.json").read_text())
    mapping = {sprite["name"]: sprite["path"] for sprite in layout["sprites"]}
    (OUTPUT / "resource_map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
    provenance = {"select_weapon_panel": {"layout": "select_weapon/prefab-layout.json", "source": layout["source"],
                                           "sprites": layout["sprites"], "errors": layout["errors"]}}
    (OUTPUT / "provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"prefab": layout["prefab"]["address"], "sprites": len(layout["sprites"]), "errors": layout["errors"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--existing", type=Path)
    arguments = parser.parse_args()
    main(arguments.apk, arguments.existing)
