#!/usr/bin/env python3
"""Verify deer action/dependency/media provenance against the supplied APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from import_region_combat import references, walk
from import_player_lifecycle import manifest_records


ROOT = Path(__file__).resolve().parents[2]
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"


def media(value):
    if isinstance(value, dict):
        return set().union(*(media(child) for child in value.values()))
    if isinstance(value, list):
        return set().union(*(media(child) for child in value))
    if isinstance(value, str) and value.lower().endswith(".prefab"):
        return {Path(value).name.lower().removesuffix(".prefab")}
    return set()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    parser.add_argument("--output", type=Path, default=ROOT / "goDot/reports/deer-skill-source-audit.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("Unexpected APK SHA-256")
    raw = json.loads((args.evidence / "raw-catalog.json").read_text())
    provenance = json.loads((args.evidence / "provenance.json").read_text())
    if provenance["apk_sha256"] != APK_SHA:
        raise ValueError("Source evidence belongs to another APK")
    combat = json.loads((ROOT / "goDot/assets/data/combat.json").read_text())
    presentation = json.loads((ROOT / "goDot/assets/combat_presentation/catalog.json").read_text())
    deer = next(row for row in combat["enemies"] if row["id"] == 33001)
    actions = {key: value for key, value in raw.items() if isinstance(value, dict) and "ActId" in value
               and Path(provenance["assets"][key]["source_asset"]).parent.name.lower() == "actgroup_jiaolu"}
    selected = actions | {deer["ai"]: raw[deer["ai"]]}
    pending = list(selected.values())
    required = {key: set() for key in ("buff", "summon", "damage")}
    missing = {key: [] for key in required}
    while pending:
        value = pending.pop()
        refs = references(value)
        for item in walk(value):
            if item.get("CommonBuffEffectId"):
                refs["buff"].add(str(item["CommonBuffEffectId"]))
            for field in ("BuffId", "CheckBuffId"):
                if isinstance(item.get(field), dict) and item[field].get("_value"):
                    refs["buff"].add(str(item[field]["_value"]))
        for kind, ids in refs.items():
            for ident in ids - required[kind]:
                required[kind].add(ident)
                if kind == "damage":
                    continue
                key = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
                if key in raw:
                    selected[key] = raw[key]
                    pending.append(raw[key])
                else:
                    missing[kind].append(ident)
    records, media_records, cache = {}, {}, {}
    with zipfile.ZipFile(args.apk) as archive:
        member = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(member))
        manifest = {"assets": assets, "bundles": bundles}
        index = {row["path"].lower(): row for row in manifest["assets"]}

        def bundle(name):
            if name not in cache:
                cache[name] = archive.read(name)
            return cache[name]

        for member in sorted({provenance["assets"][key]["bundle"] for key in selected}):
            payload = bundle(member)
            by_id = {int(provenance["assets"][key]["path_id"]): key for key in selected
                     if provenance["assets"][key]["bundle"] == member}
            for obj in UnityPy.load(payload).objects:
                key = by_id.get(obj.path_id)
                if key is None:
                    continue
                if obj.type.name == "TextAsset":
                    text = obj.read().m_Script
                    if isinstance(text, bytes):
                        text = text.decode("utf-8-sig")
                    value = json.loads(text.lstrip("\ufeff"))
                else:
                    value = json.loads(obj.read_typetree()["_serializedGraph"])
                records[key] = dict(provenance["assets"][key], matches_fresh_apk=value == selected[key]
                                    and hashlib.sha256(payload).hexdigest() == provenance["assets"][key]["bundle_sha256"])
        for name in sorted(media(list(selected.values()))):
            if name.startswith("audio_"):
                media_records[name] = {"kind": "audio", "present": name in presentation["audio"]}
                continue
            effect = presentation["effects"].get(name)
            if effect is None:
                media_records[name] = {"kind": "effect", "present": False}
                continue
            asset = index.get(effect["source"].lower())
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][asset["bundle"]]["hash"] + ".bundle" if asset else ""
            resources = {layer["mesh"] for layer in effect.get("layers", []) if layer.get("mesh")}
            resources.update(effect.get("textures", []))
            resources.update(model["scene"] for model in effect.get("models", []))
            for model in effect.get("models", []):
                for material in model.get("material_animation", {}).get("materials", {}).values():
                    resources.update(item["texture"] for item in material.get("textures", []))
            media_records[name] = {"kind": "effect", "present": True, "source": effect["source"],
                "bundle": member, "bundle_sha256_matches_apk": bool(member) and hashlib.sha256(bundle(member)).hexdigest() == effect["source_sha256"],
                "layers": len(effect.get("layers", [])), "models": effect.get("models", []),
                "unsupported": effect.get("unsupported", []),
                "missing_resources": [path for path in sorted(resources) if not (ROOT / "goDot" / path.removeprefix("res://")).exists()]}
            if name == "24070801_fx_enemy_jiaolu_attack3_soul":
                source_objects = UnityPy.load(bundle(member)).objects
                source_types = [obj.type.name for obj in source_objects]
                media_records[name]["source_skinned_mesh_renderers"] = source_types.count("SkinnedMeshRenderer")
                media_records[name]["source_animators"] = source_types.count("Animator")
                media_records[name]["required_model_present"] = bool(effect.get("models"))
                renderer = next(obj.read_typetree() for obj in source_objects if obj.type.name == "SkinnedMeshRenderer")
                media_records[name]["source_cast_shadows"] = renderer["m_CastShadows"]
                media_records[name]["cast_shadow_matches_apk"] = bool(effect.get("models")) and all(
                    model.get("cast_shadow") == bool(renderer["m_CastShadows"]) for model in effect["models"])
    action_records = []
    for key, action in sorted(actions.items()):
        enabled = [row for field in ("Events", "AttackDefs", "Interrupts") for row in action.get(field, []) if row.get("Enabled", True)]
        action_records.append({"source_key": key, "id": action["ActId"], "duration": action["TotalTime"] / 1000,
            "animations": sorted({row["EventData"]["AnimName"] for row in enabled if row.get("EventType") == "EET_PlayAnim"}),
            "media": sorted(media(enabled)), "summons": [{"time": row["TriggerTime"] / 1000, **row["EventData"]["AddSummonUnitDef"]}
                for row in enabled if "AddSummonUnitDef" in row.get("EventData", {})],
            "hit_times": [row["TriggerTime"] / 1000 for row in action.get("AttackDefs", []) if row.get("Enabled", True)]})
    summons = {}
    for ident in sorted(required["summon"]):
        value = raw.get("SummonUnitCfg_[" + ident + "]", {}).get("SummonUnitData", {})
        summons[ident] = {key: value.get(key) for key in ("Prefab", "Duration", "MaxExistCount", "FirstTriggerDelayTime", "TriggerDuration", "EmitType", "EmitProperty", "MotionAnimatorProperty")}
    missing_media = [name for name, row in media_records.items() if not row["present"]]
    mismatches = [key for key, row in records.items() if not row["matches_fresh_apk"]]
    report = {"apk_sha256": APK_SHA, "evidence_type": "Fresh offline UnityPy TextAsset/NodeCanvas and packaged bundle SHA-256 verification; no runtime execution",
        "rea_evidence_ids": [], "enemy": {key: deer[key] for key in ("id", "name", "group", "ai", "phase_rules")},
        "actions": action_records, "dependencies": {key: sorted(value) for key, value in required.items()},
        "summon_configuration": summons, "source_records": records, "source_mismatches": mismatches,
        "missing_dependencies": missing, "media": media_records, "missing_media": missing_media,
        "passed": len(actions) == 26 and len(records) == len(selected) and not mismatches and not missing_media
            and not any(missing.values()) and all(row.get("bundle_sha256_matches_apk", True) and row.get("required_model_present", True)
                and row.get("cast_shadow_matches_apk", True) and not row.get("missing_resources") for row in media_records.values()),
        "limitations": ["Includes disabled serialized rows and AI buff predicates without enabling them.",
            "Audio catalog presence is checked; fresh audio decode and damage definition serialization are outside this audit.",
            "Bundle identity and model bindings do not establish Unity shader, material animation or pixel equivalence.",
            "Summon timing and capacities are serialized configuration; actual simultaneous runtime count is unobserved."]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "actions": len(actions), "source_records": len(records), "media": len(media_records),
        "dependencies": {key: len(value) for key, value in required.items()}, "missing_media": missing_media, "source_mismatches": mismatches}))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
