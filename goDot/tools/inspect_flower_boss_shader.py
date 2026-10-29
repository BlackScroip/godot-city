#!/usr/bin/env python3
"""Inspect the flower boss star particle and its exact APK shader pass.

Requires UnityPy. This is a read-only, static inspection of the APK and the
local exported descriptors; it does not execute the original application.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy
from UnityPy.export.ShaderConverter import ShaderSubProgram
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader


ROOT = Path(__file__).resolve().parents[2]
APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
BUNDLES = {
    "prefab": "07f33b242d99e8c8c88e47652d2eee6a",
    "material": "01db71b2e539697ed1a9ca10877ef328",
    "shader": "6cf9f765ef1c8e037ad4f013333c5a9a",
    "texture": "60666d11127f2795c5004f6510227f9b",
}
PREFAB_FILE = "CAB-1be07386f3dcfdfe3a007298149cd3af"
MATERIAL_FILE = "CAB-e355e6b0d05ab47d2012d0e8ccc2b413"
SHADER_FILE = "CAB-e0e868e1a4508c641226989c4c20c91b"
TEXTURE_FILE = "CAB-23eafb40fff4ce2d244a63ded2ec646b"
GAME_OBJECT_ID = -1334384038134774551
PARTICLE_ID = -8394211105394293527
RENDERER_ID = 8639195290814416105
MATERIAL_ID = 6028709936780744974
SHADER_ID = -7807925893294491066
TEXTURE_ID = -6384927136374821270
SHADER_NAME = "AllIn1Vfx/AllIn1VfxSRPBatch"
KEYWORDS = {"ADDITIVECONFIG_ON", "SHAPE1ROTATE_ON", "VERTOFFSET_ON"}
PROGRAM_SHA256 = "dc1f92f8434187f565fef0606a2e2116e60336ce27d0c8b086594812ff0d8efc"


def pointer_identity(owner, ref):
    file_id = ref["m_FileID"]
    name = owner.assets_file.name if file_id == 0 else owner.assets_file.externals[file_id - 1].path.rsplit("/", 1)[-1]
    return name, ref["m_PathID"]


def line_evidence(code, text):
    matches = [{"line": number, "text": line.strip()} for number, line in enumerate(code.splitlines(), 1) if text in line]
    if len(matches) != 1:
        raise ValueError("Expected one shader line containing " + text)
    return matches[0]


def inspect(apk, descriptors):
    with apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA256:
            raise ValueError("This evidence query targets a different APK SHA-256")
    env, sources = UnityPy.Environment(), {}
    with zipfile.ZipFile(apk) as archive:
        for kind, bundle_id in BUNDLES.items():
            member = "assets/yoo/DefaultPackage/" + bundle_id + ".bundle"
            payload = archive.read(member)
            loaded = env.load_file(payload, name=member)
            for item in loaded.files.values():
                if hasattr(item, "objects"):
                    sources[item.name] = {"kind": kind, "member": member, "sha256": hashlib.sha256(payload).hexdigest()}
    objects = {(obj.assets_file.name, obj.path_id): obj for obj in env.objects}

    game_object = objects[(PREFAB_FILE, GAME_OBJECT_ID)].read_typetree()
    particle = objects[(PREFAB_FILE, PARTICLE_ID)].read_typetree()
    renderer_obj = objects[(PREFAB_FILE, RENDERER_ID)]
    renderer = renderer_obj.read_typetree()
    if game_object["m_Name"] != "26070901_shoubuxuli_xingxing":
        raise ValueError("Unexpected prefab object")
    if not {PARTICLE_ID, RENDERER_ID}.issubset({ref["component"]["m_PathID"] for ref in game_object["m_Component"]}):
        raise ValueError("Particle and renderer do not share the selected game object")
    if particle["m_GameObject"]["m_PathID"] != GAME_OBJECT_ID or renderer["m_GameObject"]["m_PathID"] != GAME_OBJECT_ID:
        raise ValueError("Unexpected particle or renderer owner")
    if [pointer_identity(renderer_obj, ref) for ref in renderer["m_Materials"]] != [(MATERIAL_FILE, MATERIAL_ID)]:
        raise ValueError("Unexpected star particle material")

    material_obj = objects[(MATERIAL_FILE, MATERIAL_ID)]
    material = material_obj.read_typetree()
    keywords = set(material.get("m_ValidKeywords", []) or material.get("m_ShaderKeywords", "").split())
    shader_identity = pointer_identity(material_obj, material["m_Shader"])
    if keywords != KEYWORDS or shader_identity != (SHADER_FILE, SHADER_ID):
        raise ValueError("Unexpected material keywords or shader")
    floats = dict(material["m_SavedProperties"]["m_Floats"])
    colors = dict(material["m_SavedProperties"]["m_Colors"])
    texenvs = dict(material["m_SavedProperties"]["m_TexEnvs"])
    main_texture = pointer_identity(material_obj, texenvs["_MainTex"]["m_Texture"])
    if main_texture != (TEXTURE_FILE, TEXTURE_ID):
        raise ValueError("Unexpected main texture")
    texture = objects[main_texture].read()
    image = texture.image.convert("RGBA")
    if texture.m_Name != "Flare7" or image.getchannel("A").getextrema() != (255, 255):
        raise ValueError("Unexpected source texture or alpha range")
    if [floats.get(k) for k in ("_SrcMode", "_DstMode", "_SrcBlend", "_DstBlend")] != [1.0, 1.0, 1.0, 0.0]:
        raise ValueError("Unexpected serialized blend properties")

    shader = objects[shader_identity].read_typetree()
    if shader["m_ParsedForm"]["m_Name"] != SHADER_NAME:
        raise ValueError("Unexpected shader name")
    passes = shader["m_ParsedForm"]["m_SubShaders"][0]["m_Passes"]
    if len(shader["m_ParsedForm"]["m_SubShaders"]) != 1 or len(passes) != 1:
        raise ValueError("Unexpected subshader or pass count")
    if passes[0]["progFragment"]["m_PlayerSubPrograms"]:
        raise ValueError("Unexpected separate fragment program table")
    state = passes[0]["m_State"]
    blend = state["rtBlend0"]
    blend_bindings = {key: blend[key]["name"] for key in ("srcBlend", "destBlend", "srcBlendAlpha", "destBlendAlpha")}
    if blend_bindings != {"srcBlend": "_SrcMode", "destBlend": "_DstMode", "srcBlendAlpha": "_SrcMode", "destBlendAlpha": "_DstMode"}:
        raise ValueError("Unexpected shader pass blend bindings")

    blob = bytes(shader["compressedBlob"])
    programs = []
    for platform, offsets, sizes, lengths in zip(shader["platforms"], shader["offsets"], shader["compressedLengths"], shader["decompressedLengths"]):
        if platform != 9:
            continue
        if not isinstance(offsets, list):
            offsets, sizes, lengths = [offsets], [sizes], [lengths]
        chunks = [CompressionHelper.decompress_lz4(blob[offset:offset + size], length)
                  for offset, size, length in zip(offsets, sizes, lengths)]
        for index in range(struct.unpack_from("<i", chunks[0])[0]):
            offset, size, segment = struct.unpack_from("<iii", chunks[0], 4 + index * 12)
            program = ShaderSubProgram(EndianBinaryReader(chunks[segment][offset:offset + size], endian="<"))
            if set(program.m_Keywords) | set(program.m_LocalKeywords or []) != keywords:
                continue
            code = program.m_ProgramCode.decode("utf-8")
            digest = hashlib.sha256(code.encode("utf-8")).hexdigest()
            if digest != PROGRAM_SHA256:
                raise ValueError("Exact-keyword GLES program has an unexpected digest")
            if "#ifdef VERTEX" not in code or "#ifdef FRAGMENT" not in code:
                raise ValueError("Expected a combined GLES vertex/fragment program")
            bindings = []
            for stage in ("progVertex", "progFragment"):
                for group in passes[0].get(stage, {}).get("m_PlayerSubPrograms", []):
                    if any(binding["m_BlobIndex"] == index for binding in group):
                        bindings.append(stage)
            programs.append({"platform": platform, "index": index, "segment": segment,
                "sha256": digest, "bindings": bindings,
                "evidence_lines": {
                    "vertex_color_passthrough": line_evidence(code, "vs_COLOR0 = in_COLOR0;"),
                    "sample_rgba": line_evidence(code, "u_xlat16_0 = texture(_MainTex, u_xlat0.xy);"),
                    "tint_sample": line_evidence(code, "u_xlat16_0 = u_xlat16_0 * _ShapeColor;"),
                    "particle_rgb": line_evidence(code, "u_xlat16_2.xyz = vs_COLOR0.xyz * _Color.xyz;"),
                    "particle_alpha": line_evidence(code, "u_xlat16_2.w = vs_COLOR0.w * _Alpha;"),
                    "combine_rgba": line_evidence(code, "u_xlat16_2 = u_xlat16_0 * u_xlat16_2;"),
                    "premultiply_rgb": line_evidence(code, "SV_Target0.xyz = u_xlat16_2.www * u_xlat16_2.xyz;"),
                    "output_alpha": line_evidence(code, "SV_Target0.w = u_xlat16_2.w;")}})
    if len(programs) != 1 or programs[0]["bindings"] != ["progVertex"]:
        raise ValueError("Expected one exact-keyword combined GLES program")

    with descriptors.open() as stream:
        catalog = json.load(stream)
    same_file_rows = [(reference, row) for reference, row in catalog.items()
                      if row.get("shader") == SHADER_NAME and reference.startswith(MATERIAL_FILE + ":")]
    checked, conflicts = [], []
    fields = ("_SrcMode", "_DstMode", "_SrcBlend", "_DstBlend")
    for reference, row in same_file_rows:
        obj = objects[(MATERIAL_FILE, int(reference.rsplit(":", 1)[1]))]
        raw = obj.read_typetree()
        actual_floats = dict(raw["m_SavedProperties"]["m_Floats"])
        if pointer_identity(obj, raw["m_Shader"]) != shader_identity:
            raise ValueError("Descriptor name refers to a different shader: " + reference)
        if any(actual_floats.get(k) != row.get("source_floats", {}).get(k) for k in fields):
            raise ValueError("Descriptor blend values differ from APK: " + reference)
        values = {k: actual_floats.get(k) for k in fields}
        checked.append(values)
        if values["_SrcMode"] == values["_DstMode"] == 1.0 and (values["_SrcBlend"], values["_DstBlend"]) != (1.0, 1.0):
            conflicts.append({"reference": reference, "name": raw["m_Name"], "descriptor_blend": row.get("blend"), "values": values})
    other_file = [reference for reference, row in catalog.items()
                  if row.get("shader") == SHADER_NAME and not reference.startswith(MATERIAL_FILE + ":")]
    other_file_one_one = [reference for reference in other_file
                          if catalog[reference].get("source_floats", {}).get("_SrcMode") == 1.0
                          and catalog[reference].get("source_floats", {}).get("_DstMode") == 1.0]
    return {"apk_sha256": APK_SHA256,
        "prefab": {"source": sources[PREFAB_FILE], "game_object_id": GAME_OBJECT_ID,
                   "particle_id": PARTICLE_ID, "renderer_id": RENDERER_ID, "renderer_enabled": renderer["m_Enabled"]},
        "material": {"source": sources[MATERIAL_FILE], "file": MATERIAL_FILE, "path_id": MATERIAL_ID,
            "name": material["m_Name"], "keywords": sorted(keywords), "main_texture": list(main_texture),
            "floats": {k: floats.get(k) for k in (*fields, "_Alpha", "_ShapeRotationOffset", "_ShapeRotationSpeed", "_VertOffsetAmount")},
            "colors": {k: colors[k] for k in ("_Color", "_ShapeColor")}},
        "texture": {"source": sources[TEXTURE_FILE], "file": TEXTURE_FILE, "path_id": TEXTURE_ID,
            "name": texture.m_Name, "size": list(image.size), "rgba_extrema": image.getextrema(),
            "corner_pixel": image.getpixel((0, 0)), "center_pixel": image.getpixel((image.width // 2, image.height // 2))},
        "shader": {"source": sources[SHADER_FILE], "file": SHADER_FILE, "path_id": SHADER_ID,
            "name": SHADER_NAME, "rt_blend_0": blend, "rt_separate_blend": state["rtSeparateBlend"], "programs": programs},
        "batch": {"same_file_shader_pointer_and_floats_verified": len(checked),
            "same_name_other_file_not_checked": len(other_file),
            "same_name_other_file_one_one_descriptors": len(other_file_one_one), "one_one_conflicts": len(conflicts),
            "descriptor_blends": dict(Counter(row["descriptor_blend"] for row in conflicts)), "conflicts": conflicts},
        "interpretation": {"blend": "pass uses _SrcMode/_DstMode = One/One, not the saved _SrcBlend/_DstBlend values",
            "alpha": "A = sampled_main.a * _ShapeColor.a * vertex_color.a * _Alpha",
            "rgb": "sampled_main.rgb * _ShapeColor.rgb * vertex_color.rgb * _Color.rgb * A",
            "output_alpha": "A"},
        "limitations": ["Static serialized objects and exact-keyword GLES combined program only; APK runtime was not observed.",
            "Same-name descriptors in other serialized files are not shader-pointer-verified by this query.",
            "Other keyword combinations and graphics backends are not established by the decoded fragment formula."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--descriptors", type=Path, default=ROOT / "goDot/assets/combat_presentation/materials.json")
    parser.add_argument("--output", type=Path, help="Optional summary JSON")
    args = parser.parse_args()
    output = json.dumps(inspect(args.apk, args.descriptors), ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
