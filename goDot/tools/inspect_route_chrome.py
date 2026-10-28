"""Recover route panel chrome and serialized animation/layout evidence.

This inspects the supplied APK statically. Sprite identity and prefab geometry
are package observations; no Android playback or transition was observed.
Requires UnityPy, Pillow, and the dependencies of recover_route_art.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


PREFABS = ("ATPanel_RegionMapSelect", "ATPanel_RoadMapSelect", "ATSlot_RoadMapNode")
CHROME = {
    "sprite_materialicon_102": "magic_essence",
    "sprite_abilityitemicon_15101": "search_point",
    "\u8d27\u5e01_\u5e95": "resource_bar",
    "\u51e0\u4f55ui-\u5f02\u5f62\u767d\u8272\u6309\u94ae": "select_button",
    "\u9000\u51fa\u6309\u94ae": "back_button",
    "\u52fe\u9009\u6846": "checkbox",
    "\u52fe\u9009": "checkmark",
    "\u987b\u77e5": "help_button",
}
RECT_FIELDS = ("m_AnchorMin", "m_AnchorMax", "m_AnchoredPosition", "m_SizeDelta",
               "m_Pivot", "m_LocalScale", "m_LocalRotation")


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def json_safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    return value


def inspect(apk, output, report):
    output.mkdir(parents=True, exist_ok=True)
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    result = {"apk": str(apk), "apk_sha256": apk_sha, "prefabs": [], "clips": [],
              "sprites": {}, "effects": [],
              "limitations": ["Static serialized prefab and AnimationClip evidence only; "
                              "original runtime playback was not observed."]}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        result["manifest"] = {"member": manifest_name, "sha256": digest(manifest)}
        lookup = {asset["address"]: asset for asset in assets}
        pending, seen = [], set()
        for address in PREFABS:
            dependencies, edges = package_dependencies(manifest, address)
            pending.extend([lookup[address]["bundle"], *dependencies])
        env, objects, sources = UnityPy.Environment(), {}, {}
        while pending:
            index = pending.pop()
            if index in seen:
                continue
            seen.add(index)
            pending.extend(edges[index])
            bundle = bundles[index]
            member = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            payload = archive.read(member)
            loaded = env.load_file(payload)
            objects[index] = []
            for file in loaded.files.values():
                if not hasattr(file, "objects"):
                    continue
                objects[index].extend(file.objects.values())
                sources[file.name] = {"member": member, "bundle_name": bundle["name"],
                                      "bundle_hash": bundle["hash"], "sha256": digest(payload)}

        def deref(pointer, owner):
            return PPtr(**pointer, assetsfile=owner.assets_file).deref()

        def go_rect(go):
            for entry in go.read_typetree()["m_Component"]:
                component = deref(entry["component"], go)
                if component.type.name == "RectTransform":
                    return component
            return None

        def rect_path(rect):
            tree = rect.read_typetree()
            name = deref(tree["m_GameObject"], rect).peek_name()
            parent = tree.get("m_Father")
            if parent and parent["m_PathID"]:
                return rect_path(deref(parent, rect)) + "/" + name
            return name

        def component_layout(obj, tree):
            go = deref(tree["m_GameObject"], obj)
            rect = go_rect(go)
            return {"game_object": go.peek_name(),
                    "path": rect_path(rect) if rect else go.peek_name(),
                    "rect": {key: rect.read_typetree()[key] for key in RECT_FIELDS} if rect else {},
                    "active": go.read_typetree().get("m_IsActive")}

        def effect_tree(root):
            if root.type.name != "GameObject":
                root = deref(root.read_typetree()["m_GameObject"], root)
            rows, materials = [], {}

            def walk(go, parent):
                tree = go.read_typetree()
                path = parent + "/" + tree["m_Name"] if parent else tree["m_Name"]
                for entry in tree["m_Component"]:
                    component = deref(entry["component"], go)
                    fields = component.read_typetree()
                    rows.append({"path": path, "type": component.type.name,
                                 "path_id": str(component.path_id), "tree": fields})
                    for pointer in fields.get("m_Materials", []):
                        material = deref(pointer, component)
                        material_tree = material.read_typetree()
                        material_record = {
                            "name": material.peek_name(), "source": sources[material.assets_file.name],
                            "tree": material_tree, "textures": []}
                        for slot, properties in material_tree["m_SavedProperties"]["m_TexEnvs"]:
                            pointer = properties["m_Texture"]
                            if not pointer["m_PathID"]:
                                continue
                            texture = deref(pointer, material)
                            picture = texture.read().image.convert("RGBA")
                            suffix = material.peek_name().split("bossnode_")[-1]
                            filename = "boss_" + suffix + slot.lower() + ".png"
                            target = output / filename
                            picture.save(target)
                            material_record["textures"].append({
                                "slot": slot, "name": texture.peek_name(),
                                "path_id": str(texture.path_id),
                                "source": sources[texture.assets_file.name],
                                "resource": "res://assets/ui/route/chrome/" + filename,
                                "dimensions": [picture.width, picture.height],
                                "png_sha256": digest(target.read_bytes())})
                        materials[str(material.path_id)] = material_record
                    for pointer in fields.get("m_Children", []):
                        transform = deref(pointer, component)
                        walk(deref(transform.read_typetree()["m_GameObject"], transform), path)

            walk(root, "")
            return {"name": root.peek_name(), "source": sources[root.assets_file.name],
                    "components": rows, "materials": materials}

        for address in PREFABS:
            asset = lookup[address]
            record = {"address": address, "path": asset["path"], "images": [], "controllers": [],
                      "button_components": []}
            for obj in objects[asset["bundle"]]:
                if obj.type.name not in ("MonoBehaviour", "Animator", "Animation"):
                    continue
                tree = obj.read_typetree()
                if "m_GameObject" not in tree:
                    continue
                layout = component_layout(obj, tree)
                if address == "ATPanel_RoadMapSelect" and "/ATBtn_Select" in layout["path"]:
                    record["button_components"].append({**layout, "type": obj.type.name,
                                                        "path_id": str(obj.path_id), "tree": tree})
                if obj.type.name != "MonoBehaviour":
                    record["controllers"].append({**layout, "type": obj.type.name, "tree": tree})
                    continue
                pointer = tree.get("m_Sprite")
                if pointer and pointer["m_PathID"]:
                    sprite_obj = deref(pointer, obj)
                    sprite_tree = sprite_obj.read_typetree()
                    picture = sprite_obj.read().image.convert("RGBA")
                    image = {**layout, "name": sprite_obj.peek_name(),
                             "sprite_path_id": str(sprite_obj.path_id),
                             "image_path_id": str(obj.path_id),
                             "sprite_rect": sprite_tree["m_Rect"],
                             "sprite_border": sprite_tree.get("m_Border"),
                             "dimensions": [picture.width, picture.height],
                             "alpha_bounds": picture.getchannel("A").getbbox(),
                             "color": tree.get("m_Color"), "image_type": tree.get("m_Type"),
                             "source": sources[sprite_obj.assets_file.name]}
                    record["images"].append(image)
                    if image["name"] in CHROME:
                        key = CHROME[image["name"]]
                        if key not in result["sprites"]:
                            target = output / (key + ".png")
                            picture.save(target)
                            result["sprites"][key] = {
                                **image, "resource": "res://assets/ui/route/chrome/" + target.name,
                                "png_sha256": digest(target.read_bytes())}
                if any(key in tree for key in ("mFirtNodeInitPos", "mColumnNodeSpace",
                                               "stateArray_NoReachable", "m_Animations")):
                    record["controllers"].append({**layout, "type": obj.type.name,
                                                  "path_id": str(obj.path_id), "tree": tree})
                    if address == "ATSlot_RoadMapNode" and tree.get("Fx", {}).get("m_PathID"):
                        result["effects"].append(effect_tree(deref(tree["Fx"], obj)))
            result["prefabs"].append(record)
        for obj in env.objects:
            if obj.type.name not in ("AnimationClip", "AnimatorController"):
                continue
            result["clips"].append({"name": obj.peek_name(), "type": obj.type.name,
                                    "path_id": str(obj.path_id),
                                    "source": sources[obj.assets_file.name],
                                    "tree": obj.read_typetree()})
    path = report
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(json_safe(result), ensure_ascii=False, indent=2) + "\n")
    provenance = {key: result[key] for key in ("apk", "apk_sha256", "manifest", "sprites", "limitations")}
    provenance["effects"] = []
    for effect in result["effects"]:
        materials = []
        for material in effect["materials"].values():
            properties = material["tree"]["m_SavedProperties"]
            materials.append({key: material[key] for key in ("name", "source", "textures")} | {
                "float_parameters": dict(properties["m_Floats"]),
                "color_parameters": dict(properties["m_Colors"])})
        particles = []
        for component in effect["components"]:
            if component["type"] != "ParticleSystem":
                continue
            fields = component["tree"]
            initial = fields["InitialModule"]
            particles.append({"name": component["path"].split("/")[-1],
                              "duration": fields["lengthInSec"], "looping": fields["looping"],
                              "prewarm": fields["prewarm"],
                              "lifetime": initial["startLifetime"]["scalar"],
                              "start_color": initial["startColor"]["maxColor"],
                              "rate": fields["EmissionModule"]["rateOverTime"]["scalar"]})
        provenance["effects"].append({"name": effect["name"], "source": effect["source"],
                                      "materials": materials, "particles": particles})
    animations = []
    for clip in result["clips"]:
        if not (clip["name"] in ("SelectNode", "Anim_RoadMapNode_Init", "Panel_RoadMapSelectOpen")
                or clip["name"].startswith("CharaCardMove_")):
            continue
        fields = clip["tree"]
        animations.append({"name": clip["name"], "path_id": clip["path_id"], "source": clip["source"],
                           "sample_rate": fields["m_SampleRate"], "wrap_mode": fields["m_WrapMode"],
                           "curves": [{"path": curve["path"],
                                       "attribute": curve.get("attribute", group),
                                       "keys": curve["curve"]["m_Curve"]}
                                      for group in ("m_ScaleCurves", "m_PositionCurves", "m_FloatCurves")
                                      for curve in fields[group]]})
    provenance["animations"] = [{key: clip[key] for key in ("name", "path_id", "source", "sample_rate", "wrap_mode")}
                                 | {"curves": [{"path": curve["path"], "attribute": curve["attribute"],
                                                "keys": [{key: point[key] for key in ("time", "value")}
                                                         for point in curve["keys"]]}
                                               for curve in clip["curves"]]}
                                 for clip in animations]
    (output / "provenance.json").write_text(json.dumps(json_safe(provenance), ensure_ascii=False, indent=2) + "\n")
    curve_report = report.with_name(report.stem + "-curves.json")
    curve_report.write_text(json.dumps(json_safe(animations), ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(path), "prefabs": len(result["prefabs"]),
                      "clips": len(result["clips"])}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1]
                        / "assets/ui/route/chrome")
    parser.add_argument("--report", type=Path, default=Path(__file__).resolve().parents[1]
                        / "reports/route-chrome-apk-source.json")
    args = parser.parse_args()
    inspect(args.apk, args.output, args.report)
