#!/usr/bin/env python3
"""Recover exact selected APK enemy prefabs, skins and controller clips."""

import argparse
from collections import Counter
import gc
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zipfile
import zlib

import numpy as np
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler
from UnityPy.helpers.PackedBitVector import unpack_ints

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies
from recover_region_environments import SceneExporter, sha, xyz

ROOT = Path(__file__).resolve().parents[2]
APK = Path("/Users/7700k/Library/Application Support/TapTap/support/android_emulator/games/716987/apk/1061664.apk")
MANIFEST = "assets/yoo/DefaultPackage/DefaultPackage_2026-10-09-1177.bytes"


class ActorExporter(SceneExporter):
    def __init__(self, archive, manifest, assets, bundles, name):
        self.archive, self.name, self.bundles = archive, name, bundles
        self.asset = next(row for row in assets if row["address"].lower() == name.lower())
        direct, edges = package_dependencies(manifest, self.asset["address"])
        pending, seen = [self.asset["bundle"], *direct], set()
        while pending:
            index = pending.pop()
            if index not in seen:
                seen.add(index)
                pending.extend(edges[index])
        self.env, self.bundle_evidence = UnityPy.Environment(), []
        for index in sorted(seen):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            self.env.load_file(payload)
            self.bundle_evidence.append({"member": member, "sha256": sha(payload)})
        pointers = [pointer for path, pointer in self.env.container.items() if path.lower() == self.asset["path"].lower()]
        if len(pointers) != 1:
            raise ValueError("Expected one exact prefab container entry: " + name)
        root = pointers[0].deref()
        self.root_object = root
        self.scene_file = root.assets_file.name
        all_objects = {obj.path_id: obj for obj in self.env.objects if obj.assets_file.name == self.scene_file}
        all_raw = {key: obj.read_typetree() for key, obj in all_objects.items() if obj.type.name in ("GameObject", "Transform", "RectTransform")}
        all_transforms = {key: value for key, value in all_raw.items() if all_objects[key].type.name in ("Transform", "RectTransform")}
        root_transform = next(key for key, value in all_transforms.items() if value["m_GameObject"]["m_PathID"] == root.path_id)
        transform_ids, pending = set(), [root_transform]
        while pending:
            key = pending.pop()
            transform_ids.add(key)
            pending.extend(row["m_PathID"] for row in all_transforms[key].get("m_Children", []))
        game_ids = {all_transforms[key]["m_GameObject"]["m_PathID"] for key in transform_ids}
        component_ids = {ref["component"]["m_PathID"] for key in game_ids for ref in all_raw[key].get("m_Component", [])}
        self.objects = {key: value for key, value in all_objects.items() if key in game_ids | component_ids}
        self.raw = {key: obj.read_typetree() for key, obj in self.objects.items()}
        self.games = {key: self.raw[key] for key in game_ids}
        self.transforms = {key: self.raw[key] for key in transform_ids}
        self.game_transform = {value["m_GameObject"]["m_PathID"]: key for key, value in self.transforms.items()}
        self.root_transform = root_transform
        self.nodes_by_transform = {}
        self.mesh_cache, self.material_cache, self.texture_cache = {}, {}, {}
        self.binary, self.bounds = bytearray(), []
        self.unsupported = Counter()
        self.failures, self.material_sources, self.bindings, self.renderer_evidence = [], [], [], []
        self.external_textures, self.terrain_materials, self.water_materials = {}, {}, {}
        self.animations = []
        self.data = {"asset": {"version": "2.0", "generator": "Exact APK enemy prefab and animation recovery"},
            "scene": 0, "scenes": [{"name": name, "nodes": []}], "nodes": [], "meshes": [], "skins": [],
            "materials": [], "textures": [], "images": [], "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}]}

    def accessor(self, values, kind, dtype="<f4", target=34962, bounds=False):
        result = super().accessor(values, kind, dtype, target, bounds)
        if dtype == "<u2":
            self.data["accessors"][result]["componentType"] = 5123
        if target is None:
            self.data["bufferViews"][self.data["accessors"][result]["bufferView"]].pop("target", None)
        return result

    def geometry(self, pointer, renderer, transform_id):
        raw = self.raw[renderer.path_id]
        bones = raw.pop("m_Bones", None)
        try:
            super().geometry(pointer, renderer, transform_id)
        finally:
            if bones is not None:
                raw["m_Bones"] = bones
        if renderer.type.name != "SkinnedMeshRenderer":
            return
        mesh_pointer = self.pointer(pointer, raw["m_Mesh"])
        mesh = mesh_pointer.read()
        handler = MeshHandler(mesh)
        handler.process()
        compressed = mesh.m_CompressedMesh
        if compressed and compressed.m_Weights.m_NumItems:
            packed_weights = unpack_ints(compressed.m_Weights)
            packed_joints = unpack_ints(compressed.m_BoneIndices)
            weights, joints = [], []
            wi, ji = 0, 0
            for _ in handler.m_Vertices:
                vertex_weights, vertex_joints = [0.] * 4, [0] * 4
                total = 0
                for slot in range(3):
                    value = packed_weights[wi]
                    wi += 1
                    vertex_weights[slot], vertex_joints[slot] = value / 31., packed_joints[ji]
                    ji += 1
                    total += value
                    if total >= 31:
                        break
                else:
                    # Unity stores the fourth 5-bit weight implicitly. Some
                    # UnityPy versions subtract the integer sum from 1 here.
                    vertex_weights[3], vertex_joints[3] = (31 - total) / 31., packed_joints[ji]
                    ji += 1
                weights.append(vertex_weights)
                joints.append(vertex_joints)
            if wi != len(packed_weights) or ji != len(packed_joints):
                raise ValueError("Compressed skin weight/index payload not fully consumed")
            handler.m_BoneWeights, handler.m_BoneIndices = weights, joints
        node = self.data["nodes"][self.nodes_by_transform[transform_id]]
        if not handler.m_BoneWeights or not handler.m_BoneIndices:
            raise ValueError("Skinned source mesh has no bone weights")
        weights = np.asarray(handler.m_BoneWeights, dtype=np.float64)
        weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-20)
        weight_accessor = self.accessor(weights, "VEC4")
        joint_accessor = self.accessor(handler.m_BoneIndices, "VEC4", "<u2")
        for primitive in self.data["meshes"][node["mesh"]]["primitives"]:
            primitive["attributes"].update(WEIGHTS_0=weight_accessor, JOINTS_0=joint_accessor)
        joints = [self.nodes_by_transform.get(ref["m_PathID"]) for ref in raw.get("m_Bones", [])]
        for slot, joint in enumerate(joints):
            if joint is None:
                if np.any(weights[np.asarray(handler.m_BoneIndices) == slot] > 1e-6):
                    raise ValueError("Weighted skin joint outside source prefab")
                joints[slot] = len(self.data["nodes"])
                self.data["nodes"].append({"name": "UnusedUnityBone_" + str(slot)})
                self.data["nodes"][self.nodes_by_transform[self.root_transform]].setdefault("children", []).append(joints[slot])
                self.unsupported["source_unweighted_null_bone"] += 1
        mesh_raw = mesh_pointer.read_typetree()
        bindposes = mesh_raw["m_BindPose"]
        if len(bindposes) != len(joints):
            raise ValueError("Bone and bind pose count differs")
        matrices = [[pose["e" + str(r) + str(c)] for c in range(4) for r in range(4)] for pose in bindposes]
        skin = {"joints": joints, "inverseBindMatrices": self.accessor(matrices, "MAT4", target=None)}
        skeleton = self.nodes_by_transform.get(raw.get("m_RootBone", {}).get("m_PathID"))
        if skeleton is not None:
            skin["skeleton"] = skeleton
        self.data["skins"].append(skin)
        node["skin"] = len(self.data["skins"]) - 1

    def controllers(self):
        result = []
        for key, obj in self.objects.items():
            if obj.type.name != "Animator" or not self.raw[key].get("m_Controller", {}).get("m_PathID"):
                continue
            controller = self.pointer(obj, self.raw[key]["m_Controller"])
            result.append((key, controller, controller.read_typetree()))
        return result

    def animation_tracks(self, clip, animator_transform, avatar_paths):
        muscle = clip["m_MuscleClip"]
        packed_clip = muscle["m_Clip"].get("data", muscle["m_Clip"])
        stream, dense, constant = [packed_clip.get(key, {}) for key in ("m_StreamedClip", "m_DenseClip", "m_ConstantClip")]
        bindings = clip["m_ClipBindingConstant"]["genericBindings"]
        duration = float(muscle["m_StopTime"] - muscle.get("m_StartTime", 0))
        sample_rate = max(30., float(clip.get("m_SampleRate", 30)))
        times = np.linspace(0, duration, max(2, int(math.ceil(duration * sample_rate)) + 1))
        stream_count, dense_count = int(stream.get("curveCount", 0)), int(dense.get("m_CurveCount", 0))
        total = stream_count + dense_count + len(constant.get("data", []))
        values = np.full((len(times), total), np.nan)
        payload = struct.pack("<" + "I" * len(stream.get("data", [])), *stream.get("data", []))
        offset, curves = 0, {}
        while offset < len(payload):
            time, count = struct.unpack_from("<fi", payload, offset)
            offset += 8
            for _ in range(count):
                curve, *coefficient = struct.unpack_from("<i4f", payload, offset)
                offset += 20
                if math.isfinite(time):
                    curves.setdefault(curve, []).append((float(time), coefficient))
        for curve in range(stream_count):
            keys = curves.get(curve, [])
            if not keys:
                raise ValueError("Streamed animation curve has no keys")
            key_times = np.asarray([item[0] for item in keys])
            indexes = np.clip(np.searchsorted(key_times, times, side="right") - 1, 0, len(keys) - 1)
            for frame, key_index in enumerate(indexes):
                key_time, coefficient = keys[key_index]
                delta = max(0., times[frame] - key_time) if key_time > -1e10 else 0.
                a, b, c, d = coefficient
                values[frame, curve] = ((a * delta + b) * delta + c) * delta + d
        if dense_count:
            samples = np.asarray(dense["m_SampleArray"]).reshape((dense["m_FrameCount"], dense_count))
            source_times = dense["m_BeginTime"] + np.arange(len(samples)) / dense["m_SampleRate"]
            for curve in range(dense_count):
                values[:, stream_count + curve] = np.interp(times, source_times, samples[:, curve])
        if constant.get("data"):
            values[:, stream_count + dense_count:] = constant["data"]
        if not np.all(np.isfinite(values)):
            raise ValueError("Animation contains unresolved or non-finite source samples")
        parent_path = self.path(animator_transform)
        paths = {}
        relative_paths = {}
        for transform_id in self.transforms:
            path = self.path(transform_id)
            if path[:len(parent_path)] == parent_path:
                relative = "/".join(path[len(parent_path):])
                paths[zlib.crc32(relative.encode())] = self.nodes_by_transform[transform_id]
                relative_paths[relative] = self.nodes_by_transform[transform_id]
        # Variant prefabs rename the model root while retaining the original
        # Avatar binding paths. Resolve the remaining exact bone-name suffix.
        for source_hash, source_path in avatar_paths.items():
            if source_hash in paths or not source_path:
                continue
            parts = source_path.split("/")
            for start in range(len(parts)):
                suffix = "/".join(parts[start:])
                matches = [node for path, node in relative_paths.items() if path == suffix or path.endswith("/" + suffix)]
                if len(matches) == 1:
                    paths[source_hash] = matches[0]
                    break
        channels, index = [], 0
        for binding in bindings:
            attribute = binding["attribute"]
            components = 4 if attribute == 2 and binding.get("typeID") == 4 else 3 if attribute in (1, 3, 4) and binding.get("typeID") == 4 else 1
            samples = values[:, index:index + components].copy()
            index += components
            if binding.get("typeID") != 4 or attribute not in (1, 2, 3):
                self.unsupported["animation_non_trs_binding"] += 1
                continue
            if binding["path"] not in paths:
                self.unsupported["animation_unbound_path"] += 1
                continue
            if attribute == 2:
                samples /= np.maximum(np.linalg.norm(samples, axis=1, keepdims=True), 1e-20)
                for frame in range(1, len(samples)):
                    if np.dot(samples[frame - 1], samples[frame]) < 0:
                        samples[frame] *= -1
            channels.append((paths[binding["path"]], {1: "translation", 2: "rotation", 3: "scale"}[attribute], times, samples))
        if index != total:
            raise ValueError("Source clip binding component count differs from serialized curves")
        return duration, bool(muscle.get("m_LoopTime", False)), channels

    def recover_animations(self):
        imported = {}
        for animator_id, controller_pointer, controller in self.controllers():
            animator_transform = self.game_transform[self.raw[animator_id]["m_GameObject"]["m_PathID"]]
            avatar_paths = {}
            avatar = self.raw[animator_id].get("m_Avatar", {})
            if avatar.get("m_PathID"):
                avatar_paths = dict(self.pointer(self.objects[animator_id], avatar).read_typetree().get("m_TOS", []))
            names = dict(controller.get("m_TOS", []))
            refs = controller.get("m_AnimationClips", [])
            states = []
            for machine in controller["m_Controller"].get("m_StateMachineArray", []):
                for wrapped in machine["data"].get("m_StateConstantArray", []):
                    state = wrapped["data"]
                    clip_ids = []
                    for tree in state.get("m_BlendTreeConstantArray", []):
                        for node in tree["data"].get("m_NodeArray", []):
                            value = node["data"]
                            if not value.get("m_ChildIndices") and value.get("m_ClipID", 4294967295) < len(refs):
                                clip_ids.append(value["m_ClipID"])
                    if len(set(clip_ids)) == 1:
                        states.append((names.get(state["m_NameID"], "State"), clip_ids[0]))
                    elif clip_ids:
                        self.unsupported["animation_blendtree_state"] += 1
            for state_name, clip_id in states:
                pointer = self.pointer(controller_pointer.deref(), refs[clip_id])
                clip = pointer.read_typetree()
                duration, loop, channels = self.animation_tracks(clip, animator_transform, avatar_paths)
                if not channels:
                    self.unsupported["animation_empty_controller_state"] += 1
                    continue
                entry = imported.setdefault(state_name, {"duration": duration, "loop": loop, "tracks": [], "sources": []})
                entry["duration"] = max(entry["duration"], duration)
                entry["tracks"].extend(channels)
                entry["sources"].append({"controller": self.identity(controller_pointer), "clip": self.identity(pointer), "clip_name": clip["m_Name"], "state_name": state_name})
        for state_name, value in imported.items():
            name = re.sub(r"[^A-Za-z0-9_]+", "_", state_name).strip("_").lower()
            animation = {"name": name, "channels": [], "samplers": []}
            for node, path, times, samples in value["tracks"]:
                time_accessor = self.accessor(times, "SCALAR", target=None, bounds=True)
                output = self.accessor(samples, "VEC4" if path == "rotation" else "VEC3", target=None)
                sampler = len(animation["samplers"])
                animation["samplers"].append({"input": time_accessor, "output": output, "interpolation": "LINEAR"})
                animation["channels"].append({"sampler": sampler, "target": {"node": node, "path": path}})
            self.data.setdefault("animations", []).append(animation)
            self.animations.append({"name": name, "source_name": state_name, "duration": value["duration"],
                "loop": value["loop"], "tracks": len(value["tracks"]), "apk_sources": value["sources"],
                "sampling": "source streamed cubic coefficients and dense/constant curves resampled at source rate (minimum 30Hz)"})

    def build(self):
        for ident, transform in self.transforms.items():
            game = self.games[transform["m_GameObject"]["m_PathID"]]
            name = game.get("m_Name", "Node")
            self.nodes_by_transform[ident] = len(self.data["nodes"])
            self.data["nodes"].append({"name": name,
                "translation": xyz(transform.get("m_LocalPosition", {})),
                "rotation": [transform.get("m_LocalRotation", {}).get(axis, 1 if axis == "w" else 0) for axis in "xyzw"],
                "scale": xyz(transform.get("m_LocalScale", {}), (1, 1, 1)),
                "extras": {"unityFileID": str(ident), "unityName": name, "unityActive": bool(game.get("m_IsActive", True))}})
        for ident, transform in self.transforms.items():
            parent = transform.get("m_Father", {}).get("m_PathID", 0)
            if parent in self.nodes_by_transform:
                self.data["nodes"][self.nodes_by_transform[parent]].setdefault("children", []).append(self.nodes_by_transform[ident])
            else:
                self.data["scenes"][0]["nodes"].append(self.nodes_by_transform[ident])
        renderers = {raw["m_GameObject"]["m_PathID"]: self.objects[key] for key, raw in self.raw.items() if self.objects[key].type.name == "MeshRenderer"}
        for ident, obj in self.objects.items():
            raw = self.raw[ident]
            transform_id = self.game_transform.get(raw.get("m_GameObject", {}).get("m_PathID"))
            if transform_id is None or obj.type.name not in ("MeshFilter", "SkinnedMeshRenderer"):
                continue
            renderer = obj if obj.type.name == "SkinnedMeshRenderer" else renderers.get(raw["m_GameObject"]["m_PathID"])
            if renderer is None or not self.active(transform_id) or not self.raw[renderer.path_id].get("m_Enabled", True):
                continue
            self.geometry(obj, renderer, transform_id)
        if not self.data["meshes"]:
            raise ValueError("Exact source prefab has no exported meshes")

    def write(self, path):
        self.data["buffers"][0]["byteLength"] = len(self.binary)
        encoded = json.dumps(self.data, separators=(",", ":")).encode()
        encoded += b" " * (-len(encoded) % 4)
        binary = bytes(self.binary) + b"\0" * (-len(self.binary) % 4)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(encoded) + 8 + len(binary)) +
            struct.pack("<II", len(encoded), 0x4E4F534A) + encoded + struct.pack("<II", len(binary), 0x004E4942) + binary)


def main(args):
    actor_index = Path("/private/tmp/city-new-map-evidence/enemy-actor-index.json")
    if actor_index.exists():
        index = json.loads(actor_index.read_text())
    else:
        combat = json.loads((ROOT / "goDot/assets/data/combat.json").read_text())
        ids = json.loads((ROOT / "goDot/reports/region-combat-import.json").read_text())["enemy_ids"]
        index = {"new_enemy_ids": ids, "enemies": [{"id": row["id"], "actor": {"Prefab": row["prefab"], "ActionGroup": row["group"]}} for row in combat["enemies"] if row["id"] in ids]}
    rows = [row for row in index["enemies"] if row["id"] in (args.enemy or index["new_enemy_ids"])]
    combat = json.loads((ROOT / "goDot/assets/data/combat.json").read_text())
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(MANIFEST)
        assets, bundles = manifest_records(manifest)
        report_path = ROOT / "goDot/reports/region-actor-import.json"
        report = json.loads(report_path.read_text()) if report_path.exists() else {"schema": 1, "manifest": MANIFEST, "actors": {}}
        with args.apk.open("rb") as stream:
            report["apk_sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
        for ident, entry in report["actors"].items():
            enemy = next((enemy for enemy in combat["enemies"] if str(enemy["id"]) == ident), None)
            if entry.get("status") != "imported" or enemy is None:
                continue
            states = {item["source_name"].lower() for item in entry.get("animations", [])}
            entry["source_action_animation_gaps"] = sorted({event["anim"] for action in combat["actions"] if action["group"] == enemy["group"] for event in action["events"] if event["type"] == "EET_PlayAnim" and event["enabled"] and event.get("anim", "").lower() not in states})
        report["limitations"] = ["Original Unity custom shaders are approximated with source textures and PBR materials.",
            "Animator root-motion property curves remain outside the TRS animation import. The runtime action-motion adapter owns movement.",
            "Bindings for removed low-poly helper bones and blend-tree state mixtures are counted explicitly; source action states are verified separately."]
        for row in rows:
            name = row["actor"]["Prefab"].removesuffix(".prefab")
            if not any(asset["address"].lower() == name.lower() for asset in assets):
                report["actors"][str(row["id"])] = {"prefab": row["actor"]["Prefab"], "status": "source_prefab_absent_from_manifest"}
                report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
                print(json.dumps({"id": row["id"], "source_prefab_missing": row["actor"]["Prefab"]}), flush=True)
                continue
            exporter = ActorExporter(archive, manifest, assets, bundles, name)
            controllers = exporter.controllers()
            if args.inspect:
                folder = Path("/private/tmp/city-region-combat-evidence")
                (folder / (str(row["id"]) + ".paths.json")).write_text(json.dumps([exporter.path(key) for key in exporter.transforms], ensure_ascii=False, indent=2))
                for key, pointer, raw in controllers:
                    (folder / (str(row["id"]) + ".controller.json")).write_text(json.dumps(raw, ensure_ascii=False, indent=2))
                    avatar = exporter.raw[key].get("m_Avatar", {})
                    if avatar.get("m_PathID"):
                        avatar_tree = exporter.pointer(exporter.objects[key], avatar).read_typetree()
                        (folder / (str(row["id"]) + ".avatar.json")).write_text(json.dumps(avatar_tree, ensure_ascii=False, indent=2))
                    clips = []
                    refs = raw.get("m_AnimationClips", [])
                    for ref in refs:
                        clip = exporter.pointer(pointer.deref(), ref)
                        tree = clip.read_typetree()
                        clips.append({"source": exporter.identity(clip), "tree": tree})
                    (folder / (str(row["id"]) + ".controller-clips.json")).write_text(json.dumps(clips, ensure_ascii=False, separators=(",", ":")))
                print(json.dumps({"id": row["id"], "objects": len(exporter.objects), "controller_keys": [list(raw) for _, _, raw in controllers]}, separators=(",", ":")), flush=True)
            else:
                exporter.build()
                exporter.recover_animations()
                target = ROOT / ("goDot/assets/enemies/enemy_" + str(row["id"]) + ".glb")
                exporter.write(target)
                lower = np.min(np.asarray([pair[0] for pair in exporter.bounds]), axis=0)
                upper = np.max(np.asarray([pair[1] for pair in exporter.bounds]), axis=0)
                model_catalog_path = ROOT / "goDot/assets/catalog.json"
                catalog = json.loads(model_catalog_path.read_text())
                aliases = {entry["source_name"].lower(): entry["name"] for entry in exporter.animations}
                defaults = {key: next((aliases[alias] for alias in choices if alias in aliases), exporter.animations[0]["name"] if exporter.animations else "")
                    for key, choices in {"idle": ["idle", "idle1"], "run": ["moveforward", "move", "run"], "attack": ["attack", "attack1"]}.items()}
                catalog["enemies"][str(row["id"])] = {"id": row["id"], "path": "res://" + str(target.relative_to(ROOT / "goDot")),
                    "source": exporter.asset["path"], "source_sha256": sha(archive.read("assets/yoo/DefaultPackage/" + bundles[exporter.asset["bundle"]]["hash"] + ".bundle")),
                    "apk_manifest": MANIFEST, "bounds": {"min": lower.tolist(), "max": upper.tolist(), "size": (upper - lower).tolist()},
                    "nodes": len(exporter.data["nodes"]), "meshes": len(exporter.data["meshes"]), "skins": len(exporter.data["skins"]),
                    "bytes": target.stat().st_size, "animations": exporter.animations, "default_animations": defaults,
                    "unsupported": dict(exporter.unsupported), "bundle_sources": exporter.bundle_evidence,
                    "rendering": "Exact source mesh, skin, textures and color; Unity custom shader approximated with PBR"}
                model_catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")) + "\n")
                report["actors"][str(row["id"])] = {"prefab": row["actor"]["Prefab"], "status": "imported",
                    "model_sha256": sha(target.read_bytes()), "animations": [{key: value for key, value in item.items() if key != "apk_sources"} for item in exporter.animations],
                    "unsupported": dict(exporter.unsupported), "source_asset": exporter.asset["path"]}
                source_states = {item["source_name"].lower() for item in exporter.animations}
                report["actors"][str(row["id"])]["source_action_animation_gaps"] = sorted({event["anim"] for action in combat["actions"] if action["group"] == row["actor"]["ActionGroup"] for event in action["events"] if event["type"] == "EET_PlayAnim" and event["enabled"] and event.get("anim", "").lower() not in source_states})
                report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
                print(json.dumps({"id": row["id"], "meshes": len(exporter.data["meshes"]), "skins": len(exporter.data["skins"]), "animations": len(exporter.animations), "unsupported": dict(exporter.unsupported), "bytes": target.stat().st_size}), flush=True)
            for method in (exporter.world, exporter.active, exporter.path, exporter.sibling_path):
                method.cache_clear()
            del exporter
            gc.collect()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=APK)
    parser.add_argument("--enemy", action="append", type=int)
    parser.add_argument("--inspect", action="store_true")
    main(parser.parse_args())
