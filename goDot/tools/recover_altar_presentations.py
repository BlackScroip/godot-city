#!/usr/bin/env python3
"""Recover altar billboard and model identities from the selected APK prefabs."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from PIL import Image

from recover_chest_effects import package_manifest


ROOT = Path(__file__).resolve().parents[1]
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def recover(apk, output, evidence):
    targets = {"EnvUnit_Interactable_" + name for name in ["CurseAltar", "SacrificialAltar", "SpritesAltar"]}
    targets.add("LevelMap_1010901")
    with zipfile.ZipFile(apk) as archive:
        member = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest_raw = archive.read(member)
        manifest = package_manifest(manifest_raw)
        assert hashlib.file_digest(apk.open("rb"), "sha256").hexdigest() == APK_SHA
        selected = [asset for asset in manifest["assets"] if asset["address"] in targets]
        indices = set()
        pending = [index for asset in selected for index in [asset["bundle"], *asset["deps"]]]
        while pending:
            index = pending.pop()
            if index in indices:
                continue
            indices.add(index)
            pending.extend(manifest["bundles"][index]["deps"])
        env = UnityPy.Environment()
        bundles = {}
        for index in sorted(indices):
            bundle = manifest["bundles"][index]
            path = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            raw = archive.read(path)
            env.load_file(raw, name=path)
            bundles[index] = dict(member=path, sha256=digest(raw))
    objects = {(obj.assets_file.name, obj.path_id): obj for obj in env.objects}
    cache = {}

    def tree(obj):
        if obj is None:
            return {}
        key = obj.assets_file.name, obj.path_id
        if key not in cache:
            cache[key] = obj.read_typetree()
        return cache[key]

    def resolve(obj, ref):
        if not ref or not ref.get("m_PathID"):
            return None
        file_id = int(ref.get("m_FileID", 0))
        filename = obj.assets_file.name if not file_id else obj.assets_file.externals[file_id - 1].path.rsplit("/", 1)[-1]
        return objects.get((filename, ref["m_PathID"]))

    def source(obj):
        return "%s:%s" % (obj.assets_file.name, obj.path_id)

    def pointer(obj, ref):
        other = resolve(obj, ref)
        if other is None:
            return None
        return dict(source=source(other), type=other.type.name, name=tree(other).get("m_Name", ""))

    altars = {}
    for asset in selected:
        root = None
        embedded = asset["address"] == "LevelMap_1010901"
        for obj in env.objects:
            if embedded and obj.type.name == "GameObject" and tree(obj).get("m_Name") == "EnvUnit_Interactable_OldDayAltar":
                root = obj
                break
            if obj.type.name != "AssetBundle":
                continue
            for path, entry in tree(obj).get("m_Container", []):
                if path.lower() == asset["path"].lower():
                    root = resolve(obj, entry["asset"])
        assert root is not None, asset["address"]
        nodes = []

        def walk(go, path):
            data = tree(go)
            path = path + [data["m_Name"]]
            components = [resolve(go, entry.get("component", entry)) for entry in data.get("m_Component", [])]
            components = [obj for obj in components if obj is not None]
            transform = next(obj for obj in components if obj.type.name in ["Transform", "RectTransform"])
            tr = tree(transform)
            record = dict(name=data["m_Name"], path="/".join(path), source=source(go), position=tr["m_LocalPosition"], rotation=tr["m_LocalRotation"], scale=tr["m_LocalScale"], active=bool(data.get("m_IsActive", True)), renderers=[])
            for component in components:
                fields = tree(component)
                if component.type.name == "SpriteRenderer":
                    sprite = resolve(component, fields.get("m_Sprite"))
                    assert sprite is not None
                    sprite_data = tree(sprite)
                    texture_name = "spirit_altar_egg.png" if sprite_data["m_Name"] == "SpritesAltar" else "altar_pickup_" + sprite_data["m_Name"] + ".png"
                    texture_path = output.parent / texture_name
                    image = sprite.read().image
                    rect = sprite_data["m_Rect"]
                    canvas_size = round(rect["width"]), round(rect["height"])
                    if image.size != canvas_size:
                        offset = sprite_data["m_RD"]["textureRectOffset"]
                        canvas = Image.new("RGBA", canvas_size)
                        canvas.paste(image, (round(offset["x"]), canvas_size[1] - round(offset["y"]) - image.height))
                        image = canvas
                    image.save(texture_path)
                    record["renderers"].append(dict(type="SpriteRenderer", source=source(component), sprite=pointer(component, fields.get("m_Sprite")), color=fields.get("m_Color"), enabled=fields.get("m_Enabled"), pixels_per_unit=sprite_data.get("m_PixelsToUnits", 100), rect=sprite_data.get("m_Rect"), pivot=sprite_data.get("m_Pivot"), texture_rect=sprite_data.get("m_RD", {}).get("textureRect"), texture_offset=sprite_data.get("m_RD", {}).get("textureRectOffset"), texture="res://" + texture_path.relative_to(ROOT).as_posix(), texture_sha256=digest(texture_path.read_bytes())))
                elif component.type.name == "MeshRenderer":
                    record["renderers"].append(dict(type="MeshRenderer", source=source(component), enabled=fields.get("m_Enabled"), materials=[pointer(component, reference) for reference in fields.get("m_Materials", [])]))
                elif component.type.name == "MeshFilter":
                    record["mesh"] = pointer(component, fields.get("m_Mesh"))
            nodes.append(record)
            for reference in tr.get("m_Children", []):
                child_transform = resolve(transform, reference)
                walk(resolve(child_transform, tree(child_transform)["m_GameObject"]), path)

        walk(root, [])
        address = "EnvUnit_Interactable_OldDayAltar" if embedded else asset["address"]
        altars[address] = dict(source_asset=asset["path"], bundle=bundles[asset["bundle"]], root_source=source(root), nodes=nodes)
    result = dict(apk_sha256=APK_SHA, manifest=dict(member=member, sha256=digest(manifest_raw)), prefabs=altars, limitations=["Static prefab extraction; no original APK execution.", "OldDayAltar is scene embedded and has no standalone manifest prefab address."])
    evidence.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    billboards = {}
    for address, prefab in altars.items():
        sprite = next(renderer for node in prefab["nodes"] for renderer in node["renderers"] if renderer["type"] == "SpriteRenderer")
        billboards["EnvUnit_MonoData_BtnDisplayName_" + address.removeprefix("EnvUnit_Interactable_")] = sprite
    output.write_text(json.dumps(dict(apk_sha256=APK_SHA, billboards=billboards), ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(dict(catalog=str(output), evidence=str(evidence), prefabs=len(altars), billboards={key: value["sprite"]["name"] for key, value in billboards.items()})))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "assets/environment_effects/altar_catalog.json")
    parser.add_argument("--evidence", type=Path, default=ROOT / "reports/APK_ALTAR_PRESENTATION_20261027.json")
    args = parser.parse_args()
    recover(args.apk, args.output, args.evidence)
