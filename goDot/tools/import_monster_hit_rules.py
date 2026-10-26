#!/usr/bin/env python3
"""Extract monster tenacity and hit rules from the audited APK TextAssets."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import zipfile

from inspect_camp_progression import manifest_records


APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
FIELDS = (
    "BaseTenacity", "BaseTenacityAccReduce", "BaseWeakTime", "EliteBreakEnable",
    "Weight", "PushForceResist", "UpperForceResist", "BeHitBlendStateName",
    "BeHitBlendStateRatio_SpecialAction", "BeHitBlendStateRatio_NormalAction",
)
ACTION_STATES = {
    "Idle": 0, "Move": 1, "NorAtk": 21, "SAtk": 22, "DodgeAtk": 23,
    "SubSkill": 31, "MainSkill": 32, "Dodge": 33, "MonsterPartnerSkill": 34,
    "Born": 7, "Dead": 4, "Relive": 5, "BeHit": 6, "SwitchExit": 91,
    "SwitchEnter": 92, "Sys": 999, "Sys_ChangeBorn": 1000,
    "Sys_ChangeDead": 1001, "Sys_ChangeIdle": 1002, "Sys_ChangeMove": 1003,
    "Sys_ChangeBeHit": 1004, "Sys_ChangeNorAtk": 1005, "Sys_ChangeSatk": 1006,
    "Sys_ChangeDodgeAtk": 1007, "Sys_ChangeDodge": 1008, "Sys_ChangeSkill": 1009,
}


def extract(apk):
    import UnityPy

    with apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != APK_SHA256:
        raise ValueError("Monster hit rules require the audited 1061664.apk")
    enemies, action_states, action_sources, raw_actions, action_hit_rules = {}, {}, {}, {}, {}
    with zipfile.ZipFile(apk) as archive:
        manifests = [name for name in archive.namelist()
                     if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_")
                     and name.endswith(".bytes")]
        if len(manifests) != 1:
            raise ValueError("Expected exactly one package manifest")
        manifest_member = manifests[0]
        manifest_bytes = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest_bytes)
        selected = {row["address"]: row for row in assets
                    if row["address"].startswith("MonsterActionCfg_[")
                    or "/ActGroup_" in row["path"]}
        if not selected:
            raise ValueError("No MonsterActionCfg TextAssets in package manifest")
        for bundle_index in sorted({row["bundle"] for row in selected.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[bundle_index]["hash"] + ".bundle"
            bundle_bytes = archive.read(member)
            for obj in UnityPy.load(bundle_bytes).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in selected:
                    continue
                asset = obj.read()
                script = asset.m_Script
                text = script.decode("utf-8-sig") if isinstance(script, bytes) else script.lstrip("\ufeff")
                source = json.loads(text)
                if "ActId" in source:
                    group = Path(selected[asset.m_Name]["path"]).parent.name
                    key = group + "/" + source["ActId"]
                    state = source["ActionStatus"]
                    if state not in ACTION_STATES or key in action_states:
                        raise ValueError("Unknown state or duplicate action: " + key)
                    action_states[key] = ACTION_STATES[state]
                    action_hit_rules[key] = {field: source[field] for field in ("StableValue", "WeightAddValue", "CanHit") if field in source}
                    raw_actions[key] = source
                    action_sources[group] = {
                        "bundle": member,
                        "bundle_sha256": hashlib.sha256(bundle_bytes).hexdigest(),
                        "source_directory": str(Path(selected[asset.m_Name]["path"]).parent),
                    }
                    continue
                ident = str(source["ID"])
                if asset.m_Name != "MonsterActionCfg_[" + ident + "]" or ident in enemies:
                    raise ValueError("Unexpected or duplicate monster asset identity: " + asset.m_Name)
                missing = set(FIELDS) - source.keys() - {"EliteBreakEnable"}
                if missing:
                    raise ValueError("Missing authored hit rules: " + str(sorted(missing)))
                row = {key: source[key] for key in FIELDS if key in source}
                # An absent serialized bool retains the native MonsterProperty bool default.
                row.setdefault("EliteBreakEnable", False)
                row["provenance"] = {
                    "source_asset": selected[asset.m_Name]["path"],
                    "asset": asset.m_Name,
                    "bundle": member,
                    "bundle_sha256": hashlib.sha256(bundle_bytes).hexdigest(),
                    "path_id": str(obj.path_id),
                    "decoded_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
                    "fields": sorted(key for key in FIELDS if key in source),
                    "defaulted_fields": ["EliteBreakEnable"] if "EliteBreakEnable" not in source else [],
                }
                enemies[ident] = row
        if len(enemies) + len(action_states) != len(selected):
            raise ValueError("Incomplete MonsterActionCfg extraction")
    return {
        "schema": 1,
        "provenance": {
            "apk_sha256": digest,
            "manifest": manifest_member,
            "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
            "evidence_type": "static package TextAssets; no runtime observation",
            "native_semantics": "reports/monster-hit-rules-native-static.json",
        },
        "enemies": dict(sorted(enemies.items(), key=lambda item: int(item[0]))),
        "action_states": dict(sorted(action_states.items())),
        "action_hit_rules": dict(sorted(action_hit_rules.items())),
        "action_state_provenance": {
            "field": "ActionStatus",
            "hit_rule_fields": ["StableValue", "WeightAddValue", "CanHit"],
            "enum": ACTION_STATES,
            "groups": dict(sorted(action_sources.items())),
        },
    }, raw_actions


def check_hit_action_parity(result, raw_actions, combat):
    from import_region_combat import event

    def is_hit_check(row):
        return any(condition.get("InterruptType") == "EIT_CheckHitAction"
                   for condition in json.loads(row["raw"]).get("Conditions", []))

    current = {row["key"]: row for row in combat["actions"]}
    checked, changed, absent = [], [], []
    for key, action in raw_actions.items():
        authored = [event(row) for row in action.get("Events", []) + action.get("Interrupts", [])]
        source_checks = [row for row in authored if is_hit_check(row)]
        if not source_checks:
            continue
        if key not in current:
            absent.append(key)
            continue
        checked.append(key)
        imported_checks = [row for row in current[key]["events"] if is_hit_check(row)]
        if source_checks != imported_checks:
            changed.append({"key": key, "apk": source_checks, "current": imported_checks})
    return {
        "schema": 1, "apk_sha256": result["provenance"]["apk_sha256"],
        "evidence_type": "static authored EIT_CheckHitAction event comparison",
        "checked_action_count": len(checked), "equal_action_count": len(checked) - len(changed),
        "changed": changed, "apk_actions_missing_from_current": sorted(absent),
        "checked_actions": sorted(checked),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "assets/data/monster_hit_rules.json")
    parser.add_argument("--audit", action="store_true")
    parser.add_argument("--combat", type=Path, default=Path(__file__).resolve().parents[1] / "assets/data/combat.json")
    parser.add_argument("--parity-output", type=Path, default=Path(__file__).resolve().parents[1] / "reports/monster-hit-action-parity.json")
    args = parser.parse_args()
    result, raw_actions = extract(args.apk)
    parity = check_hit_action_parity(result, raw_actions, json.loads(args.combat.read_text()))
    if args.audit:
        if json.loads(args.output.read_text()) != result:
            raise ValueError("Imported monster hit rules differ from the APK")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        args.parity_output.parent.mkdir(parents=True, exist_ok=True)
        args.parity_output.write_text(json.dumps(parity, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"enemies": len(result["enemies"]), "action_states": len(result["action_states"]), "hit_check_actions_equal": parity["equal_action_count"], "hit_check_actions_changed": len(parity["changed"]), "tenacity_values": dict(Counter(str(row["BaseTenacity"]) for row in result["enemies"].values())), "audit": args.audit}))


if __name__ == "__main__":
    main()
