#!/usr/bin/env python3
"""Check unresolved effect keys against APK addresses, source JSON and FX objects.

This is a bounded static comparison, not a fallback or alias generator.
Requires UnityPy. No APK directory is extracted.
"""

import argparse
import json
from pathlib import Path
import re
import zipfile

import UnityPy

from import_player_lifecycle import digest, file_digest, manifest_records, resource_key


QUERIES = {
    "202402029_fx_mpskill_shuixiyi": r"shuixiyi",
    "23011601_fx_skill_thunderwand_ailisitonghua_soldier": r"thunder.*wand|wand.*thunder|ailisi",
    "24120601_fx_enemy_feimolong_fan_thunder": r"feimolong.*fan.*thunder",
    "fx_hit_breakpoint01": r"fx_other_breakeffect",
    "fx_other_changecharacter": r"changecharacter|charachange|transfer(rise|drop)",
    "fx_wand_atk_bullet_1": r"wand_atk_(waterbomb|launch|move)",
    "fx_wand_atk_exp_1": r"wand_atk_explode",
}


def pointer(value):
    return str(value).replace("~", "~0").replace("/", "~1")


def references(value, path="", context=()):
    if isinstance(value, dict):
        if "Enabled" in value or "EventType" in value:
            context += ({field: value[field] for field in (
                "Enabled", "EventType", "TriggerTime", "CheckAllCondition", "Conditions")
                if field in value},)
        for key, child in value.items():
            yield from references(child, path + "/" + pointer(key), context)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from references(child, path + "/" + str(index), context)
    elif isinstance(value, str):
        key = resource_key(value)
        if key in QUERIES:
            yield key, {"json_pointer": path, "value": value, "event_context": context}


def inspect(apk, project, scan_fx=True):
    keys = {key: {"exact_manifest_matches": [], "source_references": [],
                  "exact_fx_gameobject_matches": [], "near_names": []} for key in QUERIES}
    bundles_seen, inspected_configs, fx_objects, fx_bundles = {}, 0, 0, 0
    media = json.loads((project / "assets/combat_presentation/catalog.json").read_text())
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        config_assets = [row for row in assets if "/ActionEngineCfg/" in row["path"]]
        effects = [row for row in assets if "/Prefabs/BattleSys/FX/" in row["path"]]
        source_names = {row["address"]: row for row in config_assets}

        def read_bundle(index):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            bundles_seen[str(index)] = {"name": bundles[index]["name"], "member": member,
                                        "sha256": digest(payload)}
            return UnityPy.load(payload)

        for row in assets:
            name = resource_key(row["address"])
            filename = resource_key(Path(row["path"]).name)
            for key in QUERIES:
                if name == key or filename == key:
                    keys[key]["exact_manifest_matches"].append(row)
        for key, pattern in QUERIES.items():
            for row in effects:
                if re.search(pattern, row["address"], re.I):
                    keys[key]["near_names"].append({**row,
                        "already_imported": row["address"].lower() in media.get("effects", {}),
                        "relationship": "lexical candidate only; no source equivalence established"})

        config_bundle_indices = sorted({row["bundle"] for row in config_assets})
        for index in config_bundle_indices:
            for obj in read_bundle(index).objects:
                if obj.type.name != "TextAsset":
                    continue
                item = obj.read()
                if item.m_Name not in source_names:
                    continue
                raw = item.m_Script
                payload = raw if isinstance(raw, bytes) else raw.encode("utf-8", "surrogateescape")
                try:
                    parsed = json.loads(payload.decode("utf-8-sig"))
                except (ValueError, UnicodeError):
                    continue
                inspected_configs += 1
                for key, hit in references(parsed):
                    keys[key]["source_references"].append({"address": item.m_Name,
                        "asset_path": source_names[item.m_Name]["path"], "bundle": index,
                        "path_id": str(obj.path_id), "json_sha256": digest(payload), **hit})
        if scan_fx:
            for index in sorted({row["bundle"] for row in effects}):
                fx_bundles += 1
                for obj in read_bundle(index).objects:
                    if obj.type.name != "GameObject":
                        continue
                    item = obj.read()
                    fx_objects += 1
                    key = resource_key(item.m_Name)
                    if key in keys:
                        keys[key]["exact_fx_gameobject_matches"].append({"bundle": index,
                            "name": item.m_Name, "path_id": str(obj.path_id)})
                if fx_bundles % 200 == 0:
                    print(json.dumps({"fx_bundles_inspected": fx_bundles}), flush=True)
    for key, entry in keys.items():
        entry["status"] = "exact_resource_found" if (entry["exact_manifest_matches"] or
            entry["exact_fx_gameobject_matches"]) else "not_found_within_declared_scan"
        entry["action"] = "No alias or visual substitution was generated from similar names."
    return {
        "schema": 1, "evidence_type": "static APK manifest, Unity TextAsset JSON and GameObject names",
        "source": {"apk": apk.name, "apk_sha256": file_digest(apk),
                   "manifest_member": manifest_name, "manifest_sha256": digest(manifest)},
        "coverage": {"manifest_assets": len(assets), "manifest_bundles": len(bundles),
                     "action_configuration_assets_declared": len(config_assets),
                     "action_configuration_assets_parsed": inspected_configs,
                     "action_configuration_bundles": len(config_bundle_indices),
                     "fx_bundles": fx_bundles, "fx_gameobjects": fx_objects},
        "queries": keys, "bundles": bundles_seen,
        "observations": ["Query keys are exact case-insensitive comparisons after removing an optional .prefab suffix.",
                         "Source reference records include exact JSON pointers, source SHA-256 and enclosing event enable/condition fields."],
        "inferences": ["An unresolved name in source JSON does not establish that an Addressable resource of that name was shipped.",
                       "Different date prefixes and neighboring resource names do not establish aliases."],
        "unknowns": ["Bundles outside declared BattleSys/FX assets were not searched for hidden GameObjects.",
                     "This static inspection does not establish fallback names chosen by native runtime code or original application behavior."],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--skip-fx-objects", action="store_true")
    args = parser.parse_args()
    result = inspect(args.apk, args.project, not args.skip_fx_objects)
    output = args.output or args.project / "reports/unresolved-effects-apk.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=True) + "\n")
    print(json.dumps({"output": str(output), "coverage": result["coverage"],
                      "queries": {key: {"status": entry["status"],
                           "source_references": len(entry["source_references"]),
                           "near_names": len(entry["near_names"])}
                           for key, entry in result["queries"].items()}}))


if __name__ == "__main__":
    main()
