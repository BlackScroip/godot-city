#!/usr/bin/env python3
"""Import only existing heavy actions from hash-verified October APK evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from import_region_combat import event, hit, load, packed

PROJECT = Path(__file__).resolve().parents[1]


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def merge(args):
    provenance = load(args.evidence / "provenance.json")
    with args.apk.open("rb") as stream:
        apk_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_hash != provenance["apk_sha256"]:
        raise ValueError("APK and retained TextAsset evidence have different hashes")
    raw = load(args.evidence / "raw-catalog.json")
    combat_path = args.project / "assets/data/combat.json"
    heavy_path = args.project / "assets/data/heavy_attacks.json"
    combat, heavy = load(combat_path), load(heavy_path)
    sources = {row["ActId"]: (name, row) for name, row in raw.items()
        if name.startswith("ActGroup_playerchara_") and isinstance(row, dict)}
    actions = {row["key"]: row for row in combat["actions"]}
    selected = {name: sources[name] for name in heavy["actions"]}
    bundles = {provenance["assets"][name]["bundle"]: provenance["assets"][name]["bundle_sha256"]
        for name, _ in selected.values()}
    buff_sources = {ident: "BuffCfg_[" + ident + "]" for ident in heavy["buffs"]}
    for name in buff_sources.values():
        proof = provenance["assets"][name]
        bundles[proof["bundle"]] = proof["bundle_sha256"]
    with zipfile.ZipFile(args.apk) as archive:
        for member, expected in bundles.items():
            if digest(archive.read(member)) != expected:
                raise ValueError("APK bundle no longer matches extraction: " + member)
    fixture = {"apk_sha256": apk_hash, "manifest": provenance["manifest"], "actions": {}}
    for ident, (name, row) in selected.items():
        key = "ActGroup_playerchara/" + ident
        if key not in actions:
            raise ValueError("Heavy import cannot introduce an unimplemented action: " + ident)
        source = provenance["assets"][name]
        normalized = {"key": key, "group": "ActGroup_playerchara", "id": ident,
            "name": row.get("Name_EDT", ""), "duration": row["TotalTime"] / 1000.0,
            "speed": row["PlaySpeed"],
            "events": [event(command) for command in row.get("Events", []) + row.get("Interrupts", [])],
            "hits": [hit(command["EventData"], combat["damage_definitions"], command)
                | {"duration": command.get("Duration", 0) / 1000.0}
                for command in row.get("AttackDefs", [])],
            "source": source["source_asset"], "apk_source": source}
        actions[key] = normalized
        source_hash = digest(packed(row).encode())
        heavy["actions"][ident] = {"can_hit": row["CanHit"], "stable_value": row["StableValue"],
            "source_sha256": source_hash, "apk_source": source}
        # Immutable source fingerprints catch altered flags, conditions, and raw
        # payloads without duplicating every large authored command in fixtures.
        fixture["actions"][ident] = {"duration": normalized["duration"], "speed": normalized["speed"],
            "can_hit": row["CanHit"], "stable_value": row["StableValue"], "source_sha256": source_hash,
            "events": [{"type": command["EventType"], "time": command["TriggerTime"] / 1000.0,
                "duration": command["Duration"] / 1000.0, "enabled": command.get("Enabled", True),
                "all": command.get("CheckAllCondition", True), "raw_sha256": digest(packed(command["EventData"]).encode()),
                "condition_sha256": [digest(packed(condition).encode()) for condition in command.get("Conditions", [])]}
                for command in row.get("Events", []) + row.get("Interrupts", [])],
            "hits": [{"time": command["TriggerTime"] / 1000.0,
                "duration": command.get("Duration", 0) / 1000.0, "enabled": command.get("Enabled", True),
                "all": command.get("CheckAllCondition", True), "raw_sha256": digest(packed(command["EventData"]).encode()),
                "condition_sha256": [digest(packed(condition).encode()) for condition in command.get("Conditions", [])]}
                for command in row.get("AttackDefs", [])]}
    combat["actions"] = list(actions.values())
    state = raw[buff_sources["200202"]]["BuffData"]
    sync = raw[buff_sources["200208"]]["BuffData"]
    heavy["buffs"]["200202"] = {"expiryLayers": state["OnceReduceNumCount"],
        "disposeBuff": state["DisposeTriggerBuff"]["BuffTriggerId"],
        "disposeLayers": state["DisposeTriggerBuff"]["BuffAddLayer"]}
    heavy["buffs"]["200208"] = {"syncSource": sync["SyncSourceBuffId"],
        "syncTargets": sync["ModifyBuffId"].split("|")}
    heavy["buff_sources"] = {ident: {"source_sha256": digest(packed(raw[name]).encode()),
        "apk_source": provenance["assets"][name]} for ident, name in buff_sources.items()}
    heavy["apk_sha256"] = apk_hash
    heavy["manifest"] = provenance["manifest"]
    heavy["source_hash_encoding"] = "SHA-256 of compact UTF-8 JSON retaining extracted object order"
    combat_path.write_text(packed(combat) + "\n")
    heavy_path.write_text(json.dumps(heavy, ensure_ascii=False, indent=2) + "\n")
    fixture_path = args.project / "tests/fixtures/heavy_october_actions.json"
    fixture_path.parent.mkdir(exist_ok=True)
    fixture_path.write_text(json.dumps(fixture, ensure_ascii=False, indent=2) + "\n")
    report = {"apk_sha256": apk_hash, "manifest": provenance["manifest"],
        "bundles": bundles, "actions": sorted(selected), "evidence": str(args.evidence),
        "scope": "Existing heavy player actions only; exact serialized events, interrupts, hit definitions and flags. Other actions and combat dependencies retained."}
    (args.project / "reports/heavy-october-import.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(packed(report))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    merge(parser.parse_args())
