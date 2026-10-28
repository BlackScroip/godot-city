"""Inspect the selected APK's purification altar gate and authored scene markers."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

import inspect_new_camp_native as native
from recover_altar_ui import decode_literals
from recover_chest_effects import package_manifest


APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
ALTAR_KEY = "EnvUnit_MonoData_BtnDisplayName_SacrificialAltar"
ROOT = Path(__file__).resolve().parents[1]


def inspect(apk, binary, metadata, stubs):
    with apk.open("rb") as handle:
        apk_sha = hashlib.file_digest(handle, "sha256").hexdigest()
    assert apk_sha == APK_SHA, "Unexpected APK identity"
    native.SELECTION.clear()
    native.SELECTED_OFFSETS.clear()
    native.SELECTED_OFFSETS.update({
        0x2E730B8, 0x2E4250C, 0x2E5B088, 0x2E6A8CC,
        0x2E58044, 0x2E58410, 0x2E6A3DC, 0x2E6DFC0,
    })
    result = native.inspect(binary, stubs)
    assert result["native_sha256"] == NATIVE_SHA, "Native file differs from selected APK"
    result["apk"] = str(apk)
    result["apk_sha256"] = apk_sha
    result["rea_inventory_evidence"] = "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323"
    result["literal_relocations"] = decode_literals(binary.read_bytes(), metadata.read_bytes(), {
        0x65C5B00, 0x65C59A8, 0x65C59B0, 0x65C59B8,
    })
    scenes = []
    with zipfile.ZipFile(apk) as archive:
        manifest_member = next(name for name in archive.namelist()
                               if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest_raw = archive.read(manifest_member)
        manifest = package_manifest(manifest_raw)
        result["manifest"] = {"member": manifest_member, "sha256": hashlib.sha256(manifest_raw).hexdigest()}
        for region in range(101, 108):
            name = f"LevelMap_{region}9101"
            asset = next(asset for asset in manifest["assets"] if asset["address"] == name)
            bundle = manifest["bundles"][asset["bundle"]]
            member = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            payload = archive.read(member)
            environment = UnityPy.load(payload)
            markers = []
            for obj in environment.objects:
                if obj.type.name != "MonoBehaviour":
                    continue
                data = obj.read_typetree()
                definition = json.loads(data.get("PropertyJson") or "{}")
                if definition.get("EnvUnitData", {}).get("UIBtnName") != ALTAR_KEY:
                    continue
                owner_ref = data["m_GameObject"]
                assert owner_ref["m_FileID"] == 0
                owner = obj.assets_file.objects[owner_ref["m_PathID"]]
                owner_data = owner.read_typetree()
                markers.append({
                    "serialized_file": obj.assets_file.name,
                    "component_path_id": str(obj.path_id),
                    "gameobject_path_id": str(owner.path_id),
                    "name": owner_data["m_Name"],
                    "root_local_active": bool(owner_data["m_IsActive"]),
                    "ResId": data["ResId"], "SpawnId": data["SpawnId"],
                    "property": definition,
                })
            imported = json.loads((ROOT / "assets/environments" / (name + ".markers.json")).read_text())
            imported_markers = [row for row in imported["semantic_markers"]
                                if json.loads(row.get("DataJson") or "{}").get("UIBtnName") == ALTAR_KEY]
            scenes.append({
                "scene": name, "asset_path": asset["path"],
                "bundle_member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                "source_markers": markers, "imported_markers": imported_markers,
            })
    result["scenes"] = scenes
    result["limitations"] = [
        "Static package and native instruction evidence; the Android runtime was not executed.",
        "Scene object IDs and imported IDs are recorded separately; imports can originate from earlier serialized layouts.",
        "REA inventory binds package identity only; Capstone instructions and Unity serialized fields establish the rules.",
    ]
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = inspect(args.apk, args.native, args.metadata, args.stubs)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(report["methods"]),
                      "scenes": {row["scene"]: [{"ResId": marker["ResId"], "SpawnId": marker["SpawnId"]}
                                               for marker in row["source_markers"]] for row in report["scenes"]}}))
