#!/usr/bin/env python3
"""Inspect the exact APK flying-dragon TrailRenderer material and GLES variant.

Requires UnityPy. Outputs only identities, hashes and short evidence lines,
not the complete original shader. No APK runtime is executed.
"""

import argparse
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
    "prefab": "5a208e992bc862c818adba86917b252e",
    "material": "01db71b2e539697ed1a9ca10877ef328",
    "shader": "6cf9f765ef1c8e037ad4f013333c5a9a",
}
MATERIAL_FILE = "CAB-e355e6b0d05ab47d2012d0e8ccc2b413"
MATERIAL_ID = -7520495672365228611
SHADER_ID = -7807925893294491066
KEYWORDS = {"FADE_ON", "SHAPE1ROTATE_ON", "SHAPE1SHAPECOLOR_ON"}
PROGRAM_SHA256 = "c9f346ad24a3c29072c97295fab6d74e642a42521766a200ee7844dfca7066a7"


def file_sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def pointer_identity(owner, ref):
    file_id = ref["m_FileID"]
    name = owner.assets_file.name if file_id == 0 else owner.assets_file.externals[file_id - 1].path.rsplit("/", 1)[-1]
    return name, ref["m_PathID"]


def line_evidence(code, text):
    matches = [{"line": number, "text": line.strip()} for number, line in enumerate(code.splitlines(), 1) if text in line]
    if len(matches) != 1:
        raise ValueError("Expected one shader line containing " + text)
    return matches[0]


def inspect(apk):
    if file_sha256(apk) != APK_SHA256:
        raise ValueError("This evidence query targets a different APK SHA-256")
    env, sources = UnityPy.Environment(), {}
    with zipfile.ZipFile(apk) as archive:
        for kind, bundle_id in BUNDLES.items():
            member = "assets/yoo/DefaultPackage/" + bundle_id + ".bundle"
            payload = archive.read(member)
            loaded = env.load_file(payload, name=member)
            for item in loaded.files.values():
                if hasattr(item, "objects"):
                    sources[item.name] = {"kind": kind, "member": member,
                                          "sha256": hashlib.sha256(payload).hexdigest()}
    objects = {(obj.assets_file.name, obj.path_id): obj for obj in env.objects}
    material = objects[(MATERIAL_FILE, MATERIAL_ID)]
    raw = material.read_typetree()
    keywords = set(raw.get("m_ValidKeywords", []) or raw.get("m_ShaderKeywords", "").split())
    if keywords != KEYWORDS:
        raise ValueError("Trail material keywords changed")
    shader_identity = pointer_identity(material, raw["m_Shader"])
    if shader_identity[1] != SHADER_ID:
        raise ValueError("Trail material references a different shader")
    shader = objects[shader_identity]
    tree = shader.read_typetree()
    blob = bytes(tree["compressedBlob"])

    trails, prefab_files = [], set()
    for obj in env.objects:
        if obj.type.name != "TrailRenderer" or sources.get(obj.assets_file.name, {}).get("kind") != "prefab":
            continue
        data = obj.read_typetree()
        refs = [pointer_identity(obj, ref) for ref in data.get("m_Materials", [])]
        prefab_files.add(obj.assets_file.name)
        trails.append({"path_id": obj.path_id, "materials": ["%s:%s" % ref for ref in refs],
                       "uses_selected_material": (MATERIAL_FILE, MATERIAL_ID) in refs,
                       "duration": data.get("m_Time"), "min_vertex_distance": data.get("m_MinVertexDistance")})
    if len(prefab_files) != 1 or len(trails) != 6 or any(not trail["uses_selected_material"] for trail in trails):
        raise ValueError("Expected six prefab trails using the selected material")

    programs = []
    for platform, offsets, sizes, lengths in zip(tree["platforms"], tree["offsets"], tree["compressedLengths"], tree["decompressedLengths"]):
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
                raise ValueError("Exact-keyword GLES variant has an unexpected digest")
            bindings = []
            for sub_index, subshader in enumerate(tree["m_ParsedForm"]["m_SubShaders"]):
                for pass_index, shader_pass in enumerate(subshader["m_Passes"]):
                    if platform not in shader_pass.get("m_Platforms", []):
                        continue
                    for stage in ("progVertex", "progFragment"):
                        for group in shader_pass.get(stage, {}).get("m_PlayerSubPrograms", []):
                            if any(binding["m_BlobIndex"] == index for binding in group):
                                bindings.append({"subshader": sub_index, "pass": pass_index, "stage": stage,
                                                 "name": shader_pass["m_State"]["m_Name"]})
            programs.append({"platform": platform, "index": index, "segment": segment,
                "sha256": digest, "bindings": bindings,
                "evidence_lines": {"vertex_passthrough": line_evidence(code, "vs_COLOR0 = in_COLOR0;"),
                    "fade_vertex_alpha": line_evidence(code, "(-vs_COLOR0.w) + _FadeAmount;"),
                    "main_red": line_evidence(code, "texture(_MainTex, u_xlat0.xy).x;"),
                    "alpha_multiply": line_evidence(code, "u_xlat16_2.x = u_xlat16_2.x * u_xlat16_0;"),
                    "output_alpha": line_evidence(code, "SV_Target0.w = u_xlat16_2.x * _Alpha;")}})
    if len(programs) != 1:
        raise ValueError("Expected one GLES program matching the material's exact keywords")
    floats = dict(raw["m_SavedProperties"]["m_Floats"])
    return {"apk_sha256": APK_SHA256, "prefab_bundle": sources[prefab_files.pop()],
        "trails": sorted(trails, key=lambda row: row["path_id"]),
        "material": {"file": MATERIAL_FILE, "path_id": MATERIAL_ID, "name": raw["m_Name"],
            "source": sources[MATERIAL_FILE], "keywords": sorted(keywords),
            "fade_values": {name: floats.get(name) for name in ("_FadeAmount", "_FadePower", "_FadeTransition")}},
        "shader": {"file": shader_identity[0], "path_id": SHADER_ID, "source": sources[shader_identity[0]],
            "name": tree["m_ParsedForm"]["m_Name"], "compressed_blob_sha256": hashlib.sha256(blob).hexdigest(),
            "programs": programs},
        "interpretation": {"fade_input": "clamp(1 - vertex_color_alpha + _FadeAmount, 0, 1)",
            "output_alpha": "main_texture_red * fade * _Alpha; no additional vertex alpha multiplication"},
        "limitations": ["Static serialized objects and the exact-keyword GLES program only; no APK runtime was observed.",
            "Other keyword combinations, graphics backends and Unity runtime vertex generation are not established."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--output", type=Path, help="Optional summary JSON")
    args = parser.parse_args()
    output = json.dumps(inspect(args.apk), ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
