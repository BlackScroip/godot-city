#!/usr/bin/env python3
"""Export source-bound Unity environment particle definitions directly from APK."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "goDot/assets/environment_effects"


def finite_json(value):
    if isinstance(value, float) and not math.isfinite(value): return 0.0
    if isinstance(value, dict): return {k: finite_json(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)): return [finite_json(v) for v in value]
    return value


def compact(value):
    if isinstance(value, dict):
        if "time" in value and "value" in value:
            return {k: value[k] for k in ("time", "value", "inSlope", "outSlope") if k in value}
        omitted = {"serializedVersion", "m_PreInfinity", "m_PostInfinity", "m_RotationOrder"}
        state = value.get("minMaxState")
        if state in (0, 2): omitted.update(("minCurve", "maxCurve"))
        if state in (0, 2) and "maxColor" in value: omitted.update(("minGradient", "maxGradient"))
        if state == 0: omitted.update(("minScalar", "minColor"))
        if state == 1: omitted.update(("minCurve", "minGradient", "minColor", "maxColor"))
        return {k: compact(v) for k, v in value.items() if k not in omitted}
    if isinstance(value, (list, tuple)): return [compact(v) for v in value]
    return value


def properties(value):
    return value if isinstance(value, dict) else dict(value or [])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "com.teamelo.dungeonchasers.apk")
    parser.add_argument("--manifest", type=Path, default=Path("/private/tmp/city-charge-assets/manifest.json"))
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    additional = {"23121501_fx_other_propblue", "23122101_fx_other_treasureboxyellow", "23121501_fx_other_proppurple", "23121501_fx_other_proppurpleappear", "23122101_fx_other_treasureboxcurse", "23122101_fx_other_treasureboxcurseopen", "25020601_fx_other_liulangshangren"}
    assets = [a for a in manifest["assets"] if "/FX/Env/" in a["path"] or a["address"] in additional]
    embedded = {"envunit_destoryable_lode_gold": "25021101_fx_env_lodegold_aura",
                "envunit_destoryable_lode_magicpoint": "25021102_fx_env_lodemagicpoint_aura",
                "envunit_destoryable_mine_material1": "25021201_fx_env_moonstone_aura",
                "envunit_destoryable_mine_material2": "25021202_fx_env_topaz_aura"}
    for asset in manifest["assets"]:
        if asset["address"].lower() in embedded:
            assets.append(dict(asset, address=embedded[asset["address"].lower()], subroot=embedded[asset["address"].lower()]))
    indices = sorted({i for a in assets for i in [a["bundle"], *a["deps"]]})
    OUT.mkdir(parents=True, exist_ok=True)
    env = UnityPy.Environment()
    bundles, files_by_bundle = {}, {}
    with zipfile.ZipFile(args.apk) as archive:
        for index in indices:
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"
            raw = archive.read(member)
            bundle = env.load_file(raw, name=member)
            files_by_bundle[index] = list(bundle.files.values())
            bundles[index] = {"member": member, "sha256": hashlib.sha256(raw).hexdigest()}
    objects = {(o.assets_file.name, o.path_id): o for o in env.objects}
    trees, materials, textures, meshes, errors = {}, {}, {}, {}, []

    def key(obj): return (obj.assets_file.name, obj.path_id)

    def tree(obj):
        if obj is None: return {}
        ident = key(obj)
        if ident not in trees: trees[ident] = obj.read_typetree()
        return trees[ident]

    def resolve(obj, ref):
        if not ref or not ref.get("m_PathID"): return None
        file_id = ref.get("m_FileID", 0)
        filename = obj.assets_file.name if not file_id else obj.assets_file.externals[file_id - 1].path.rsplit("/", 1)[-1]
        return objects.get((filename, ref["m_PathID"]))

    def source(obj): return "%s:%s" % key(obj)

    def texture(obj):
        if obj is None: return ""
        ident = source(obj)
        if ident in textures: return textures[ident]["resource"]
        filename = "texture_" + hashlib.sha256(ident.encode()).hexdigest()[:20] + ".png"
        try:
            data = obj.read()
            data.image.save(OUT / filename)
            textures[ident] = {"name": data.m_Name, "resource": "res://assets/environment_effects/" + filename,
                               "sha256": hashlib.sha256((OUT / filename).read_bytes()).hexdigest()}
            return textures[ident]["resource"]
        except Exception as exc:
            errors.append({"source": ident, "type": "texture", "error": str(exc)})
            return ""

    def material(obj):
        if obj is None: return None
        ident = source(obj)
        if ident in materials: return materials[ident]
        data = tree(obj)
        saved = data.get("m_SavedProperties", {})
        floats = properties(saved.get("m_Floats"))
        colors = properties(saved.get("m_Colors"))
        maps = []
        for name, value in properties(saved.get("m_TexEnvs")).items():
            resource = texture(resolve(obj, value.get("m_Texture")))
            if resource: maps.append({"property": name, "texture": resource, "scale": value.get("m_Scale", {}), "offset": value.get("m_Offset", {})})
        primary = next((t for t in maps if t["property"] in ("_MainTex", "_BaseMap", "_BaseColorMap", "_ShapeTexture")), maps[0] if maps else {})
        shader_obj = resolve(obj, data.get("m_Shader"))
        shader = tree(shader_obj)
        shader_name = shader.get("m_Name", shader.get("m_ParsedForm", {}).get("m_Name", ""))
        src = floats.get("_SrcBlend", floats.get("_SrcMode"))
        dst = floats.get("_DstBlend", floats.get("_DstMode"))
        blend = "add" if dst == 1 and src in (1, 5) else "alpha" if dst == 10 and src in (1, 5) else "unknown"
        white = {"r": 1, "g": 1, "b": 1, "a": 1}
        result = {"source": ident, "name": data.get("m_Name", ""), "texture": primary.get("texture", ""),
                  "texture_scale": primary.get("scale", {}), "texture_offset": primary.get("offset", {}),
                  "color": colors.get("_TintColor", colors.get("_Color", colors.get("_BaseColor", white))),
                  "shape_color": colors.get("_ShapeColor", colors.get("_Color", white)),
                  "alpha_from_luminance": "allin1" in shader_name.lower() and floats.get("_ShapeAlphaWeight", 0) > 0,
                  "alpha": floats.get("_Alpha", 1), "glow": floats.get("_Glow", 0), "glow_global": floats.get("_GlowGlobal", 1),
                  "shape_alpha_weight": floats.get("_ShapeAlphaWeight", 0), "shape_brightness": floats.get("_ShapeBrightness", 0),
                  "blend": blend, "shader": shader_name, "textures": maps, "source_floats": floats, "source_colors": colors}
        materials[ident] = result
        return result

    def mesh(obj):
        if obj is None: return ""
        ident = source(obj)
        if ident in meshes: return meshes[ident]
        filename = "mesh_" + hashlib.sha256(ident.encode()).hexdigest()[:20] + ".obj"
        try:
            data = obj.read()
            handler = MeshHandler(data)
            handler.process()
            lines = ["g source_mesh"]
            # Preserve numeric Unity coordinates, matching scene import and layer transforms.
            lines += ["v %.9g %.9g %.9g" % tuple(v[:3]) for v in handler.m_Vertices]
            uv, normals = handler.m_UV0, handler.m_Normals
            if uv: lines += ["vt %.9g %.9g" % tuple(v[:2]) for v in uv]
            if normals: lines += ["vn %.9g %.9g %.9g" % tuple(v[:3]) for v in normals]
            def face(i):
                i += 1
                return f"{i}/{i}/{i}" if uv and normals else f"{i}/{i}" if uv else f"{i}//{i}" if normals else str(i)
            for triangles in handler.get_triangles():
                lines += ["f " + " ".join(face(i) for i in tri) for tri in triangles]
            (OUT / filename).write_text("\n".join(lines) + "\n")
            meshes[ident] = "res://assets/environment_effects/" + filename
        except Exception as exc:
            errors.append({"source": ident, "type": "mesh", "error": str(exc)})
            meshes[ident] = ""
        return meshes[ident]

    effects = {}
    for asset in assets:
        bundle_objects = [o for f in files_by_bundle[asset["bundle"]] if hasattr(f, "objects") for o in f.objects.values()]
        root = None
        for obj in bundle_objects:
            if obj.type.name != "AssetBundle": continue
            for path, entry in properties(tree(obj).get("m_Container")).items():
                if path.lower() == asset["path"].lower(): root = resolve(obj, entry["asset"])
        if root is None: raise RuntimeError("Missing root: " + asset["address"])
        if asset.get("subroot"):
            candidates = [o for o in bundle_objects if o.type.name == "GameObject" and tree(o).get("m_Name", "").lower() == asset["subroot"]]
            if len(candidates) != 1: raise RuntimeError("Ambiguous embedded root: " + asset["subroot"] + " " + str(len(candidates)))
            root = candidates[0]
        layers, unsupported, visited = [], set(), set()

        def walk(go, chain, inherited_active, is_root=False):
            if go is None or key(go) in visited: return
            visited.add(key(go))
            data = tree(go)
            active = inherited_active and bool(data.get("m_IsActive", True))
            components = [resolve(go, c.get("component", c)) for c in data.get("m_Component", [])]
            by_type = {c.type.name: c for c in components if c}
            transform = by_type.get("Transform")
            tr = tree(transform)
            if not is_root:
                chain = chain + [{"position": tr.get("m_LocalPosition", {}), "rotation": tr.get("m_LocalRotation", {}), "scale": tr.get("m_LocalScale", {})}]
            ps = by_type.get("ParticleSystem")
            renderer_obj = by_type.get("ParticleSystemRenderer")
            renderer = tree(renderer_obj)
            if ps:
                system = tree(ps)
                mats = [material(resolve(renderer_obj, ref)) for ref in renderer.get("m_Materials", [])]
                mats = [m for m in mats if m]
                modules = {k: compact(v) for k, v in system.items() if k.endswith("Module") and k not in ("InitialModule", "EmissionModule", "ShapeModule") and isinstance(v, dict) and v.get("enabled")}
                unresolved = [k for k in modules if k not in ("ColorModule", "SizeModule", "RotationModule", "VelocityModule", "UVModule")]
                mesh_resource = mesh(resolve(renderer_obj, renderer.get("m_Mesh"))) if renderer.get("m_RenderMode") == 4 else ""
                if renderer.get("m_RenderMode") == 4 and not mesh_resource: unresolved.append("mesh_unresolved")
                if any(m["blend"] == "unknown" for m in mats): unresolved.append("shader_blend_not_serialized")
                if mats: unresolved.append("custom_shader_equivalence_not_verified")
                if renderer and renderer.get("m_Materials") and not mats: unresolved.append("renderer_material_unresolved")
                unsupported.update(unresolved)
                layers.append({"name": data.get("m_Name", ""), "source_file_id": str(ps.path_id), "active": active,
                    "transform_chain": chain, "duration": system.get("lengthInSec", 1), "simulation_speed": system.get("simulationSpeed", 1),
                    "looping": bool(system.get("looping")), "play_on_awake": bool(system.get("playOnAwake")), "prewarm": bool(system.get("prewarm")),
                    "start_delay": compact(system.get("startDelay", {})), "simulation_space": system.get("moveWithTransform", 0),
                    "initial": compact(system.get("InitialModule", {})), "emission": compact(system.get("EmissionModule", {})),
                    "shape": compact(system.get("ShapeModule", {})), "modules": modules,
                    "renderer": {"enabled": bool(renderer) and bool(renderer.get("m_Enabled", 1)), "has_renderer": bool(renderer),
                    "material_slot_count": len(renderer.get("m_Materials", [])), "render_mode": renderer.get("m_RenderMode", 0),
                    "length_scale": renderer.get("m_LengthScale", 1), "velocity_scale": renderer.get("m_VelocityScale", 0), "alignment": renderer.get("m_RenderAlignment", 0)},
                    "materials": [{k: v for k, v in m.items() if k not in ("textures", "source_floats", "source_colors")} for m in mats],
                    "mesh": mesh_resource, "unsupported": unresolved})
            for kind in by_type:
                if kind in ("MonoBehaviour", "Animator", "Animation", "TrailRenderer", "MeshRenderer", "SkinnedMeshRenderer"): unsupported.add(kind)
            for child_ref in tr.get("m_Children", []):
                child_tr = resolve(transform, child_ref)
                walk(resolve(child_tr, tree(child_tr).get("m_GameObject")), chain, active)

        walk(root, [], True, True)
        effects[asset["address"].lower()] = {"source": asset["path"], "source_sha256": bundles[asset["bundle"]]["sha256"],
            "source_root": source(root), "particle_systems": len(layers), "layers": layers,
            "textures": sorted({m["texture"] for layer in layers for m in layer["materials"] if m["texture"]}),
            "unsupported": sorted(unsupported), "mode": "APK Unity particle data; Godot runtime approximation"}
        print(asset["address"], len(layers), flush=True)
    identity = hashlib.sha256(args.apk.read_bytes()).hexdigest()
    catalog = {"apk_sha256": identity, "coordinate_convention": "native numeric XYZ, prefab root transform excluded", "effects": effects}
    (OUT / "catalog.json").write_text(json.dumps(finite_json(catalog), separators=(",", ":"), allow_nan=False) + "\n")
    evidence = {"apk": str(args.apk), "apk_sha256": identity, "manifest_sha256": hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
                "bundles": bundles, "textures": textures, "meshes": meshes, "materials": materials, "errors": errors,
                "effect_count": len(effects), "particle_layer_count": sum(len(e["layers"]) for e in effects.values()),
                "limitations": ["Static extraction, not runtime observation", "Custom Unity shaders, scripts and unsupported particle modules are not exact runtime equivalents", "Nonfinite Unity curve tangents normalized to zero for strict JSON and finite runtime interpolation", "Particle prefab roots excluded because scene anchors already carry their transforms", "Mesh coordinates preserve native numeric XYZ"]}
    report = ROOT / "goDot/reports/environment-effects-extraction.json"
    report.write_text(json.dumps(finite_json(evidence), indent=2, allow_nan=False) + "\n")
    print(json.dumps({k: evidence[k] for k in ("effect_count", "particle_layer_count", "errors")}))


if __name__ == "__main__": main()
