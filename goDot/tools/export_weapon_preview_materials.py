#!/usr/bin/env python3
"""Recover only the evidenced weapon 202 preview plane material from the APK."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr
from UnityPy.export.ShaderConverter import ShaderSubProgram
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


ROOT = Path(__file__).resolve().parents[2]
PREFAB = "weapon_20001_low"
MATERIAL = "mat_fx_24092401_20001_fire"
TEXTURES = {
    "_MainTex": "tex_fx_noise_32",
    "_DistortTex": "tex_fx_noise_37",
    "_FadeTex": "tex_fx_noise_7",
    "_MaskTex": "tex_fx_mask_4c",
}


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def export_shader_evidence(shader, material, apk_sha256):
    directory = ROOT / "goDot/reports/shader_evidence/weapon_preview"
    directory.mkdir(parents=True, exist_ok=True)
    blob = bytes(shader["compressedBlob"])
    expected = set(material["keywords"])
    programs = []
    for platform, offsets, sizes, lengths in zip(shader["platforms"], shader["offsets"],
                                                 shader["compressedLengths"], shader["decompressedLengths"]):
        if platform != 9:
            continue
        if not isinstance(offsets, list):
            offsets, sizes, lengths = [offsets], [sizes], [lengths]
        chunks = [CompressionHelper.decompress_lz4(blob[offset:offset + size], length)
                  for offset, size, length in zip(offsets, sizes, lengths)]
        for index in range(struct.unpack_from("<i", chunks[0])[0]):
            offset, size, segment = struct.unpack_from("<iii", chunks[0], 4 + index * 12)
            program = ShaderSubProgram(EndianBinaryReader(chunks[segment][offset:offset + size], endian="<"))
            keywords = set(program.m_Keywords) | set(program.m_LocalKeywords or [])
            if keywords != expected:
                continue
            code = program.m_ProgramCode.decode("utf-8")
            if "#version" not in code or "(-vs_COLOR0.w) + _FadeAmount;" not in code:
                raise RuntimeError("Exact shader variant no longer matches the observed vertex-alpha fade formula")
            destination = directory / (MATERIAL + "_program_" + str(index) + ".glsl")
            destination.write_text(code)
            pass_bindings = []
            for subshader_index, subshader in enumerate(shader["m_ParsedForm"]["m_SubShaders"]):
                for pass_index, shader_pass in enumerate(subshader["m_Passes"]):
                    if platform not in shader_pass.get("m_Platforms", []):
                        continue
                    for stage in ("progVertex", "progFragment"):
                        for group in shader_pass.get(stage, {}).get("m_PlayerSubPrograms", []):
                            for binding in group:
                                if binding["m_BlobIndex"] == index:
                                    pass_bindings.append({"subshader": subshader_index, "pass": pass_index,
                                                          "stage": stage, "pass_name": shader_pass["m_State"]["m_Name"]})
            programs.append({"platform": platform, "program_index": index, "segment": segment,
                             "offset": offset, "size": size, "keywords": sorted(keywords),
                             "pass_bindings": pass_bindings,
                             "path": str(destination.relative_to(ROOT / "goDot")),
                             "sha256": digest(code.encode("utf-8")),
                             "fade_formula_lines": [473, 495]})
    if len(programs) != 1:
        raise RuntimeError("Expected exactly one matching GLES subprogram")
    report = {
        "evidence_type": "Static original GLES subprogram exported from Unity serialized Shader; no APK runtime execution",
        "apk_sha256": apk_sha256, "material": MATERIAL,
        "material_source": material["source_identity"], "shader_source": material["shader_source"],
        "shader_name": material["shader"], "compressed_blob_sha256": digest(blob),
        "programs": programs,
        "observed_formula": {
            "q": "clamp(1.0 - vertex_color_alpha + _FadeAmount, 0.0, 1.0)",
            "threshold": "sample(_FadeTex).r + 1.0 - 2.0 * min(pow(q, _FadePower), 1.0)",
            "transition": "max((1.0 - pow(1.0 - q, 5.0)) * _FadeTransition, 0.01)",
            "fade": "smoothstep(0.0, transition, threshold)",
            "material_values": {"_FadeAmount": material["source_floats"]["_FadeAmount"],
                                "_FadePower": material["source_floats"]["_FadePower"],
                                "_FadeTransition": material["source_floats"]["_FadeTransition"]},
            "consequence": "For vertex alpha 1, q is approximately 0.66. Omitting vertex alpha clamps q to 1 and makes fade zero for sampled texture values at or below 1."
        },
        "limits": ["The formula is established for this material's exact DISTORT_ON/FADE_ON/MASK_ON keyword set.",
                   "Do not apply this observation to unverified keyword variants or particle stream layouts."]
    }
    destination = ROOT / "goDot/reports/weapon-preview-shader-evidence-20261028.json"
    destination.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    return str(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--output", type=Path, default=ROOT / "goDot/assets/ui/role_weapon")
    parser.add_argument("--shader-evidence", action="store_true")
    args = parser.parse_args()
    with zipfile.ZipFile(args.apk) as archive:
        manifest_member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest)
        prefab = next(asset for asset in assets if asset["address"] == PREFAB)
        direct, edges = package_dependencies(manifest, PREFAB)
        pending, indices = [prefab["bundle"], *direct], set()
        while pending:
            index = pending.pop()
            if index in indices:
                continue
            indices.add(index)
            pending.extend(edges[index])
        environment, sources, primary = UnityPy.Environment(), {}, None
        for index in sorted(indices):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            loaded = environment.load_file(payload)
            for cab in loaded.files.values():
                if not hasattr(cab, "objects"):
                    continue
                sources[cab.name] = {"member": member, "sha256": digest(payload)}
                if index == prefab["bundle"]:
                    primary = cab

    def resolve(owner, pointer):
        return PPtr(**pointer, assetsfile=owner.assets_file).deref()

    def identity(obj):
        return {
            "serialized_asset": obj.assets_file.name,
            "path_id": str(obj.path_id),
            **sources[obj.assets_file.name],
        }

    candidates = [obj for obj in environment.objects if obj.type.name == "Material"
                  and obj.read_typetree().get("m_Name") == MATERIAL]
    if len(candidates) != 1 or primary is None:
        raise RuntimeError("Expected one material and one weapon prefab serialized asset")
    material_obj = candidates[0]
    data = material_obj.read_typetree()
    shader_obj = resolve(material_obj, data["m_Shader"])
    shader_tree = shader_obj.read_typetree()
    shader = shader_tree.get("m_Name") or shader_tree.get("m_ParsedForm", {}).get("m_Name", "")
    if shader != "AllIn1Vfx/AllIn1VfxSRPBatch":
        raise RuntimeError("Unexpected shader: " + shader)
    properties = data["m_SavedProperties"]
    floats, colors = dict(properties["m_Floats"]), dict(properties["m_Colors"])
    texture_slots = [(key, slot) for key, slot in properties["m_TexEnvs"]
                     if slot["m_Texture"]["m_PathID"]]
    if {key for key, _ in texture_slots} != set(TEXTURES):
        raise RuntimeError("The material texture bindings differ from the bounded evidence")

    output_textures = args.output / "preview_effects"
    output_textures.mkdir(parents=True, exist_ok=True)
    maps = []
    for key, slot in texture_slots:
        texture_obj = resolve(material_obj, slot["m_Texture"])
        texture_tree = texture_obj.read_typetree()
        name = texture_tree["m_Name"]
        if name != TEXTURES[key]:
            raise RuntimeError("Unexpected texture for " + key + ": " + name)
        texture_file = output_textures / (name + ".png")
        image = texture_obj.read().image
        image.save(texture_file)
        settings = texture_tree.get("m_TextureSettings", {})
        maps.append({
            "property": key,
            "texture": "res://" + str(texture_file.relative_to(ROOT / "goDot")),
            "scale": slot["m_Scale"], "offset": slot["m_Offset"],
            "wrap": {"x": settings.get("m_WrapU", 0), "y": settings.get("m_WrapV", 0)},
            "source_name": name, "source": identity(texture_obj),
            "width": image.width, "height": image.height,
            "png_sha256": digest(texture_file.read_bytes()),
        })

    bindings = []
    for obj in primary.objects.values():
        if obj.type.name != "MeshRenderer":
            continue
        tree = obj.read_typetree()
        for surface, pointer in enumerate(tree.get("m_Materials", [])):
            bound = resolve(obj, pointer)
            if (bound.assets_file.name, bound.path_id) != (material_obj.assets_file.name, material_obj.path_id):
                continue
            game_object = resolve(obj, tree["m_GameObject"])
            bindings.append({
                "renderer": identity(obj), "game_object_path_id": str(game_object.path_id),
                "game_object_name": game_object.read_typetree()["m_Name"], "surface": surface,
            })
    if not bindings:
        raise RuntimeError("The target material is not bound to a renderer in the selected weapon prefab")

    main_texture = next(entry for entry in maps if entry["property"] == "_MainTex")
    white = {"r": 1, "g": 1, "b": 1, "a": 1}
    source_mode, dest_mode = floats.get("_SrcMode"), floats.get("_DstMode")
    blend = "alpha" if source_mode in (1, 5) and dest_mode == 10 else "add" if source_mode in (1, 5) and dest_mode == 1 else "unknown"
    if blend == "unknown":
        raise RuntimeError("Unsupported source blend")
    material = {
        "name": MATERIAL, "source": material_obj.assets_file.name + ":" + str(material_obj.path_id),
        "source_identity": identity(material_obj), "shader_source": identity(shader_obj),
        "texture": main_texture["texture"], "texture_scale": main_texture["scale"],
        "texture_offset": main_texture["offset"], "textures": maps,
        "keywords": data.get("m_ValidKeywords", []), "shader": shader,
        "render_queue": data.get("m_CustomRenderQueue"),
        "color": colors.get("_Color", white), "shape_color": colors.get("_ShapeColor", white),
        "alpha": floats.get("_Alpha", 1), "shape_alpha_weight": floats.get("_ShapeAlphaWeight", 0),
        "shape_brightness": floats.get("_ShapeBrightness", 0), "glow": floats.get("_Glow", 0),
        "glow_global": floats.get("_GlowGlobal", 1),
        "alpha_from_luminance": floats.get("_ShapeAlphaWeight", 0) > 0,
        "fade_vertex_alpha": True,
        "fade_vertex_alpha_evidence": {
            "platform": 9, "program_index": 827,
            "keywords": ["DISTORT_ON", "FADE_ON", "MASK_ON"],
            "source_formula": "clamp(1.0 - vs_COLOR0.w + _FadeAmount, 0.0, 1.0)",
            "report": "reports/weapon-preview-shader-evidence-20261028.json",
        },
        "blend": blend, "source_floats": floats, "source_colors": colors,
    }
    with args.apk.open("rb") as stream:
        apk_sha256 = hashlib.file_digest(stream, "sha256").hexdigest()
    output = {
        "apk": args.apk.name, "apk_sha256": apk_sha256,
        "manifest": {"member": manifest_member, "sha256": digest(manifest)},
        "prefab": {**prefab, "serialized_asset": primary.name, **sources[primary.name]},
        "bindings": bindings, "materials": {MATERIAL: material},
        "limits": [
            "Static material and renderer binding evidence only; the APK was not executed.",
            "Only this one weapon preview material and its four bound textures are exported.",
            "The recovered Godot shader is an approximation; export does not establish visual equivalence to the compiled Unity shader.",
        ],
    }
    destination = args.output / "source_materials.json"
    destination.write_text(json.dumps(output, indent=2, allow_nan=False) + "\n")
    shader_evidence = export_shader_evidence(shader_tree, material, apk_sha256) if args.shader_evidence else None
    print(json.dumps({"path": str(destination), "materials": len(output["materials"]),
                      "textures": len(maps), "bindings": bindings, "shader": shader, "blend": blend,
                      "shader_evidence": shader_evidence}))


if __name__ == "__main__":
    main()
