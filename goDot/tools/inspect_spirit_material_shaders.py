#!/usr/bin/env python3
"""Match source fire-follower materials to exact APK GLES shader programs."""
import argparse
import json
from pathlib import Path
import zipfile

from import_player_lifecycle import file_digest, manifest_records
from import_skill_model_materials import shader_programs
from recover_region_actors import ActorExporter

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "assets/yoo/DefaultPackage/DefaultPackage_2026-10-09-1177.bytes"


def main(args):
    catalog = json.loads((ROOT / "assets/spirit_followers/catalog.json").read_text())
    digest = file_digest(args.apk)
    if digest != catalog["apk_sha256"]: raise ValueError("Follower catalog belongs to another APK")
    output = ROOT / "reports/shader_evidence/spirit_runtime"
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(MANIFEST)
        assets, bundles = manifest_records(manifest)
        exporter = ActorExporter(archive, manifest, assets, bundles, "summonunit_sprite_fire_1")
        objects = {obj.assets_file.name + ":" + str(obj.path_id): obj for obj in exporter.env.objects}
        materials = []
        for layer in catalog["effects"]["summonunit_sprite_fire_1"]["layers"]:
            for material in layer["materials"]:
                if not material["shader"].startswith("AllIn1Vfx/"): continue
                obj = objects[material["source"]]
                materials.append({"name": material["name"], "material_source": material["source"],
                    "keywords": material["keywords"],
                    "programs": shader_programs(exporter, obj, set(material["keywords"]), output)})
        result = {"apk_sha256": digest, "prefab": "summonunit_sprite_fire_1", "materials": materials,
                  "source_bundles": exporter.bundle_evidence,
                  "scope": "Static original GLES source matched against complete serialized material keyword sets; not original APK runtime observation."}
        (ROOT / "reports/spirit-source-shader-evidence.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"materials": len(materials), "matched": sum(bool(row["programs"]) for row in materials)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    main(parser.parse_args())
