#!/usr/bin/env python3
"""Recover exact model-based skill effect prefabs omitted by particle imports."""

import argparse
import gc
import hashlib
import json
from pathlib import Path
import re
import zipfile

from import_player_lifecycle import file_digest, manifest_records
from recover_region_actors import ActorExporter


ROOT = Path(__file__).resolve().parents[1]


def defaults(exporter):
    names = []
    for _, _, controller in exporter.controllers():
        strings = dict(controller.get("m_TOS", []))
        for machine in controller["m_Controller"].get("m_StateMachineArray", []):
            data = machine["data"]
            states = data.get("m_StateConstantArray", [])
            index = int(data.get("m_DefaultState", -1))
            if 0 <= index < len(states):
                name = strings.get(states[index]["data"].get("m_NameID"), "")
                if name: names.append(name)
    return names


def main(args):
    coverage = json.loads(args.coverage.read_text())
    identity = file_digest(args.apk)
    if coverage["apk_sha256"] != identity: raise ValueError("Coverage belongs to another APK")
    catalog_path = ROOT / "assets/combat_presentation/catalog.json"
    catalog = json.loads(catalog_path.read_text())
    output = ROOT / "assets/combat_presentation/models"
    output.mkdir(parents=True, exist_ok=True)
    report = {"schema": 1, "apk_sha256": identity, "prefabs": {},
        "limitations": ["Static source geometry, skins, textures and controller TRS animation recovery.",
            "Unity material and GameObject animation properties outside TRS remain explicitly counted.",
            "Custom Unity shaders are represented with their original textures and PBR parameters; original shader equivalence is unknown."]}
    selected = [(name, row) for name, row in coverage["resources"].items()
                if row["status"] == "source_present_unrendered" and row.get("source_asset")
                and "/FX/" in row["source_asset"]["path"]]
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(coverage["manifest"]["member"])
        assets, bundles = manifest_records(manifest)
        for name, row in selected:
            exporter = None
            try:
                exporter = ActorExporter(archive, manifest, assets, bundles, row["source_asset"]["address"])
                source_defaults = defaults(exporter)
                exporter.build()
                exporter.recover_animations()
                root = exporter.data["nodes"][exporter.nodes_by_transform[exporter.root_transform]]
                root.update(translation=[0, 0, 0], rotation=[0, 0, 0, 1], scale=[1, 1, 1])
                for animation in exporter.data.get("animations", []):
                    if animation["name"].endswith("_loop"): animation["name"] += "_clip"
                for animation in exporter.animations:
                    if animation["name"].endswith("_loop"): animation["name"] += "_clip"
                aliases = {entry["source_name"].lower(): entry["name"] for entry in exporter.animations}
                default = next((aliases[name.lower()] for name in source_defaults if name.lower() in aliases), "")
                target = output / (name + ".glb")
                exporter.write(target)
                model = {"scene": "res://" + str(target.relative_to(ROOT)), "aliases": aliases,
                    "animations": [{k: v for k, v in item.items() if k != "apk_sources"} for item in exporter.animations],
                    "default_animation": default,
                    "duration": max((item["duration"] for item in exporter.animations), default=0.5)}
                catalog["effects"][name]["models"] = [model]
                report["prefabs"][name] = {"status": "imported", "source_asset": exporter.asset,
                    "root_path_id": str(exporter.root_object.path_id), "bundles": exporter.bundle_evidence,
                    "source_default_states": source_defaults, "model": model, "meshes": len(exporter.data["meshes"]),
                    "skins": len(exporter.data["skins"]), "unsupported": dict(exporter.unsupported),
                    "failures": exporter.failures, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                    "materials": exporter.material_sources}
            except (ValueError, KeyError, IndexError, TypeError) as exc:
                report["prefabs"][name] = {"status": "unresolved", "error": str(exc)}
            finally:
                if exporter:
                    for method in (exporter.world, exporter.active, exporter.path, exporter.sibling_path): method.cache_clear()
                del exporter
                gc.collect()
            print(json.dumps({"prefab": name, "status": report["prefabs"][name]["status"]}), flush=True)
    catalog_path.write_text(json.dumps(catalog, separators=(",", ":"), ensure_ascii=False) + "\n")
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=True) + "\n")
    print(json.dumps({"imported": sum(row["status"] == "imported" for row in report["prefabs"].values()), "selected": len(selected)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--coverage", type=Path, default=ROOT / "reports/skill-presentation-apk-coverage.json")
    parser.add_argument("--output", type=Path, default=ROOT / "reports/skill-presentation-model-import.json")
    main(parser.parse_args())
