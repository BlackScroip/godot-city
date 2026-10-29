#!/usr/bin/env python3
"""Recover the APK's omitted skinned phantom deer and its material animation."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import zipfile

from audit_deer_skill_source import APK_SHA
from import_player_lifecycle import file_digest, manifest_records
from import_skill_models import defaults
from import_skill_model_materials import recover
from recover_region_actors import ActorExporter


ROOT = Path(__file__).resolve().parents[1]
NAME = "24070801_fx_enemy_jiaolu_attack3_soul"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT.parent / "1061664.apk")
    args = parser.parse_args()
    if file_digest(args.apk) != APK_SHA:
        raise ValueError("Unexpected APK SHA-256")
    output = ROOT / "assets/combat_presentation/models"
    shaders = ROOT / "reports/shader_evidence/deer_model"
    output.mkdir(parents=True, exist_ok=True)
    shaders.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.apk) as archive:
        member = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(member)
        assets, bundles = manifest_records(manifest)
        ex = ActorExporter(archive, manifest, assets, bundles, NAME)
        counts = Counter(obj.type.name for obj in ex.objects.values())
        if counts["SkinnedMeshRenderer"] != 1 or counts["Animator"] != 1:
            raise ValueError("Unexpected phantom deer renderer or animator count")
        source_renderers = [{"path_id": str(key), **{field: ex.raw[key].get(field)
            for field in ("m_Enabled", "m_CastShadows", "m_ReceiveShadows")}}
            for key, obj in ex.objects.items() if obj.type.name == "SkinnedMeshRenderer"]
        source_defaults = defaults(ex)
        ex.build()
        ex.recover_animations()
        # Models are instantiated directly, so preserve the same root TRS as the particles.
        root = ex.data["nodes"][ex.nodes_by_transform[ex.root_transform]]
        source_root = {key: root.get(key) for key in ("translation", "rotation", "scale")}
        for animation in ex.data.get("animations", []):
            if animation["name"].endswith("_loop"):
                animation["name"] += "_clip"
        for animation in ex.animations:
            if animation["name"].endswith("_loop"):
                animation["name"] += "_clip"
        aliases = {entry["source_name"].lower(): entry["name"] for entry in ex.animations}
        default = next((aliases[name.lower()] for name in source_defaults if name.lower() in aliases), "")
        target = output / (NAME + ".glb")
        ex.write(target)
        material_animation, unresolved, programs = recover(ex, output, shaders)
        model = {"scene": "res://" + str(target.relative_to(ROOT)), "aliases": aliases,
            "animations": [{key: value for key, value in item.items() if key != "apk_sources"} for item in ex.animations],
            "default_animation": default, "duration": max((item["duration"] for item in ex.animations), default=0.5),
            "material_animation": material_animation,
            "cast_shadow": bool(source_renderers[0]["m_CastShadows"]), "source_renderer_settings": source_renderers}
        model["duration"] = max(model["duration"], max((clip["duration"] for controller in material_animation["controllers"]
            for clip in controller["clips"].values()), default=0.0))
        report = {"apk_sha256": APK_SHA, "evidence_type": "Fresh static UnityPy source prefab, skin, controller, material and shader extraction; no APK runtime observation",
            "prefab": NAME, "source_asset": ex.asset, "source_root": source_root, "source_bundles": ex.bundle_evidence,
            "source_object_counts": dict(counts), "source_default_states": source_defaults,
            "meshes": len(ex.data["meshes"]), "skins": len(ex.data["skins"]), "model": model,
            "unsupported": dict(ex.unsupported), "failures": ex.failures, "material_unresolved": unresolved,
            "shader_programs": programs, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "limitations": ["Material and skin assets are source exact; Godot shader parity requires separate rendering verification.",
                "Unbound animation properties are reported, without invented replacement motion."]}
        catalog_path = ROOT / "assets/combat_presentation/catalog.json"
        catalog = json.loads(catalog_path.read_text())
        catalog["effects"][NAME]["models"] = [model]
        catalog_path.write_text(json.dumps(catalog, separators=(",", ":"), ensure_ascii=False) + "\n")
        (ROOT / "reports/deer-skill-model-recovery.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(json.dumps({"meshes": report["meshes"], "skins": report["skins"], "animations": len(ex.animations),
            "default": default, "unsupported": report["unsupported"], "material_unresolved": len(unresolved), "failures": ex.failures}))


if __name__ == "__main__":
    main()
