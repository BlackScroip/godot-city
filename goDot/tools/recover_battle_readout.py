"""Recover the APK hit-counter layout, animation settings and exact sprites."""

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


def recover(apk, output, report):
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        selected = next(asset for asset in assets if asset["address"] == "Panel_BattlePlayerCtrl")
        dependencies, bundle_dependencies = package_dependencies(manifest, selected["address"])
        pending, loaded_indices, primary, sources = [selected["bundle"], *dependencies], set(), [], {}
        environment = UnityPy.Environment()
        while pending:
            index = pending.pop()
            if index in loaded_indices:
                continue
            loaded_indices.add(index)
            pending.extend(bundle_dependencies[index])
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            loaded = environment.load_file(payload)
            for cab in loaded.files.values():
                if hasattr(cab, "objects"):
                    sources[cab.name] = {"member": member, "sha256": digest(payload)}
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

    images, components, rectangles, resources = [], [], [], {}
    for obj in primary:
        if obj.type.name != "MonoBehaviour":
            continue
        tree = obj.read_typetree()
        path = hierarchy(by_game_object.get(tree["m_GameObject"]["m_PathID"]))
        if "HitCount" not in path:
            continue
        try:
            script = dereference(tree["m_Script"], obj).read().m_ClassName
        except (KeyError, AttributeError, TypeError):
            script = ""
        components.append({"path": path, "script": script, "fields": tree})
        pointer = tree.get("m_Sprite")
        if pointer and pointer["m_PathID"]:
            sprite_obj = dereference(pointer, obj)
            sprite = sprite_obj.read()
            filename = hashlib.sha256(sprite.m_Name.encode("utf-8")).hexdigest()[:16] + ".png"
            sprite.image.save(output / filename)
            resource = "res://assets/ui/battle_readout/" + filename
            resources[sprite.m_Name] = resource
            images.append({"path": path, "name": sprite.m_Name, "resource": resource,
                           "source": sources.get(sprite_obj.assets_file.name),
                           "png_sha256": digest((output / filename).read_bytes())})
    for transform_id, tree in transforms.items():
        path = hierarchy(transform_id)
        if "HitCount" in path:
            rectangles.append({"path": path, "fields": tree,
                               "active": objects[tree["m_GameObject"]["m_PathID"]]["m_IsActive"]})
    for obj in environment.objects:
        if obj.type.name != "Sprite":
            continue
        sprite = obj.read()
        if not sprite.m_Name.startswith(("bar_hits_", "tail_hits_", "word_hits_")):
            continue
        filename = hashlib.sha256(sprite.m_Name.encode("utf-8")).hexdigest()[:16] + ".png"
        sprite.image.save(output / filename)
        resources[sprite.m_Name] = "res://assets/ui/battle_readout/" + filename
        if not any(image["name"] == sprite.m_Name for image in images):
            images.append({"path": "stage-resource", "name": sprite.m_Name,
                           "resource": resources[sprite.m_Name],
                           "source": sources.get(obj.assets_file.name),
                           "png_sha256": digest((output / filename).read_bytes())})
    (output / "resource_map.json").write_text(json.dumps(resources, ensure_ascii=False, indent=2) + "\n")
    evidence = {"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
                "evidence_type": "Static Unity prefab and sprite extraction; no original runtime observation",
                "manifest": manifest_name, "manifest_sha256": digest(manifest),
                "prefab": selected, "bundle_sources": sources,
                "components": components, "rectangles": rectangles, "images": images, "resources": resources}
    report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"report": str(report), "image_count": len(images), "resource_count": len(resources)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    recover(args.apk, args.output, args.report)
