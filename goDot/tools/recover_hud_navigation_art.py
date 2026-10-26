"""Extract two exact HUD navigation sprites from the audited APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


SELECTED = {3330690163951857322: "Btn_GoComment", 5233595934828719786: "Btn_CatMealBuff"}


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
                    sources[cab.name] = {"member": member, "sha256": digest(payload), "index": index}
                    if index == selected["bundle"]:
                        primary.extend(cab.objects.values())
    images, resources = [], {}
    for obj in primary:
        if obj.path_id not in SELECTED:
            continue
        tree = obj.read_typetree()
        sprite_object = PPtr(**tree["m_Sprite"], assetsfile=obj.assets_file).deref()
        sprite = sprite_object.read()
        target = output / (hashlib.sha256(sprite.m_Name.encode("utf-8")).hexdigest()[:16] + ".png")
        sprite.image.save(target)
        resource = "res://assets/ui/hud_navigation/" + target.name
        resources[sprite.m_Name] = resource
        images.append({"button": SELECTED[obj.path_id], "image_component_path_id": str(obj.path_id),
                       "source_sprite": sprite.m_Name, "sprite_path_id": str(sprite_object.path_id),
                       "source_bundle": sources[sprite_object.assets_file.name], "resource": resource,
                       "sprite_rect": {"width": sprite.m_Rect.width, "height": sprite.m_Rect.height},
                       "png_sha256": digest(target.read_bytes())})
    if len(images) != len(SELECTED):
        raise ValueError("Expected both current-APK navigation sprite components")
    (output / "resource_map.json").write_text(json.dumps(resources, ensure_ascii=False, indent=2) + "\n")
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    evidence = {"evidence_type": "Static exact Unity sprite extraction; no APK runtime executed",
                "apk_sha256": apk_sha, "manifest_member": manifest_name,
                "manifest_sha256": digest(manifest), "prefab": selected, "images": images,
                "resources": resources}
    report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(evidence, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    recover(args.apk, args.output, args.report)
