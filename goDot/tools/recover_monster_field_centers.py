"""Recover a monster's authored field center from serialized APK scene objects."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--environment-id", default="1050104")
    parser.add_argument("--marker-id", type=int, default=300021)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    scene_name = "LevelMap_" + args.environment_id
    addresses = [scene_name, scene_name + ".EnvUnitLayer.EnvUnitGroupSet_NPCAndFuncItem"]
    indices = [next(asset["bundle"] for asset in manifest["assets"] if asset["address"] == address) for address in addresses]
    indices.append(next(bundle["id"] for bundle in manifest["bundles"] if bundle["name"] == "assets_[00002]resource_texture_commonassets.bundle"))
    env = UnityPy.Environment()
    sources = []
    with zipfile.ZipFile(args.apk) as archive:
        for index in indices:
            bundle = manifest["bundles"][index]
            member = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            raw = archive.read(member)
            loaded = env.load_file(raw, name=member)
            sources.append({"bundle_name": bundle["name"], "member": member, "sha256": hashlib.sha256(raw).hexdigest(), "files": list(loaded.files)})
    objects = {(obj.assets_file.name, obj.path_id): obj for obj in env.objects}
    trees = {}

    def tree(obj):
        key = (obj.assets_file.name, obj.path_id)
        if key not in trees:
            trees[key] = obj.read_typetree()
        return trees[key]

    def resolve(obj, ref):
        if not ref or not ref.get("m_PathID"):
            return None
        file_id = ref.get("m_FileID", 0)
        filename = obj.assets_file.name if not file_id else obj.assets_file.externals[file_id - 1].path.rsplit("/", 1)[-1]
        return objects.get((filename, ref["m_PathID"]))

    records = []
    for obj in env.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        data = tree(obj)
        if data.get("SpawnId") != args.marker_id:
            continue
        script = resolve(obj, data["m_Script"])
        assert script and tree(script)["m_ClassName"] == "EnvUnitMonoData", "Marker must be an actual environment unit"
        owner = resolve(obj, data["m_GameObject"])
        components = [resolve(owner, component["component"]) for component in tree(owner)["m_Component"]]
        transform = next(component for component in components if component and component.type.name == "Transform")
        chain = []
        point = [0.0, 0.0, 0.0]
        seen = set()
        while transform:
            key = (transform.assets_file.name, transform.path_id)
            assert key not in seen, "Transform ancestry must be acyclic"
            seen.add(key)
            value = tree(transform)
            position, scale, rotation = value["m_LocalPosition"], value["m_LocalScale"], value["m_LocalRotation"]
            x, y, z, w = [rotation[axis] for axis in "xyzw"]
            rotation_matrix = [
                [1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
                [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
                [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)],
            ]
            scaled = [point[index] * scale[axis] for index, axis in enumerate("xyz")]
            point = [sum(rotation_matrix[row][column] * scaled[column] for column in range(3)) + position[axis] for row, axis in enumerate("xyz")]
            transform_owner = resolve(transform, value["m_GameObject"])
            chain.append({"name": tree(transform_owner)["m_Name"], "transform_path_id": str(transform.path_id), "position": position, "rotation": rotation, "scale": scale})
            parent = value["m_Father"]
            transform = resolve(transform, parent)
            assert not parent["m_PathID"] or transform, "Missing parent cannot establish an exact world position"
        records.append({"serialized_file": obj.assets_file.name, "component_path_id": str(obj.path_id), "gameobject_path_id": str(owner.path_id), "name": tree(owner)["m_Name"], "class": tree(script)["m_ClassName"], "properties": {key: data[key] for key in ("ResId", "SpawnId", "mEnvUnitType", "PropertyJson")}, "position": point, "transform_chain_leaf_to_root": chain})
    assert len(records) == 2, "Expected the scene instance and corresponding prefab"
    assert records[0]["position"] == records[1]["position"], "Scene and prefab positions must agree"
    field = {"position": records[0]["position"], "kind": "EEUT_PosChecker", "name": records[0]["name"]}
    output = {"schema": 1, "coordinate_space": "Unity native numeric xyz; same as imported Godot environments", "environments": {args.environment_id: {str(args.marker_id): field}}}
    report = {"schema": 1, "apk": str(args.apk), "apk_sha256": hashlib.sha256(args.apk.read_bytes()).hexdigest(), "environment_id": args.environment_id, "marker_id": args.marker_id, "sources": sources, "records": records, "scope": "Static serialized scene and prefab comparison; APK runtime was not observed."}
    (args.project / "assets/data/monster_field_centers.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    (args.project / "reports/apk-monster-field-centers.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"environment_id": args.environment_id, "marker_id": args.marker_id, "position": field["position"], "corroborating_objects": len(records)}))


if __name__ == "__main__":
    main()
