#!/usr/bin/env python3
"""Audit exact skill presentation references against the selected APK manifest.

The retained raw-catalog/provenance pair must belong to this APK. Resource
names are compared exactly; missing names never generate aliases or effects.
"""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from import_player_lifecycle import Reader, file_digest, resource_key


ROOT = Path(__file__).resolve().parents[1]
VISUAL_FIELDS = {
    "EffectName", "Effect", "ModlePrefab", "EntityEndEffect", "mEntityEndEffect_Floor",
    "TargetEffect", "AimEffect", "KeepEffect", "StartEffect", "EndEffect",
    "PlayEffectWhenLayerMax", "HitEffect_OnTarget", "HitEffect_UnitCenter",
    "DetectionEffectName", "ReplaceEffectName", "Prefab", "PickUpEffect",
    "EffectName_Start", "EffectName_Loop", "EffectName_End", "HitEffect", "DestoryEffect", "InitEffect", "BeAttackEffect",
    "TriggerEffectName_Delay", "TriggerEffectName_NoDelay", "BounceEffect", "CounterFx",
}
PLACEHOLDERS = {"triggereffectname_delay", "triggereffectname_nodelay"}


def manifest_document(payload):
    reader = Reader(payload)
    reader.number("I")
    reader.string()
    for _ in range(3): reader.number("B")
    for _ in range(2): reader.number("i")
    for _ in range(4): reader.string()
    assets = []
    for _ in range(reader.number("i")):
        address, path, guid = [reader.string() for _ in range(3)]
        tags = reader.array(reader.string)
        bundle = reader.number("i")
        deps = reader.array(lambda: reader.number("i"))
        assets.append({"address": address, "path": path, "bundle": bundle, "deps": deps})
    bundles = []
    for _ in range(reader.number("i")):
        name = reader.string()
        reader.number("I")
        digest = reader.string()
        reader.string()
        reader.number("q")
        reader.number("B")
        reader.array(reader.string)
        deps = reader.array(lambda: reader.number("i"))
        bundles.append({"name": name, "hash": digest, "deps": deps})
    if reader.offset != len(payload): raise ValueError("Manifest was not completely parsed")
    return {"assets": assets, "bundles": bundles}


def references(value, pointer=""):
    if isinstance(value, dict):
        for field, child in value.items():
            path = pointer + "/" + field.replace("~", "~0").replace("/", "~1")
            if field in VISUAL_FIELDS and isinstance(child, str) and child:
                name = resource_key(child)
                if name not in PLACEHOLDERS:
                    yield name, {"pointer": path, "field": field, "value": child}
            yield from references(child, path)
    elif isinstance(value, list):
        for index, child in enumerate(value): yield from references(child, pointer + "/" + str(index))


def main(args):
    apk_hash = file_digest(args.apk)
    provenance = json.loads((args.evidence / "provenance.json").read_text())
    if provenance["apk_sha256"] != apk_hash:
        raise ValueError("Retained configuration evidence belongs to a different APK")
    raw = json.loads((args.evidence / "raw-catalog.json").read_text())
    media = json.loads((ROOT / "assets/combat_presentation/catalog.json").read_text())
    follower_path = ROOT / "assets/spirit_followers/catalog.json"
    followers = json.loads(follower_path.read_text()) if follower_path.exists() else {}
    if followers and followers.get("apk_sha256") != apk_hash:
        raise ValueError("Follower presentation catalog belongs to a different APK")
    with zipfile.ZipFile(args.apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest_bytes = archive.read(manifest_name)
    manifest = manifest_document(manifest_bytes)
    assets = {resource_key(row["address"]): row for row in manifest["assets"]}
    found = {}
    for config, value in raw.items():
        source = provenance["assets"][config]
        for name, entry in references(value):
            # Prefab may be a summoned actor rather than an effect. Keep that
            # boundary explicit instead of counting an existing actor as absent FX.
            asset = assets.get(name)
            if asset and "/Prefabs/BattleSys/Role/" in asset["path"]: continue
            if name in media.get("audio", {}): continue
            found.setdefault(name, []).append({"configuration": config, "source": source, **entry})
    bundle_hashes = {}
    with zipfile.ZipFile(args.apk) as archive:
        for index in sorted({assets[name]["bundle"] for name in found if name in assets}):
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"
            bundle_hashes[index] = hashlib.sha256(archive.read(member)).hexdigest()
    records = {}
    export = []
    for name, refs in sorted(found.items()):
        asset = assets.get(name)
        effect = media["effects"].get(name, {})
        follower = followers.get("effects", {}).get(name, {})
        status = "authored_follower" if follower else "authored_particles" if effect.get("layers") else "authored_model" if effect.get("models") else "source_present_unrendered" if asset else "exact_resource_absent"
        if asset and not follower and (args.export_all or status == "source_present_unrendered"):
            export.append(asset["address"])
        expected_hash = bundle_hashes.get(asset["bundle"], "") if asset else ""
        style = follower or effect
        source_bound = bool(expected_hash) and style.get("source_sha256") == expected_hash
        records[name] = {"status": status, "selected_apk_binding": source_bound,
            "source_bundle_sha256": expected_hash, "source_asset": asset, "references": refs}
    counts = {status: sum(row["status"] == status for row in records.values()) for status in (
        "authored_particles", "authored_model", "authored_follower", "source_present_unrendered", "exact_resource_absent")}
    report = {"schema": 1, "apk": str(args.apk), "apk_sha256": apk_hash,
        "evidence_type": "static shipped Unity action/buff/summon/ability JSON and exact manifest addresses",
        "manifest": {"member": manifest_name, "sha256": hashlib.sha256(manifest_bytes).hexdigest()},
        "configuration_count": len(raw), "unique_visual_references": len(records), "coverage": counts,
        "source_bound_resources": sum(row["selected_apk_binding"] for row in records.values()),
        "unverified_bindings": [name for name, row in records.items() if row["source_asset"] and not row["selected_apk_binding"]],
        "resources": records,
        "limitations": ["Static source serialization does not observe original APK execution.",
            "Names absent from the exact manifest have no inferred alias or substituted style.",
            "Imported particle materials retain source textures and parameters; Unity shader/runtime equivalence is not established.",
            "Control-node names, summoned actors and audio-prefab feedback are not classified as particle effects."]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=True) + "\n")
    if args.export_list: args.export_list.write_text(json.dumps(export, indent=2) + "\n")
    if args.export_manifest: args.export_manifest.write_text(json.dumps(manifest, separators=(",", ":")) + "\n")
    print(json.dumps({"output": str(args.output), "configuration_count": len(raw), "unique_visual_references": len(records), "coverage": counts, "exportable_fx": len(export)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    parser.add_argument("--output", type=Path, default=ROOT / "reports/skill-presentation-apk-coverage.json")
    parser.add_argument("--export-list", type=Path)
    parser.add_argument("--export-all", action="store_true", help="Select all exact source FX for a matched-APK refresh")
    parser.add_argument("--export-manifest", type=Path)
    main(parser.parse_args())
