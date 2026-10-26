"""Recover the five route increment icons and their shared frame from an APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


KINDS = {10000: "mineral", 70001: "gold", 70002: "magic", 13006: "partner", 13008: "spirit"}


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def recover(apk, output):
    output.mkdir(parents=True, exist_ok=True)
    env, sources, primary = UnityPy.Environment(), {}, []
    with zipfile.ZipFile(apk) as archive:
        member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(member)
        assets, bundles = manifest_records(manifest)
        asset = next(row for row in assets if row["address"] == "ATSlot_RoadMapNode")
        direct, dependencies = package_dependencies(manifest, asset["address"])
        pending, seen = [asset["bundle"], *direct], set()
        while pending:
            index = pending.pop()
            if index in seen:
                continue
            seen.add(index)
            pending.extend(dependencies[index])
            source_member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(source_member)
            loaded = env.load_file(payload)
            for cab in loaded.files.values():
                if not hasattr(cab, "objects"):
                    continue
                sources[cab.name] = {"member": source_member, "sha256": digest(payload)}
                if index == asset["bundle"]:
                    primary.extend(cab.objects.values())

    def deref(pointer, owner):
        return PPtr(**pointer, assetsfile=owner.assets_file).deref()

    def sprites(game_object):
        images = []
        children = []
        tree = game_object.read_typetree()
        for component in tree["m_Component"]:
            obj = deref(component["component"], game_object)
            if obj.type.name == "MonoBehaviour":
                pointer = obj.read_typetree().get("m_Sprite")
                if pointer and pointer["m_PathID"]:
                    images.append(deref(pointer, obj))
            elif obj.type.name == "RectTransform":
                children.extend(deref(child, obj) for child in obj.read_typetree()["m_Children"])
        for transform in children:
            images.extend(sprites(deref(transform.read_typetree()["m_GameObject"], transform)))
        return images

    controller = next(obj for obj in primary if obj.type.name == "MonoBehaviour"
                      and "stateArray_NoReachable" in obj.read_typetree())
    tree = controller.read_typetree()
    records = {}

    def export(name, sprite_obj):
        image = sprite_obj.read().image.convert("RGBA")
        path = output / (name + ".png")
        image.save(path)
        records[name] = {"sprite_name": sprite_obj.peek_name(), "sprite_path_id": str(sprite_obj.path_id),
                         "source": sources[sprite_obj.assets_file.name], "dimensions": list(image.size),
                         "png_sha256": digest(path.read_bytes()), "alpha_bounds": image.getchannel("A").getbbox()}

    for increment in tree["Increments"]:
        images = sprites(deref(increment["IconGameObject"], controller))
        if len(images) != 2:
            raise ValueError("Expected one frame and one icon for increment " + str(increment["IncrementId"]))
        export(KINDS[increment["IncrementId"]], images[1])
        if "frame" not in records:
            export("frame", images[0])
    layout = next(obj.read_typetree() for obj in primary if obj.type.name == "MonoBehaviour"
                  and "m_CellSize" in obj.read_typetree())
    provenance = {"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
                  "manifest": {"member": member, "sha256": digest(manifest)},
                  "prefab": asset["path"], "controller_path_id": str(controller.path_id),
                  "increments": [{"id": row["IncrementId"], "kind": KINDS[row["IncrementId"]]} for row in tree["Increments"]],
                  "layout": {key: layout[key] for key in ("m_CellSize", "m_Spacing", "m_StartCorner", "m_ChildAlignment")},
                  "sprites": records, "limitations": ["Static packaged images and layout only; original APK was not executed."]}
    (output / "provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"sprites": list(records), "output": str(output)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    recover(args.apk, args.output)
