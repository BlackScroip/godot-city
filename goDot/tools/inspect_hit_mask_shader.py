#!/usr/bin/env python3
"""Retain the source character shader used by native damage mask feedback."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

from import_player_lifecycle import file_digest, manifest_records
from recover_region_actors import ActorExporter
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader
from UnityPy.export.ShaderConverter import ShaderSubProgram

ROOT = Path(__file__).resolve().parents[1]
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
MANIFEST = "assets/yoo/DefaultPackage/DefaultPackage_2026-10-09-1177.bytes"
SHADER_NAME = "NeoShader/NPR_Simple"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--prefab", default="myplayer_shuangdao_simply")
    parser.add_argument("--output", type=Path, default=ROOT / "reports/hit-mask-shader-static.json")
    parser.add_argument("--program-dir", type=Path, default=ROOT / "reports/shader_evidence/hit_mask")
    args = parser.parse_args()
    digest = file_digest(args.apk)
    if digest != APK_SHA:
        raise ValueError("This evidence map is bound to the supplied APK hash")
    args.program_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(MANIFEST)
        assets, bundles = manifest_records(manifest)
        exporter = ActorExporter(archive, manifest, assets, bundles, args.prefab)
        renderers, materials, shaders = [], {}, {}
        for key, obj in exporter.objects.items():
            if obj.type.name != "SkinnedMeshRenderer":
                continue
            raw = exporter.raw[key]
            material_ids = []
            for reference in raw["m_Materials"]:
                pointer = exporter.pointer(obj, reference)
                material_id = exporter.identity(pointer)
                material = pointer.read_typetree()
                shader_pointer = exporter.pointer(pointer.deref(), material["m_Shader"])
                shader = shader_pointer.read_typetree()
                if shader["m_ParsedForm"]["m_Name"] != SHADER_NAME:
                    continue
                material_ids.append(material_id)
                shader_id = exporter.identity(shader_pointer)
                keywords = set(material.get("m_ValidKeywords", [])) | set(material.get("m_ShaderKeywords", "").split())
                materials[material_id] = {"name": material["m_Name"], "shader_source": shader_id, "keywords": sorted(keywords), "saved_properties": material["m_SavedProperties"]}
                if shader_id not in shaders:
                    shaders[shader_id] = {"raw": shader, "keyword_sets": set()}
                shaders[shader_id]["keyword_sets"].add(tuple(sorted(keywords)))
            renderers.append({"source": obj.assets_file.name + ":" + str(obj.path_id), "game_object": exporter.games[raw["m_GameObject"]["m_PathID"]]["m_Name"], "matching_materials": material_ids})
        programs, shader_evidence = [], {}
        for shader_id, entry in shaders.items():
            shader = entry["raw"]
            parsed = shader["m_ParsedForm"]
            shader_evidence[shader_id] = {"name": parsed["m_Name"], "keyword_sets": [list(row) for row in sorted(entry["keyword_sets"])], "subshaders": [{"tags": row.get("m_Tags"), "passes": [{"type": item.get("m_Type"), "state": item.get("m_State"), "serialized_fields": {key: value for key, value in item.items() if key != "m_State"}} for item in row["m_Passes"]]} for row in parsed["m_SubShaders"]]}
            blob = bytes(shader["compressedBlob"])
            for platform, offsets, sizes, lengths in zip(shader["platforms"], shader["offsets"], shader["compressedLengths"], shader["decompressedLengths"]):
                if platform != 9:
                    continue
                if not isinstance(offsets, list):
                    offsets, sizes, lengths = [offsets], [sizes], [lengths]
                chunks = [CompressionHelper.decompress_lz4(blob[o:o + size], length) for o, size, length in zip(offsets, sizes, lengths)]
                for index in range(struct.unpack_from("<i", chunks[0])[0]):
                    offset, size, segment = struct.unpack_from("<iii", chunks[0], 4 + index * 12)
                    program = ShaderSubProgram(EndianBinaryReader(chunks[segment][offset:offset + size], endian="<"))
                    keywords = tuple(sorted(set(program.m_Keywords) | set(program.m_LocalKeywords or [])))
                    if keywords not in entry["keyword_sets"]:
                        continue
                    code = program.m_ProgramCode.decode("utf-8")
                    if "#version" not in code:
                        continue
                    pass_bindings = []
                    for subshader_index, subshader in enumerate(parsed["m_SubShaders"]):
                        for pass_index, shader_pass in enumerate(subshader["m_Passes"]):
                            if platform not in shader_pass.get("m_Platforms", []):
                                continue
                            for stage in ("progVertex", "progFragment"):
                                for group_index, entries in enumerate(shader_pass.get(stage, {}).get("m_PlayerSubPrograms", [])):
                                    for binding in entries:
                                        if binding["m_BlobIndex"] == index:
                                            pass_bindings.append({"subshader_index": subshader_index, "pass_index": pass_index, "pass_name": shader_pass["m_State"]["m_Name"], "stage": stage, "pass_platforms": shader_pass["m_Platforms"], "blob_platform": platform, "serialized_program_group_index": group_index, "binding": binding})
                    if not pass_bindings:
                        raise ValueError("Matching GLES source has no serialized pass binding")
                    target = args.program_dir / f"shader_{sha(shader_id.encode())[:12]}_program_{index}.glsl"
                    target.write_text(code)
                    programs.append({"shader_source": shader_id, "program_index": index, "segment": segment, "offset": offset, "size": size, "keywords": list(keywords), "pass_bindings": pass_bindings, "path": str(target.relative_to(ROOT)), "sha256": sha(code.encode("utf-8")), "has_modify_color": "_ModifyColor" in code, "has_enable_modify_color": "_EnableModifyColor" in code})
        if not materials or not programs:
            raise ValueError("No exact character material and GLES shader matches recovered")
        findings = [
            {"id": "source-mask-formula", "kind": "observation", "detail": "The matching empty-keyword GLES program uses selected = (_EnableModifyColor != 0) ? (_ModifyColor * _ModifyColorIntensity) : vec4(1). It mixes RampShadowColor0 toward selected using the computed light ramp, multiplies MainTex and MainColor, then adds its Fresnel term. See original retained program lines163..178. Damage mask white/intensity1.5 increases the lit ramp endpoint; textures, shadow tint and Fresnel remain part of the output."},
            {"id": "source-mask-opacity", "kind": "observation", "detail": "The original ForwardBase pass has RenderType Opaque, source blend1/destination blend0 for RGB and alpha, blend op0, ZWrite1 and color mask15. The shader applies its operations to vec4 including alpha; no custom0.65 overlay opacity or full-white replacement branch appears. Pass state and all serialized pass metadata are retained."},
            {"id": "source-mask-coverage", "kind": "observation", "detail": "All three selected character skinned materials (face/body/hair) bind the same NeoShader/NPR_Simple with an empty keyword set. One matching GLES program is retained. This establishes this prefab's source mask formula; it does not claim every actor uses the same shader or has been ported."},
        ]
        report = {"schema": 1, "evidence_type": "ordinary-shell-static-UnityPy-export; not REA Evidence or runtime observation", "apk_sha256": digest, "manifest": {"member": MANIFEST, "sha256": sha(manifest)}, "prefab": args.prefab, "prefab_source": exporter.asset, "source_bundles": exporter.bundle_evidence, "renderers": renderers, "materials": materials, "shaders": shader_evidence, "programs": programs, "findings": findings, "limitations": ["This retains only the selected prefab's exact serialized material keyword sets and original GLES subprograms.", "Original rendering has not been executed; Godot output, tone mapping, and visual equivalence require separate verification."]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "materials": len(materials), "shaders": len(shaders), "programs": len(programs), "mask_programs": sum(row["has_enable_modify_color"] for row in programs)}))


if __name__ == "__main__":
    main()
