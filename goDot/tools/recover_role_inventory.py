"""Retain inventory/warehouse source art and layout from the recovered role prefab."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = json.loads(args.source.read_text())
    digest = hashlib.file_digest(args.apk.open("rb"), "sha256").hexdigest()
    assert source["apk_sha256"] == digest
    assert source["prefab"]["address"] == "Panel_PlayerStateMenu"

    def relevant(path):
        return "/Mode_Warehouse" in path or "/Mode_Item" in path

    images = [row for row in source["images"] if relevant(row["path"])]
    names = {row["sprite"] for row in images if row.get("sprite")}
    args.output.mkdir(parents=True, exist_ok=True)
    sprites, mapping = [], {}
    for sprite in source["sprites"]:
        if sprite["name"] not in names:
            continue
        filename = Path(sprite["path"]).name
        origin = args.source.parent / filename
        assert origin.exists(), origin
        destination = args.output / filename
        shutil.copyfile(origin, destination)
        record = dict(sprite)
        record["path"] = "res://assets/ui/role_inventory/" + filename
        assert hashlib.sha256(destination.read_bytes()).hexdigest() == record["png_sha256"]
        sprites.append(record)
        mapping[record["name"]] = record["path"]

    transforms = source["transforms"]
    go_paths = {int(row["data"]["m_GameObject"]["m_PathID"]): row["path"] for row in transforms}
    controls, image_settings = [], []
    with zipfile.ZipFile(args.apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest_name))
        asset = next(row for row in assets if row["address"] == "Panel_PlayerStateMenu")
        member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
        payload = archive.read(member)
        assert hashlib.sha256(payload).hexdigest() == source["source"]["sha256"]
        environment = UnityPy.load(payload)
        for obj in environment.objects:
            if obj.type.name != "MonoBehaviour":
                continue
            tree = obj.read_typetree()
            path = go_paths.get(int(tree.get("m_GameObject", {}).get("m_PathID", 0)), "")
            if relevant(path) and "m_Sprite" in tree:
                image_settings.append({"path": path, "settings": {key: tree.get(key) for key in
                    ["m_Type", "m_PixelsPerUnitMultiplier", "m_FillCenter", "m_Color"]}})
            if relevant(path) and ("m_CellSize" in tree or "m_ConstraintCount" in tree):
                controls.append({"path": path, "path_id": str(obj.path_id), "fields": tree})
        dynamic = {row["address"]: row for row in assets if re.fullmatch(r"slotfg_rare_square_[1-5]_v2", row["address"])}
        for index in sorted({row["bundle"] for row in dynamic.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            objects = list(UnityPy.load(payload).objects)
            objects.sort(key=lambda obj: obj.type.name != "Sprite")
            for obj in objects:
                if obj.type.name not in ("Sprite", "Texture2D"):
                    continue
                name = obj.peek_name()
                if name not in dynamic:
                    continue
                destination = args.output / (name + ".png")
                if name in mapping:
                    continue
                picture = obj.read().image.convert("RGBA")
                picture.save(destination)
                resource = "res://assets/ui/role_inventory/" + destination.name
                mapping[name] = resource
                sprites.append({"name": name, "path": resource, "sprite_path_id": str(obj.path_id),
                                "source": {"member": member, "sha256": hashlib.sha256(payload).hexdigest()},
                                "source_asset": dynamic[name]["path"], "width": picture.width, "height": picture.height,
                                "png_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "runtime_lookup": True})

    layout = {key: source[key] for key in ["apk_sha256", "prefab", "source", "limit"]}
    layout.update({"images": images, "texts": [row for row in source["texts"] if relevant(row["path"])],
                   "transforms": [row for row in transforms if relevant(row["path"])],
                   "sprites": sprites, "layout_components": controls, "image_settings": image_settings,
                   "navigation_texts": [row for row in source["texts"] if "/ATPageBtnBox/" in row["path"] and row["text"]],
                   "shared_shell": "res://assets/ui/role_character/resource_map.json",
                   "observed_runtime": False})
    (args.output / "resource_map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
    (args.output / "prefab-layout.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"sprites": len(sprites), "images": len(images), "layout_components": len(controls),
                      "output": str(args.output)}))


if __name__ == "__main__":
    main()
