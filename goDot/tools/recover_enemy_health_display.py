"""Recover APK enemy/Boss health sprites, serialized layout and lock animations."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


def sha(data):
    return hashlib.sha256(data).hexdigest()


def recover(apk, output, report, rea_evidence):
    output.mkdir(parents=True, exist_ok=True)
    targets = {"normal": "Box_EnemyState", "elite": "Box_EnemyState_Elite",
               "boss": "Panel_BattlePlayerCtrl"}
    result = {"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
              "rea_inventory_evidence": rea_evidence,
              "evidence_type": "Static Unity serialization and exact sprite extraction; no APK execution",
              "prefabs": {}, "sprites": {}, "tables": {}}
    styles = {}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(n for n in archive.namelist() if n.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        result["manifest"] = {"member": manifest_name, "sha256": sha(manifest)}
        for kind, name in targets.items():
            asset = next(a for a in assets if a["address"] == name)
            dependencies, edges = package_dependencies(manifest, name)
            pending, seen, primary, sources = [asset["bundle"], *dependencies], set(), [], {}
            env = UnityPy.Environment()
            while pending:
                index = pending.pop()
                if index in seen:
                    continue
                seen.add(index)
                pending.extend(edges[index])
                member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
                payload = archive.read(member)
                loaded = env.load_file(payload)
                for cab in loaded.files.values():
                    if hasattr(cab, "objects"):
                        sources[cab.name] = {"member": member, "sha256": sha(payload)}
                        if index == asset["bundle"]:
                            primary.extend(cab.objects.values())

            def deref(pointer, owner):
                return PPtr(**pointer, assetsfile=owner.assets_file).deref()

            objects = {o.path_id: o.read_typetree() for o in primary if o.type.name == "GameObject"}
            transforms = {o.path_id: o.read_typetree() for o in primary
                          if o.type.name in ("Transform", "RectTransform")}
            by_object = {t["m_GameObject"]["m_PathID"]: key for key, t in transforms.items()}

            def hierarchy(key):
                if key not in transforms:
                    return ""
                tree = transforms[key]
                prefix = hierarchy(tree["m_Father"]["m_PathID"])
                return prefix + "/" + objects[tree["m_GameObject"]["m_PathID"]]["m_Name"]

            root_path = "/" + name if kind != "boss" else (
                "/Panel_BattlePlayerCtrl/PanelLayer_PlayerControll/Mode_InBattle/Box_EnemyBossHpState")

            def relative(key):
                path = hierarchy(key)
                return path[len(root_path):].lstrip("/") if path == root_path or path.startswith(root_path + "/") else None

            prefab = {"asset": asset, "rectangles": {}, "components": [], "animations": []}
            style = {"images": {}, "texts": {}, "bars": {}, "lock_animations": {}}
            for key, tree in transforms.items():
                path = relative(key)
                if path is None or "Box_UnitBuff" in path:
                    continue
                prefab["rectangles"][path] = {
                    "path_id": str(key), "active": objects[tree["m_GameObject"]["m_PathID"]]["m_IsActive"],
                    **{k: tree[k] for k in ("m_AnchorMin", "m_AnchorMax", "m_AnchoredPosition",
                                          "m_SizeDelta", "m_Pivot", "m_LocalScale", "m_LocalRotation", "m_Children") if k in tree}}
            for obj in primary:
                if obj.type.name not in ("MonoBehaviour", "Animation"):
                    continue
                tree = obj.read_typetree()
                path = relative(by_object.get(tree["m_GameObject"]["m_PathID"]))
                if path is None or "Box_UnitBuff" in path:
                    continue
                if obj.type.name == "Animation":
                    for pointer in tree["m_Animations"]:
                        clip = deref(pointer, obj)
                        fields = clip.read_typetree()
                        prefab["animations"].append({"path": path, "path_id": str(clip.path_id),
                                                     "source": sources[clip.assets_file.name],
                                                     "fields": fields})
                        if path == "HpStateBar/Invincible":
                            style["lock_animations"][fields["m_Name"]] = {
                                "scale": fields["m_ScaleCurves"][0]["curve"]["m_Curve"],
                                "floats": [{"path": c["path"], "attribute": c["attribute"],
                                            "keys": c["curve"]["m_Curve"]} for c in fields["m_FloatCurves"]]}
                    continue
                script = deref(tree["m_Script"], obj).read().m_ClassName
                prefab["components"].append({"path": path, "script": script,
                                             "path_id": str(obj.path_id), "fields": tree})
                if script == "HpStateBar":
                    style["bars"][path] = {k: tree[k] for k in ("HPModel", "mShakeStrength", "mShakeDuration", "mShakeVibrato")}
                if script == "TextMeshProUGUI":
                    style["texts"][path] = {k: tree[k] for k in ("m_text", "m_fontSize", "m_fontColor", "m_enableAutoSizing")}
                pointer = tree.get("m_Sprite")
                if not pointer or not pointer["m_PathID"]:
                    continue
                sprite_obj = deref(pointer, obj)
                sprite = sprite_obj.read()
                sprite_tree = sprite_obj.read_typetree()
                filename = sha(sprite.m_Name.encode())[:16] + ".png"
                target = output / filename
                if filename not in result["sprites"]:
                    picture = sprite.image
                    picture.save(target)
                    result["sprites"][filename] = {
                        "name": sprite.m_Name, "path_id": str(sprite_obj.path_id),
                        "source": sources[sprite_obj.assets_file.name],
                        "png_sha256": sha(target.read_bytes()), "width": picture.width, "height": picture.height,
                        "border": sprite_tree["m_Border"], "rect": sprite_tree["m_Rect"],
                        "texture_rect_offset": sprite_tree["m_RD"]["textureRectOffset"]}
                style["images"][path] = {"resource": "res://assets/ui/enemy_health/" + filename,
                    "name": sprite.m_Name, "color": tree["m_Color"], "type": tree.get("m_Type", 1),
                    "border": result["sprites"][filename]["border"],
                    "rect": result["sprites"][filename]["rect"],
                    "texture_rect_offset": result["sprites"][filename]["texture_rect_offset"]}
            prefab["bundle_sources"] = sources
            result["prefabs"][kind] = prefab
            styles[kind] = style
        for name in ("EnemyData", "EnemyNumericalConfigData"):
            asset = next(a for a in assets if a["address"] == name)
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            obj = next(o for o in UnityPy.load(payload).objects if o.type.name == "TextAsset" and o.peek_name() == name)
            text = obj.read().m_Script
            if isinstance(text, bytes):
                text = text.decode("utf-8-sig")
            imported = Path(__file__).resolve().parents[1] / "assets/data" / (name + ".json")
            local = json.loads(imported.read_text())
            if name == "EnemyNumericalConfigData" and isinstance(local, list) and len(local) == 1:
                local = local[0]
            matches = json.loads(text) == local
            result["tables"][name] = {"member": member, "bundle_sha256": sha(payload),
                "path_id": str(obj.path_id), "text_sha256": sha(text.encode()), "matches_imported_data": matches}
            if not matches:
                raise ValueError("Imported enemy table differs from this APK: " + name)
    (output / "styles.json").write_text(json.dumps(styles, ensure_ascii=False, indent=2) + "\n")
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"report": str(report), "sprites": len(result["sprites"]), "tables": result["tables"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--rea-inventory-evidence", required=True)
    args = parser.parse_args()
    recover(args.apk, args.output, args.report, args.rea_inventory_evidence)
