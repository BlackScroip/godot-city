#!/usr/bin/env python3
"""Inspect compiled shader evidence from the original APK environment materials."""
import json
from pathlib import Path
import hashlib
import zipfile
import struct
import UnityPy
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader
from UnityPy.export.ShaderConverter import ShaderSubProgram

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads(Path("/private/tmp/city-charge-assets/manifest.json").read_text())
asset = next(a for a in manifest["assets"] if a["address"] == "23051504_fx_env_obliquelight")
env = UnityPy.Environment()
with zipfile.ZipFile(ROOT / "com.teamelo.dungeonchasers.apk") as archive:
    for index in [asset["bundle"], *asset["deps"]]:
        env.load_file(archive.read("assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"))
out = Path("/private/tmp/city-environment-shaders")
out.mkdir(exist_ok=True)
summary = []
for obj in env.objects:
    if obj.type.name != "Shader": continue
    tree = obj.read_typetree()
    name = tree.get("m_Name") or tree.get("m_ParsedForm", {}).get("m_Name", "")
    if name not in ("AllIn1Vfx/AllIn1VfxSRPBatch", "AllIn1Vfx/AllIn1Vfx"): continue
    data = obj.read()
    row = {"name": name, "source": f"{obj.assets_file.name}:{obj.path_id}", "platforms": tree.get("platforms"),
           "blob_size": len(tree.get("compressedBlob", [])), "keys": list(tree)}
    segments = []
    blob = bytes(tree["compressedBlob"])
    for platform, offsets, sizes, expanded in zip(tree["platforms"], tree["offsets"], tree["compressedLengths"], tree["decompressedLengths"]):
        if not isinstance(offsets, list): offsets, sizes, expanded = [offsets], [sizes], [expanded]
        for index, (offset, size, length) in enumerate(zip(offsets, sizes, expanded)):
            raw = CompressionHelper.decompress_lz4(blob[offset:offset + size], length)
            target = out / (name.rsplit("/", 1)[-1] + f"-{platform}-{index}.bin")
            target.write_bytes(raw)
            segments.append({"platform": platform, "index": index, "path": str(target), "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
    row["segments"] = segments
    if name.endswith("SRPBatch"):
        catalog = json.loads((ROOT / "goDot/assets/environment_effects/catalog.json").read_text())
        wanted = {m["name"]: set(m["keywords"]) for effect in ("23051504_fx_env_obliquelight", "25040703_fx_other_spritesaltar", "24102301_fx_env_maincityprotal") for layer in catalog["effects"][effect]["layers"] for m in layer["materials"] if "allin1" in m["shader"].lower()}
        portal_materials = json.loads((ROOT / "goDot/assets/environment_effects/camp_portal_materials.json").read_text())["materials"]
        wanted.update({name: set(m["keywords"]) for name, m in portal_materials.items()})
        chunks = [Path(s["path"]).read_bytes() for s in segments]
        matches = []
        for index in range(struct.unpack_from("<i", chunks[0])[0]):
            offset, size, segment = struct.unpack_from("<iii", chunks[0], 4 + index * 12)
            try:
                program = ShaderSubProgram(EndianBinaryReader(chunks[segment][offset:offset+size], endian="<"))
                code = program.m_ProgramCode.decode("utf-8")
            except Exception:
                continue
            if "#version" not in code: continue
            keywords = set(program.m_Keywords) | set(program.m_LocalKeywords or [])
            for material, expected in wanted.items():
                if keywords != expected: continue
                target = ROOT / "goDot/reports/shader_evidence" / (material + ".glsl")
                target.parent.mkdir(exist_ok=True)
                target.write_text(code)
                matches.append({"material": material, "keywords": sorted(keywords), "program_index": index, "segment": segment, "offset": offset, "size": size, "code_sha256": hashlib.sha256(code.encode()).hexdigest(), "path": str(target.relative_to(ROOT))})
        row["matched_programs"] = matches
    try:
        exported = data.export()
        target = out / (name.rsplit("/", 1)[-1] + ".shader")
        target.write_text(exported)
        row.update(export_path=str(target), export_sha256=hashlib.sha256(exported.encode()).hexdigest(), export_chars=len(exported))
    except Exception as exc:
        row["export_error"] = str(exc)
    summary.append(row)
print(json.dumps(summary, indent=2))
(ROOT / "goDot/reports/environment-shader-program-evidence.json").write_text(json.dumps(summary, indent=2) + "\n")
