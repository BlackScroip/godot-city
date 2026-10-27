"""Verify drop tables and retained ARM64 exports against the selected APK.

Requires UnityPy and capstone. This only reads the package; it never launches it.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import UnityPy
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

from inspect_camp_progression import manifest_records
from compare_camp_apks import differences as table_differences


APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA256 = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
TABLES = {"RogueConfigData", "ItemPoolData", "ItemPoolSubData", "LootData", "EnemyData", "NodeData"}
DROP_FIELD = re.compile(
    "Drop|TreasureBox|RecoverItemLootPool|ArmorItemLootPool|AbilityItemLootPool|"
    "LootInactive|SelectTalentIfMax|AbilityItem_SelectLootItem|AbilityItem_CharaTalentItem"
)
EXPORTS = (
    "city-new-map-drops.txt", "city-new-map-chests.txt",
    "city-new-map-extra-drops.txt", "city-new-map-amplify-tier.txt",
    "drop-rate-selection-native-20261026.txt",
    "drop-rate-random-native-20261027.txt",
    "chest-quality-native-20261027.txt",
    "challenge-chest-native-20261027.txt",
    "reward-slime-drop-native-20261027.txt",
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def verify_export(path, native):
    text = path.read_text()
    if "Native SHA256 " + sha256(native) not in text:
        raise ValueError("Native identity mismatch in " + str(path))
    pattern = re.compile(r"file_offset=(0x[0-9a-f]+) va=(0x[0-9a-f]+) length=(0x[0-9a-f]+)\n([^\n]+(?:\n0x[^\n]+)*)")
    decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    methods = []
    for match in pattern.finditer(text):
        offset, va, length = (int(value, 16) for value in match.groups()[:3])
        expected = [line.split("\t;")[0] for line in match.group(4).splitlines()]
        actual = [hex(ins.address) + "\t" + ins.mnemonic + "\t" + ins.op_str
                  for ins in decoder.disasm(native[offset:offset + length], va)]
        if expected != actual:
            raise ValueError("Instruction mismatch at " + hex(offset) + " in " + str(path))
        methods.append({"file_offset": hex(offset), "va": hex(va), "bytes": length,
                        "sha256": sha256(native[offset:offset + length]),
                        "instructions": len(actual)})
    if not methods:
        raise ValueError("No native methods found in " + str(path))
    return {"path": str(path), "sha256": sha256(path.read_bytes()), "methods": methods}


def audit(apk, project):
    with apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != APK_SHA256:
        raise ValueError("Selected APK differs from the authoritative 1061664.apk")
    result = {"apk": str(apk), "apk_sha256": digest,
              "evidence_type": "static APK configuration and byte-verified ARM64 exports; no APK execution",
              "tables": {}, "native_exports": [], "differences": []}
    with zipfile.ZipFile(apk) as archive:
        manifests = [name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes")]
        if len(manifests) != 1:
            raise ValueError("Expected exactly one YooAsset manifest")
        manifest = archive.read(manifests[0])
        result["manifest"] = {"member": manifests[0], "sha256": sha256(manifest)}
        assets, bundles = manifest_records(manifest)
        selected = [asset for asset in assets if asset["address"] in TABLES]
        for index in sorted({asset["bundle"] for asset in selected}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in TABLES:
                    continue
                asset = obj.read()
                raw = asset.m_Script
                raw = raw if isinstance(raw, bytes) else raw.encode("utf-8")
                source = json.loads(raw.decode("utf-8-sig"))
                if asset.m_Name == "NodeData":
                    campaign = json.loads((project / "assets/data/campaign.json").read_text())
                    local_by_id = {int(row["Id"]): row for row in campaign["Nodes"]}
                    active = [row for row in source if row.get("IsActive") and row.get("GenerateRule", {}).get("NodeLevel", 0) > 0]
                    changed = []
                    for row in active:
                        attributes = row.get("AttributeSet", {})
                        expected = {"FightType": attributes.get("FightType", ""),
                                    "FightData": attributes.get("FightData", {}),
                                    "EnemyClass": attributes.get("RoomEnemyType", ""),
                                    "FinalBoss": attributes.get("IsFinalBoss", False)}
                        if int(row["Type"]) == 5:
                            expected["TreasureBoxType"] = attributes.get("TreasureBoxType", "Normal")
                        for field, value in expected.items():
                            if local_by_id.get(int(row["Id"]), {}).get(field) != value:
                                changed.append({"id": int(row["Id"]), "field": field, "expected": value})
                    differences = [str(row["id"]) + "/" + row["field"] for row in changed]
                    comparison = {"active_room_rows": len(active), "compared_fields": ["FightType", "FightData", "EnemyClass", "FinalBoss", "TreasureBoxType (treasure-only nodes)"],
                                  "treasure_only_nodes": sum(int(row["Type"]) == 5 for row in active), "differences": changed}
                elif asset.m_Name == "RogueConfigData":
                    local = json.loads((project / "assets/data" / (asset.m_Name + ".json")).read_text())
                    keys = sorted(key for key in source if DROP_FIELD.search(key))
                    differences = [key for key in keys if source[key] != local.get(key)]
                    comparison = {"compared_drop_fields": keys, "mismatched_drop_fields": differences}
                else:
                    local = json.loads((project / "assets/data" / (asset.m_Name + ".json")).read_text())
                    changed = table_differences(local, source)
                    differences = [row["path"] for row in changed]
                    comparison = {"rows": len(source), "entire_table_matches_by_id": not differences,
                                  "differences": changed}
                result["tables"][asset.m_Name] = {
                    "member": member, "bundle_sha256": sha256(payload),
                    "path_id": str(obj.path_id), "text_sha256": sha256(raw),
                    "comparison": comparison,
                }
                result["differences"].extend(asset.m_Name + ":" + diff for diff in differences)
        if missing := TABLES - result["tables"].keys():
            raise ValueError("Missing tables: " + str(sorted(missing)))
        native_member = "lib/arm64-v8a/libil2cpp.so"
        native = archive.read(native_member)
        if sha256(native) != NATIVE_SHA256:
            raise ValueError("APK native identity differs from the retained analysis")
        result["native"] = {"member": native_member, "sha256": sha256(native)}
        for filename in EXPORTS:
            result["native_exports"].append(verify_export(project / "reports" / filename, native))
    result["passed"] = not result["differences"]
    return result


if __name__ == "__main__":
    project = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=project.parent / "1061664.apk")
    parser.add_argument("--project", type=Path, default=project)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.apk, args.project)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": result["passed"], "output": str(args.output),
                      "apk_sha256": result["apk_sha256"], "tables": len(result["tables"]),
                      "drop_config_fields": len(result["tables"]["RogueConfigData"]["comparison"]["compared_drop_fields"]),
                      "verified_native_methods": sum(len(row["methods"]) for row in result["native_exports"]),
                      "differences": result["differences"]}))
    raise SystemExit(0 if result["passed"] else 1)
