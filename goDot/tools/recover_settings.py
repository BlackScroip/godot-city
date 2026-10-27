"""Recover settings and guide prefab evidence and exact sprites from the APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_camp_developer_ui import recover
from recover_route_art import package_dependencies


def recover_panel(apk, output, prefab, folder):
    recover(apk, output, prefab, folder)
    target = output / folder
    layout_path = target / "prefab-layout.json"
    layout = json.loads(layout_path.read_text())
    layout["evidence_type"] = "Static Unity serialized prefab; original APK was not executed"
    with zipfile.ZipFile(apk) as archive:
        payload = archive.read(layout["source"]["member"])
    environment = UnityPy.load(payload)
    objects = list(environment.objects)
    game_objects = {obj.path_id: obj.read_typetree() for obj in objects if obj.type.name == "GameObject"}
    transforms = {obj.path_id: obj.read_typetree() for obj in objects if obj.type.name in ("RectTransform", "Transform")}
    transform_by_go = {tree["m_GameObject"]["m_PathID"]: path_id for path_id, tree in transforms.items()}

    def hierarchy(transform_id):
        if transform_id not in transforms:
            return ""
        transform = transforms[transform_id]
        parent = hierarchy(transform.get("m_Father", {}).get("m_PathID", 0))
        name = game_objects.get(transform["m_GameObject"]["m_PathID"], {}).get("m_Name", "?")
        return parent + "/" + name if parent else name

    components = []
    for obj in objects:
        if obj.type.name != "MonoBehaviour":
            continue
        tree = obj.read_typetree()
        try:
            script = PPtr(**tree["m_Script"], assetsfile=obj.assets_file).deref().read().m_ClassName
        except (KeyError, AttributeError, TypeError):
            script = ""
        path = hierarchy(transform_by_go.get(tree["m_GameObject"]["m_PathID"]))
        if any(key in tree for key in ("m_MinValue", "List_Btn_ShowPopDamage", "m_IsOn", "GuideDatas", "m_CustomLocalizationKey")) or script in ("ATPanel_Option", "ATPanel_Guide", "ATPanel_GuideSub", "ATPanel_CloudSave"):
            components.append({"path": path, "path_id": str(obj.path_id), "script": script, "fields": tree})
    layout["components"] = components
    layout["game_objects"] = [{"path": hierarchy(transform_by_go.get(path_id)), "path_id": str(path_id), "active": tree.get("m_IsActive")} for path_id, tree in game_objects.items()]

    def fix_paths(value):
        if isinstance(value, dict):
            return {key: fix_paths(item) for key, item in value.items()}
        if isinstance(value, list):
            return [fix_paths(item) for item in value]
        if isinstance(value, str):
            return value.replace("res://assets/ui/camp/", "res://assets/ui/settings/")
        return value

    layout = fix_paths(layout)
    layout_path.write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n")
    for name in ("resource_map.json", "provenance.json"):
        path = output / name
        data = fix_paths(json.loads(path.read_text()))
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return layout


def recover_guide_data(apk, output):
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest_name))
        sources = []
        for address in ("GuideData", "LocalizationData_GuideData"):
            asset = next(row for row in assets if row["address"] == address)
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            environment = UnityPy.load(payload)
            text = next(obj.read() for obj in environment.objects if obj.type.name == "TextAsset" and obj.read().m_Name == address)
            data = json.loads(text.m_Script)
            (output / (address + ".json")).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
            sources.append({"address": address, "member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(), "data_sha256": hashlib.sha256(text.m_Script.encode("utf-8")).hexdigest()})
        (output / "guide-data-source.json").write_text(json.dumps(sources, ensure_ascii=False, indent=2) + "\n")
        guides = json.loads((output / "GuideData.json").read_text())
        image_names = {name.strip() for row in guides for name in row["middle_image_name"].split("|")}
        selected_assets = [row for row in assets if row["address"] in image_names]
        loaded_indices = set()
        environment = UnityPy.Environment()
        sprite_sources = {}
        for asset in selected_assets:
            dependencies, bundle_dependencies = package_dependencies(archive.read(manifest_name), asset["address"])
            pending = [asset["bundle"], *dependencies]
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
                        sprite_sources[cab.name] = {"member": member, "sha256": hashlib.sha256(payload).hexdigest()}
        image_folder = output / "guide_images"
        image_folder.mkdir(exist_ok=True)
        image_map, image_evidence = {}, []
        for obj in environment.objects:
            if obj.type.name != "Sprite":
                continue
            sprite = obj.read()
            if sprite.m_Name not in image_names or sprite.m_Name in image_map:
                continue
            filename = hashlib.sha256(sprite.m_Name.encode("utf-8")).hexdigest()[:16] + ".png"
            path = image_folder / filename
            sprite.image.save(path)
            resource = "res://assets/ui/settings/guide_images/" + filename
            image_map[sprite.m_Name] = resource
            image_evidence.append({"name": sprite.m_Name, "path": resource, "sprite_path_id": str(obj.path_id), "source": sprite_sources[obj.assets_file.name], "png_sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        if set(image_map) != image_names:
            raise ValueError("Missing guide images: " + repr(image_names - set(image_map)))
        (output / "guide_images" / "provenance.json").write_text(json.dumps(image_evidence, ensure_ascii=False, indent=2) + "\n")
        normalize_guides(output)


def normalize_guides(output):
    guides = json.loads((output / "GuideData.json").read_text())
    image_evidence = json.loads((output / "guide_images" / "provenance.json").read_text())
    image_map = {row["name"]: row["path"] for row in image_evidence}
    normalized = []
    for row in sorted(guides, key=lambda item: (item["type_name"], item["title_order"], item["id"])):
        heads = [part.strip() for part in row["head_text"].split("|")]
        tails = [part.strip() for part in row["tail_text"].split("|")]
        names = [part.strip() for part in row["middle_image_name"].split("|")]
        pages = [{"head": heads[index] if index < len(heads) else "", "body": tails[index] if index < len(tails) else "", "image": image_map.get(names[index], "") if index < len(names) else ""} for index in range(max(len(heads), len(tails), len(names)))]
        pages = [page for page in pages if page["head"] or page["body"] or page["image"]]
        normalized.append({"id": row["id"], "title": row["title"], "category": row["type_name"], "order": row["title_order"], "body": "\n\n".join(page["head"] + "\n" + page["body"] for page in pages), "images": [image_map[name] for name in names if name], "pages": pages})
    (output / "guides.json").write_text(json.dumps(normalized, ensure_ascii=False, indent=2) + "\n")


def recover_community(apk, output):
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest_name))
        asset = next(row for row in assets if row["address"] == "RogueConfigData")
        member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
        payload = archive.read(member)
        environment = UnityPy.load(payload)
        text = next(obj.read() for obj in environment.objects if obj.type.name == "TextAsset" and obj.read().m_Name == "RogueConfigData")
        data = json.loads(text.m_Script)
        community = {key: value for key, value in data.items() if key.startswith("URL_")}
        (output / "community.json").write_text(json.dumps(community, ensure_ascii=False, indent=2) + "\n")
        provenance = {"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(), "source_asset": asset, "source_member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(), "data_sha256": hashlib.sha256(text.m_Script.encode("utf-8")).hexdigest(), "evidence_type": "Static packaged configuration, no URL was opened or fetched"}
        (output / "community-source.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
        buff_sources = {}
        for ident in ("26080801", "26081001"):
            address = "BuffCfg_[" + ident + "]"
            asset = next(row for row in assets if row["address"] == address)
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            environment = UnityPy.load(payload)
            obj = next(obj for obj in environment.objects if obj.type.name == "TextAsset" and obj.read().m_Name == address)
            source = {"source_asset": asset["path"], "bundle": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(), "path_id": str(obj.path_id)}
            raw = json.loads(obj.read().m_Script)
            buff_sources[ident] = {"raw": raw, "apk_source": source}
        (output / "dodge_buffs.json").write_text(json.dumps(buff_sources, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    for prefab, folder in (("ATPanel_Option", "option"), ("ATPanel_Guide", "guide"), ("ATPanel_GuideSub", "guide_sub"), ("ATPanel_CloudSave", "cloud_save"), ("ATPanel_RedemptionCode", "redemption_code")):
        recover_panel(args.apk, args.output, prefab, folder)
    recover_guide_data(args.apk, args.output)
    recover_community(args.apk, args.output)
