#!/usr/bin/env python3
"""Restore omitted MainCity construction meshes from exact APK renderer paths."""
import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile

import numpy as np
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler
from UnityPy.classes.PPtr import PPtr

ROOT = Path(__file__).resolve().parents[2]
CONTAINERS = {"居所Container", "冒险者协会Container", "铁匠铺Container", "遗物图鉴Container", "任务板Container", "怪物工作点Container", "篝火酒馆Container"}


def sync_metadata(target, mesh_count, byte_count):
    conversion_path = target.with_suffix(".conversion.json")
    if conversion_path.exists():
        conversion = json.loads(conversion_path.read_text())
        conversion["result"].update(meshes=mesh_count, bytes=byte_count)
        conversion["construction_geometry_report"] = "goDot/reports/camp-construction-geometry.json"
        conversion_path.write_text(json.dumps(conversion, indent=2, ensure_ascii=False) + "\n")
    catalog_path = ROOT / "goDot/assets/catalog.json"
    catalog = json.loads(catalog_path.read_text())
    catalog["environments"]["10000"].update(meshes=mesh_count, bytes=byte_count)
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--target", default=str(ROOT / "goDot/assets/environments/EnvDesignMap_MainCity.glb"))
    args = parser.parse_args()
    target = Path(args.target)
    source = target.read_bytes()
    json_length, _ = struct.unpack_from("<II", source, 12)
    data = json.loads(source[20:20 + json_length])
    binary_length, _ = struct.unpack_from("<II", source, 20 + json_length)
    binary = bytearray(source[28 + json_length:28 + json_length + binary_length])
    manifest = json.loads(Path(args.manifest).read_text())
    asset = next(x for x in manifest["assets"] if x["address"] == "EnvDesignMap_MainCity.ArtLayer.DetailContainer")
    env = UnityPy.Environment()
    bundle_evidence = []
    with zipfile.ZipFile(ROOT / "com.teamelo.dungeonchasers.apk") as archive:
        for index in [asset["bundle"], *asset["deps"]]:
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"
            raw = archive.read(member)
            env.load_file(raw)
            bundle_evidence.append({"member": member, "sha256": hashlib.sha256(raw).hexdigest()})

    nodes = data["nodes"]
    parents = {child: index for index, node in enumerate(nodes) for child in node.get("children", [])}

    def gltf_path(index):
        names = []
        while index is not None:
            node = nodes[index]
            names.append(node.get("extras", {}).get("unityName", node["name"]))
            index = parents.get(index)
        return list(reversed(names))

    targets = {}
    for index, node in enumerate(nodes):
        path = gltf_path(index)
        if "ArtLayer" not in path or "EnvFunc" not in path or not CONTAINERS.intersection(path):
            continue
        key = "/".join(path[path.index("EnvFunc"):])
        targets.setdefault(key, []).append(index)

    def unity_path(transform):
        names = []
        while transform:
            names.append(transform.m_GameObject.read().m_Name)
            transform = transform.m_Father.read() if transform.m_Father.path_id else None
        return list(reversed(names))

    def transforms_match(index, transform):
        while transform and index is not None:
            node = nodes[index]
            for field, default, source_value, axes in [
                ("translation", [0, 0, 0], transform.m_LocalPosition, "xyz"),
                ("rotation", [0, 0, 0, 1], transform.m_LocalRotation, "xyzw"),
                ("scale", [1, 1, 1], transform.m_LocalScale, "xyz"),
            ]:
                if not np.allclose(node.get(field, default), [getattr(source_value, axis) for axis in axes], atol=0.00001):
                    return False
            if transform.m_GameObject.read().m_Name == "EnvFunc":
                return True
            index = parents.get(index)
            transform = transform.m_Father.read() if transform.m_Father.path_id else None
        return False

    def accessor(values, kind, dtype="<f4", target_type=34962, bounds=False):
        values = np.asarray(values, dtype=dtype)
        while len(binary) % 4:
            binary.append(0)
        view = len(data["bufferViews"])
        raw = values.tobytes()
        data["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(raw), "target": target_type})
        binary.extend(raw)
        entry = {"bufferView": view, "componentType": 5125 if dtype == "<u4" else 5126, "count": len(values), "type": kind}
        if bounds:
            entry.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        data["accessors"].append(entry)
        return len(data["accessors"]) - 1

    material_names = {entry["name"]: i for i, entry in enumerate(data["materials"])}
    added_materials = []
    texture_cache = {}

    def material_index(pointer):
        raw = pointer.read_typetree()
        name = raw["m_Name"]
        if name in material_names:
            return material_names[name]
        saved = raw["m_SavedProperties"]
        textures = dict(saved.get("m_TexEnvs", []))
        colors = dict(saved.get("m_Colors", []))
        floats = dict(saved.get("m_Floats", []))
        color = colors.get("_BaseColor", colors.get("_Color", {}))
        rgba = [max(0.0, min(1.0, color.get(axis, 1.0))) for axis in "rgba"]
        rgba[:3] = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgba[:3]]
        pbr = {"baseColorFactor": rgba, "metallicFactor": 0.0, "roughnessFactor": 0.8}
        entry = {"name": name, "pbrMetallicRoughness": pbr, "doubleSided": True, "extras": {"apkMaterialSource": pointer.deref().assets_file.name + ":" + str(pointer.path_id), "shaderAppearance": "PBR approximation matching existing scene conversion"}}
        keywords = set(raw.get("m_ValidKeywords", [])) | set(str(raw.get("m_ShaderKeywords", "")).split())
        if floats.get("_Cutout", 0) or floats.get("_AlphaClip", 0) or floats.get("_AlphaClipEnable", 0) or floats.get("_Mode") == 1 or keywords.intersection({"CUTOUT", "_ALPHATEST_ON", "_ALPHACLIP_ON"}):
            entry.update(alphaMode="MASK", alphaCutoff=max(0.0, min(1.0, floats.get("_Cutoff", 0.5))))
        elif floats.get("_Mode") in (2, 3) or floats.get("_Surface") == 1 or rgba[3] < 1 or floats.get("_ZWrite") == 0 or keywords.intersection({"_ALPHABLEND_ON", "_ALPHAPREMULTIPLY_ON", "TRANSPARENCY"}):
            entry["alphaMode"] = "BLEND"
        for slot in ("_BaseMap", "_MainTex", "_BaseColorMap", "_Albedo"):
            binding = textures.get(slot, {})
            reference = binding.get("m_Texture", {})
            if not reference.get("m_PathID", 0):
                continue
            texture_pointer = PPtr(m_FileID=reference["m_FileID"], m_PathID=reference["m_PathID"], assetsfile=pointer.deref().assets_file)
            identity = (texture_pointer.deref().assets_file.name, texture_pointer.path_id)
            if identity not in texture_cache:
                image = texture_pointer.read().image
                stream = io.BytesIO()
                image.save(stream, format="PNG")
                encoded_image = stream.getvalue()
                while len(binary) % 4:
                    binary.append(0)
                view = len(data["bufferViews"])
                data["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(encoded_image)})
                binary.extend(encoded_image)
                data["images"].append({"name": texture_pointer.read().m_Name, "bufferView": view, "mimeType": "image/png"})
                data["textures"].append({"source": len(data["images"]) - 1})
                texture_cache[identity] = len(data["textures"]) - 1
            info = {"index": texture_cache[identity]}
            scale, offset = binding.get("m_Scale", {}), binding.get("m_Offset", {})
            sx, sy, ox, oy = scale.get("x", 1), scale.get("y", 1), offset.get("x", 0), offset.get("y", 0)
            if (sx, sy, ox, oy) != (1, 1, 0, 0):
                info["extensions"] = {"KHR_texture_transform": {"scale": [sx, sy], "offset": [ox, 1 - sy - oy]}}
                if "KHR_texture_transform" not in data.setdefault("extensionsUsed", []):
                    data["extensionsUsed"].append("KHR_texture_transform")
            pbr["baseColorTexture"] = info
            break
        data["materials"].append(entry)
        material_names[name] = len(data["materials"]) - 1
        added_materials.append({"name": name, "source": entry["extras"]["apkMaterialSource"], "source_properties": saved})
        return material_names[name]

    recovered, meshes, coverage = [], {}, Counter()
    equivalent_signatures, equivalent_counts = {}, Counter()
    for obj in env.objects:
        if obj.type.name != "MeshRenderer":
            continue
        renderer = obj.read()
        if not renderer.m_Enabled:
            continue
        game_object = renderer.m_GameObject.read()
        components = [p.component.read() for p in game_object.m_Component]
        transform = next((x for x in components if type(x).__name__ == "Transform"), None)
        mesh_filter = next((x for x in components if type(x).__name__ == "MeshFilter"), None)
        if transform is None or mesh_filter is None or not mesh_filter.m_Mesh.path_id:
            continue
        path = unity_path(transform)
        if not path or path[0] != asset["address"] or "EnvFunc" not in path:
            continue
        key = "/".join(path[path.index("EnvFunc"):])
        indices = targets.get(key, [])
        if not indices:
            continue
        if len(indices) > 1:
            indices = [i for i in indices if transforms_match(i, transform)]
        if not indices:
            raise ValueError("No exact source path and transform match: " + key)
        if len(indices) > 1:
            group = tuple(indices)
            signature = (obj.assets_file.name, mesh_filter.m_Mesh.m_FileID, mesh_filter.m_Mesh.path_id, tuple((p.m_FileID, p.path_id) for p in renderer.m_Materials))
            if group in equivalent_signatures and equivalent_signatures[group] != signature:
                raise ValueError("Overlapping same-name nodes have different source geometry: " + key)
            equivalent_signatures[group] = signature
            equivalent_counts[group] += 1
        coverage[path[path.index("EnvFunc") + 1]] += 1
        missing_nodes = [i for i in indices if "mesh" not in nodes[i]]
        if not missing_nodes:
            continue
        materials = [pointer.read() for pointer in renderer.m_Materials]
        for pointer in renderer.m_Materials:
            material_index(pointer)
        mesh_obj = mesh_filter.m_Mesh.read()
        mesh_source = str(mesh_filter.m_Mesh.assetsfile.externals[mesh_filter.m_Mesh.m_FileID - 1].path) if mesh_filter.m_Mesh.m_FileID else obj.assets_file.name
        mesh_key = (mesh_source, mesh_filter.m_Mesh.path_id, tuple(m.m_Name for m in materials))
        if mesh_key not in meshes:
            handler = MeshHandler(mesh_obj)
            handler.process()
            positions = np.asarray(handler.m_Vertices, dtype=np.float32)[:, :3]
            attributes = {"POSITION": accessor(positions, "VEC3", bounds=True)}
            if handler.m_Normals and len(handler.m_Normals) == len(positions):
                attributes["NORMAL"] = accessor(np.asarray(handler.m_Normals)[:, :3], "VEC3")
            if handler.m_Tangents and len(handler.m_Tangents) == len(positions):
                tangents = np.asarray(handler.m_Tangents).copy()
                tangents[:, 3] *= -1
                attributes["TANGENT"] = accessor(tangents, "VEC4")
            for channel in range(2):
                uv = getattr(handler, "m_UV" + str(channel), None)
                if uv and len(uv) == len(positions):
                    values = np.asarray(uv)[:, :2].copy()
                    values[:, 1] = 1 - values[:, 1]
                    attributes["TEXCOORD_" + str(channel)] = accessor(values, "VEC2")
            if handler.m_Colors and len(handler.m_Colors) == len(positions):
                colors = np.asarray(handler.m_Colors)
                attributes["COLOR_0"] = accessor(np.clip(colors, 0, 1), "VEC" + str(colors.shape[1]))
            primitives = []
            for submesh, faces in enumerate(handler.get_triangles()):
                indices = np.asarray(faces, dtype=np.uint32).reshape(-1)
                if not len(indices):
                    continue
                if indices.max() >= len(positions):
                    raise ValueError("Invalid source mesh indices " + key)
                primitives.append({"attributes": attributes.copy(), "indices": accessor(indices, "SCALAR", "<u4", 34963), "mode": 4, "material": material_names[materials[min(submesh, len(materials) - 1)].m_Name]})
            data["meshes"].append({"name": mesh_obj.m_Name, "primitives": primitives, "extras": {"apkMeshSource": mesh_source, "apkMeshPathID": str(mesh_filter.m_Mesh.path_id)}})
            meshes[mesh_key] = len(data["meshes"]) - 1
        for index in missing_nodes:
            nodes[index]["mesh"] = meshes[mesh_key]
            recovered.append({"node": nodes[index]["name"], "source_path": key, "renderer": obj.assets_file.name + ":" + str(obj.path_id), "mesh_source": mesh_source, "mesh_path_id": str(mesh_filter.m_Mesh.path_id), "materials": [m.m_Name for m in materials], "equivalent_overlapping_nodes": len(indices)})

    if any(equivalent_counts[group] != len(group) for group in equivalent_signatures):
        raise ValueError("Source overlapping-renderer multiplicity does not match imported nodes")
    if not all(coverage.get(name, 0) > 0 for name in CONTAINERS):
        raise ValueError("Incomplete source hierarchy coverage: " + str(coverage))
    if not recovered:
        sync_metadata(target, len(data["meshes"]), len(source))
        print("All source construction renderers already restored")
        return
    data["buffers"][0]["byteLength"] = len(binary)
    encoded = json.dumps(data, separators=(",", ":"), ensure_ascii=False).encode()
    encoded += b" " * (-len(encoded) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    output = struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
    output += struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
    output += struct.pack("<II", len(binary), 0x004E4942) + binary
    backup = Path("/tmp/camp-before-geometry-" + hashlib.sha256(source).hexdigest()[:12] + ".glb")
    if not backup.exists():
        backup.write_bytes(source)
    target.write_bytes(output)
    report = {"method": "Exact original renderer hierarchy paths and MeshFilter PPtr references; existing materials matched by unique original names. No source transforms changed.", "before_sha256": hashlib.sha256(source).hexdigest(), "after_sha256": hashlib.sha256(output).hexdigest(), "restored_renderers": len(recovered), "added_meshes": len(meshes), "source_renderer_counts": dict(coverage), "bundles": bundle_evidence, "renderers": recovered, "added_materials": added_materials}
    (ROOT / "goDot/reports/camp-construction-geometry.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    sync_metadata(target, len(data["meshes"]), len(output))
    print(json.dumps({"restored_renderers": len(recovered), "added_meshes": len(meshes), "bytes": len(output), "backup": str(backup)}))


if __name__ == "__main__":
    main()
