"""Recover startup UI references from the supplied APK without executing it."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


TARGETS = ("ATPanel_StartGame", "ATPanel_Load")
REA_EVIDENCE = "ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def recover(apk, project):
    output = project / "assets/ui/startup"
    evidence = project / "reports/startup"
    output.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    env, sources, primary = UnityPy.Environment(), {}, {}
    with zipfile.ZipFile(apk) as archive:
        member = next(n for n in archive.namelist() if n.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes"))
        manifest = archive.read(member)
        assets, bundles = manifest_records(manifest)
        lookup = {row["address"]: row for row in assets}
        indices, pending = set(), []
        for target in TARGETS:
            deps, bundle_deps = package_dependencies(manifest, target)
            pending.extend([lookup[target]["bundle"], *deps])
        while pending:
            index = pending.pop()
            if index not in indices:
                indices.add(index)
                pending.extend(bundle_deps[index])
        for index in sorted(indices):
            bundle = bundles[index]
            name = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            payload = archive.read(name)
            loaded = env.load_file(payload)
            objects = []
            for cab in loaded.files.values():
                if not hasattr(cab, "objects"):
                    continue
                sources[cab.name] = {"member": name, "sha256": digest(payload)}
                objects.extend(cab.objects.values())
            for target in TARGETS:
                if lookup[target]["bundle"] == index:
                    primary[target] = objects

        resources, sprites, records = {}, {}, []
        for target, objects in primary.items():
            transforms, game_objects = {}, {}
            for obj in objects:
                if obj.type.name in ("Transform", "RectTransform"):
                    tree = obj.read_typetree()
                    transforms[tree["m_GameObject"]["m_PathID"]] = tree
                elif obj.type.name == "GameObject":
                    game_objects[obj.path_id] = obj.read_typetree()

            def hierarchy(go_id):
                name = game_objects.get(go_id, {}).get("m_Name", "")
                transform = transforms.get(go_id)
                if not transform or not transform["m_Father"]["m_PathID"]:
                    return name
                parent = PPtr(**transform["m_Father"], assetsfile=objects[0].assets_file).deref()
                return hierarchy(parent.read_typetree()["m_GameObject"]["m_PathID"]) + "/" + name

            components = []
            for obj in objects:
                if obj.type.name != "MonoBehaviour":
                    continue
                tree = obj.read_typetree()
                go_id = tree.get("m_GameObject", {}).get("m_PathID", 0)
                row = {"path": hierarchy(go_id), "component_path_id": str(obj.path_id),
                       "active": game_objects.get(go_id, {}).get("m_IsActive"),
                       "rect": transforms.get(go_id), "fields": tree}
                pointer = tree.get("m_Sprite") or tree.get("m_Texture")
                if pointer and pointer["m_PathID"]:
                    asset = PPtr(**pointer, assetsfile=obj.assets_file).deref()
                    if asset.type.name in ("Sprite", "Texture2D"):
                        data = asset.read()
                        source = sources[asset.assets_file.name]
                        key = source["member"] + ":" + str(asset.path_id)
                        filename = digest(key.encode())[:16] + ".png"
                        resource = "res://assets/ui/startup/" + filename
                        if key not in sprites:
                            image = data.image.convert("RGBA")
                            image.save(output / filename)
                            sprites[key] = {"name": data.m_Name, "resource": resource,
                                            "path_id": str(asset.path_id), "source": source,
                                            "size": list(image.size),
                                            "png_sha256": digest((output / filename).read_bytes())}
                        row["art"] = sprites[key]
                        resources[row["path"]] = resource
                components.append(row)
            record = {"address": target, "source_asset": lookup[target]["path"],
                      "source": sources[objects[0].assets_file.name], "components": components}
            records.append({"address": target, "source": record["source"]})
            (evidence / (target + ".json")).write_text(
                json.dumps(record, ensure_ascii=False, indent=2) + "\n")
        provenance = {"apk": apk.name, "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
                      "rea_inventory_evidence": REA_EVIDENCE,
                      "manifest": {"member": member, "sha256": digest(manifest)},
                      "prefabs": records, "sprites": list(sprites.values()),
                      "limitations": "Static prefab references and serialized layout only; no original runtime observation."}
        (output / "provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
        (output / "resource_map.json").write_text(json.dumps(resources, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"prefabs": list(primary), "sprites": len(sprites), "output": str(output)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    recover(args.apk, args.project)
