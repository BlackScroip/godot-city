"""Recover construction scrolling, selection arrows and animation evidence."""

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import zipfile

import UnityPy
from PIL import Image
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_APK = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
PREFAB = "ATPanel_MainCityDeveloper"
REA_EVIDENCE = "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323"
REA_BUNDLE = "reports/construction-apk-rea-evidence-20261027.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return "Infinity" if value > 0 else "-Infinity" if value < 0 else "NaN"
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    return value


def image_bytes(image):
    stream = io.BytesIO()
    image.convert("RGBA").save(stream, format="PNG")
    return stream.getvalue()


def quaternion_product(left, right):
    x, y, z, w = (left[key] for key in ("x", "y", "z", "w"))
    a, b, c, d = (right[key] for key in ("x", "y", "z", "w"))
    return {"x": w * a + x * d + y * c - z * b,
            "y": w * b - x * c + y * d + z * a,
            "z": w * c + x * b - y * a + z * d,
            "w": w * d - x * a - y * b - z * c}


def recover(apk, output):
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != EXPECTED_APK:
        raise ValueError("Expected the explicitly selected 1061664.apk")
    output.mkdir(parents=True, exist_ok=True)
    environment = UnityPy.Environment()
    sources, loaded_indices, objects_by_bundle = {}, set(), {}
    with zipfile.ZipFile(apk) as archive:
        manifest_member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest)

        def load_address(address):
            asset = next(row for row in assets if row["address"] == address)
            dependencies, edges = package_dependencies(manifest, address)
            pending, closure = [asset["bundle"], *dependencies], set()
            while pending:
                index = pending.pop()
                if index in closure:
                    continue
                closure.add(index)
                pending.extend(edges[index])
                if index in loaded_indices:
                    continue
                loaded_indices.add(index)
                member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
                payload = archive.read(member)
                loaded = environment.load_file(payload)
                source = {"bundle_index": index, "bundle_name": bundles[index]["name"],
                          "bundle_hash": bundles[index]["hash"], "member": member,
                          "sha256": sha(payload)}
                objects_by_bundle[index] = []
                for cab in loaded.files.values():
                    if not hasattr(cab, "objects"):
                        continue
                    sources[cab.name] = source
                    objects_by_bundle[index].extend(cab.objects.values())
            return asset, objects_by_bundle[asset["bundle"]], closure

        asset, primary, prefab_closure = load_address(PREFAB)

        def deref(pointer, owner):
            return PPtr(**pointer, assetsfile=owner.assets_file).deref()

        def location(obj):
            return {"path_id": str(obj.path_id), "cab": obj.assets_file.name,
                    "source": sources[obj.assets_file.name]}

        game_objects = {obj.path_id: obj.read_typetree() for obj in primary
                        if obj.type.name == "GameObject"}
        transforms = {obj.path_id: obj.read_typetree() for obj in primary
                      if obj.type.name in ("Transform", "RectTransform")}
        transform_by_go = {tree["m_GameObject"]["m_PathID"]: key
                           for key, tree in transforms.items()}

        def hierarchy(transform_id):
            if transform_id not in transforms:
                return ""
            tree = transforms[transform_id]
            return hierarchy(tree["m_Father"]["m_PathID"]) + "/" + game_objects[
                tree["m_GameObject"]["m_PathID"]]["m_Name"]

        def object_path(obj, tree=None):
            tree = obj.read_typetree() if tree is None else tree
            transform_id = obj.path_id if obj.type.name in ("Transform", "RectTransform") else transform_by_go.get(
                tree.get("m_GameObject", {}).get("m_PathID", obj.path_id))
            return hierarchy(transform_id)

        def rectangle(obj):
            tree = obj.read_typetree()
            if obj.type.name not in ("Transform", "RectTransform"):
                tree = transforms[transform_by_go[tree.get("m_GameObject", {}).get("m_PathID", obj.path_id)]]
            return {key: tree[key] for key in ("m_AnchorMin", "m_AnchorMax", "m_AnchoredPosition",
                    "m_SizeDelta", "m_Pivot", "m_LocalScale", "m_LocalRotation") if key in tree}

        result = {"schema": 1, "apk": str(apk.resolve()), "apk_sha256": apk_sha,
                  "evidence_type": "Static packaged Unity data; APK runtime was not executed",
                  "rea_evidence_id": REA_EVIDENCE, "rea_bundle": REA_BUNDLE,
                  "script": {"path": str(Path(__file__).resolve()), "sha256": sha(Path(__file__).read_bytes())},
                  "manifest": {"member": manifest_member, "sha256": sha(manifest)},
                  "prefab": asset, "dependency_bundle_count": len(prefab_closure),
                  "animations": {}, "scroll": {}, "sprites": [], "selection": {}, "controller": {},
                  "decorations": {}}
        existing_path = ROOT / "assets/ui/camp/developer/prefab-layout.json"
        existing_layout = json.loads(existing_path.read_text())
        existing_sprites = {row["name"]: row for row in existing_layout["sprites"]}
        existing_map = json.loads((ROOT / "assets/ui/camp/resource_map.json").read_text())
        for name, resource in existing_map.items():
            existing_sprites.setdefault(name, {"path": resource})
        sprite_entries, clip_entries = {}, {}

        def sprite_record(pointer, owner):
            obj = deref(pointer, owner)
            key = obj.assets_file.name + ":" + str(obj.path_id)
            if key in sprite_entries:
                return sprite_entries[key]
            sprite = obj.read()
            image = sprite.image.convert("RGBA")
            encoded = image_bytes(image)
            entry = {"name": sprite.m_Name, "pointer": pointer, "image_size": list(image.size),
                     "png_sha256": sha(encoded), "pixel_sha256": sha(image.tobytes()),
                     "border": obj.read_typetree().get("m_Border"), "prefab_image_paths": [], **location(obj)}
            existing = existing_sprites.get(sprite.m_Name)
            if existing:
                path = ROOT / existing["path"].removeprefix("res://")
                pixels = Image.open(path).convert("RGBA")
                entry["existing"] = {"path": existing["path"], "image_size": list(pixels.size),
                                     "png_sha256": sha(path.read_bytes()),
                                     "same_png": sha(path.read_bytes()) == entry["png_sha256"],
                                     "same_pixels": pixels.size == image.size and sha(pixels.tobytes()) == entry["pixel_sha256"]}
            filename = "arrow.png" if obj.path_id == -7962153020995228324 else sha(key.encode("utf-8"))[:16] + ".png"
            destination = output / filename
            if destination.exists() and destination.read_bytes() != encoded:
                raise ValueError("Refusing to replace a different existing " + filename)
            destination.write_bytes(encoded)
            entry["resource"] = "res://" + str(destination.relative_to(ROOT))
            sprite_entries[key] = entry
            return entry

        def animation_record(pointer, owner):
            obj = deref(pointer, owner)
            key = obj.assets_file.name + ":" + str(obj.path_id)
            if key not in clip_entries:
                tree = obj.read_typetree()
                tracks = [{"path": curve["path"], "property": curve["attribute"],
                           "keys": curve["curve"]["m_Curve"]} for curve in tree["m_FloatCurves"]]
                clip_entries[key] = {"name": tree["m_Name"], "sample_rate": tree["m_SampleRate"],
                                     "legacy": tree["m_Legacy"], "wrap_mode": tree["m_WrapMode"],
                                     "duration": max((k["time"] for track in tracks for k in track["keys"]), default=0),
                                     "float_curves": tree["m_FloatCurves"], "tracks": tracks,
                                     "other_curves": {field: tree[field] for field in (
                                         "m_PositionCurves", "m_ScaleCurves", "m_EulerCurves", "m_RotationCurves")},
                                     "events": tree.get("m_Events", []), **location(obj)}
            return clip_entries[key]

        for obj in primary:
            if obj.type.name not in ("MonoBehaviour", "Animation"):
                continue
            tree = obj.read_typetree()
            path = object_path(obj, tree)
            if "Content_DeveloperSlot" in tree:
                result["controller"] = {"path": path, "fields": tree, **location(obj)}
                result["animations"]["open"] = animation_record(tree["OpenAnimation"], obj)
                result["animations"]["close"] = animation_record(tree["CloseAnimation"], obj)
            if "m_Horizontal" in tree and "m_Content" in tree:
                result["scroll"] = {"path": path, "fields": {key: tree[key] for key in (
                    "m_Horizontal", "m_Vertical", "m_MovementType", "m_Elasticity", "m_Inertia",
                    "m_DecelerationRate", "m_ScrollSensitivity", "m_HorizontalScrollbarVisibility",
                    "m_VerticalScrollbarVisibility")}, "content_rect": rectangle(deref(tree["m_Content"], obj)),
                    "viewport_rect": rectangle(deref(tree["m_Viewport"], obj)), **location(obj)}
            if obj.type.name == "Animation" and path.endswith("/Box_Select"):
                result["animations"]["select"] = animation_record(tree["m_Animations"][0], obj)
            pointer = tree.get("m_Sprite", {})
            if not pointer.get("m_PathID"):
                continue
            entry = sprite_record(pointer, obj)
            entry["prefab_image_paths"].append({"path": path, "component_path_id": str(obj.path_id),
                                                  "pointer": pointer})
            if path.endswith(("/Box_Select/Left", "/Box_Select/Right")):
                side = path.rsplit("/", 1)[-1].lower()
                if "/Container_Prefab/Prefab_SlotGroup/" in path:
                    result["selection"][side] = {"path": path, "sprite": entry,
                                                  "rect": rectangle(obj), "image_fields": tree}
            if path.endswith("/ATTitleBox/Btn_Exit"):
                result["exit_button"] = {"path": path, "sprite": entry, "rect": rectangle(obj)}
            if path in ("/" + PREFAB + "/Wood", "/" + PREFAB + "/Hammer"):
                result["decorations"][path.rsplit("/", 1)[-1]] = {
                    "path": path, "sprite": entry, "rect": rectangle(obj),
                    "rect_transform_fields": transforms[transform_by_go[tree["m_GameObject"]["m_PathID"]]],
                    **location(obj)}

        if set(result["animations"]) != {"open", "close", "select"} or set(result["selection"]) != {"left", "right"}:
            raise ValueError("Construction animation or selection binding is missing")
        for curve in result["animations"]["open"]["other_curves"]["m_RotationCurves"]:
            name = curve["path"]
            if name not in result["decorations"]:
                continue
            base = curve["curve"]["m_Curve"][0]["value"] if name == "Wood" else {"x": 0, "y": 0, "z": 0, "w": 1}
            inverse = {key: -base[key] if key != "w" else base[key] for key in base}
            samples = []
            for key in curve["curve"]["m_Curve"]:
                value = quaternion_product(key["value"], inverse)
                angle = math.degrees(math.atan2(2 * (value["w"] * value["z"] + value["x"] * value["y"]),
                                              1 - 2 * (value["y"] ** 2 + value["z"] ** 2)))
                samples.append({"time": key["time"], "unity_z_degrees": angle,
                                "godot_screen_degrees": -angle})
            rect = result["decorations"][name]["rect"]
            result["decorations"][name]["godot_guidance"] = {
                "horizontal_flip": name == "Wood", "rotation_basis": base,
                "rotation_samples": samples,
                "pivot_offset_at_source_size": [rect["m_Pivot"]["x"] * rect["m_SizeDelta"]["x"],
                                                 (1 - rect["m_Pivot"]["y"]) * rect["m_SizeDelta"]["y"]],
                "interpretation": "Suggested 2D mapping: preserve Wood's fixed Y-axis flip with flip_h; slerp the original quaternions, remove rotation_basis on the right, then negate the resulting Z angle for downward-positive screen Y. Scale the pivot offset to the rendered rectangle."}
        config_asset, config_objects, _ = load_address("RogueConfigData")
        config_object = next(obj for obj in config_objects if obj.type.name == "TextAsset" and obj.peek_name() == "RogueConfigData")
        raw_config = config_object.read().m_Script
        buildings = json.loads(raw_config)["MainCityDevelopDataList"]
        icon_names = sorted({name for row in buildings for name in row["icon_name"].split("|") if name})
        icon_records = []
        for name in icon_names:
            icon_asset, icon_objects, _ = load_address(name)
            icon_object = next(obj for obj in icon_objects if obj.type.name == "Sprite" and obj.peek_name() == name)
            entry = sprite_record({"m_FileID": 0, "m_PathID": icon_object.path_id}, icon_object)
            icon_records.append({"name": name, "asset": icon_asset, "sprite": entry})
        result["building_icons"] = {"names": icon_names, "records": icon_records,
                                    "configuration_asset": config_asset, "configuration_source": location(config_object),
                                    "configuration_sha256": sha(raw_config.encode("utf-8")), "buildings": buildings}
        result["sprites"] = sorted(sprite_entries.values(), key=lambda row: (row["name"], row["path_id"]))
        scoped_map = {}
        duplicates = []
        for row in result["sprites"]:
            if row["name"] in scoped_map and scoped_map[row["name"]] != row["resource"]:
                duplicates.append(row["name"])
            else:
                scoped_map[row["name"]] = row["resource"]
        result["resource_map"] = "res://" + str((output / "resource_map.json").relative_to(ROOT))
        result["duplicate_sprite_names"] = sorted(set(duplicates))
        if duplicates:
            raise ValueError("Scoped name lookup needs explicit binding for: " + repr(duplicates))
        (output / "resource_map.json").write_text(json.dumps(scoped_map, ensure_ascii=False, indent=2) + "\n")
        result["sprite_consistency"] = {"existing_layout": "res://assets/ui/camp/developer/prefab-layout.json",
            "compared": sum("existing" in row for row in result["sprites"]),
            "png_mismatches": [row["name"] for row in result["sprites"] if "existing" in row and not row["existing"]["same_png"]],
            "pixel_mismatches": [row["name"] for row in result["sprites"] if "existing" in row and not row["existing"]["same_pixels"]],
            "existing_images_modified": False}

        guide_asset, guide_objects, _ = load_address("GuideData")
        guide_object = next(obj for obj in guide_objects if obj.type.name == "TextAsset" and obj.peek_name() == "GuideData")
        raw_guide = guide_object.read().m_Script
        guide = next(row for row in json.loads(raw_guide) if int(row["id"]) == 101)
        existing_guides = json.loads((ROOT / "assets/ui/settings/guides.json").read_text())
        normalized = next(row for row in existing_guides if int(row["id"]) == 101)
        expected = {"head": guide["head_text"], "body": guide["tail_text"], "image": normalized["pages"][0]["image"]}
        _, image_objects, _ = load_address(guide["middle_image_name"])
        image_object = next(obj for obj in image_objects if obj.type.name == "Sprite" and obj.peek_name() == guide["middle_image_name"])
        guide_image = image_object.read().image.convert("RGBA")
        existing_image = ROOT / expected["image"].removeprefix("res://")
        existing_pixels = Image.open(existing_image).convert("RGBA")
        result["guide"] = {"id": 101, "raw": guide, "normalized": normalized,
                           "same_title": normalized["title"] == guide["title"],
                           "same_pages": normalized["pages"] == [expected],
                           "image": {"name": guide["middle_image_name"], "existing": expected["image"],
                                     "png_sha256": sha(image_bytes(guide_image)),
                                     "existing_png_sha256": sha(existing_image.read_bytes()),
                                     "same_png": sha(image_bytes(guide_image)) == sha(existing_image.read_bytes()),
                                     "same_pixels": guide_image.size == existing_pixels.size and guide_image.tobytes() == existing_pixels.tobytes(),
                                     **location(image_object)},
                           "asset": guide_asset, "data_sha256": sha(raw_guide.encode("utf-8")),
                           **location(guide_object)}
        result["sources"] = sorted({source["member"]: source for source in sources.values()}.values(), key=lambda row: row["bundle_index"])
    result["limitations"] = ["Serialized curves and image pointers establish authored values, not observed APK playback.",
                             "Unity anchored-position Y points upward; the Godot implementation must invert that axis."]
    (output / "source.json").write_text(json.dumps(json_safe(result), ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    print(json.dumps({"output": str(output / "source.json"), "prefab_bundle_count": result["dependency_bundle_count"],
                      "animation_tracks": {key: len(value["tracks"]) for key, value in result["animations"].items()},
                      "sprites": len(result["sprites"]), "consistency": result["sprite_consistency"],
                      "guide_matches": result["guide"]["same_title"] and result["guide"]["same_pages"] and result["guide"]["image"]["same_pixels"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "assets/ui/camp/construction")
    args = parser.parse_args()
    recover(args.apk, args.output)
