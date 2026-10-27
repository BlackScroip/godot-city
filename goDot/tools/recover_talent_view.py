"""Recover talent inspector/detail artwork and type names from the supplied APK."""

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
OUTPUT = ROOT / "assets/ui/talent_view"


def normalize(value):
    if isinstance(value, dict):
        return {key: normalize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [normalize(item) for item in value]
    if isinstance(value, str):
        for folder in ("inspector", "detail"):
            value = value.replace("res://assets/ui/camp/" + folder + "/",
                                  "res://assets/ui/talent_view/" + folder + "/")
    return value


def main(apk):
    for address, folder in (("ATPanel_CharTalentInspector", "inspector"),
                            ("ATPanel_CharTalentDetail", "detail")):
        if not (OUTPUT / folder / "prefab-layout.json").exists():
            recover(apk, OUTPUT, address, folder)
    for path in (OUTPUT / "resource_map.json", OUTPUT / "provenance.json",
                 *OUTPUT.glob("*/prefab-layout.json")):
        path.write_text(json.dumps(normalize(json.loads(path.read_text())),
                                   ensure_ascii=False, indent=2) + "\n")
    with zipfile.ZipFile(apk) as archive:
        manifest = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest))
        mapping = json.loads((OUTPUT / "resource_map.json").read_text())
        for asset in assets:
            if not asset["address"].startswith("sprite_charatalent_8"):
                continue
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            for obj in UnityPy.load(archive.read(member)).objects:
                if obj.type.name != "Sprite" or obj.read().m_Name != asset["address"]:
                    continue
                destination = OUTPUT / (asset["address"] + ".png")
                obj.read().image.save(destination)
                mapping[asset["address"]] = "res://" + str(destination.relative_to(ROOT))
        (OUTPUT / "resource_map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
        for table in ("CharTalentData", "CharTalentLevelData"):
            asset = next(item for item in assets if item["address"] == table)
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset" or obj.read().m_Name != table:
                    continue
                data = json.loads(obj.read().m_Script)
                target = ROOT / "assets/data" / (table + ".json")
                existing = json.loads(target.read_text())
                ids = {row["id"] for row in existing}
                added = [row for row in data if row["id"] not in ids]
                changed_fields = {}
                for row in data:
                    old = next((old for old in existing if old["id"] == row["id"]), None)
                    if old is not None and old != row:
                        changed_fields[row["id"]] = {key: {"existing": old.get(key), "apk": value}
                                                    for key, value in row.items() if old.get(key) != value}
                changed = list(changed_fields)
                for row in existing:
                    for key, diff in changed_fields.get(row["id"], {}).items():
                        if key in ("description", "effect_description"):
                            row[key] = diff["apk"]
                if added or changed_fields:
                    target.write_text(json.dumps(existing + added, ensure_ascii=False, separators=(",", ":")))
                    manifest_path = ROOT / "assets/data/manifest.json"
                    manifest_data = json.loads(manifest_path.read_text())
                    manifest_data["tables"][table].update({
                        "rows": len(existing) + len(added),
                        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                        "source": "APK 1061664: missing talent rows appended and description fields refreshed",
                        "evidence": {"report": "assets/ui/talent_view/" + table + "-merge.json"}})
                    manifest_path.write_text(json.dumps(manifest_data, ensure_ascii=False, separators=(",", ":")))
                report_path = OUTPUT / (table + "-merge.json")
                previous = json.loads(report_path.read_text()) if report_path.exists() else {}
                report_path.write_text(json.dumps({
                    "member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                    "path_id": str(obj.path_id), "added_ids": sorted(set(previous.get("added_ids", []) + [row["id"] for row in added])),
                    "description_ids_refreshed": sorted(set(previous.get("description_ids_refreshed", []) + changed)),
                    "changed_fields": changed_fields or previous.get("changed_fields", {}),
                    "apk_rows": len(data)}, ensure_ascii=False, indent=2) + "\n")
        asset = next(item for item in assets if item["address"] == "LocalizationData_SingleKeyword")
        member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
        tokens = set()
        for table in ("CharTalentData", "CharTalentLevelData"):
            tokens.update(re.findall(r"<#specinfo=[^>]+>", (ROOT / "assets/data" / (table + ".json")).read_text()))
        for obj in UnityPy.load(archive.read(member)).objects:
            if obj.type.name != "TextAsset" or obj.read().m_Name != asset["address"]:
                continue
            rows = [row for row in json.loads(obj.read().m_Script) if row["key"] in tokens]
            (OUTPUT / "specinfo.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")
            sprite_names = set(re.findall(r'<sprite name="([^"]+)"', " ".join(row["text_cn"] for row in rows)))
        sprite_map = {}
        sprite_sources = []
        for asset in assets:
            if asset["address"] not in sprite_names:
                continue
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "Sprite" or obj.read().m_Name != asset["address"]:
                    continue
                name = asset["address"]
                existing = next((ROOT / "assets").rglob(name + ".png"), None)
                if existing is None:
                    existing = OUTPUT / "inline" / (name + ".png")
                    existing.parent.mkdir(exist_ok=True)
                    obj.read().image.save(existing)
                sprite_map[name] = "res://" + str(existing.relative_to(ROOT))
                sprite_sources.append({"name": name, "member": member,
                                       "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                                       "path_id": str(obj.path_id), "output": sprite_map[name]})
        (OUTPUT / "inline_map.json").write_text(json.dumps(sprite_map, ensure_ascii=False, indent=2) + "\n")
        (OUTPUT / "inline-provenance.json").write_text(json.dumps({
            "sprites": sprite_sources, "unresolved": sorted(sprite_names - sprite_map.keys())},
            ensure_ascii=False, indent=2) + "\n")
        asset = next(item for item in assets if item["address"] == "CharTalentTypeData")
        member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
        payload = archive.read(member)
        for obj in UnityPy.load(payload).objects:
            if obj.type.name != "TextAsset":
                continue
            item = obj.read()
            if item.m_Name != "CharTalentTypeData":
                continue
            data = json.loads(item.m_Script)
            (OUTPUT / "CharTalentTypeData.json").write_text(
                json.dumps(data, ensure_ascii=False, indent=2) + "\n")
            (OUTPUT / "types-provenance.json").write_text(json.dumps({
                "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
                "member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                "path_id": str(obj.path_id), "evidence": "Static serialized TextAsset"}, indent=2) + "\n")
    print(json.dumps({"output": str(OUTPUT), "sprites": len(json.loads(
        (OUTPUT / "resource_map.json").read_text()))}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    main(parser.parse_args().apk)
