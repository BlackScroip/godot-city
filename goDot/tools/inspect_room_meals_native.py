"""Retain hash-bound CatMeal_Shop interaction and purchase-rule evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records
import inspect_new_camp_native as native_audit


APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
SELECTION = {
    "ATGameManager": ["private void Msg_OpenCatMealMenu(Message"],
    "ATPanel_CatMealMenu": ["<RegisterItem>b__37_1", "<UpdateUIInfo>b__35_0", "<UpdateUIInfo>b__35_7"],
    "GameDataModel_AT": ["public bool BuyMeal", "public void CompletePurchased", "public void ClearInvalidMeal", "public bool CheckCanRecookLastMeal", "public int get_OrderLimitCount", "public bool CheckSelectedNeedMaterialsAndGold"],
    "RogueStableData": ["public void set_Gold("],
}


def sha(value):
    return hashlib.sha256(value).hexdigest()


def inspect(apk, native_path, metadata_path, stubs):
    native = native_path.read_bytes()
    metadata = metadata_path.read_bytes()
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != APK_SHA or sha(native) != NATIVE_SHA:
        raise ValueError("Room meal audit requires the supplied current APK/native hashes")
    with zipfile.ZipFile(apk) as archive:
        if archive.read("lib/arm64-v8a/libil2cpp.so") != native or archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat") != metadata:
            raise ValueError("Extracted native/metadata differ from supplied APK")
        manifest_member = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest)
        addresses = {row["address"]: row for row in assets}
        packaged = []
        for address in ["EnvUnit_Interactable_CatMeal_Shop", "CatMealData"]:
            asset = addresses[address]
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            objects = []
            for obj in UnityPy.load(payload).objects:
                if address == "CatMealData":
                    if obj.type.name != "TextAsset":
                        continue
                    tree = obj.read_typetree()
                    if tree.get("m_Name") != address:
                        continue
                    raw = tree["m_Script"]
                    parsed = json.loads(raw.decode("utf-8-sig") if isinstance(raw, bytes) else raw)
                    objects.append({"path_id": str(obj.path_id), "type": obj.type.name, "data": parsed})
                elif obj.type.name in ["GameObject", "Transform", "BoxCollider", "MonoBehaviour"]:
                    tree = obj.read_typetree()
                    if obj.type.name == "MonoBehaviour" and "Rogue_OpenCatMealMenu" not in json.dumps(tree) and "PropertyJson" not in tree:
                        continue
                    objects.append({"path_id": str(obj.path_id), "type": obj.type.name, "data": tree})
            packaged.append({"evidence_id": "room-meal-package-" + address, "address": address, "member": member, "bundle_sha256": sha(payload), "objects": objects})
    native_audit.SELECTION = SELECTION
    native_audit.SELECTED_OFFSETS = set()
    evidence = native_audit.inspect(native_path, stubs)
    for method in evidence["methods"]:
        start, length = int(method["file_offset"], 16), method["length"]
        method["evidence_id"] = "room-meal-native-" + method["file_offset"][2:]
        method["code_sha256"] = sha(native[start:start + length])
    source_root = stubs / "Assembly-CSharp" / "Teamelo" / "ProjectAT"
    field_evidence = []
    for filename, terms in {
        "ATPanel_CatMealMenu.cs": ["Shop =", "Research =", "PanelType;"],
        "CatMealData.cs": ["Never =", "CompleteRegion =", "EffectType;"],
        "RogueRunData.cs": ["PurchasedMealOnRegin;"],
        "ERogueEventType.cs": ["CompleteRegion =", "CompleteRun ="],
        "RogueStableData.cs": ["mGold;", "MaterialDict;"],
    }.items():
        path = source_root / filename
        content = path.read_bytes()
        field_evidence.append({"file": str(path), "sha256": sha(content), "declarations": [{"line": index + 1, "text": line.strip()} for index, line in enumerate(content.decode().splitlines()) if any(term in line for term in terms)]})
    placements = []
    project = Path(__file__).resolve().parents[1]
    for marker_file in sorted((project / "assets" / "environments").glob("*.markers.json")):
        payload = marker_file.read_bytes()
        for marker in json.loads(payload).get("semantic_markers", []):
            data = json.loads(marker.get("DataJson", "{}"))
            if data.get("UIBtnName") == "EnvUnit_MonoData_BtnDisplayName_CatMeal_Shop":
                placements.append({"file": str(marker_file), "sha256": sha(payload), "scene": marker["SceneName"], "source_game_object_id": marker["SourceGameObjectId"], "object_name": marker["ObjectName"], "position": marker["world_position"], "interaction": data})
    packaged_meals = next(item for item in packaged if item["address"] == "CatMealData")["objects"][0]["data"]
    imported_meals = json.loads((project / "assets" / "data" / "CatMealData.json").read_text())
    gameplay_fields = ["Id", "EffectType", "AbilityItemId", "NeedGold", "NeedMaterials", "UnlockDataId"]
    config_match = [{"id": row["Id"], "matches": all(row[field] == next(local for local in imported_meals if local["Id"] == row["Id"])[field] for field in gameplay_fields)} for row in packaged_meals]
    evidence.update({"apk": str(apk), "apk_sha256": apk_sha, "metadata_sha256": sha(metadata), "manifest_member": manifest_member, "manifest_sha256": sha(manifest), "packaged": packaged, "field_evidence": field_evidence, "derived_scene_placements": placements, "gameplay_config_matches": config_match, "limitations": ["Static disassembly and packaged prefab/configuration evidence; the original APK was not executed.", "Scene-placement enumeration uses the existing packaged-scene marker export; the reusable prefab itself is re-read directly from the supplied APK.", "End-of-run purchased meal reset is retained from the existing domain service; this bounded audit establishes the CompleteRegion expiry path, not all APK cleanup call sites."]})
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    evidence = inspect(args.apk, args.native, args.metadata, args.stubs)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(evidence["methods"]), "packaged": [entry["address"] for entry in evidence["packaged"]]}))
