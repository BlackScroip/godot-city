"""Recover exact guide and charge sprites from the user-supplied APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def recover(apk, output, report, prefab):
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        selected = next(asset for asset in assets if asset["address"] == prefab)
        dependencies, bundle_dependencies = package_dependencies(manifest, selected["address"])
        pending, loaded_indices, primary, sources = [selected["bundle"], *dependencies], set(), [], {}
        environment = UnityPy.Environment()
        while pending:
            index = pending.pop()
            if index in loaded_indices:
                continue
            loaded_indices.add(index)
            pending.extend(bundle_dependencies[index])
            bundle = bundles[index]
            member = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            payload = archive.read(member)
            loaded = environment.load_file(payload)
            for cab in loaded.files.values():
                if hasattr(cab, "objects"):
                    sources[cab.name] = {"member": member, "sha256": digest(payload), "index": index}
                    if index == selected["bundle"]:
                        primary.extend(cab.objects.values())

    def dereference(pointer, owner):
        return PPtr(**pointer, assetsfile=owner.assets_file).deref()

    transforms = {obj.path_id: obj.read_typetree() for obj in primary if obj.type.name in ("Transform", "RectTransform")}
    objects = {obj.path_id: obj.read_typetree() for obj in primary if obj.type.name == "GameObject"}
    by_game_object = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}

    def hierarchy(transform_id):
        if not transform_id or transform_id not in transforms:
            return ""
        transform = transforms[transform_id]
        parent = hierarchy(transform["m_Father"]["m_PathID"])
        return (parent + "/" if parent else "") + objects[transform["m_GameObject"]["m_PathID"]]["m_Name"]

    images, controllers, resources, components = [], [], {}, []
    for obj in primary:
        if obj.type.name != "MonoBehaviour":
            continue
        tree = obj.read_typetree()
        transform_id = by_game_object.get(tree["m_GameObject"]["m_PathID"])
        path = hierarchy(transform_id)
        try:
            script = dereference(tree["m_Script"], obj).read().m_ClassName
        except (KeyError, AttributeError, TypeError):
            script = ""
        components.append({"path": path, "script": script, "path_id": str(obj.path_id), "keys": list(tree)})
        if script in ("Panel_PlayerBattleCtrl", "Box_BattleCharaInspector", "Panel_BattlePlayerCtrl_CustomAttackArea", "Box_MonsterSupportSkill", "SpecialStateBar_Buff") or "Sp" in script:
            controllers.append({"path": path, "script": script, "fields": tree})
        sprite_pointer = tree.get("m_Sprite")
        if not sprite_pointer or not sprite_pointer["m_PathID"]:
            continue
        if not prefab.startswith("SpecialStateBar_") and not any(token in path for token in ("GizmoTip", "CharaState", "CharaInspector", "Skill2", "SpBar", "SkillBar", "SpMax", "Box_SP", "Box_Sp")):
            continue
        sprite_object = dereference(sprite_pointer, obj)
        sprite = sprite_object.read()
        name = sprite.m_Name
        target = output / (hashlib.sha256(name.encode("utf-8")).hexdigest()[:16] + ".png")
        sprite.image.save(target)
        resource = "res://assets/ui/battle_guide/" + target.name
        resources[name] = resource
        images.append({"path": path, "source_sprite": name, "sprite_path_id": str(sprite_object.path_id),
                       "source_bundle": sources.get(sprite_object.assets_file.name), "resource": resource,
                       "sprite_rect": {"width": sprite.m_Rect.width, "height": sprite.m_Rect.height},
                       "texture_rect_offset": {"x": sprite.m_RD.textureRectOffset.x, "y": sprite.m_RD.textureRectOffset.y},
                       "png_sha256": digest(target.read_bytes()), "rect": transforms.get(transform_id),
                       "color": tree.get("m_Color"), "image_type": tree.get("m_Type"),
                       "fill_method": tree.get("m_FillMethod"), "fill_origin": tree.get("m_FillOrigin"),
                       "fill_amount": tree.get("m_FillAmount")})
    evidence = {"evidence_type": "Static UnityPy serialization and exact sprite extraction; no original runtime execution",
                "apk": str(apk), "apk_sha256": digest(apk.read_bytes()), "manifest": manifest_name,
                "manifest_sha256": digest(manifest), "prefab": selected, "controllers": controllers,
                "images": images, "resources": resources, "bundle_sources": sources}
    evidence["components"] = components
    report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"report": str(report), "image_count": len(images), "resources": resources}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--prefab", default="Panel_BattlePlayerCtrl")
    args = parser.parse_args()
    recover(args.apk, args.output, args.report, args.prefab)
