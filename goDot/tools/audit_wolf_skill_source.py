#!/usr/bin/env python3
"""Verify the wolf's complete static skill/media closure against the exact APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from import_region_combat import references, walk
from recover_chest_effects import package_manifest


ROOT = Path(__file__).resolve().parents[2]
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
GROUP = "ActGroup_senlinlangwang"


def media(value):
    found = set()
    if isinstance(value, dict):
        for child in value.values():
            found.update(media(child))
    elif isinstance(value, list):
        for child in value:
            found.update(media(child))
    elif isinstance(value, str) and value.lower().endswith(".prefab"):
        found.add(Path(value).name.lower().removesuffix(".prefab"))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    parser.add_argument("--output", type=Path, default=ROOT / "goDot/reports/wolf-skill-source-audit.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("Unexpected APK")
    raw = json.loads((args.evidence / "raw-catalog.json").read_text())
    provenance = json.loads((args.evidence / "provenance.json").read_text())
    if provenance["apk_sha256"] != APK_SHA:
        raise ValueError("Mismatched source evidence")
    combat = json.loads((ROOT / "goDot/assets/data/combat.json").read_text())
    presentation = json.loads((ROOT / "goDot/assets/combat_presentation/catalog.json").read_text())
    embedded = json.loads((ROOT / "goDot/assets/combat_presentation/wolf_embedded/catalog.json").read_text())
    effects = presentation["effects"] | embedded["effects"]
    wolf = next(row for row in combat["enemies"] if row["id"] == 13001)
    source_actions = {key: value for key, value in raw.items() if isinstance(value, dict) and "ActId" in value
        and Path(provenance["assets"][key]["source_asset"]).parent.name.lower() == GROUP.lower()}
    selected = source_actions | {wolf["ai"]: raw[wolf["ai"]]}
    queue = list(selected.values())
    required = {key: set() for key in ("buff", "summon", "damage")}
    missing = {key: [] for key in required}
    while queue:
        value = queue.pop()
        refs = references(value)
        for item in walk(value):
            if item.get("CommonBuffEffectId"):
                refs["buff"].add(str(item["CommonBuffEffectId"]))
            for key in ("BuffId", "CheckBuffId"):
                if isinstance(item.get(key), dict) and item[key].get("_value"):
                    refs["buff"].add(str(item[key]["_value"]))
        for kind, identifiers in refs.items():
            for ident in identifiers - required[kind]:
                required[kind].add(ident)
                if kind == "damage":
                    continue
                key = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
                if key not in raw:
                    missing[kind].append(ident)
                else:
                    selected[key] = raw[key]
                    queue.append(raw[key])
    all_media = media(list(selected.values())) | set(embedded["effects"])
    records, bundle_cache, raw_mismatches, media_records = {}, {}, [], {}
    with zipfile.ZipFile(args.apk) as archive:
        manifest_member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = package_manifest(archive.read(manifest_member))
        asset_index = {row["path"].lower(): row for row in manifest["assets"]}

        def bundle(member):
            if member not in bundle_cache:
                bundle_cache[member] = archive.read(member)
            return bundle_cache[member]

        for member in sorted({provenance["assets"][key]["bundle"] for key in selected}):
            payload = bundle(member)
            selected_by_id = {int(provenance["assets"][key]["path_id"]): key for key in selected
                if provenance["assets"][key]["bundle"] == member}
            for obj in UnityPy.load(payload).objects:
                key = selected_by_id.get(obj.path_id)
                if key is None:
                    continue
                if obj.type.name == "TextAsset":
                    text = obj.read().m_Script
                    if isinstance(text, bytes):
                        text = text.decode("utf-8-sig")
                    value = json.loads(text.lstrip("\ufeff"))
                else:
                    value = json.loads(obj.read_typetree()["_serializedGraph"])
                matches = value == selected[key] and hashlib.sha256(payload).hexdigest() == provenance["assets"][key]["bundle_sha256"]
                records[key] = dict(provenance["assets"][key], matches_fresh_apk=matches)
                if not matches:
                    raw_mismatches.append(key)
        for name in sorted(all_media):
            if name.startswith("audio_"):
                media_records[name] = {"kind": "audio", "present": name in presentation["audio"]}
                continue
            effect = effects.get(name)
            if effect is None:
                media_records[name] = {"kind": "effect", "present": False}
                continue
            asset = asset_index.get(effect["source"].lower())
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][asset["bundle"]]["hash"] + ".bundle" if asset else ""
            matches = bool(member) and hashlib.sha256(bundle(member)).hexdigest() == effect["source_sha256"]
            resources = {resource for layer in effect.get("layers", []) for resource in [layer.get("mesh", "")] if resource}
            resources.update(effect.get("textures", []))
            absent = [resource for resource in sorted(resources) if not (ROOT / "goDot" / resource.removeprefix("res://")).exists()]
            media_records[name] = {"kind": "embedded" if name in embedded["effects"] else "effect", "present": True,
                "source": effect["source"], "source_root": effect.get("source_root"), "bundle": member,
                "bundle_sha256_matches_apk": matches, "layers": len(effect.get("layers", [])),
                "missing_resources": absent, "unsupported": effect.get("unsupported", [])}
    action_records = []
    for key, action in sorted(source_actions.items(), key=lambda pair: pair[1]["Name_EDT"]):
        enabled = [row for field in ("Events", "AttackDefs", "Interrupts") for row in action.get(field, []) if row.get("Enabled", True)]
        disabled = [row for field in ("Events", "AttackDefs", "Interrupts") for row in action.get(field, []) if not row.get("Enabled", True)]
        action_records.append({"id": action["ActId"], "name": action["Name_EDT"], "duration": action["TotalTime"] / 1000,
            "speed": action["PlaySpeed"], "source_key": key,
            "animations": sorted({row["EventData"]["AnimName"] for row in enabled if row.get("EventType") == "EET_PlayAnim"}),
            "media": sorted(media(enabled)), "disabled_media": sorted(media(disabled)),
            "monster_generation": [{"time": row["TriggerTime"] / 1000, "enabled": row.get("Enabled", True), **row["EventData"]} for row in action.get("Events", []) if row.get("EventType") == "EET_MonsterGeneration"],
            "hit_times": [row["TriggerTime"] / 1000 for row in action.get("AttackDefs", []) if row.get("Enabled", True)]})
    absent_media = [name for name, row in media_records.items() if not row["present"]]
    report = {"apk_sha256": APK_SHA, "evidence_type": "Fresh static Unity TextAsset/NodeCanvas comparison and packaged media bundle verification; no APK runtime execution",
        "rea_evidence_ids": ["ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c", "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323"],
        "enemy": {key: wolf[key] for key in ("id", "name", "group", "ai", "phase_rules")},
        "actions": action_records, "dependencies": {key: sorted(value) for key, value in required.items()},
        "missing_dependencies": missing, "source_records": records, "source_mismatches": raw_mismatches,
        "media": media_records, "missing_media": absent_media,
        "passed": len(source_actions) == 23 and len(records) == len(selected) and not raw_mismatches and not absent_media and not any(missing.values())
            and all(row.get("bundle_sha256_matches_apk", True) and not row.get("missing_resources") for row in media_records.values()),
        "limitations": ["A matching asset bundle proves source provenance, not pixel parity of Godot particle/shader execution.",
            "The dependency closure includes disabled serialized rows and AI buff predicates. Disabled actions or rows are retained without enabling them.",
            "Audio presence verifies existing catalog binding only; fresh audio decode parity is outside this bounded audit.",
            "Damage definitions are inventoried by ID but not re-decoded here; original existing boss source audit covers damage serialization."]}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "actions": len(action_records), "source_records": len(records), "media": len(media_records),
        "dependencies": {key: len(value) for key, value in required.items()}, "source_mismatches": raw_mismatches,
        "missing_media": absent_media, "bundle_mismatches": [name for name, row in media_records.items() if row.get("bundle_sha256_matches_apk") is False]}))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
