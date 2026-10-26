#!/usr/bin/env python3
"""Export exact packaged region scenes and their interaction/collision sidecars.

UnityPy resolves the scene's real YooAsset dependency closure. Only objects in
the selected scene SerializedFile are instantiated; dependency prefabs are not
mistaken for scene instances. Coordinates retain Unity's numeric xyz convention
used by the existing Godot environment importer.
"""

import argparse
from collections import Counter
from functools import lru_cache
import gc
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import zipfile

import numpy as np
import UnityPy
from UnityPy.classes.PPtr import PPtr
from UnityPy.helpers.MeshHelper import MeshHandler

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "goDot/assets/environments"
COLLISIONS = ROOT / "goDot/assets/collisions"
SURFACES = ROOT / "goDot/assets/environment_recovered/region"
MANIFEST = "assets/yoo/DefaultPackage/DefaultPackage_2026-10-09-1177.bytes"
APK = "/Users/7700k/Library/Application Support/TapTap/support/android_emulator/games/716987/apk/1061664.apk"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def xyz(value, default=(0, 0, 0)):
    return [value.get(axis, default[i]) for i, axis in enumerate("xyz")]


def matrix(position, rotation, scale):
    x, y, z, w = rotation
    result = np.eye(4)
    result[:3, :3] = np.asarray([
        [1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
        [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
        [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)],
    ]) @ np.diag(scale)
    result[:3, 3] = position
    return result


class SceneExporter:
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
            self.bundle_evidence.append({"member": member, "sha256": sha(raw)})
        for index in sorted(seen):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            raw = archive.read(member)
            self.env.load_file(raw)
            self.bundle_evidence.append({"member": member, "sha256": sha(raw)})
        member = "assets/yoo/DefaultPackage/" + bundles[self.asset["bundle"]]["hash"] + ".bundle"
        primary = UnityPy.load(archive.read(member))
        self.scene_file = next(obj.assets_file.name for obj in primary.objects if obj.type.name == "RenderSettings")
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
        self.data = {"asset": {"version": "2.0", "generator": "Exact APK UnityPy region scene recovery"},
                     "scene": 0, "scenes": [{"name": name, "nodes": []}], "nodes": [],
                     "meshes": [], "materials": [], "textures": [], "images": [],
                     "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}]}

    def pointer(self, source, reference):
        return PPtr(m_FileID=reference.get("m_FileID", 0), m_PathID=reference.get("m_PathID", 0), assetsfile=source.assets_file)

    def identity(self, pointer):
        return pointer.deref().assets_file.name + ":" + str(pointer.path_id)

    def accessor(self, values, kind, dtype="<f4", target=34962, bounds=False):
        values = np.asarray(values, dtype=dtype)
        while len(self.binary) % 4:
            self.binary.append(0)
        view = len(self.data["bufferViews"])
        raw = values.tobytes()
        self.data["bufferViews"].append({"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(raw), "target": target})
        self.binary.extend(raw)
        entry = {"bufferView": view, "componentType": {"<u4": 5125, "<u2": 5123, "<f4": 5126}[dtype],
                 "count": len(values), "type": kind}
        if bounds:
            entry.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        self.data["accessors"].append(entry)
        return len(self.data["accessors"]) - 1

    def texture(self, pointer):
        identity = self.identity(pointer)
        if identity in self.texture_cache:
            return self.texture_cache[identity]
        texture = pointer.read()
        stream = io.BytesIO()
        texture.image.save(stream, format="PNG")
        raw = stream.getvalue()
        while len(self.binary) % 4:
            self.binary.append(0)
        view = len(self.data["bufferViews"])
        self.data["bufferViews"].append({"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(raw)})
        self.binary.extend(raw)
        self.data["images"].append({"name": texture.m_Name, "bufferView": view, "mimeType": "image/png",
                                    "extras": {"apkTextureSource": identity}})
        self.data["textures"].append({"source": len(self.data["images"]) - 1})
        result = len(self.data["textures"]) - 1
        self.texture_cache[identity] = result
        return result

    def external_texture(self, source, reference):
        if not reference.get("m_PathID"):
            return None
        pointer = self.pointer(source, reference)
        identity = self.identity(pointer)
        if identity not in self.external_textures:
            texture = pointer.read()
            target = SURFACES / ("texture_" + sha(identity.encode())[:20] + ".png")
            target.parent.mkdir(parents=True, exist_ok=True)
            texture.image.save(target)
            self.external_textures[identity] = {"path": "res://" + str(target.relative_to(ROOT / "goDot")),
                                                 "name": texture.m_Name, "width": texture.m_Width, "height": texture.m_Height,
                                                 "source": identity, "sha256": sha(target.read_bytes())}
        return self.external_textures[identity]

    def material(self, pointer):
        if not pointer.path_id:
            if "null" not in self.material_cache:
                self.material_cache["null"] = len(self.data["materials"])
                self.data["materials"].append({"name": "UnityNullMaterial", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1}})
            return self.material_cache["null"]
        identity = self.identity(pointer)
        if identity in self.material_cache:
            return self.material_cache[identity]
        raw = pointer.read_typetree()
        saved = raw.get("m_SavedProperties", {})
        textures, colors, floats = [dict(saved.get(field, [])) for field in ("m_TexEnvs", "m_Colors", "m_Floats")]
        color = colors.get("_BaseColor", colors.get("_Color", {}))
        rgba = [max(0., min(1., color.get(axis, 1.))) for axis in "rgba"]
        rgba[:3] = [value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4 for value in rgba[:3]]
        pbr = {"baseColorFactor": rgba, "metallicFactor": 0., "roughnessFactor": .9}
        entry = {"name": raw.get("m_Name", identity), "pbrMetallicRoughness": pbr,
                 "doubleSided": floats.get("_Cull", 0) == 0,
                 "extras": {"apkMaterialSource": identity, "shaderAppearance": "source texture and color; custom shader approximated with PBR"}}
        keywords = set(raw.get("m_ValidKeywords", [])) | set(str(raw.get("m_ShaderKeywords", "")).split())
        if floats.get("_Cutout", 0) or floats.get("_AlphaClip", 0) or floats.get("_AlphaClipEnable", 0) or floats.get("_Mode") == 1 or keywords.intersection({"CUTOUT", "_ALPHATEST_ON", "_ALPHACLIP_ON"}):
            entry.update(alphaMode="MASK", alphaCutoff=max(0., min(1., floats.get("_Cutoff", .5))))
        elif floats.get("_Mode") in (2, 3) or floats.get("_Surface") == 1 or rgba[3] < 1 or floats.get("_ZWrite") == 0 or keywords.intersection({"_ALPHABLEND_ON", "_ALPHAPREMULTIPLY_ON", "TRANSPARENCY"}):
            entry["alphaMode"] = "BLEND"
        shader = raw.get("m_Shader", {})
        shader_name = ""
        if shader.get("m_PathID"):
            try:
                shader_data = self.pointer(pointer.deref(), shader).read_typetree()
                shader_name = shader_data.get("m_ParsedForm", {}).get("m_Name", shader_data.get("m_Name", ""))
            except Exception:
                shader_name = "unreadable source shader"
        for slot in ("_BaseMap", "_MainTex", "_BaseColorMap", "_Albedo"):
            binding = textures.get(slot, {})
            reference = binding.get("m_Texture", {})
            if not reference.get("m_PathID"):
                continue
            texture_pointer = self.pointer(pointer.deref(), reference)
            info = {"index": self.texture(texture_pointer)}
            scale, offset = binding.get("m_Scale", {}), binding.get("m_Offset", {})
            sx, sy, ox, oy = scale.get("x", 1), scale.get("y", 1), offset.get("x", 0), offset.get("y", 0)
            if (sx, sy, ox, oy) != (1, 1, 0, 0):
                info["extensions"] = {"KHR_texture_transform": {"scale": [sx, sy], "offset": [ox, 1 - sy - oy]}}
                if "KHR_texture_transform" not in self.data.setdefault("extensionsUsed", []):
                    self.data["extensionsUsed"].append("KHR_texture_transform")
            pbr["baseColorTexture"] = info
            break
        index = len(self.data["materials"])
        self.data["materials"].append(entry)
        self.material_cache[identity] = index
        self.material_sources.append({"name": entry["name"], "source": identity, "shader": shader_name,
                                      "source_properties": saved})
        if "_T2M_Layer_Count" in floats:
            count = int(floats["_T2M_Layer_Count"])
            terrain = {"source": identity, "layer_count": count, "height_blend": floats.get("_T2M_EnableHeightBlend", 0),
                       "layers": [], "controls": []}
            for layer in range(count):
                prefix = "_T2M_Layer_" + str(layer)
                uv = [colors.get(prefix + "_uvScaleOffset", {}).get(axis, default) for axis, default in zip("rgba", [1, 1, 0, 0])]
                terrain["layers"].append({"diffuse": self.external_texture(pointer.deref(), textures.get(prefix + "_Diffuse", {}).get("m_Texture", {})),
                                           "normal": self.external_texture(pointer.deref(), textures.get(prefix + "_NormalMap", {}).get("m_Texture", {})),
                                           "unity_uv_scale_offset": uv, "godot_uv_scale_offset": [uv[0], uv[1], uv[2], 1 - uv[1] - uv[3]],
                                           "tint": [colors.get(prefix + "_ColorTint", {}).get(axis, 1) for axis in "rgba"],
                                           "normal_scale": floats.get(prefix + "_NormalScale", 1)})
            for layer in range((count + 3) // 4):
                terrain["controls"].append(self.external_texture(pointer.deref(), textures.get("_T2M_SplatMap_" + str(layer), {}).get("m_Texture", {})))
            if count > 3:
                self.unsupported["terrain_layers_above_runtime_limit"] += count - 3
            self.terrain_materials[entry["name"]] = terrain
        if shader_name == "TA/ToonWater":
            self.water_materials[entry["name"]] = {"source": identity, "colors": colors, "floats": floats}
        return index

    @lru_cache(maxsize=None)
    def world(self, transform_id):
        transform = self.transforms[transform_id]
        node = self.data["nodes"][self.nodes_by_transform[transform_id]]
        local = matrix(node["translation"], node["rotation"], node["scale"])
        parent = transform.get("m_Father", {}).get("m_PathID", 0)
        return self.world(parent) @ local if parent in self.transforms else local

    @lru_cache(maxsize=None)
    def active(self, transform_id):
        transform = self.transforms[transform_id]
        if not self.games[transform["m_GameObject"]["m_PathID"]].get("m_IsActive", True):
            return False
        parent = transform.get("m_Father", {}).get("m_PathID", 0)
        return self.active(parent) if parent in self.transforms else True

    @lru_cache(maxsize=None)
    def path(self, transform_id):
        transform = self.transforms[transform_id]
        name = self.games[transform["m_GameObject"]["m_PathID"]]["m_Name"]
        parent = transform.get("m_Father", {}).get("m_PathID", 0)
        return self.path(parent) + [name] if parent in self.transforms else [name]

    @lru_cache(maxsize=None)
    def sibling_path(self, transform_id):
        parent = self.transforms[transform_id].get("m_Father", {}).get("m_PathID", 0)
        if parent in self.transforms:
            children = [ref["m_PathID"] for ref in self.transforms[parent].get("m_Children", [])]
            return self.sibling_path(parent) + [children.index(transform_id)]
        roots = [ident for ident, transform in self.transforms.items() if transform.get("m_Father", {}).get("m_PathID", 0) not in self.transforms]
        return [roots.index(transform_id)]

    def geometry(self, pointer, renderer, transform_id):
        mesh_pointer = self.pointer(pointer, self.raw[pointer.path_id]["m_Mesh"])
        renderer_raw = self.raw[renderer.path_id]
        materials = [self.pointer(renderer, reference) for reference in renderer_raw.get("m_Materials", [])]
        material_ids = [self.material(material) for material in materials]
        batch = renderer_raw.get("m_StaticBatchInfo", {})
        skinned = "m_Bones" in renderer_raw
        key = (self.identity(mesh_pointer), tuple(material_ids), batch.get("firstSubMesh", 0), batch.get("subMeshCount", 0), skinned)
        if key not in self.mesh_cache:
            mesh = mesh_pointer.read()
            handler = MeshHandler(mesh)
            handler.process()
            positions = np.asarray(handler.m_Vertices, dtype=np.float32)[:, :3]
            if not len(positions):
                raise ValueError("empty source mesh")
            attributes = {"POSITION": self.accessor(positions, "VEC3", bounds=True)}
            if handler.m_Normals and len(handler.m_Normals) == len(positions):
                attributes["NORMAL"] = self.accessor(np.asarray(handler.m_Normals)[:, :3], "VEC3")
            if handler.m_Tangents and len(handler.m_Tangents) == len(positions):
                tangents = np.asarray(handler.m_Tangents).copy()
                tangents[:, 3] *= -1
                attributes["TANGENT"] = self.accessor(tangents, "VEC4")
            for channel in range(2):
                uv = getattr(handler, "m_UV" + str(channel), None)
                if uv and len(uv) == len(positions):
                    values = np.asarray(uv)[:, :2].copy()
                    values[:, 1] = 1 - values[:, 1]
                    attributes["TEXCOORD_" + str(channel)] = self.accessor(values, "VEC2")
            if handler.m_Colors and len(handler.m_Colors) == len(positions):
                colors = np.clip(np.asarray(handler.m_Colors), 0, 1)
                attributes["COLOR_0"] = self.accessor(colors, "VEC" + str(colors.shape[1]))
            if skinned:
                if len(handler.m_BoneIndices) != len(positions) or len(handler.m_BoneWeights) != len(positions):
                    raise ValueError("source skinned mesh has incomplete bone weights")
                attributes["JOINTS_0"] = self.accessor(handler.m_BoneIndices, "VEC4", "<u2")
                attributes["WEIGHTS_0"] = self.accessor(handler.m_BoneWeights, "VEC4")
            primitives = []
            groups = list(handler.get_triangles())
            first, count = int(batch.get("firstSubMesh", 0)), int(batch.get("subMeshCount", 0))
            groups = groups[first:first + count] if count else groups
            used_vertices = []
            for submesh, faces in enumerate(groups):
                indices = np.asarray(faces, dtype=np.uint32).reshape(-1)
                if not len(indices):
                    continue
                if indices.max() >= len(positions):
                    raise ValueError("source mesh index outside vertex array")
                primitive = {"attributes": attributes.copy(), "indices": self.accessor(indices, "SCALAR", "<u4", 34963), "mode": 4}
                if material_ids:
                    primitive["material"] = material_ids[min(submesh, len(material_ids) - 1)]
                primitives.append(primitive)
                used_vertices.append(positions[indices])
            if not primitives:
                raise ValueError("source mesh has no triangles")
            self.data["meshes"].append({"name": mesh.m_Name, "primitives": primitives,
                                        "extras": {"apkMeshSource": self.identity(mesh_pointer)}})
            self.mesh_cache[key] = (len(self.data["meshes"]) - 1, np.concatenate(used_vertices), mesh_pointer.read_typetree().get("m_BindPose", []))
        mesh_index, positions, bindposes = self.mesh_cache[key]
        node = self.data["nodes"][self.nodes_by_transform[transform_id]]
        node["mesh"] = mesh_index
        if skinned:
            joints = [self.nodes_by_transform.get(reference.get("m_PathID", 0)) for reference in renderer_raw["m_Bones"]]
            if None in joints or len(joints) != len(bindposes):
                raise ValueError("source skin joint references outside scene or mismatched bind poses")
            matrices = [[pose["e" + str(row) + str(column)] for column in range(4) for row in range(4)] for pose in bindposes]
            skin = {"joints": joints, "inverseBindMatrices": self.accessor(matrices, "MAT4")}
            root_bone = self.nodes_by_transform.get(renderer_raw.get("m_RootBone", {}).get("m_PathID", 0))
            if root_bone is not None:
                skin["skeleton"] = root_bone
            self.data.setdefault("skins", []).append(skin)
            node["skin"] = len(self.data["skins"]) - 1
        points = np.column_stack((positions, np.ones(len(positions))))
        transformed = (self.world(transform_id) @ points.T).T[:, :3]
        self.bounds.append((transformed.min(axis=0), transformed.max(axis=0)))
        self.renderer_evidence.append({"path": "/".join(self.path(transform_id)), "renderer": str(renderer.path_id),
                                       "mesh": self.identity(mesh_pointer), "materials": [self.identity(p) if p.path_id else None for p in materials]})

    def collision_mesh(self, obj, raw):
        reference = raw.get("m_Mesh", {})
        if not reference.get("m_PathID"):
            return None
        pointer = self.pointer(obj, reference)
        identity = self.identity(pointer)
        target = COLLISIONS / ("apk_" + sha(identity.encode())[:20] + ".faces.json")
        if not target.exists():
            handler = MeshHandler(pointer.read())
            handler.process()
            positions = np.asarray(handler.m_Vertices, dtype=np.float32)[:, :3]
            indices = np.asarray([face for group in handler.get_triangles() for face in group], dtype=np.uint32).reshape(-1)
            if not len(indices):
                return None
            COLLISIONS.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps({"source": identity, "coordinate_space": "Unity native numeric xyz",
                                          "faces": positions[indices].reshape(-1).tolist()}, separators=(",", ":")))
        return "res://" + str(target.relative_to(ROOT / "goDot"))

    def export(self, config, apk_digest):
        for ident, transform in self.transforms.items():
            game = self.games[transform["m_GameObject"]["m_PathID"]]
            name = game.get("m_Name", "Node")
            safe = re.sub(r"[^A-Za-z0-9_]+", "_", name).strip("_") or "Node"
            self.nodes_by_transform[ident] = len(self.data["nodes"])
            self.data["nodes"].append({"name": safe + "__u" + str(ident).replace("-", "n"),
                                       "translation": xyz(transform.get("m_LocalPosition", {})),
                                       "rotation": [transform.get("m_LocalRotation", {}).get(axis, 1 if axis == "w" else 0) for axis in "xyzw"],
                                       "scale": xyz(transform.get("m_LocalScale", {}), (1, 1, 1)),
                                       "extras": {"unityFileID": str(ident), "unityGameObjectID": str(transform["m_GameObject"]["m_PathID"]),
                                                  "unityName": name, "unityActive": bool(game.get("m_IsActive", True))}})
        for ident, transform in self.transforms.items():
            parent = transform.get("m_Father", {}).get("m_PathID", 0)
            if parent in self.nodes_by_transform:
                self.data["nodes"][self.nodes_by_transform[parent]].setdefault("children", []).append(self.nodes_by_transform[ident])
            else:
                self.data["scenes"][0]["nodes"].append(self.nodes_by_transform[ident])
        renderers = {raw["m_GameObject"]["m_PathID"]: self.objects[key] for key, raw in self.raw.items() if self.objects[key].type.name == "MeshRenderer"}
        markers, semantic = [], []
        unsupported_types = {"Terrain", "TerrainCollider", "ParticleSystem", "ParticleSystemRenderer", "SpriteRenderer", "Light", "AudioSource", "Animator", "Animation"}
        for ident, obj in self.objects.items():
            raw, kind = self.raw[ident], obj.type.name
            game_id = raw.get("m_GameObject", {}).get("m_PathID")
            transform_id = self.game_transform.get(game_id)
            if transform_id is None:
                continue
            node_index = self.nodes_by_transform[transform_id]
            if kind in ("MeshFilter", "SkinnedMeshRenderer"):
                renderer = obj if kind == "SkinnedMeshRenderer" else renderers.get(game_id)
                if renderer is None or not self.active(transform_id) or not self.raw[renderer.path_id].get("m_Enabled", True) or not raw.get("m_Mesh", {}).get("m_PathID"):
                    continue
                try:
                    self.geometry(obj, renderer, transform_id)
                except Exception as error:
                    self.failures.append({"type": kind, "path": "/".join(self.path(transform_id)), "component": str(ident), "error": str(error)})
            elif kind in ("MeshCollider", "BoxCollider", "SphereCollider", "CapsuleCollider"):
                marker = {"kind": {"MeshCollider": 64, "BoxCollider": 65, "SphereCollider": 135, "CapsuleCollider": 136}[kind],
                          "fileID": str(ident), "node": node_index, "path": self.name + "/" + "/".join(self.path(transform_id)),
                          "active": self.active(transform_id), "world_matrix": self.world(transform_id).reshape(16).tolist(),
                          "properties": raw, "exported_node_name": self.data["nodes"][node_index]["name"]}
                if kind == "MeshCollider":
                    try:
                        resource = self.collision_mesh(obj, raw)
                        if resource:
                            marker["mesh_faces_path"] = resource
                    except Exception as error:
                        self.failures.append({"type": kind, "component": str(ident), "error": str(error)})
                markers.append(marker)
            elif kind == "MonoBehaviour" and raw.get("PropertyJson"):
                definition = json.loads(raw["PropertyJson"])
                data = definition.get("EnvUnitData", {})
                semantic.append({"SceneName": self.name, "ObjectName": self.games[game_id]["m_Name"],
                                 "Path": self.path(transform_id), "SiblingPath": self.sibling_path(transform_id), "SourceGameObjectId": str(game_id),
                                 "Type": definition["EnvUnitType"], "DataJson": json.dumps(data, ensure_ascii=False, separators=(",", ":")),
                                 "TriggerId": data.get("TriggerId", 0), "InitiallyActive": self.active(transform_id),
                                 "Message": "", "MessageParam": "", "node": node_index,
                                 "exported_node_name": self.data["nodes"][node_index]["name"],
                                 "world_matrix": self.world(transform_id).reshape(16).tolist(),
                                 "world_position": self.world(transform_id)[:3, 3].tolist()})
                self.bindings.append({"SceneName": self.name, "SourceGameObjectId": str(game_id), "SourceComponentId": str(ident), "ConfigId": raw.get("ResId", ""),
                                      "SpawnId": raw.get("SpawnId", 0), "CheckDisplayUnlockDataId": raw.get("CheckDisplayUnlockDataId", ""),
                                      "Type": definition["EnvUnitType"], "ConfigType": definition["EnvUnitType"], "SupportsRules": True,
                                      "OverrideJson": "{}", "SourceScene": self.asset["path"], "Path": self.path(transform_id),
                                      "SiblingPath": self.sibling_path(transform_id), "FirstTriggerDelayTime": raw.get("FirstTriggerDelayTime", 0),
                                      "TriggerIdleTime": raw.get("TriggerIdleTime", 0)})
            elif kind in unsupported_types:
                self.unsupported[kind] += 1
                if self.active(transform_id) and raw.get("m_Enabled", True):
                    self.unsupported["active_" + kind] += 1
        if self.failures:
            raise ValueError(self.name + " source conversion failures: " + json.dumps(self.failures, ensure_ascii=False))
        if not self.bounds:
            raise ValueError(self.name + " has no active source geometry")
        low = np.min([value[0] for value in self.bounds], axis=0)
        high = np.max([value[1] for value in self.bounds], axis=0)
        target = OUT / (self.name + ".glb")
        self.data["buffers"][0]["byteLength"] = len(self.binary)
        encoded = json.dumps(self.data, ensure_ascii=False, separators=(",", ":")).encode()
        encoded += b" " * (-len(encoded) % 4)
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        output = struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(self.binary))
        output += struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
        output += struct.pack("<II", len(self.binary), 0x004E4942) + self.binary
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(output)
        sidecar = {"coordinate_space": "Unity native numeric xyz", "world_matrix_layout": "row-major; transform local point by matrix times column vector",
                   "exported_node_lookup": "unique exported_node_name below imported scene root", "markers": markers, "semantic_markers": semantic}
        target.with_suffix(".markers.json").write_text(json.dumps(sidecar, ensure_ascii=False, separators=(",", ":")))
        result = {"path": "res://" + str(target.relative_to(ROOT / "goDot")), "animations": [],
                  "bounds": {"min": low.tolist(), "max": high.tolist(), "size": (high-low).tolist()},
                  "meshes": len(self.data["meshes"]), "nodes": len(self.data["nodes"]), "skins": len(self.data.get("skins", [])),
                  "unsupported": dict(self.unsupported), "bytes": len(output),
                  "source": "APK:" + self.asset["path"], "source_sha256": apk_digest,
                  "default_animations": {}, "markers": "res://" + str(target.with_suffix(".markers.json").relative_to(ROOT / "goDot")),
                  "colliders": len(markers), "scene_name": self.name,
                  "player_start": dict(zip("XYZ", map(float, config["PlayerInitPos"].split(",")))),
                  "player_rotation": dict(zip("XYZ", map(float, config["PlayerInitRotate"].split(",")))),
                  "camera_rotation": [config["CameraInitRotate_X"], config["CameraInitRotate_Y"]]}
        report = {"source_apk_sha256": apk_digest, "source_address": self.name, "source_serialized_file": self.scene_file,
                  "source_asset": self.asset, "source_env_config": config, "bundles": self.bundle_evidence, "result": result,
                  "source_object_counts": dict(Counter(obj.type.name for obj in self.objects.values())),
                  "renderers": self.renderer_evidence, "materials": self.material_sources, "interaction_bindings": self.bindings,
                  "limitations": ["Inactive source geometry omitted; inactive hierarchy and collision markers retained.",
                                  "Custom Unity shaders use source base texture/color through glTF PBR.",
                                  "Source environment skins retain exact joints, bind poses and weights; animation clips are not exported.",
                                  "Unsupported component counts are explicit; particles, sprites and TerrainData are not replaced with unrelated assets."]}
        target.with_suffix(".conversion.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return result, self.bindings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", default=APK)
    parser.add_argument("--manifest-member", default=MANIFEST)
    parser.add_argument("--config-dir", help="Optional pre-extracted EnvCfg JSON directory; otherwise read exact TextAssets from the APK")
    parser.add_argument("--scenes", nargs="+", required=True)
    parser.add_argument("--no-catalog", action="store_true")
    args = parser.parse_args()
    apk_digest = sha(Path(args.apk).read_bytes())
    results, bindings, terrains, waters, textures = {}, [], {}, {}, {}
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(args.manifest_member)
        assets, bundles = manifest_records(manifest)
        config_bundles = {}
        for name in args.scenes:
            scene = name if name.startswith("LevelMap_") else "LevelMap_" + name
            config_name = "EnvCfg_[" + scene.removeprefix("LevelMap_") + "]"
            if args.config_dir:
                config = json.loads((Path(args.config_dir) / (config_name + ".json")).read_text())
            else:
                config_asset = next(asset for asset in assets if asset["address"] == config_name)
                bundle_id = config_asset["bundle"]
                if bundle_id not in config_bundles:
                    config_env = UnityPy.load(archive.read("assets/yoo/DefaultPackage/" + bundles[bundle_id]["hash"] + ".bundle"))
                    config_bundles[bundle_id] = {obj.read_typetree()["m_Name"]: obj.read_typetree()["m_Script"]
                                                  for obj in config_env.objects if obj.type.name == "TextAsset"}
                config = json.loads(config_bundles[bundle_id][config_name])
            exporter = SceneExporter(archive, manifest, assets, bundles, scene)
            result, scene_bindings = exporter.export(config, apk_digest)
            results[scene.removeprefix("LevelMap_")] = result
            bindings.extend(scene_bindings)
            terrains.update(exporter.terrain_materials)
            waters.update(exporter.water_materials)
            textures.update(exporter.external_textures)
            print(json.dumps({"scene": scene, "meshes": result["meshes"], "bytes": result["bytes"],
                              "colliders": result["colliders"], "semantic": len(scene_bindings), "unsupported": result["unsupported"]}), flush=True)
            exporter.world.cache_clear()
            exporter.active.cache_clear()
            exporter.path.cache_clear()
            exporter.sibling_path.cache_clear()
            del exporter
            gc.collect()
    if not args.no_catalog:
        catalog_path = ROOT / "goDot/assets/catalog.json"
        catalog = json.loads(catalog_path.read_text())
        catalog["environments"].update(results)
        catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    terrain_path = ROOT / "goDot/assets/environment_recovered/terrain/materials.json"
    terrain_catalog = json.loads(terrain_path.read_text())
    terrain_catalog["materials"].update(terrains)
    terrain_path.write_text(json.dumps(terrain_catalog, ensure_ascii=False, indent=2) + "\n")
    water_path = ROOT / "goDot/assets/environment_recovered/water_materials.json"
    water_catalog = json.loads(water_path.read_text())
    water_catalog.update(waters)
    water_path.write_text(json.dumps(water_catalog, ensure_ascii=False, indent=2) + "\n")
    material_path = SURFACES / "materials.json"
    region_materials = json.loads(material_path.read_text()) if material_path.exists() else {"terrain": {}, "water": {}, "textures": {}}
    region_materials["source_apk_sha256"] = apk_digest
    region_materials["terrain"].update(terrains)
    region_materials["water"].update(waters)
    region_materials["textures"].update(textures)
    material_path.parent.mkdir(parents=True, exist_ok=True)
    material_path.write_text(json.dumps(region_materials, ensure_ascii=False, indent=2) + "\n")
    report_path = ROOT / "goDot/reports/region-environment-recovery.json"
    previous = json.loads(report_path.read_text()) if report_path.exists() else {"scenes": {}, "interaction_bindings": []}
    previous["source_apk_sha256"] = apk_digest
    previous.setdefault("baseline", {"semantic_markers": 3999, "rule_bindings": 2681,
                                      "replaced_scenes": {"LevelMap_1069101": {"semantic_markers": 13, "rule_bindings": 1}}})
    previous["scenes"].update(results)
    ids = {"LevelMap_" + key for key in results}
    previous["interaction_bindings"] = [entry for entry in previous["interaction_bindings"] if entry["SceneName"] not in ids] + bindings
    report_path.write_text(json.dumps(previous, ensure_ascii=False, indent=2) + "\n")
    marker_path = ROOT / "goDot/assets/data/markers.json"
    marker_catalog = json.loads(marker_path.read_text())
    marker_catalog["Markers"] = [marker for marker in marker_catalog["Markers"] if marker["SceneName"] not in ids]
    for name in results:
        sidecar = json.loads((OUT / ("LevelMap_" + name + ".markers.json")).read_text())
        marker_catalog["Markers"].extend({key: value for key, value in marker.items()
                                           if key not in ("node", "exported_node_name", "world_matrix", "world_position")}
                                         for marker in sidecar["semantic_markers"])
    marker_path.write_text(json.dumps(marker_catalog, ensure_ascii=False, separators=(",", ":")) + "\n")
    rules_path = ROOT / "goDot/assets/environment_rules.json"
    rules = json.loads(rules_path.read_text())
    definitions = {entry["ID"]: entry for entry in rules["Definitions"]}
    changed_bindings = []
    for binding in bindings:
        if binding["Type"] not in ("EEUT_DestoryableItem", "EEUT_TriggerTrap"):
            continue
        definition = definitions.get(str(binding["ConfigId"]), {})
        binding = dict(binding, ConfigType=definition.get("Type", ""), SupportsRules=definition.get("Type") == binding["Type"])
        changed_bindings.append(binding)
    rules["Bindings"] = [binding for binding in rules["Bindings"] if binding["SceneName"] not in ids] + changed_bindings
    rules_path.write_text(json.dumps(rules, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
