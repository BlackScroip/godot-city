#!/usr/bin/env python3
"""Recover the selected APK's camp scarecrow without modifying shared catalogs."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import numpy as np
import UnityPy

from inspect_camp_progression import manifest_records
from recover_region_actors import ActorExporter, MANIFEST


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(args.apk.read_bytes()).hexdigest()
    wanted = {"MonsterActionCfg_[90010]", "EnvUnitCfg_[90010]", "EnemyAIBT_CityScareCrow"}
    values, evidence = {}, {}
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(MANIFEST)
        assets, bundles = manifest_records(manifest)
        selected = {row["address"]: row for row in assets if row["address"] in wanted}
        for index in sorted({row["bundle"] for row in selected.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name not in ("TextAsset", "MonoBehaviour") or obj.peek_name() not in wanted:
                    continue
                name = obj.peek_name()
                text = obj.read().m_Script if obj.type.name == "TextAsset" else obj.read_typetree()["_serializedGraph"]
                if isinstance(text, bytes):
                    text = text.decode("utf-8-sig")
                values[name] = json.loads(text.lstrip("\ufeff"))
                evidence[name] = {"member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                                  "source_asset": selected[name]["path"], "path_id": str(obj.path_id)}
        if set(values) != wanted:
            raise ValueError("An exact scarecrow configuration is missing")
        exporter = ActorExporter(archive, manifest, assets, bundles, "monster_cityscarecrow")
        exporter.build()
        exporter.recover_animations()
        target = args.output / "scarecrow.glb"
        exporter.write(target)
        lower = np.min(np.asarray([pair[0] for pair in exporter.bounds]), axis=0)
        upper = np.max(np.asarray([pair[1] for pair in exporter.bounds]), axis=0)
        result = {"apk_sha256": digest, "manifest": MANIFEST, "observed_runtime": False,
                  "source": values, "source_evidence": evidence,
                  "model": {"path": "res://assets/camp_training/scarecrow.glb", "source_asset": exporter.asset["path"],
                            "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "bundle_sources": exporter.bundle_evidence,
                            "bounds": {"min": lower.tolist(), "max": upper.tolist(), "size": (upper - lower).tolist()},
                            "meshes": len(exporter.data["meshes"]), "skins": len(exporter.data["skins"]),
                            "animations": exporter.animations, "unsupported": dict(exporter.unsupported)},
                  "limitations": ["Source EnemyData has no 90010 record; training uses zero defense and no attacks.",
                                   "Unity custom material shaders use source textures with Godot PBR approximations.",
                                   "Session statistics, resets and isolated player combat are reconstruction choices."]}
        (args.output / "source.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"model": str(target), "meshes": result["model"]["meshes"],
                          "animations": [row["source_name"] for row in exporter.animations], "apk_sha256": digest}))


if __name__ == "__main__":
    main()
