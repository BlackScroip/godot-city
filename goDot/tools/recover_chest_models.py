#!/usr/bin/env python3
"""Recover the selected APK's chest geometry, material inputs and opening clip."""

import argparse
import gc
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import numpy as np
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader
from UnityPy.export.ShaderConverter import ShaderSubProgram

from recover_chest_effects import APK_SHA, evidence_json, package_manifest
from recover_region_actors import ActorExporter


ROOT = Path(__file__).resolve().parents[1]
QUALITIES = ("Normal", "Unusual", "Luxury", "Curse")


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


class ChestExporter(ActorExporter):
    def __init__(self, *args, output):
        super().__init__(*args)
        self.output = output
        self.chest_materials = {}
        self.shaders = {}
        model = next(ident for ident in self.transforms if self.path(ident)[-1] == "Box_Model")
        model_path = self.path(model)
        # Runtime particle restoration owns Box_Effect. Keeping its named empty
        # transforms in the model would make the scene scanner bind it twice.
        keep_transforms = {ident for ident in self.transforms if ident == self.root_transform or self.path(ident)[:len(model_path)] == model_path}
        keep_games = {self.transforms[ident]["m_GameObject"]["m_PathID"] for ident in keep_transforms}
        keep_components = {entry["component"]["m_PathID"] for ident in keep_games for entry in self.games[ident]["m_Component"]}
        self.objects = {ident: obj for ident, obj in self.objects.items() if ident in keep_games | keep_components}
        self.raw = {ident: raw for ident, raw in self.raw.items() if ident in self.objects}
        self.games = {ident: game for ident, game in self.games.items() if ident in keep_games}
        self.transforms = {ident: transform for ident, transform in self.transforms.items() if ident in keep_transforms}
        self.game_transform = {game: transform for game, transform in self.game_transform.items() if transform in keep_transforms}

    def source_texture(self, pointer):
        identity = self.identity(pointer)
        if identity not in self.external_textures:
            texture = pointer.read()
            target = self.output / ("texture_" + sha(identity.encode())[:20] + ".png")
            texture.image.save(target)
            self.external_textures[identity] = {
                "path": "res://" + target.relative_to(ROOT).as_posix(),
                "name": texture.m_Name, "source": identity,
                "sha256": sha(target.read_bytes()),
            }
        return self.external_textures[identity]

    def material(self, pointer):
        index = super().material(pointer)
        if not pointer.path_id:
            return index
        identity = self.identity(pointer)
        if identity in self.chest_materials:
            return index
        raw = pointer.read_typetree()
        saved = raw["m_SavedProperties"]
        floats, colors, textures = [dict(saved[key]) for key in ("m_Floats", "m_Colors", "m_TexEnvs")]
        recovered = {}
        for name, texture in textures.items():
            if texture["m_Texture"].get("m_PathID"):
                recovered[name] = dict(self.source_texture(self.pointer(pointer.deref(), texture["m_Texture"])),
                                       scale=texture["m_Scale"], offset=texture["m_Offset"])
        shader_pointer = self.pointer(pointer.deref(), raw["m_Shader"])
        shader = shader_pointer.read_typetree()
        shader_name = shader.get("m_ParsedForm", {}).get("m_Name", shader.get("m_Name", ""))
        keywords = sorted(set(raw.get("m_ValidKeywords", [])) | set(raw.get("m_ShaderKeywords", "").split()))
        self.chest_materials[identity] = dict(name=raw["m_Name"], source=identity, shader=shader_name,
                                              shader_source=self.identity(shader_pointer), keywords=keywords,
                                              textures=recovered, floats=floats, colors=colors)
        self.shaders[self.identity(shader_pointer)] = shader
        return index

    def opening_clip(self):
        component = next(obj for obj in self.objects.values() if obj.type.name == "Animation")
        pointer = self.pointer(component, self.raw[component.path_id]["m_Animations"][0])
        raw = pointer.read_typetree()
        assert raw["m_Name"] == "anim_treasurebox_openthendisappear"
        return dict(source=self.identity(pointer), name=raw["m_Name"],
                    euler_curves=raw["m_EulerCurves"], float_curves=raw["m_FloatCurves"],
                    sample_rate=raw.get("m_SampleRate", 60),
                    settings=raw.get("m_AnimationClipSettings", {}))


def shader_evidence(tree, identity, expected, output, name="chest_omnishade_source"):
    """Retain a readable source-variant program, including its keyword delta."""
    blob = bytes(tree["compressedBlob"])
    candidates = []
    for platform, offsets, sizes, expanded in zip(tree["platforms"], tree["offsets"], tree["compressedLengths"], tree["decompressedLengths"]):
        if not isinstance(offsets, list):
            offsets, sizes, expanded = [offsets], [sizes], [expanded]
        chunks = [CompressionHelper.decompress_lz4(blob[offset:offset + size], length)
                  for offset, size, length in zip(offsets, sizes, expanded)]
        for index in range(struct.unpack_from("<i", chunks[0])[0]):
            offset, size, segment = struct.unpack_from("<iii", chunks[0], 4 + index * 12)
            try:
                program = ShaderSubProgram(EndianBinaryReader(chunks[segment][offset:offset + size], endian="<"))
                code = program.m_ProgramCode.decode("utf-8")
            except (ValueError, UnicodeDecodeError, EOFError, NotImplementedError, struct.error):
                continue
            keywords = set(program.m_Keywords) | set(program.m_LocalKeywords or [])
            if "#version" not in code or "RIM" not in keywords or "_RimAmount" not in code:
                continue
            candidates.append((len(expected ^ keywords), platform, index, segment, offset, size, keywords, code))
    if not candidates:
        return dict(source=identity, status="no_readable_rim_variant")
    mismatch, platform, index, segment, offset, size, keywords, code = min(candidates, key=lambda row: row[0])
    target = output / (name + ".glsl")
    target.write_text(code)
    return dict(source=identity, program_index=index, platform=platform, segment=segment,
                segment_offset=offset, segment_size=size, keywords=sorted(keywords),
                material_keyword_delta=sorted(expected ^ keywords), code_sha256=sha(code.encode()),
                path="res://" + target.relative_to(ROOT).as_posix())


def recover(args):
    args.output.mkdir(parents=True, exist_ok=True)
    apk_digest = hashlib.file_digest(args.apk.open("rb"), "sha256").hexdigest()
    assert apk_digest == APK_SHA, "This recovery is bound to the selected 1061664.apk"
    catalog = dict(apk_sha256=apk_digest, models={}, materials={}, animation={})
    report = dict(apk_sha256=apk_digest, prefabs={}, limitations=[
        "Static APK extraction; original APK execution was not observed.",
        "Godot retains source geometry, transforms, textures, rim/emissive values and Euler curve keys; engine lighting remains renderer-dependent.",
    ])
    with zipfile.ZipFile(args.apk) as archive:
        member = next(path for path in archive.namelist() if path.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and path.endswith(".bytes"))
        manifest_raw = archive.read(member)
        manifest = package_manifest(manifest_raw)
        report["manifest"] = dict(member=member, sha256=sha(manifest_raw))
        for quality in QUALITIES:
            exporter = ChestExporter(archive, manifest_raw, manifest["assets"], manifest["bundles"],
                                     "EnvUnit_TreasureBox_" + quality, output=args.output)
            exporter.build()
            target = args.output / (quality.lower() + ".glb")
            exporter.write(target)
            clip = exporter.opening_clip()
            if not catalog["animation"]:
                catalog["animation"] = evidence_json(clip)
                shader_id, shader = next(iter(exporter.shaders.items()))
                expected = set(next(iter(exporter.chest_materials.values()))["keywords"])
                report["shader_evidence"] = shader_evidence(shader, shader_id, expected, args.output)
            else:
                assert catalog["animation"] == evidence_json(clip), "Chest variant clip differs"
            if quality == "Curse":
                shader_id, shader = next(iter(exporter.shaders.items()))
                expected = set(next(iter(exporter.chest_materials.values()))["keywords"])
                report["normal_map_shader_evidence"] = shader_evidence(shader, shader_id, expected, args.output, "chest_omnishade_normal_source")
            low, high = [operation([value[i] for value in exporter.bounds], axis=0).tolist()
                         for i, operation in enumerate((np.min, np.max))]
            catalog["models"][quality] = dict(path="res://" + target.relative_to(ROOT).as_posix(),
                                               prefab=exporter.asset["address"],
                                               model_sha256=sha(target.read_bytes()),
                                               materials=list(exporter.chest_materials.values()),
                                               bounds=dict(min=low, max=high), meshes=len(exporter.data["meshes"]),
                                               lid_path="Box_Model/Model/Top")
            report["prefabs"][quality] = dict(asset=exporter.asset, bundles=exporter.bundle_evidence,
                                              renderers=exporter.renderer_evidence,
                                              materials=list(exporter.chest_materials.values()),
                                              model=catalog["models"][quality]["path"],
                                              model_sha256=sha(target.read_bytes()))
            print(json.dumps(dict(quality=quality, meshes=len(exporter.data["meshes"]), textures=len(exporter.external_textures), bytes=target.stat().st_size)), flush=True)
            for method in (exporter.world, exporter.active, exporter.path, exporter.sibling_path):
                method.cache_clear()
            del exporter
            gc.collect()
    catalog["models"]["Curse_Final"] = dict(catalog["models"]["Curse"], rendering_alias="Curse")
    catalog.pop("materials")
    (args.output / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    args.report.write_text(json.dumps(evidence_json(report), ensure_ascii=False, indent=2, allow_nan=False) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT.parent / "1061664.apk")
    parser.add_argument("--output", type=Path, default=ROOT / "assets/chests")
    parser.add_argument("--report", type=Path, default=ROOT / "reports/chest-model-source-20261028.json")
    recover(parser.parse_args())
