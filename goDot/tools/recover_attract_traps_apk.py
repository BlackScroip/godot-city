"""Recover the APK's three quicksand instances, target transforms and configuration."""

import argparse
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from inspect_camp_progression import manifest_records


def matrix(node):
    x, y, z, w = (node["m_LocalRotation"][key] for key in "xyzw")
    scale = [node["m_LocalScale"][key] for key in "xyz"]
    result = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0],
              [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0],
              [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0], [0, 0, 0, 1]]
    for row in range(3):
        for col in range(3): result[row][col] *= scale[col]
        result[row][3] = node["m_LocalPosition"]["xyz"[row]]
    return result


def multiply(first, second):
    return [[sum(first[row][i] * second[i][col] for i in range(4)) for col in range(4)] for row in range(4)]


def recover(apk, root):
    evidence = {"schema": 1, "apk": str(apk), "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
                "kind": "static packaged configuration and scene transforms", "instances": [], "definitions": [],
                "limitations": ["No APK runtime execution. Existing local scene identities are mapped by exact hierarchy path; packaged GameObject IDs are retained separately."]}
    with zipfile.ZipFile(apk) as archive:
        manifest = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest))
        assets = {asset["address"]: asset for asset in assets}

        def read_asset(address):
            asset = assets[address]
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            return UnityPy.load(payload), {"member": member, "sha256": hashlib.sha256(payload).hexdigest(), "asset_path": asset["path"]}

        for sidecar_path in sorted((root / "assets/environments").glob("*.markers.json")):
            markers = [row for row in json.loads(sidecar_path.read_text())["semantic_markers"] if row["Type"] == "EEUT_AttractTrap"]
            if not markers:
                continue
            scene = markers[0]["SceneName"]
            env, provenance = read_asset(scene)
            raw = {obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name in ["GameObject", "Transform", "MonoBehaviour"]}
            games = {obj.path_id: raw[obj.path_id] for obj in env.objects if obj.type.name == "GameObject"}
            transforms = {obj.path_id: raw[obj.path_id] for obj in env.objects if obj.type.name == "Transform"}
            game_transform = {row["m_GameObject"]["m_PathID"]: key for key, row in transforms.items()}

            @lru_cache(None)
            def hierarchy(ident):
                node = transforms[ident]
                name = games[node["m_GameObject"]["m_PathID"]]["m_Name"]
                parent = node["m_Father"]["m_PathID"]
                return (*hierarchy(parent), name) if parent in transforms else (name,)

            @lru_cache(None)
            def world(ident):
                node = transforms[ident]
                result = matrix(node)
                parent = node["m_Father"]["m_PathID"]
                return multiply(world(parent), result) if parent in transforms else result

            components = {}
            for obj in env.objects:
                if obj.type.name != "MonoBehaviour":
                    continue
                row = raw[obj.path_id]
                if "EEUT_AttractTrap" not in row.get("PropertyJson", ""):
                    continue
                game = row["m_GameObject"]["m_PathID"]
                components[hierarchy(game_transform[game])] = (obj.path_id, game, row)
            for marker in markers:
                path = tuple(marker["Path"])
                component_id, game_id, component = components[path]
                targets = [ident for ident in transforms if hierarchy(ident) == (*path, "AttractTarget")]
                if len(targets) != 1:
                    raise ValueError(f"Expected one source AttractTarget at {scene}/{path}")
                target_matrix = world(targets[0])
                source_matrix = world(game_transform[game_id])
                if max(abs(float(source_matrix[row][col]) - float(marker["world_matrix"][row * 4 + col])) for row in range(4) for col in range(4)) > 0.001:
                    raise ValueError(f"Source scene transform differs from imported marker {scene}/{path}")
                binding = {"SceneName": scene, "SourceGameObjectId": marker["SourceGameObjectId"], "SourceComponentId": str(component_id),
                           "ApkSourceGameObjectId": str(game_id), "ConfigId": str(component["ResId"]), "Type": "EEUT_AttractTrap", "ConfigType": "EEUT_AttractTrap",
                           "SupportsRules": True, "CheckDisplayUnlockDataId": component.get("CheckDisplayUnlockDataId", ""), "OverrideJson": "{}", "Path": list(path),
                           "AttractTargetPosition": [target_matrix[row][3] for row in range(3)], "AttractTargetForward": [target_matrix[row][2] for row in range(3)]}
                evidence["instances"].append({"binding": binding, "provenance": provenance, "component": component,
                                              "target_transform_id": targets[0], "target_world_matrix": [value for row in target_matrix for value in row]})
        for config_id in sorted({row["binding"]["ConfigId"] for row in evidence["instances"]}):
            address = f"EnvUnitCfg_[{config_id}]"
            env, provenance = read_asset(address)
            obj = next(obj for obj in env.objects if obj.type.name == "TextAsset" and obj.read().m_Name == address)
            source = json.loads(obj.read().m_Script)
            definition = {**source["EnvUnitData"], "Type": source["EnvUnitType"], "SourceConfig": provenance["asset_path"]}
            evidence["definitions"].append({"definition": definition, "provenance": provenance, "path_id": obj.path_id})
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sync", action="store_true")
    args = parser.parse_args()
    result = recover(args.apk, args.root)
    if args.sync:
        path = args.root / "assets/environment_rules.json"
        data = json.loads(path.read_text())
        keys = {(row["binding"]["SceneName"], row["binding"]["SourceGameObjectId"]) for row in result["instances"]}
        data["Bindings"] = [row for row in data["Bindings"] if (row["SceneName"], row["SourceGameObjectId"]) not in keys] + [row["binding"] for row in result["instances"]]
        ids = {row["definition"]["ID"] for row in result["definitions"]}
        data["Definitions"] = [row for row in data["Definitions"] if row["ID"] not in ids] + [row["definition"] for row in result["definitions"]]
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        result["sync_applied"] = True
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"instances": len(result["instances"]), "definitions": len(result["definitions"]), "synced": args.sync}))
