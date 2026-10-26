"""Inspect skill-control rectangles in the supplied APK without executing it."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


TARGETS = (
    "AttackActionArea", "SkillSlot_NormalAttack", "SkillSlot_SkillDodge",
    "SkillSlot_ActiveSkill1", "SkillSlot_ActiveSkill2", "Btn_AutoAttack",
)
RECT_FIELDS = (
    "m_LocalScale", "m_AnchorMin", "m_AnchorMax", "m_AnchoredPosition",
    "m_SizeDelta", "m_Pivot",
)


def inspect(apk, inventory_evidence):
    with zipfile.ZipFile(apk) as archive:
        manifest_member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest)
        asset = next(row for row in assets if row["address"] == "Panel_BattlePlayerCtrl")
        member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
        payload = archive.read(member)
    env = UnityPy.load(payload)
    objects = {obj.path_id: obj for obj in env.objects}
    names = {obj.path_id: obj.read_typetree()["m_Name"] for obj in env.objects
             if obj.type.name == "GameObject"}
    rects = {obj.read_typetree()["m_GameObject"]["m_PathID"]: (obj.path_id, obj.read_typetree())
             for obj in env.objects if obj.type.name == "RectTransform"}

    def hierarchy(go_id):
        name = names[go_id]
        rect = rects.get(go_id)
        parent_id = rect[1]["m_Father"]["m_PathID"] if rect else 0
        if parent_id not in objects:
            return name
        parent = objects[parent_id].read_typetree()["m_GameObject"]["m_PathID"]
        return hierarchy(parent) + "/" + name

    controls = []
    for go_id, name in names.items():
        if name not in TARGETS:
            continue
        rect_id, rect = rects[go_id]
        controls.append({
            "name": name, "path": hierarchy(go_id), "game_object_path_id": str(go_id),
            "rect_path_id": str(rect_id), "rect": {key: rect[key] for key in RECT_FIELDS},
            "local_scaled_size": {axis: rect["m_SizeDelta"][axis] * rect["m_LocalScale"][axis]
                                  for axis in ("x", "y")},
        })
    return {
        "apk": str(apk), "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
        "rea_inventory_evidence": inventory_evidence,
        "manifest": {"member": manifest_member, "sha256": hashlib.sha256(manifest).hexdigest()},
        "prefab": {"asset": asset, "member": member, "sha256": hashlib.sha256(payload).hexdigest()},
        "controls": sorted(controls, key=lambda row: TARGETS.index(row["name"])),
        "observations": "Serialized local rectangles establish size hierarchy and corner anchoring.",
        "limits": [
            "Static prefab evidence only; original APK execution and click animation timing were not observed.",
            "Local scaled sizes exclude ancestor Canvas scaling and runtime user layout preferences.",
            "Godot spacing, equal auxiliary sizes, hit padding and animation curves are implementation choices.",
        ],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rea-inventory-evidence", required=True)
    args = parser.parse_args()
    result = inspect(args.apk, args.rea_inventory_evidence)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"controls": [{"name": row["name"], "size": row["local_scaled_size"]}
                                   for row in result["controls"]], "output": str(args.output)}))
