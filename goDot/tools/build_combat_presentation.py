#!/usr/bin/env python3
"""Recover presentation references; particle curves/shaders are rebuilt in Godot."""
import hashlib
import json
from pathlib import Path
import re
import shutil
from functools import lru_cache

import yaml

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "goDot/assets/combat_presentation"
OFFLINE = ROOT / "OfflineUnity/Assets"
SOURCE = ROOT / "RecoveredUnity/ExportedProject/Assets"
HEADER = re.compile(r"^--- !u!(\d+) &(-?\d+).*$", re.M)


def documents(path):
    text = path.read_text()
    text = re.sub(r"^%.*\n", "", text, flags=re.M)
    text = re.sub(r"^--- !u!\d+ &-?\d+.*$", "---", text, flags=re.M)
    return list(yaml.load_all(text, Loader=yaml.CSafeLoader))


def references(value):
    if isinstance(value, dict):
        if value.get("guid"): yield value["guid"]
        for child in value.values(): yield from references(child)
    elif isinstance(value, list):
        for child in value: yield from references(child)


def compact(value):
    if isinstance(value, dict):
        if "time" in value and "value" in value:
            return {key: value[key] for key in ("time", "value", "inSlope", "outSlope") if key in value}
        omitted = {"serializedVersion", "m_PreInfinity", "m_PostInfinity", "m_RotationOrder"}
        state = value.get("minMaxState")
        if state in (0, 2): omitted.update(("minCurve", "maxCurve"))
        if state in (0, 2) and "maxColor" in value: omitted.update(("minGradient", "maxGradient"))
        if state == 0: omitted.update(("minScalar", "minColor"))
        if state == 1: omitted.update(("minCurve", "minGradient", "minColor", "maxColor"))
        if "m_NumColorKeys" in value:
            color_count, alpha_count = value["m_NumColorKeys"], value.get("m_NumAlphaKeys", 0)
            for number in range(8):
                if number >= max(color_count, alpha_count): omitted.add("key" + str(number))
                if number >= color_count: omitted.add("ctime" + str(number))
                if number >= alpha_count: omitted.add("atime" + str(number))
        return {k: compact(v) for k, v in value.items() if k not in omitted}
    if isinstance(value, list): return [compact(v) for v in value]
    return value


def bindings(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if isinstance(child, str) and ("effect" in key.lower() or "prefab" in key.lower()) and not any(token in key.lower() for token in ("effectid", "property", "playtype", "animname", "followbufflayer")):
                if child and child.lower() not in ("none", "null") and not child.lower().startswith("ecet_"):
                    yield child.replace("\\", "/").split("/")[-1].removesuffix(".prefab").lower()
            yield from bindings(child)
    elif isinstance(value, list):
        for child in value: yield from bindings(child)
    elif isinstance(value, str) and value.lstrip().startswith(("{", "[")):
        try:
            decoded = json.loads(value)
        except (ValueError, TypeError):
            return
        yield from bindings(decoded)


def properties(value):
    if isinstance(value, dict): return value
    return {key: item for row in value or [] for key, item in row.items()}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    index = {}
    # Recovered originals take precedence over offline Unity reconstructions.
    for folder in ["Effects", "Audio"]:
        for meta in (OFFLINE / folder).rglob("*.meta"):
            data = yaml.load(meta.read_text(), Loader=yaml.CSafeLoader)
            if data and data.get("guid"): index[data["guid"]] = meta.with_suffix("")
    prefabs = {}
    for meta in SOURCE.rglob("*.meta"):
        match = re.search(r"^guid: ([0-9a-f]{32})$", meta.read_text(), re.M)
        if match: index[match[1]] = meta.with_suffix("")
        if meta.name.endswith(".prefab.meta"):
            prefabs.setdefault(meta.with_suffix("").stem.lower(), []).append(meta.with_suffix(""))
    catalog = json.loads((ROOT / "goDot/assets/catalog.json").read_text())
    textures = {}

    def texture(path):
        key = hashlib.sha256(path.read_bytes()).hexdigest()[:20] + path.suffix.lower()
        target = OUT / key
        if not target.exists(): shutil.copyfile(path, target)
        textures[key] = str(path.relative_to(ROOT))
        return "res://assets/combat_presentation/" + key

    effects = {}
    meshes = {}
    material_properties = {}

    @lru_cache(maxsize=2048)
    def material_data(path):
        material = documents(path)[0].get("Material", {})
        saved = material.get("m_SavedProperties", {})
        floats, colors = properties(saved.get("m_Floats")), properties(saved.get("m_Colors"))
        maps = []
        for name, env in properties(saved.get("m_TexEnvs")).items():
            source = index.get(env.get("m_Texture", {}).get("guid"))
            if source and source.suffix.lower() in (".png", ".jpg", ".jpeg", ".tga"):
                maps.append(dict(property=name, texture=texture(source), scale=env.get("m_Scale", {}), offset=env.get("m_Offset", {})))
        primary = next((item for item in maps if item["property"] in ("_MainTex", "_BaseMap", "_BaseColorMap")), {})
        shader = index.get(material.get("m_Shader", {}).get("guid"))
        # Blend is sourced from serialized GPU factors; shader names are not a proxy.
        src, dst = floats.get("_SrcBlend", floats.get("_SrcMode")), floats.get("_DstBlend", floats.get("_DstMode"))
        blend = "add" if dst == 1 and src in (1, 5) else "alpha" if dst == 10 and src in (1, 5) else "unknown"
        source_id = str(path.relative_to(ROOT))
        material_properties[source_id] = dict(source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), textures=maps, blend_factors={"src": src, "dst": dst}, unsupported="Custom shader float/color parameters retained in source material, not executed by Godot")
        all_in_one = bool(shader and "allin1" in str(shader).lower())
        shape_alpha_weight = floats.get("_ShapeAlphaWeight", 0)
        # Recovered shader bodies are placeholders. Luminance masking is a
        # reconstruction decision, not a recovered original fragment equation.
        return dict(source=source_id, texture=primary.get("texture", ""), texture_scale=primary.get("scale", {}), texture_offset=primary.get("offset", {}), textures=maps, color=colors.get("_TintColor", colors.get("_Color", colors.get("_BaseColor", {"r":1,"g":1,"b":1,"a":1}))), shape_color=colors.get("_ShapeColor", colors.get("_Color", {"r":1,"g":1,"b":1,"a":1})), alpha_from_luminance=all_in_one and shape_alpha_weight > 0, alpha=floats.get("_Alpha", 1), glow=floats.get("_Glow", 0), glow_global=floats.get("_GlowGlobal", 1), shape_alpha_weight=shape_alpha_weight, shape_brightness=floats.get("_ShapeBrightness", 0), blend=blend, shader=str(shader.relative_to(ROOT)) if shader else material.get("m_Shader", {}))

    def mesh_asset(ref):
        if not ref.get("fileID"): return ""
        key = hashlib.sha256(json.dumps(ref, sort_keys=True).encode()).hexdigest()[:20]
        if key in meshes: return meshes[key]
        import convert_unity as converter
        converter.INDEX.update(index)
        target = OUT / ("mesh_" + key + ".glb")
        if target.exists():
            meshes[key] = "res://assets/combat_presentation/" + target.name
            return meshes[key]
        writer = converter.Gltf(target)
        try:
            geometry, _ = writer.geometry(ref, [])
            if geometry is None: return ""
            writer.data["nodes"].append({"mesh": geometry})
            writer.data["scenes"][0]["nodes"] = [0]
            writer.save()
            meshes[key] = "res://assets/combat_presentation/" + target.name
        except (ValueError, KeyError, TypeError, IndexError, OSError):
            meshes[key] = ""
        return meshes.get(key, "")

    def export_effect(path):
        text = path.read_text()
        ids = [int(mark[2]) for mark in HEADER.finditer(text)]
        docs = documents(path)
        objects = {ident: next(iter(doc.values())) for ident, doc in zip(ids, docs)}
        types = {ident: next(iter(doc)) for ident, doc in zip(ids, docs)}
        transforms = {obj.get("m_GameObject", {}).get("fileID"): ident for ident, obj in objects.items() if types[ident] == "Transform"}
        renderers = {obj.get("m_GameObject", {}).get("fileID"): obj for ident, obj in objects.items() if types[ident] == "ParticleSystemRenderer"}
        layers, maps, unsupported = [], [], set()
        for ident, system in objects.items():
            if types[ident] != "ParticleSystem": continue
            go = system.get("m_GameObject", {}).get("fileID")
            renderer = renderers.get(go, {})
            transform_id, chain, visited = transforms.get(go), [], set()
            active = True
            while transform_id in objects and transform_id not in visited:
                visited.add(transform_id)
                tr = objects[transform_id]
                active = active and bool(objects.get(tr.get("m_GameObject", {}).get("fileID"), {}).get("m_IsActive", 1))
                chain.insert(0, dict(position=tr.get("m_LocalPosition", {}), rotation=tr.get("m_LocalRotation", {}), scale=tr.get("m_LocalScale", {})))
                transform_id = tr.get("m_Father", {}).get("fileID")
            materials = [material_data(index[guid]) for guid in references(renderer.get("m_Materials", [])) if guid in index]
            for mat in materials:
                for item in mat["textures"]:
                    if item["texture"] not in maps: maps.append(item["texture"])
            modules = {key: compact(value) for key, value in system.items() if key.endswith("Module") and key not in ("InitialModule", "EmissionModule", "ShapeModule") and isinstance(value, dict) and value.get("enabled")}
            unresolved = [key for key in modules if key not in ("ColorModule", "SizeModule", "RotationModule", "VelocityModule", "UVModule")]
            modules = {key: value for key, value in modules.items() if key not in unresolved}
            if any(mat["blend"] == "unknown" for mat in materials): unresolved.append("shader_blend_not_serialized")
            if materials: unresolved.append("custom_shader_equivalence_not_verified")
            if renderer.get("m_Enabled", 0) and renderer.get("m_Materials") and not materials:
                unresolved.append("renderer_material_unresolved")
            mesh_ref = renderer.get("m_Mesh", {})
            mesh = mesh_asset(mesh_ref) if renderer.get("m_RenderMode") == 4 else ""
            if renderer.get("m_RenderMode") == 4 and not mesh: unresolved.append("mesh_unresolved")
            unsupported.update(unresolved)
            materials = [{key: value for key, value in mat.items() if key != "textures"} for mat in materials]
            shape = system.get("ShapeModule", {})
            shape_fields = ("enabled", "type", "angle", "length", "m_Position", "m_Rotation", "m_Scale", "radius", "arc", "radiusThickness", "donutRadius", "boxThickness", "randomDirectionAmount", "sphericalDirectionAmount", "randomPositionAmount", "alignToDirection", "m_Mesh")
            shape = {key: compact(value) for key, value in shape.items() if key in shape_fields} if shape.get("enabled") else {"enabled": 0}
            layers.append(dict(name=objects.get(go, {}).get("m_Name", str(ident)), source_file_id=str(ident), active=active, transform_chain=chain, duration=system.get("lengthInSec", 1), simulation_speed=system.get("simulationSpeed", 1), looping=bool(system.get("looping")), start_delay=compact(system.get("startDelay", {})), simulation_space=system.get("moveWithTransform", 0), initial=compact(system.get("InitialModule", {})), emission=compact(system.get("EmissionModule", {})), shape=shape, modules=modules, renderer=dict(enabled=bool(renderer) and bool(renderer.get("m_Enabled", 1)), has_renderer=bool(renderer), material_slot_count=len(renderer.get("m_Materials", [])), render_mode=renderer.get("m_RenderMode", 0), length_scale=renderer.get("m_LengthScale", 1), velocity_scale=renderer.get("m_VelocityScale", 0), alignment=renderer.get("m_RenderAlignment", 0)), materials=materials, mesh=mesh, mesh_reference=mesh_ref, unsupported=unresolved))
        for ident, kind in types.items():
            if kind in ("MonoBehaviour", "Animator", "Animation", "TrailRenderer", "MeshRenderer", "SkinnedMeshRenderer"):
                unsupported.add(kind)
        return dict(source=str(path.relative_to(ROOT)), source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), textures=maps, particle_systems=len(layers), layers=layers, unsupported=sorted(unsupported), mode="source-bound Unity particle layers; Godot runtime approximation")
    entries = documents(OFFLINE / "Effects/Resources/OfflineEffectCatalog.asset")[0]["MonoBehaviour"]["entries"]
    for entry in entries:
        prefab = index.get(entry["prefab"]["guid"])
        if not prefab: continue
        docs = documents(prefab)
        maps = []
        for doc in docs:
            renderer = doc.get("ParticleSystemRenderer", {})
            for guid in references(renderer.get("m_Materials", [])):
                material_path = index.get(guid)
                if not material_path: continue
                material = documents(material_path)[0].get("Material", {})
                envs = material.get("m_SavedProperties", {}).get("m_TexEnvs", [])
                if isinstance(envs, dict): envs = [envs]
                for env in envs:
                    for name, value in env.items():
                        if name not in ["_MainTex", "_BaseMap", "_BaseColorMap"]: continue
                        source = index.get(value.get("m_Texture", {}).get("guid"))
                        if source and source.suffix.lower() in [".png", ".jpg", ".tga"]:
                            ref = texture(source)
                            if ref not in maps: maps.append(ref)
        effects[entry["name"].lower()] = {"source": entry["source"], "textures": maps[:3], "particle_systems": entry.get("particleSystems", 0), "mode": "reconstructed Godot emission and geometry; recovered textures"}
    requested = set(bindings(json.loads((ROOT / "goDot/assets/data/combat.json").read_text())))
    visual_report = ROOT / "goDot/reports/feel-visual.json"
    if visual_report.exists(): requested.update(json.loads(visual_report.read_text()).get("missing", []))
    requested.difference_update(("triggereffectname_delay", "triggereffectname_nodelay"))
    missing = []
    for name in sorted(set(effects) | requested):
        candidates = prefabs.get(name, [])
        if candidates and name in requested:
            selected = sorted(candidates, key=lambda path: ("/FX/" not in str(path), str(path)))[0]
            effects[name] = export_effect(selected)
            if len(candidates) > 1: effects[name]["source_candidates"] = [str(path.relative_to(ROOT)) for path in candidates]
        elif not candidates and name in requested:
            missing.append(name)
    audio = {}
    entries = documents(OFFLINE / "Audio/Resources/OfflineAudioCatalog.asset")[0]["MonoBehaviour"]["entries"]
    for entry in entries:
        layers = []
        for layer in entry.get("layers", []):
            clips = []
            for clip in layer.get("clips", []):
                source = index.get(clip.get("guid"))
                if source and source.stem in catalog["audio"]: clips.append(catalog["audio"][source.stem])
            if clips: layers.append({"clips": clips, "volume": layer.get("volume", 1), "pitch": layer.get("pitch", 1) * layer.get("sourcePitch", 1), "delay": layer.get("delay", 0)})
        if layers:
            audio[entry["name"].lower()] = layers
            for alias in entry.get("aliases", []): audio[str(alias).removesuffix(".prefab").lower()] = layers
    result = {"schema": 2, "effects": effects, "audio": audio, "texture_sources": textures, "material_properties": material_properties, "requested_effects": sorted(requested), "missing_effects": missing, "limitations": ["Static recovered Unity YAML is source evidence, not observation of original APK runtime.", "Original particle transforms, curves, materials and mesh geometry are preserved; custom shaders, scripted effect controllers and unsupported modules still require Godot approximations.", "Layer transform_chain is Unity local TRS from root to emitter; runtime must convert coordinates consistently.", "Missing references are listed explicitly; names are not used to infer original effect appearance.", "Inactive min/max curve branches and Unity serialization metadata are omitted; full material properties are shared by source path."]}
    result["limitations"].append("alpha_from_luminance is a Godot reconstruction choice for AllIn1 shape-alpha materials. Recovered shader source exposes Shape1 A Weight but its fragment body is a placeholder; the original alpha equation is not recovered.")
    (OUT / "catalog.json").write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(json.dumps({"effects": len(effects), "audio": len(audio), "textures": len(textures)}))


if __name__ == "__main__": main()
