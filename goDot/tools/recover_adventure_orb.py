#!/usr/bin/env python3
"""Record the selected APK's adventure orb hierarchy and particle controllers."""

import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy
from UnityPy.export.ShaderConverter import ShaderSubProgram
from UnityPy.helpers import CompressionHelper
from UnityPy.streams import EndianBinaryReader

from recover_chest_effects import package_manifest, evidence_json
import inspect_new_camp_native as native
from inspect_backpack_descriptions_native import _resolve_strings


ROOT = Path(__file__).resolve().parents[2]
APK = ROOT / "1061664.apk"
TARGETS = ["EnvUnit_Interactable_RogueAdventureEvent", "EnvUnit_Interactable_RogueAdventureEvent_Special", "24071901_fx_env_void"]


def native_lifecycle():
    binary = Path("/private/tmp/city-new-map-native/libil2cpp.so")
    stubs = Path("/private/tmp/city-new-map-addresses/DiffableCs")
    with zipfile.ZipFile(APK) as archive:
        payload = archive.read("lib/arm64-v8a/libil2cpp.so")
        metadata = archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat")
    assert binary.read_bytes() == payload
    native.SELECTION = {"RogueRoomManager": ["Msg_AdventureEvent"], "EnvUnitUIInteractable": ["<Init>b__7_0", "<Init>b__7_2"]}
    native.SELECTED_OFFSETS = set()
    result = native.inspect(binary, stubs)
    _resolve_strings(result, payload, metadata)
    return result


def sphere_shader(shader, material):
    wanted = set(material.get("m_ValidKeywords", [])) | set(material.get("m_ShaderKeywords", "").split())
    blob = bytes(shader["compressedBlob"])
    programs = []
    directory = ROOT / "goDot/reports/shader_evidence/adventure_orb"
    directory.mkdir(parents=True, exist_ok=True)
    for platform, offsets, sizes, lengths in zip(shader["platforms"], shader["offsets"], shader["compressedLengths"], shader["decompressedLengths"]):
        if platform != 9:
            continue
        if not isinstance(offsets, list):
            offsets, sizes, lengths = [offsets], [sizes], [lengths]
        chunks = [CompressionHelper.decompress_lz4(blob[offset:offset + size], length) for offset, size, length in zip(offsets, sizes, lengths)]
        for index in range(struct.unpack_from("<i", chunks[0])[0]):
            offset, size, segment = struct.unpack_from("<iii", chunks[0], 4 + index * 12)
            program = ShaderSubProgram(EndianBinaryReader(chunks[segment][offset:offset + size], endian="<"))
            keywords = set(program.m_Keywords) | set(program.m_LocalKeywords or [])
            if keywords != wanted:
                continue
            code = program.m_ProgramCode.decode("utf-8")
            assert "#version" in code and "_RimIntensity" in code
            path = directory / (material["m_Name"] + "_" + str(index) + ".glsl")
            path.write_text(code)
            programs.append(dict(platform=platform, program_index=index, segment=segment, offset=offset, size=size, keywords=sorted(keywords), path=str(path.relative_to(ROOT / "goDot")), sha256=hashlib.sha256(code.encode()).hexdigest()))
    assert len(programs) == 1
    return dict(name=shader["m_ParsedForm"]["m_Name"], compressed_blob_sha256=hashlib.sha256(blob).hexdigest(), programs=programs)


def recover():
    env = UnityPy.Environment()
    provenance = []
    with zipfile.ZipFile(APK) as archive:
        member = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        payload = archive.read(member)
        manifest = package_manifest(payload)
        selected = [asset for asset in manifest["assets"] if asset["address"] in TARGETS]
        pending = {index for asset in selected for index in [asset["bundle"], *asset["deps"]]}
        indices = set()
        while pending:
            index = pending.pop()
            if index in indices:
                continue
            indices.add(index)
            pending.update(manifest["bundles"][index]["deps"])
        for index in sorted(indices):
            bundle = manifest["bundles"][index]
            name = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            raw = archive.read(name)
            env.load_file(raw, name=name)
            provenance.append(dict(index=index, member=name, sha256=hashlib.sha256(raw).hexdigest()))
    objects = {(obj.assets_file.name, obj.path_id): obj for obj in env.objects}

    def resolve(obj, pointer):
        if not pointer or not pointer.get("m_PathID"):
            return None
        file_id = pointer.get("m_FileID", 0)
        filename = obj.assets_file.name if not file_id else obj.assets_file.externals[file_id - 1].path.rsplit("/", 1)[-1]
        return objects.get((filename, pointer["m_PathID"]))

    def identity(obj):
        return str(obj.assets_file.name) + ":" + str(obj.path_id)

    prefabs = {}
    for obj in env.objects:
        if obj.type.name != "AssetBundle":
            continue
        for path, entry in obj.read_typetree().get("m_Container", []):
            target = next((asset for asset in selected if asset["path"].lower() == path.lower()), None)
            if not target:
                continue
            game_object = resolve(obj, entry["asset"])
            nodes = []

            def walk(go, parent=""):
                tree = go.read_typetree()
                path = parent + "/" + tree["m_Name"] if parent else tree["m_Name"]
                row = dict(path=path, source=identity(go), active=bool(tree["m_IsActive"]), components=[])
                transform = None
                for pointer in tree["m_Component"]:
                    component = resolve(go, pointer.get("component", pointer))
                    if component is None:
                        continue
                    value = component.read_typetree()
                    data = dict(type=component.type.name, source=identity(component))
                    if component.type.name == "Transform":
                        transform = component
                        data["value"] = {key: value[key] for key in ("m_LocalPosition", "m_LocalRotation", "m_LocalScale")}
                    elif component.type.name == "MonoBehaviour":
                        script = resolve(component, value.get("m_Script", {}))
                        data["script"] = script.read_typetree() if script else None
                        data["value"] = value
                    elif component.type.name == "ParticleSystem":
                        data["value"] = {key: child for key, child in value.items() if not key.endswith("Module") or key in ("InitialModule", "EmissionModule")}
                    elif component.type.name in ("MeshRenderer", "ParticleSystemRenderer"):
                        data["value"] = value
                    row["components"].append(data)
                nodes.append(row)
                if transform:
                    for child in transform.read_typetree().get("m_Children", []):
                        child_transform = resolve(transform, child)
                        if child_transform:
                            walk(resolve(child_transform, child_transform.read_typetree()["m_GameObject"]), path)

            walk(game_object)
            prefabs[target["address"]] = dict(asset=target, root=identity(game_object), nodes=nodes)
            names = {int(node["source"].rsplit(":", 1)[-1]): node["path"] for node in nodes}
            for node in nodes:
                for component in node["components"]:
                    if component.get("script", {}).get("m_ClassName") != "UObjectGroupMark":
                        continue
                    prefabs[target["address"]]["groups"] = {group["GroupName"]: [names[pointer["m_PathID"]] for pointer in group["GroupObjects"]] for group in component["value"]["GroupDataList"]}
    modes = {}
    for node in prefabs["24071901_fx_env_void"]["nodes"]:
        for component in node["components"]:
            if component["type"] == "ParticleSystem":
                modes[node["path"].rsplit("/", 1)[-1]] = component["value"]
    catalog_path = ROOT / "goDot/assets/environment_effects/catalog.json"
    catalog = json.loads(catalog_path.read_text())
    effect = catalog["effects"]["24071901_fx_env_void"]
    assert len(effect["layers"]) == len(modes)
    for layer in effect["layers"]:
        source = modes[layer["name"]]
        layer["ring_buffer_mode"] = source["ringBufferMode"]
        layer["ring_buffer_loop_range"] = source["ringBufferLoopRange"]
    material_object = next(obj for obj in env.objects if obj.type.name == "Material" and obj.read_typetree()["m_Name"] == "mat_fx_24071901_void_sphere")
    material = material_object.read_typetree()
    shader_object = resolve(material_object, material["m_Shader"])
    shader_evidence = sphere_shader(shader_object.read_typetree(), material)
    shader_evidence.update(material_source=identity(material_object), shader_source=identity(shader_object))
    catalog_path.write_text(json.dumps(catalog, separators=(",", ":"), allow_nan=False) + "\n")
    declaration_path = Path("/private/tmp/city-new-map-addresses/DiffableCs/UnityEngine.ParticleSystemModule/UnityEngine/ParticleSystemRingBufferMode.cs")
    declaration = dict(path=str(declaration_path), sha256=hashlib.sha256(declaration_path.read_bytes()).hexdigest(), text=declaration_path.read_text())
    result = dict(apk=str(APK), apk_sha256=hashlib.file_digest(APK.open("rb"), "sha256").hexdigest(), manifest_member=member, manifest_sha256=hashlib.sha256(payload).hexdigest(), bundles=provenance, prefabs=prefabs, ring_buffer_enum=declaration, native_lifecycle=native_lifecycle(), sphere_shader=shader_evidence, limitations=["Static Unity serialized source and APK ARM64 lifecycle; no original Android runtime was executed."])
    output = ROOT / "goDot/reports/adventure-orb-apk-20261028.json"
    output.write_text(json.dumps(evidence_json(result), indent=2) + "\n")
    print(json.dumps({"output": str(output), "prefabs": {key: len(value["nodes"]) for key, value in prefabs.items()}, "ring_buffer_layers": {name: value["ringBufferMode"] for name, value in modes.items()}}, indent=2))


if __name__ == "__main__":
    recover()
