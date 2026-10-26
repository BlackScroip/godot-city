"""Inspect map line prefabs and verify their sprites against one shipped APK."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import FILENAMES, WORLD_WIDGET_FILENAMES, package_dependencies


def inspect(apk, project, recover_lines=False):
    result = {"apk": str(apk), "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
              "evidence_type": "static packaged prefab and sprite bytes", "prefabs": []}
    with zipfile.ZipFile(apk) as archive:
        member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(member)
        assets, bundles = manifest_records(manifest)
        result["manifest"] = {"member": member, "sha256": hashlib.sha256(manifest).hexdigest()}
        for address in ("ATPanel_RegionMapSelect", "ATPanel_RoadMapSelect", "ATSlot_RoadMapNode"):
            asset = next(row for row in assets if row["address"] == address)
            direct, dependencies = package_dependencies(manifest, address)
            pending, seen = [asset["bundle"], *direct], set()
            env, primary = UnityPy.Environment(), []
            while pending:
                index = pending.pop()
                if index in seen:
                    continue
                seen.add(index)
                pending.extend(dependencies[index])
                payload = archive.read("assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle")
                loaded = env.load_file(payload)
                if index == asset["bundle"]:
                    primary = [obj for cab in loaded.files.values() if hasattr(cab, "objects")
                               for obj in cab.objects.values()]
                    primary_sha = hashlib.sha256(payload).hexdigest()

            def deref(pointer, owner):
                return PPtr(**pointer, assetsfile=owner.assets_file).deref()

            transforms = {obj.path_id: obj.read_typetree() for obj in primary
                          if obj.type.name in ("Transform", "RectTransform")}
            objects = {obj.path_id: obj.read_typetree() for obj in primary if obj.type.name == "GameObject"}
            by_object = {tree["m_GameObject"]["m_PathID"]: key for key, tree in transforms.items()}

            def hierarchy(key):
                if key not in transforms:
                    return ""
                tree = transforms[key]
                prefix = hierarchy(tree["m_Father"]["m_PathID"])
                return (prefix + "/" if prefix else "") + objects[tree["m_GameObject"]["m_PathID"]]["m_Name"]

            record = {"address": address, "asset_path": asset["path"],
                      "bundle_hash": bundles[asset["bundle"]]["hash"], "bundle_sha256": primary_sha,
                      "layout": {}, "lines": [], "sprite_checks": {}}

            def inspect_sprite(sprite_obj):
                name = sprite_obj.peek_name()
                filename = WORLD_WIDGET_FILENAMES.get(name, FILENAMES.get(name))
                if not filename or not filename.startswith(("path_", "world_path_", "arrow_")):
                    return
                if filename in record["sprite_checks"]:
                    return
                picture = sprite_obj.read().image.convert("RGBA")
                encoded = io.BytesIO()
                picture.save(encoded, format="PNG")
                local = project / "assets/ui/route" / (filename + ".png")
                recovered = project / "assets/ui/route/connections" / (filename + ".png")
                if recover_lines:
                    recovered.parent.mkdir(parents=True, exist_ok=True)
                    recovered.write_bytes(encoded.getvalue())
                digest = hashlib.sha256(encoded.getvalue()).hexdigest()
                record["sprite_checks"][filename] = {"apk_png_sha256": digest,
                    "matches_local": local.exists() and hashlib.sha256(local.read_bytes()).hexdigest() == digest,
                    "recovered_path": "res://assets/ui/route/connections/" + filename + ".png",
                    "matches_recovered": recovered.exists() and hashlib.sha256(recovered.read_bytes()).hexdigest() == digest,
                    "size": list(picture.size), "alpha_bounds": picture.getchannel("A").getbbox()}

            for obj in env.objects:
                if obj.type.name == "SpriteAtlas" and obj.peek_name() == "SpriteAtlas_RoadMapSelect":
                    for pointer in obj.read().m_PackedSprites:
                        inspect_sprite(pointer.deref())
            for obj in primary:
                if obj.type.name != "MonoBehaviour":
                    continue
                tree = obj.read_typetree()
                if "mColumnNodeSpace" in tree:
                    record["layout"] = {key: tree[key] for key in (
                        "mColumnNodeSpace", "mLineNodeSpace", "mFirtNodeInitPos", "mMapMargin", "mGroupSize") if key in tree}
                key = by_object.get(tree["m_GameObject"]["m_PathID"])
                path = hierarchy(key)
                prefix = (address + "/Container_Prefab/ATSlot_RegionNode/Box_NodeConnect/"
                          if address == "ATPanel_RegionMapSelect" else address + "/Box_NodeConnect/")
                pointer = tree.get("m_Sprite")
                if not path.startswith(prefix) or not pointer or not pointer["m_PathID"]:
                    continue
                sprite_obj = deref(pointer, obj)
                name = sprite_obj.peek_name()
                transform = transforms[key]
                record["lines"].append({"path": path, "sprite": name, "sprite_path_id": str(sprite_obj.path_id),
                                        "color": tree.get("m_Color"), "size": transform.get("m_SizeDelta"),
                                        "position": transform.get("m_AnchoredPosition"),
                                        "scale": transform.get("m_LocalScale"), "rotation": transform.get("m_LocalRotation")})
                inspect_sprite(sprite_obj)
            record["lines"].sort(key=lambda row: row["path"])
            result["prefabs"].append(record)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--recover-lines", action="store_true")
    args = parser.parse_args()
    evidence = inspect(args.apk, Path(__file__).resolve().parents[1], args.recover_lines)
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"sha256": evidence["apk_sha256"], "prefabs": [
        {"address": row["address"], "layout": row["layout"], "lines": len(row["lines"]),
         "mismatches": [name for name, check in row["sprite_checks"].items() if not check["matches_recovered"]]}
        for row in evidence["prefabs"]]}))
