#!/usr/bin/env python3
"""Recover exact renderer material curves and shader evidence for skill models."""

import argparse
from collections import Counter
import gc
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile
import zlib

from import_player_lifecycle import file_digest, manifest_records
from recover_region_actors import ActorExporter
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader
from UnityPy.export.ShaderConverter import ShaderSubProgram

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "assets/yoo/DefaultPackage/DefaultPackage_2026-10-09-1177.bytes"


def source_curves(clip):
    muscle = clip["m_MuscleClip"]
    packed = muscle["m_Clip"].get("data", muscle["m_Clip"])
    stream, dense, constant = [packed.get(key, {}) for key in ("m_StreamedClip", "m_DenseClip", "m_ConstantClip")]
    curves = [{"kind": "streamed", "keys": []} for _ in range(int(stream.get("curveCount", 0)))]
    payload = struct.pack("<" + "I" * len(stream.get("data", [])), *stream.get("data", []))
    offset = 0
    while offset < len(payload):
        time, count = struct.unpack_from("<fi", payload, offset)
        offset += 8
        for _ in range(count):
            index, *coefficient = struct.unpack_from("<i4f", payload, offset)
            offset += 20
            if math.isfinite(time): curves[index]["keys"].append([time, *coefficient])
    count = int(dense.get("m_CurveCount", 0))
    for index in range(count):
        curves.append({"kind": "dense", "begin": dense["m_BeginTime"], "rate": dense["m_SampleRate"],
                       "values": dense["m_SampleArray"][index::count]})
    curves.extend({"kind": "constant", "value": value} for value in constant.get("data", []))
    return curves


def shader_programs(ex, material, expected, output):
    shader_pointer = ex.pointer(material, material.read_typetree()["m_Shader"])
    shader = shader_pointer.read_typetree()
    chunks = []
    blob = bytes(shader["compressedBlob"])
    for platform, offsets, sizes, lengths in zip(shader["platforms"], shader["offsets"], shader["compressedLengths"], shader["decompressedLengths"]):
        if platform != 9: continue
        if not isinstance(offsets, list): offsets, sizes, lengths = [offsets], [sizes], [lengths]
        chunks = [CompressionHelper.decompress_lz4(blob[o:o + s], length) for o, s, length in zip(offsets, sizes, lengths)]
    result = []
    if not chunks: return result
    for index in range(struct.unpack_from("<i", chunks[0])[0]):
        offset, size, segment = struct.unpack_from("<iii", chunks[0], 4 + index * 12)
        try:
            program = ShaderSubProgram(EndianBinaryReader(chunks[segment][offset:offset + size], endian="<"))
            code = program.m_ProgramCode.decode("utf-8")
        except (UnicodeDecodeError, ValueError, struct.error):
            continue
        if (set(program.m_Keywords) | set(program.m_LocalKeywords or [])) != expected or "#version" not in code: continue
        target = output / (material.read_typetree()["m_Name"] + ".glsl")
        target.write_text(code)
        result.append({"shader_source": ex.identity(shader_pointer), "program_index": index, "segment": segment,
                       "offset": offset, "size": size, "path": str(target.relative_to(ROOT)),
                       "sha256": hashlib.sha256(code.encode()).hexdigest()})
    return result


def recover(ex, output, shader_output):
    objects = {obj.assets_file.name + ":" + str(obj.path_id): obj for obj in ex.env.objects}
    material_records = {}
    programs = []
    for source in ex.material_sources:
        obj = objects[source["source"]]
        raw = obj.read_typetree()
        saved = raw["m_SavedProperties"]
        keywords = set(raw.get("m_ValidKeywords", [])) | set(raw.get("m_ShaderKeywords", "").split())
        maps = []
        for prop, value in saved.get("m_TexEnvs", []):
            reference = value.get("m_Texture", {})
            if not reference.get("m_PathID"): continue
            pointer = ex.pointer(obj, reference)
            texture = pointer.read()
            target = output / ("texture_" + hashlib.sha256(ex.identity(pointer).encode()).hexdigest()[:20] + ".png")
            texture.image.save(target)
            settings = pointer.read_typetree().get("m_TextureSettings", {})
            maps.append({"property": prop, "texture": "res://" + str(target.relative_to(ROOT)),
                         "scale": value["m_Scale"], "offset": value["m_Offset"],
                         "source": ex.identity(pointer), "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                         "wrap": {"x": settings.get("m_WrapU", 0), "y": settings.get("m_WrapV", 0)}})
        floats, colors = dict(saved.get("m_Floats", [])), dict(saved.get("m_Colors", []))
        material_records[source["source"]] = {"name": source["name"], "source": source["source"], "shader": source["shader"],
            "keywords": sorted(keywords), "source_floats": floats, "source_colors": colors, "textures": maps,
            "blend": "add" if floats.get("_DstMode") == 1 else "alpha"}
        programs.extend(shader_programs(ex, obj, keywords, shader_output))
    renderers = []
    for key, obj in ex.objects.items():
        if obj.type.name not in ("MeshRenderer", "SkinnedMeshRenderer"): continue
        raw = ex.raw[key]
        transform = ex.game_transform[raw["m_GameObject"]["m_PathID"]]
        if "mesh" not in ex.data["nodes"][ex.nodes_by_transform[transform]]: continue
        renderers.append({"transform_id": str(transform), "source_path": "/".join(ex.path(transform)),
            "node_name": ex.games[raw["m_GameObject"]["m_PathID"]]["m_Name"],
            "materials": [ex.identity(ex.pointer(obj, ref)) for ref in raw.get("m_Materials", [])]})
    controllers, unresolved = [], []
    for animator_id, pointer, controller in ex.controllers():
        animator_transform = ex.game_transform[ex.raw[animator_id]["m_GameObject"]["m_PathID"]]
        animator_path = ex.path(animator_transform)
        paths = {zlib.crc32("/".join(ex.path(key)[len(animator_path):]).encode()): str(key)
                 for key in ex.transforms if ex.path(key)[:len(animator_path)] == animator_path}
        strings = dict(controller.get("m_TOS", []))
        clips = {}
        default_state = ""
        for machine in controller["m_Controller"].get("m_StateMachineArray", []):
            data = machine["data"]
            states = data.get("m_StateConstantArray", [])
            for state_index, wrapped in enumerate(states):
                state = wrapped["data"]
                name = strings.get(state["m_NameID"], "State")
                clip_ids = {node["data"]["m_ClipID"] for tree in state.get("m_BlendTreeConstantArray", [])
                            for node in tree["data"].get("m_NodeArray", []) if not node["data"].get("m_ChildIndices")
                            and node["data"].get("m_ClipID", 4294967295) < len(controller["m_AnimationClips"])}
                if len(clip_ids) != 1: continue
                clip_pointer = ex.pointer(pointer.deref(), controller["m_AnimationClips"][next(iter(clip_ids))])
                clip = clip_pointer.read_typetree()
                curves, index, tracks = source_curves(clip), 0, []
                for binding in clip["m_ClipBindingConstant"]["genericBindings"]:
                    attribute = binding["attribute"]
                    count = 4 if attribute == 2 and binding["typeID"] == 4 else 3 if attribute in (1, 3, 4) and binding["typeID"] == 4 else 1
                    curve = curves[index]
                    index += count
                    if binding["typeID"] == 4: continue
                    reason = "animator_root_motion" if binding["typeID"] == 95 else "unsupported_component"
                    if binding.get("customType") == 22:
                        renderer = next((r for r in renderers if r["transform_id"] == paths.get(binding["path"])), None)
                        reason = "unbound_renderer"
                        if renderer:
                            matches = []
                            for source_id in renderer["materials"]:
                                source = material_records.get(source_id, {})
                                for field in ("source_floats", "source_colors"):
                                    for prop in source.get(field, {}):
                                        if zlib.crc32(prop.encode()) & 0x0fffffff == attribute & 0x0fffffff:
                                            matches.append((prop, field))
                                for tex in source.get("textures", []):
                                    if zlib.crc32((tex["property"] + "_ST").encode()) & 0x0fffffff == attribute & 0x0fffffff:
                                        matches.append((tex["property"] + "_ST", "texture_st"))
                            matches = list(set(matches))
                            reason = "unknown_material_property" if not matches else "ambiguous_material_property"
                            if len(matches) == 1:
                                prop, field = matches[0]
                                component = -1 if attribute & 0x80000000 else (attribute >> 28) & 3
                                tracks.append({"renderer": renderer["transform_id"], "property": prop, "field": field,
                                    "component": component, "source_binding": binding, "curve": curve})
                                continue
                    unresolved.append({"state": name, "clip": ex.identity(clip_pointer), "binding": binding, "reason": reason})
                if index != len(curves): raise ValueError("Source binding and curve counts differ")
                if tracks:
                    muscle = clip["m_MuscleClip"]
                    clips[name] = {"duration": muscle["m_StopTime"] - muscle.get("m_StartTime", 0),
                        "start": muscle.get("m_StartTime", 0), "loop": bool(muscle.get("m_LoopTime", False)),
                        "source": ex.identity(clip_pointer), "source_name": clip["m_Name"], "tracks": tracks}
                    if state_index == int(data.get("m_DefaultState", -1)): default_state = name
        if clips: controllers.append({"source": ex.identity(pointer), "default": default_state, "clips": clips})
    return {"materials": material_records, "renderers": renderers, "controllers": controllers}, unresolved, programs


def main(args):
    catalog_path = ROOT / "assets/combat_presentation/catalog.json"
    report = json.loads((ROOT / "reports/skill-presentation-model-import.json").read_text())
    digest = file_digest(args.apk)
    if digest != report["apk_sha256"]: raise ValueError("Model evidence belongs to another APK")
    catalog = json.loads(catalog_path.read_text())
    output = ROOT / "assets/combat_presentation/models"
    shader_output = ROOT / "reports/shader_evidence/skill_models"
    shader_output.mkdir(parents=True, exist_ok=True)
    result = {"schema": 1, "apk_sha256": digest, "property_decoder": {
        "source": "AssetRipper CustomCurveResolver.cs RendererMaterial", "crc_mask": "0x0fffffff", "scalar_bit": "0x80000000"},
        "prefabs": {}, "unresolved_counts": {}, "limitations": ["Animator root-motion and unbound TRS paths remain separately reported; no substitute motion is generated."]}
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(MANIFEST)
        assets, bundles = manifest_records(manifest)
        for name, row in report["prefabs"].items():
            ex = ActorExporter(archive, manifest, assets, bundles, row["source_asset"]["address"])
            ex.build()
            recovered, unresolved, programs = recover(ex, output, shader_output)
            model = catalog["effects"][name]["models"][0]
            model["material_animation"] = recovered
            model["duration"] = max(model["duration"], max((clip["duration"] for controller in recovered["controllers"] for clip in controller["clips"].values()), default=0))
            result["prefabs"][name] = {"material_animation": recovered, "unresolved": unresolved,
                "shader_programs": programs, "source_bundles": ex.bundle_evidence}
            print(name, "material_tracks", sum(len(c["tracks"]) for ctrl in recovered["controllers"] for c in ctrl["clips"].values()), flush=True)
            del ex
            gc.collect()
    result["unresolved_counts"] = dict(Counter(item["reason"] for row in result["prefabs"].values() for item in row["unresolved"]))
    catalog_path.write_text(json.dumps(catalog, separators=(",", ":")) + "\n")
    (ROOT / "reports/skill-model-material-animation.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    main(parser.parse_args())
