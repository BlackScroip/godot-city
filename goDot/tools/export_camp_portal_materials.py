#!/usr/bin/env python3
"""Extract only source materials used by the camp's five portal mesh layers."""
import hashlib
import argparse
import json
from pathlib import Path
import zipfile
import UnityPy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "goDot/assets/environment_effects"
NAMES = {"24102301_fx_env_maincityprotal", "24040202_fx_env_protal_entrance"}
MATERIALS = {"mat_fx_24102301_maincityprotal_" + part for part in ("glow", "pattern", "gems")}
MATERIALS.update({"mat_fx_24040202_entrance_" + part for part in ("glow", "pattern")})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "com.teamelo.dungeonchasers.apk")
    parser.add_argument("--manifest", type=Path, default=Path("/private/tmp/city-charge-assets/manifest.json"))
    parser.add_argument("--north-portal", action="store_true")
    args = parser.parse_args()
    names = {"23121601_fx_env_portalblue"} if args.north_portal else NAMES
    materials = {"mat_fx_23121601_portalblue_" + part for part in ("energyflowlight", "dark", "glow", "energyflow", "sand")} if args.north_portal else MATERIALS
    manifest = json.loads(args.manifest.read_text())
    assets = [a for a in manifest["assets"] if a["address"] in names]
    environment = UnityPy.Environment()
    provenance = []
    with zipfile.ZipFile(args.apk) as archive:
        for index in sorted({i for a in assets for i in [a["bundle"], *a["deps"]]}):
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"
            raw = archive.read(member)
            environment.load_file(raw, name=member)
            provenance.append({"member": member, "sha256": hashlib.sha256(raw).hexdigest()})
    objects = {(o.assets_file.name, o.path_id): o for o in environment.objects}

    def resolve(obj, pointer):
        if not pointer or not pointer.get("m_PathID"): return None
        index = pointer["m_FileID"]
        filename = obj.assets_file.name if not index else obj.assets_file.externals[index - 1].path.rsplit("/", 1)[-1]
        return objects.get((filename, pointer["m_PathID"]))

    def texture(obj):
        if obj is None: return ""
        identity = f"{obj.assets_file.name}:{obj.path_id}"
        filename = "texture_" + hashlib.sha256(identity.encode()).hexdigest()[:20] + ".png"
        if not (OUT / filename).exists(): obj.read().image.save(OUT / filename)
        return "res://assets/environment_effects/" + filename

    result = {}
    for obj in environment.objects:
        if obj.type.name != "Material": continue
        data = obj.read_typetree()
        name = data.get("m_Name", "")
        if name not in materials: continue
        properties = data["m_SavedProperties"]
        floats, colors = dict(properties["m_Floats"]), dict(properties["m_Colors"])
        maps = []
        for key, slot in properties["m_TexEnvs"]:
            texture_obj = resolve(obj, slot["m_Texture"])
            resource = texture(texture_obj)
            if resource:
                settings = texture_obj.read_typetree().get("m_TextureSettings", {})
                maps.append({"property": key, "texture": resource, "scale": slot["m_Scale"], "offset": slot["m_Offset"],
                             "wrap": {"x": settings.get("m_WrapU", 0), "y": settings.get("m_WrapV", 0)}})
        primary = next(t for t in maps if t["property"] == "_MainTex")
        shader = resolve(obj, data["m_Shader"]).read_typetree()
        shader_name = shader.get("m_Name") or shader.get("m_ParsedForm", {}).get("m_Name", "")
        src, dst = floats.get("_SrcMode"), floats.get("_DstMode")
        white = {"r": 1, "g": 1, "b": 1, "a": 1}
        result[name] = {"name": name, "source": f"{obj.assets_file.name}:{obj.path_id}",
            "texture": primary["texture"], "texture_scale": primary["scale"], "texture_offset": primary["offset"],
            "textures": maps, "keywords": data.get("m_ValidKeywords", []), "shader": shader_name,
            "color": colors.get("_Color", white), "shape_color": colors.get("_ShapeColor", white),
            "alpha": floats.get("_Alpha", 1), "shape_alpha_weight": floats.get("_ShapeAlphaWeight", 0),
            "shape_brightness": floats.get("_ShapeBrightness", 0), "glow": floats.get("_Glow", 0),
            "glow_global": floats.get("_GlowGlobal", 1),
            "alpha_from_luminance": "allin1" in shader_name.lower() and floats.get("_ShapeAlphaWeight", 0) > 0,
            "blend": "alpha" if src in (1, 5) and dst == 10 else "add" if src in (1, 5) and dst == 1 else "unknown",
            "source_floats": floats, "source_colors": colors}
    if set(result) != materials: raise RuntimeError(f"Missing source materials: {materials - set(result)}")
    output = {"apk": args.apk.name, "apk_sha256": hashlib.file_digest(args.apk.open("rb"), "sha256").hexdigest(), "bundles": provenance, "materials": result}
    filename = "camp_north_portal_materials.json" if args.north_portal else "camp_portal_materials.json"
    (OUT / filename).write_text(json.dumps(output, indent=2, allow_nan=False) + "\n")
    print("Exported", len(result), "exact portal materials")


if __name__ == "__main__": main()
