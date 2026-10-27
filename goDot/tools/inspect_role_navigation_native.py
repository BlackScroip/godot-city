"""Retain bounded role-menu navigation evidence from the selected APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

import inspect_new_camp_native as native_audit


APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
ROLE_MEMBER = "assets/yoo/DefaultPackage/aeecac70829d59d07c645aee68d05266.bundle"


def inspect(apk, native, stubs):
    with apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != APK_SHA:
        raise ValueError("Address declarations require the selected APK hash")
    payload = native.read_bytes()
    with zipfile.ZipFile(apk) as archive:
        if archive.read("lib/arm64-v8a/libil2cpp.so") != payload:
            raise ValueError("Native file does not match the selected APK")
        prefab = archive.read(ROLE_MEMBER)
    objects = UnityPy.load(prefab).objects
    trees = {obj.path_id: obj.read_typetree() for obj in objects
             if obj.type.name in ("GameObject", "MonoBehaviour")}
    controllers = []
    for path_id, tree in trees.items():
        if "AlwaysDisplayInRun" not in tree and "btn_ItemPanel" not in tree:
            continue
        go = trees.get(tree.get("m_GameObject", {}).get("m_PathID"), {})
        row = {"path_id": str(path_id), "game_object": go.get("m_Name"), "fields": tree}
        for key in ("AlwaysDisplayInRun", "AlwaysDisplayOutRun"):
            if key not in tree:
                continue
            row[key + "_names"] = []
            for pointer in tree[key]:
                component = trees.get(pointer.get("m_PathID"), {})
                target_go = trees.get(component.get("m_GameObject", {}).get("m_PathID"), {})
                row[key + "_names"].append(target_go.get("m_Name", "unresolved"))
        controllers.append(row)
    native_audit.SELECTION = {
        "Panel_PlayerStateMenu": ["InitSelf", "RefreshAllTabs", "UpdateUIInfo"],
        "GameDataModel_AT": ["get_InstituteLevel"],
        "ItemData": ["CheckDisplayMode"],
    }
    native_audit.SELECTED_OFFSETS = set()
    result = native_audit.inspect(native, stubs)
    for method in result["methods"]:
        offset = int(method["file_offset"], 16)
        method["bytes"] = payload[offset:offset + method["length"]].hex()
        method["stub_sha256"] = hashlib.sha256(Path(method["stub"]).read_bytes()).hexdigest()
    result.update({
        "apk_sha256": digest,
        "apk": str(apk),
        "prefab": {"member": ROLE_MEMBER, "sha256": hashlib.sha256(prefab).hexdigest(),
                   "controllers": controllers,
                   "resource_roots": [{"name": tree["m_Name"], "active": tree["m_IsActive"]}
                                      for tree in trees.values()
                                      if str(tree.get("m_Name", "")).startswith("ATResBox") and "m_IsActive" in tree]},
        "prior_rea_evidence": [
            "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323",
            "ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c",
        ],
        "findings": {
            "item_tab": "InitSelf +0x80 slot is active exactly when PanelData.IsRun is true.",
            "partner_tab": "InitSelf +0x90 slot is active when IsRun and InstituteLevel >= 3.",
            "bag_tab": "No IsRun hiding of +0x88 slot was found in the retained InitSelf method.",
            "institute_level": "Getter reads building dictionary key 4 without a level adjustment.",
            "bag_materials": "RefreshAllTabs predicate requires CheckDisplayMode(1) and positive GetItemNum().",
            "material_filter": "CheckDisplayMode(1) excludes MagicPoint (102) and TokenItem (200).",
            "role_resource_bar": "Gold starts active; AlwaysDisplayInRun contains MagicPoint, SearchPoint and TokenUpgradeItem; AlwaysDisplayOutRun is empty.",
        },
        "limitations": [
            "Static ARM64 and declarations only; the original application was not executed.",
            "Tab captions, artwork and initial active flags are established by separate prefab recovery.",
            "This bounded query does not establish every parent canvas or external visibility override.",
        ],
    })
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk, args.native, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(result["methods"]),
                      "apk_sha256": result["apk_sha256"]}))
