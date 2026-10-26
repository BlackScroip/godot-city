#!/usr/bin/env python3
"""Bind APK renderer shadow modes through unique source hierarchy and local TRS."""

import argparse
from collections import Counter, defaultdict
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy


PROJECT = Path(__file__).resolve().parents[1]


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def vector(value, axes, default):
    return [float(value.get(axis, default[i])) for i, axis in enumerate(axes)]


def same_trs(left, right):
    for name in ("translation", "scale"):
        if max(abs(a - b) for a, b in zip(left[name], right[name])) > 0.0001:
            return False
    qa, qb = left["rotation"], right["rotation"]
    return min(max(abs(a - b) for a, b in zip(qa, qb)),
               max(abs(a + b) for a, b in zip(qa, qb))) <= 0.00001


def same_hierarchy_trs(left, right):
    return len(left["ancestry"]) == len(right["ancestry"]) and all(
        same_trs(a, b) for a, b in zip(left["ancestry"], right["ancestry"]))


def imported_nodes(path, scene):
    payload = path.read_bytes()
    length, kind = struct.unpack_from("<II", payload, 12)
    if kind != 0x4E4F534A:
        raise ValueError("The first GLB chunk must contain JSON")
    document = json.loads(payload[20:20 + length])
    nodes = document["nodes"]
    parents = {child: index for index, node in enumerate(nodes) for child in node.get("children", [])}

    @lru_cache(None)
    def hierarchy(index):
        node = nodes[index]
        name = node.get("extras", {}).get("unityName", node.get("name", ""))
        parent = hierarchy(parents[index]) if index in parents else ()
        return parent + (() if not parent and name == scene else (name,))

    @lru_cache(None)
    def ancestry(index):
        node = nodes[index]
        name = node.get("extras", {}).get("unityName", node.get("name", ""))
        parent = ancestry(parents[index]) if index in parents else ()
        trs = {"translation": node.get("translation", [0.0, 0.0, 0.0]),
               "rotation": node.get("rotation", [0.0, 0.0, 0.0, 1.0]),
               "scale": node.get("scale", [1.0, 1.0, 1.0])}
        return parent + (() if not parent and name == scene else (trs,))

    result = []
    for index, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        result.append({"node": node["name"], "path": hierarchy(index), "ancestry": ancestry(index),
                       "translation": node.get("translation", [0.0, 0.0, 0.0]),
                       "rotation": node.get("rotation", [0.0, 0.0, 0.0, 1.0]),
                       "scale": node.get("scale", [1.0, 1.0, 1.0])})
    return result, digest(payload)


def source_renderers(payload, scene):
    environment = UnityPy.load(payload)
    scene_file = next(obj.assets_file.name for obj in environment.objects if obj.type.name == "RenderSettings")
    objects = [obj for obj in environment.objects if obj.assets_file.name == scene_file]
    games = {obj.path_id: obj.read_typetree() for obj in objects if obj.type.name == "GameObject"}
    transforms = {obj.path_id: obj.read_typetree() for obj in objects if obj.type.name in ("Transform", "RectTransform")}
    game_transforms = {row["m_GameObject"]["m_PathID"]: key for key, row in transforms.items()}

    @lru_cache(None)
    def hierarchy(ident):
        row = transforms[ident]
        name = games[row["m_GameObject"]["m_PathID"]].get("m_Name", "")
        parent_id = row.get("m_Father", {}).get("m_PathID", 0)
        parent = hierarchy(parent_id) if parent_id in transforms else ()
        return parent + (() if not parent and name == scene else (name,))

    @lru_cache(None)
    def ancestry(ident):
        row = transforms[ident]
        name = games[row["m_GameObject"]["m_PathID"]].get("m_Name", "")
        parent_id = row.get("m_Father", {}).get("m_PathID", 0)
        parent = ancestry(parent_id) if parent_id in transforms else ()
        trs = {"translation": vector(row.get("m_LocalPosition", {}), "xyz", (0, 0, 0)),
               "rotation": vector(row.get("m_LocalRotation", {}), "xyzw", (0, 0, 0, 1)),
               "scale": vector(row.get("m_LocalScale", {}), "xyz", (1, 1, 1))}
        return parent + (() if not parent and name == scene else (trs,))

    result = []
    for obj in objects:
        if obj.type.name not in ("MeshRenderer", "SkinnedMeshRenderer"):
            continue
        row = obj.read_typetree()
        ident = game_transforms[row["m_GameObject"]["m_PathID"]]
        transform = transforms[ident]
        result.append({"renderer": str(obj.path_id), "transform": str(ident),
                       "path": hierarchy(ident), "ancestry": ancestry(ident), "mode": int(row.get("m_CastShadows", 1)),
                       "translation": vector(transform.get("m_LocalPosition", {}), "xyz", (0, 0, 0)),
                       "rotation": vector(transform.get("m_LocalRotation", {}), "xyzw", (0, 0, 0, 1)),
                       "scale": vector(transform.get("m_LocalScale", {}), "xyz", (1, 1, 1))})
    return result, scene_file


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--scenes", nargs="+")
    parser.add_argument("--project", type=Path, default=PROJECT)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    assets = {row["address"]: row for row in manifest["assets"]}
    catalog = json.loads((args.project / "assets/catalog.json").read_text())
    output = args.project / "assets/environment_recovered/render_modes"
    output.mkdir(parents=True, exist_ok=True)
    selected = args.scenes or list(catalog["environments"])
    source_hash = digest(args.apk.read_bytes())
    totals = Counter()
    with zipfile.ZipFile(args.apk) as archive:
        for ident in selected:
            entry = catalog["environments"][ident]
            scene = entry.get("scene_name", "")
            if scene not in assets:
                print(json.dumps({"scene": ident, "status": "source_asset_missing"}), flush=True)
                continue
            imported, glb_hash = imported_nodes(args.project / entry["path"].removeprefix("res://"), scene)
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][assets[scene]["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            source, serialized_file = source_renderers(payload, scene)
            by_path = defaultdict(list)
            for row in source:
                by_path[row["path"]].append(row)
            bindings, unknown = {}, []
            for row in imported:
                candidates = [other for other in by_path[row["path"]] if same_hierarchy_trs(row, other)]
                if len(candidates) == 1:
                    match = candidates[0]
                    bindings[row["node"]] = [match["mode"], match["renderer"], match["transform"]]
                else:
                    unknown.append({"node": row["node"], "path": list(row["path"]),
                                    "reason": "missing_exact_hierarchy_trs" if not candidates else "ambiguous_hierarchy_trs"})
            report = {"schema": 1, "scene": scene, "source_apk_sha256": source_hash,
                      "source_bundle": member, "source_bundle_sha256": digest(payload),
                      "source_serialized_file": serialized_file, "imported_glb_sha256": glb_hash,
                      "matching": "Unique full Unity hierarchy and local TRS at every named ancestor; position/scale tolerance 1e-4 and quaternion tolerance 1e-5, including equivalent quaternion sign. No name-only matching.",
                      "source_modes": dict(Counter(str(row["mode"]) for row in source)),
                      "imported_meshes": len(imported), "bindings": bindings, "unknown": unknown}
            (output / (ident + ".json")).write_text(json.dumps(report, ensure_ascii=False, separators=(",", ":")) + "\n")
            counts = Counter(str(row[0]) for row in bindings.values())
            totals.update({"scenes": 1, "matched": len(bindings), "unknown": len(unknown)})
            print(json.dumps({"scene": ident, "matched": len(bindings), "unknown": len(unknown), "modes": dict(counts),
                              "unknown_examples": unknown[:2]}), flush=True)
    print(json.dumps({"totals": dict(totals)}))


if __name__ == "__main__":
    main()
