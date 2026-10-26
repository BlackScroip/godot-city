#!/usr/bin/env python3
"""Recover packaged camp decoration prefabs, dependencies and scene placement.

Reuses the exact mesh/material conversion used for region environments. Only
objects in each prefab's primary serialized file become instances. Dependency
objects provide meshes, textures and materials, never extra scene geometry.
"""

import argparse
from collections import Counter
import gc
import json
from pathlib import Path
import struct
import zipfile

import numpy as np
import UnityPy

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies
import recover_region_environments as region


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "goDot/assets/environments/camp_decorations"


class DecorationExporter(region.SceneExporter):
    def __init__(self, archive, manifest, assets, bundles, name):
        self.archive, self.name = archive, name
        self.asset = next(asset for asset in assets if asset["address"] == name)
        self.bundles = bundles
        direct, edges = package_dependencies(manifest, name)
        pending, seen = [self.asset["bundle"], *direct], set()
        while pending:
            index = pending.pop()
            if index in seen:
                continue
            seen.add(index)
            pending.extend(edges[index])
        self.env = UnityPy.Environment()
        self.bundle_evidence = []
        for member in ("assets/bin/Data/unity default resources", "assets/bin/Data/Resources/unity_builtin_extra"):
            raw = archive.read(member)
            self.env.load_file(raw, name=Path(member).name)
            self.bundle_evidence.append({"member": member, "sha256": region.sha(raw)})
        for index in sorted(seen):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            raw = archive.read(member)
            self.env.load_file(raw)
            self.bundle_evidence.append({"member": member, "sha256": region.sha(raw)})
        member = "assets/yoo/DefaultPackage/" + bundles[self.asset["bundle"]]["hash"] + ".bundle"
        primary = UnityPy.load(archive.read(member))
        root = primary.container[self.asset["path"]].deref()
        self.scene_file = root.assets_file.name
        self.objects = {obj.path_id: obj for obj in self.env.objects if obj.assets_file.name == self.scene_file}
        self.raw = {key: obj.read_typetree() for key, obj in self.objects.items()}
        self.games = {key: self.raw[key] for key, obj in self.objects.items() if obj.type.name == "GameObject"}
        self.transforms = {key: self.raw[key] for key, obj in self.objects.items() if obj.type.name in ("Transform", "RectTransform")}
        self.game_transform = {value["m_GameObject"]["m_PathID"]: key for key, value in self.transforms.items()}
        self.nodes_by_transform = {}
        self.mesh_cache, self.material_cache, self.texture_cache = {}, {}, {}
        self.binary = bytearray()
        self.bounds = []
        self.unsupported = Counter()
        self.failures, self.material_sources, self.bindings = [], [], []
        self.renderer_evidence = []
        self.external_textures, self.terrain_materials, self.water_materials = {}, {}, {}
        self.data = {"asset": {"version": "2.0", "generator": "Exact APK UnityPy camp decoration recovery"},
                     "scene": 0, "scenes": [{"name": name, "nodes": []}], "nodes": [],
                     "meshes": [], "materials": [], "textures": [], "images": [],
                     "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}]}

    def export_prefab(self, apk_digest):
        # The inherited writer also supports scene configuration; these fields
        # are removed below because prefab placement comes from its container.
        result, bindings = self.export({"PlayerInitPos": "0,0,0", "PlayerInitRotate": "0,0,0", "CameraInitRotate_X": 0, "CameraInitRotate_Y": 0}, apk_digest)
        for field in ("player_start", "player_rotation", "camera_rotation", "scene_name"):
            result.pop(field, None)
        result["prefab_name"] = self.name
        path = OUT / (self.name + ".conversion.json")
        report = json.loads(path.read_text())
        report.pop("source_env_config", None)
        report["result"] = result
        report["placement"] = "Instantiate at the exact ArtLayer decoration container matrix in index.json."
        report["limitations"].append("Decorative Unity particle systems remain explicitly unconverted; no substitute particle geometry is added.")
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return result


def read_glb(path):
    raw = path.read_bytes()
    size = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20:20 + size]), raw[28 + size:]


def geometry_bounds(model, binary, roots=None, outer=None):
    nodes = model["nodes"]
    parents = {child: i for i, node in enumerate(nodes) for child in node.get("children", [])}
    outer = np.eye(4) if outer is None else outer

    def world(i):
        node = nodes[i]
        local = region.matrix(node.get("translation", [0, 0, 0]), node.get("rotation", [0, 0, 0, 1]), node.get("scale", [1, 1, 1]))
        return world(parents[i]) @ local if i in parents else outer @ local

    def selected(i):
        return roots is None or i in roots or i in parents and selected(parents[i])

    def values(i):
        accessor = model["accessors"][i]
        view = model["bufferViews"][accessor["bufferView"]]
        dtype = {5121: "<u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[accessor["componentType"]]
        count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
        return np.ndarray((accessor["count"], count), dtype=dtype, buffer=binary,
                          offset=view.get("byteOffset", 0) + accessor.get("byteOffset", 0),
                          strides=(view.get("byteStride", np.dtype(dtype).itemsize * count), np.dtype(dtype).itemsize))

    low, high, renderers = [], [], 0
    for i, node in enumerate(nodes):
        if "mesh" not in node or not selected(i):
            continue
        renderers += 1
        for primitive in model["meshes"][node["mesh"]]["primitives"]:
            points = values(primitive["attributes"]["POSITION"])
            if "indices" in primitive:
                points = points[values(primitive["indices"]).reshape(-1)]
            placed = (world(i) @ np.column_stack((points, np.ones(len(points)))).T).T[:, :3]
            low.append(placed.min(axis=0))
            high.append(placed.max(axis=0))
    if not low:
        return None
    minimum, maximum = np.min(low, axis=0), np.max(high, axis=0)
    return {"min": minimum.tolist(), "max": maximum.tolist(), "center": ((minimum + maximum) / 2).tolist(), "renderers": renderers}


def baseline_containers(path, names):
    model, binary = read_glb(path)
    nodes = model["nodes"]
    parents = {child: i for i, node in enumerate(nodes) for child in node.get("children", [])}

    def ancestry(i):
        return (ancestry(parents[i]) if i in parents else []) + [i]

    result = {}
    for i, node in enumerate(nodes):
        name = node.get("extras", {}).get("unityName", "")
        if name not in names:
            continue
        chain = ancestry(i)
        if "ArtLayer" not in [nodes[index].get("extras", {}).get("unityName", "") for index in chain]:
            continue
        children = node.get("children", [])
        result[name] = {"exported_node_name": node["name"], "exported_node_path": [nodes[index]["name"] for index in chain],
                        "replace_children": [nodes[index]["name"] for index in children],
                        "original_world_bounds": [{"name": nodes[index].get("extras", {}).get("unityName", ""),
                                                   "exported_node_name": nodes[index]["name"],
                                                   "bounds": geometry_bounds(model, binary, {index})} for index in children]}
    return result


def scene_placements(archive, assets, bundles, slots, baseline):
    asset = next(asset for asset in assets if asset["address"] == "EnvDesignMap_MainCity")
    member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
    raw = archive.read(member)
    env = UnityPy.load(raw)
    games = {obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name == "GameObject"}
    transforms = {obj.path_id: obj.read_typetree() for obj in env.objects if obj.type.name == "Transform"}

    def chain(ident):
        parent = transforms[ident]["m_Father"]["m_PathID"]
        return (chain(parent) if parent in transforms else []) + [ident]

    def names(ident):
        return [games[transforms[key]["m_GameObject"]["m_PathID"]]["m_Name"] for key in chain(ident)]

    def world(ident):
        value = transforms[ident]
        local = region.matrix(region.xyz(value["m_LocalPosition"]), [value["m_LocalRotation"][axis] for axis in "xyzw"], region.xyz(value["m_LocalScale"], (1, 1, 1)))
        parent = value["m_Father"]["m_PathID"]
        return world(parent) @ local if parent in transforms else local

    result = {}
    for slot in slots:
        hits = [ident for ident in transforms if names(ident)[-1] == slot["container"] and "ArtLayer" in names(ident)]
        if len(hits) != 1:
            raise ValueError("Expected one ArtLayer decoration container: " + slot["container"])
        ident = hits[0]
        transform = world(ident)
        result[str(slot["slot_id"])] = dict(slot, source_transform_id=str(ident), source_path=names(ident),
                                            world_matrix=transform.reshape(16).tolist(), world_position=transform[:3, 3].tolist(),
                                            baseline=baseline.get(slot["container"], {}))
    return {"source_asset": asset, "member": member, "bundle_sha256": region.sha(raw), "slots": result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", default=region.APK)
    parser.add_argument("--manifest-member", default=region.MANIFEST)
    parser.add_argument("--names", nargs="*", help="Optional bounded prefab selection; default exports every configured decoration")
    args = parser.parse_args()
    config = json.loads((ROOT / "goDot/assets/data/RogueConfigData.json").read_text())
    apk_digest = region.sha(Path(args.apk).read_bytes())
    region.OUT = OUT
    region.SURFACES = OUT / "textures"
    region.COLLISIONS = OUT / "collisions"
    slots = config["MainCityDecorationSlotList"]
    baseline = baseline_containers(ROOT / "goDot/assets/environments/EnvDesignMap_MainCity.glb", {slot["container"] for slot in slots})
    path = OUT / "index.json"
    previous = json.loads(path.read_text()) if path.exists() else {"decorations": {}}
    if previous.get("source_apk_sha256") not in (None, apk_digest):
        raise ValueError("Existing decoration assets belong to a different APK")
    results = previous["decorations"]
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(args.manifest_member)
        assets, bundles = manifest_records(manifest)
        placement = scene_placements(archive, assets, bundles, slots, baseline)
        for row in config["MainCityDecorationDataList"]:
            if args.names and row["prefab_name"] not in args.names:
                continue
            exporter = DecorationExporter(archive, manifest, assets, bundles, row["prefab_name"])
            result = exporter.export_prefab(apk_digest)
            model, binary = read_glb(OUT / (row["prefab_name"] + ".glb"))
            container = placement["slots"][str(row["slot_id"])]
            result["world_bounds"] = geometry_bounds(model, binary, outer=np.asarray(container["world_matrix"]).reshape(4, 4))
            results[str(row["id"])] = dict(result, id=row["id"], slot_id=row["slot_id"])
            print(json.dumps({"id": row["id"], "prefab": row["prefab_name"], "meshes": result["meshes"], "bytes": result["bytes"], "unsupported": result["unsupported"]}), flush=True)
            exporter.world.cache_clear()
            exporter.active.cache_clear()
            exporter.path.cache_clear()
            exporter.sibling_path.cache_clear()
            del exporter
            gc.collect()
    OUT.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"source_apk_sha256": apk_digest, "manifest_member": args.manifest_member,
                                "coordinate_space": "Unity native numeric xyz; same convention as the existing camp GLB",
                                "world_matrix_layout": "row-major; matrix times column vector",
                                "scene_placement": placement, "decorations": results,
                                "placement_validation": "Compare actual world_bounds to each slot baseline.original_world_bounds. Authored container pivots can be over 100 units from their geometry; distance to pivot is not a valid placement test.",
                                "limitations": ["Static packaged geometry and authored placement only; no original runtime observed.",
                                                "Custom Unity shaders use source base texture/color through glTF PBR.",
                                                "Particle systems are counted in each conversion report and are not exported."]}, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"index": str(path), "decorations": len(results), "slots": len(placement["slots"])}))


if __name__ == "__main__":
    main()
