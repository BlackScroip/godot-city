"""Compare shipped camp/economy tables with an earlier APK and project data.

Reads YooAsset manifests and Unity TextAssets. No native offsets are reused and
neither package is executed. Requires UnityPy and capstone (parser dependency).
"""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


TABLES = {
    "RogueConfigData", "MaterialData", "UnlockData", "CharData", "CharTalentData",
    "CharTalentLevelData", "TalentTreeData", "TalentTreeLevelData", "MonsterPartnerData",
    "MonsterWorkData", "CatMealData", "WeaponData", "AchieveData", "SubAchieveData",
    "NPCData", "NPCFunctionData", "RelationshipTokenData", "RelationshipAmplifyData",
    "CharaTalentAwakeTreeData", "MallTradeData", "MallTradeDetailsData",
    "ShopTreasureBoxData", "ItemPoolData", "ItemPoolSubData", "MainCityDecorationData",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def extract(path):
    with path.open("rb") as stream:
        result = {"path": str(path), "sha256": hashlib.file_digest(stream, "sha256").hexdigest(), "tables": {}}
    with zipfile.ZipFile(path) as archive:
        manifests = [n for n in archive.namelist() if n.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes")]
        if len(manifests) != 1:
            raise ValueError(f"Expected one YooAsset manifest, found {manifests}")
        payload = archive.read(manifests[0])
        result["manifest"] = {"member": manifests[0], "sha256": digest(payload)}
        assets, bundles = manifest_records(payload)
        selected = [a for a in assets if a["address"] in TABLES]
        for index in sorted({a["bundle"] for a in selected}):
            bundle = bundles[index]
            member = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            data = archive.read(member)
            for obj in UnityPy.load(data).objects:
                if obj.type.name != "TextAsset":
                    continue
                asset = obj.read()
                if asset.m_Name not in TABLES:
                    continue
                payload = asset.m_Script
                if isinstance(payload, bytes):
                    payload = payload.decode("utf-8-sig")
                result["tables"][asset.m_Name] = {
                    "member": member, "bundle_sha256": digest(data), "path_id": obj.path_id,
                    "text_sha256": digest(payload.encode()), "data": json.loads(payload),
                }
        result["missing_tables"] = sorted(TABLES - result["tables"].keys())
    return result


def differences(before, after, path=""):
    if type(before) is not type(after):
        return [{"path": path, "before": before, "after": after}]
    if isinstance(before, dict):
        result = []
        for key in sorted(before.keys() | after.keys()):
            subpath = path + "/" + str(key)
            if key not in before or key not in after:
                result.append({"path": subpath, "before": before.get(key), "after": after.get(key)})
            else:
                result.extend(differences(before[key], after[key], subpath))
        return result
    if isinstance(before, list):
        # Compare table records by their shipped id rather than by shifted indexes.
        if before and after and all(isinstance(row, dict) and "id" in row for row in before + after):
            return differences({str(row["id"]): row for row in before},
                               {str(row["id"]): row for row in after}, path)
        if len(before) != len(after):
            return [{"path": path, "before": before, "after": after}]
        return [diff for i, (old, new) in enumerate(zip(before, after))
                for diff in differences(old, new, path + "/" + str(i))]
    return [] if before == after else [{"path": path, "before": before, "after": after}]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--new", type=Path, required=True)
    parser.add_argument("--project-data", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    old, new = extract(args.old), extract(args.new)
    comparison = {"evidence_type": "static Unity TextAsset JSON comparison; no target runtime", "old": old, "new": new,
                  "old_to_new": {}, "project_to_new": {}}
    for name, table in new["tables"].items():
        comparison["old_to_new"][name] = differences(old["tables"].get(name, {}).get("data"), table["data"])
        local = args.project_data / (name + ".json")
        if local.exists():
            comparison["project_to_new"][name] = differences(json.loads(local.read_text()), table["data"])
    args.output.write_text(json.dumps(comparison, ensure_ascii=False, indent=2) + "\n")
    config = new["tables"]["RogueConfigData"]["data"]
    print(json.dumps({"output": str(args.output), "new_sha256": new["sha256"],
                      "old_to_new": {k: len(v) for k, v in comparison["old_to_new"].items()},
                      "project_to_new": {k: len(v) for k, v in comparison["project_to_new"].items()},
                      "settlement_constants": {k: v for k, v in config.items() if any(
                          term in k for term in ("CharaExpGet", "CharaUpgradeItemProvide", "BlessingExpEfficiency", "MonsterWork_"))}},
                     ensure_ascii=False))
