#!/usr/bin/env python3
"""Verify recovered region model buffers, skin weights and animation coverage."""

import json
from pathlib import Path
import struct

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
IDS = [11006, 13002, 22003, 23002, 110011, 110012, 110021, 110022, 110031, 110041,
       110051, 120011, 120021, 120031, 410011, 410021, 410031, 410041, 420011, 420021]
SIZES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
DTYPES = {5126: "<f4", 5125: "<u4", 5123: "<u2"}


def inspect(path):
    payload = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", payload)
    assert (magic, version, length) == (0x46546C67, 2, len(payload))
    json_length, json_kind = struct.unpack_from("<II", payload, 12)
    assert json_kind == 0x4E4F534A
    document = json.loads(payload[20:20 + json_length])
    binary_length, binary_kind = struct.unpack_from("<II", payload, 20 + json_length)
    assert binary_kind == 0x004E4942
    binary = payload[28 + json_length:]
    assert len(binary) == binary_length

    def accessor(index):
        raw = document["accessors"][index]
        view = document["bufferViews"][raw["bufferView"]]
        count = raw["count"] * SIZES[raw["type"]]
        values = np.frombuffer(binary, dtype=DTYPES[raw["componentType"]], count=count,
            offset=view.get("byteOffset", 0) + raw.get("byteOffset", 0))
        assert np.all(np.isfinite(values))
        assert values.nbytes <= view["byteLength"]
        return values.reshape((raw["count"], SIZES[raw["type"]]))

    for index in range(len(document["accessors"])):
        accessor(index)
    weighted_nodes = set()
    for node in document["nodes"]:
        if "skin" not in node:
            continue
        skin = document["skins"][node["skin"]]
        assert len(skin["joints"]) == len(accessor(skin["inverseBindMatrices"]))
        for primitive in document["meshes"][node["mesh"]]["primitives"]:
            attributes = primitive["attributes"]
            weights, joints = accessor(attributes["WEIGHTS_0"]), accessor(attributes["JOINTS_0"])
            assert np.allclose(weights.sum(axis=1), 1., atol=1e-5)
            assert int(joints.max()) < len(skin["joints"])
            assert int(accessor(primitive["indices"]).max()) < len(weights)
            weighted_nodes.update(skin["joints"][int(joint)] for joint in np.unique(joints[weights > 1e-6]))
    animated_nodes = set()
    rotations = 0
    for animation in document.get("animations", []):
        for channel in animation["channels"]:
            assert channel["target"]["node"] < len(document["nodes"])
            sampler = animation["samplers"][channel["sampler"]]
            times, values = accessor(sampler["input"]), accessor(sampler["output"])
            assert len(times) == len(values) and np.all(np.diff(times[:, 0]) > 0)
            if channel["target"]["path"] == "rotation":
                assert np.allclose(np.linalg.norm(values, axis=1), 1., atol=1e-5)
                rotations += 1
            animated_nodes.add(channel["target"]["node"])
    assert rotations > 0 and weighted_nodes & animated_nodes
    return {"meshes": len(document["meshes"]), "skins": len(document["skins"]),
            "animations": len(document.get("animations", [])), "weighted_joints": len(weighted_nodes),
            "animated_weighted_joints": len(weighted_nodes & animated_nodes),
            "static_weighted_joints": sorted(weighted_nodes - animated_nodes)}


if __name__ == "__main__":
    results = {str(ident): inspect(ROOT / ("assets/enemies/enemy_" + str(ident) + ".glb")) for ident in IDS}
    (ROOT / "reports/region-actor-validation.json").write_text(json.dumps({"schema": 1, "actors": results}, indent=2) + "\n")
    print(json.dumps({"validated": len(results), "all_weighted_joints_animated": all(not row["static_weighted_joints"] for row in results.values()),
        "animations": sum(row["animations"] for row in results.values())}))
