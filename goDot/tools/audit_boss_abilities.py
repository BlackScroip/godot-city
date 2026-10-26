#!/usr/bin/env python3
"""Audit the imported Boss action and buff/summon/damage dependency closure."""

import argparse
import json
from pathlib import Path

from import_region_combat import references, walk
from refresh_boss_source import refresh


ROOT = Path(__file__).resolve().parents[1]
EX_BUFFS = ["45400001", "45400002", "45400003", "45400004", "45400005", "45400006", "45400010"]
KNOWN_MISSING_ACTIONS = {
    "ActGroup_dilong/EX_Attack2",
    "ActGroup_dilong/EX_Attack3",
    "ActGroup_jianchihu/attack1_EX",
    "ActGroup_jianchihu/attack3_EX",
    "ActGroup_jianchihu/attack7_EX",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    args = parser.parse_args()
    catalog = json.loads((ROOT / "assets/data/combat.json").read_text())
    raw = json.loads((args.evidence / "raw-catalog.json").read_text())
    provenance = json.loads((args.evidence / "provenance.json").read_text())
    _, parity = refresh(catalog, raw, provenance)
    behavior = json.loads((ROOT / "assets/data/monster_behavior.json").read_text())
    bosses = [enemy for enemy in catalog["enemies"] if enemy["rank"] == "Boss"]
    groups = {enemy["group"] for enemy in bosses}
    source_outputs = {enemy["group"]: set(enemy["ai_action_ids"]) for enemy in bosses}
    actions = [action for action in catalog["actions"] if action["group"] in groups]
    action_index = {action["key"]: action for action in actions}
    roots = [{"BuffId": identifier} for identifier in EX_BUFFS]
    missing_actions = []
    outside_timeline = []
    mapped_outputs = set()
    for action in actions:
        for row in action["events"] + action["hits"]:
            if not row.get("enabled", True):
                continue
            raw = json.loads(row.get("raw", "{}"))
            roots.append(raw)
            roots.extend(json.loads(condition["raw"]) for condition in row.get("conditions", []))
            if row.get("type") != "EET_Interrupt":
                if float(row.get("time", 0)) > float(action["duration"]):
                    outside_timeline.append({"action": action["key"], "type": row.get("type", "hit"), "time": row["time"], "duration": action["duration"]})
                continue
            target = action["group"] + "/" + row.get("target", "")
            if target not in action_index:
                missing_actions.append({"from": action["key"], "target": target, "requested_by_ai": row.get("target", "") in source_outputs[action["group"]]})
            else:
                mapped_outputs.update(action["group"] + "/" + condition.get("CompareVal", "") for condition in raw.get("Conditions", []) if condition.get("InterruptType") == "EIT_CheckAI")
    unmapped_outputs = []
    for enemy in bosses:
        for obj in walk(catalog["ai_graphs"][enemy["ai"]]):
            for key, value in obj.items():
                if key in ("BuffId", "CheckBuffId") and isinstance(value, dict) and isinstance(value.get("_value"), str):
                    roots.append({"BuffId": value["_value"]})
        for output in enemy["ai_action_ids"]:
            key = enemy["group"] + "/" + output
            if key not in action_index and key not in mapped_outputs:
                unmapped_outputs.append({"enemy": enemy["id"], "output": key})
    indexes = {
        "buff": {str(value["id"]): value for value in catalog["buffs"]},
        "summon": {str(value["id"]): value for value in catalog["summons"]},
        "damage": catalog["damage_definitions"],
    }
    seen = {kind: set() for kind in indexes}
    missing = {kind: [] for kind in indexes}
    while roots:
        for kind, identifiers in references(roots.pop()).items():
            for identifier in identifiers - seen[kind]:
                seen[kind].add(identifier)
                value = indexes[kind].get(identifier)
                if value is None:
                    missing[kind].append(identifier)
                elif isinstance(value, dict):
                    roots.append(value.get("raw_data", value))
                elif isinstance(value, list):
                    roots.append(value)
    observed_missing = {entry["target"] for entry in missing_actions}
    expected_source_gaps = observed_missing == KNOWN_MISSING_ACTIONS and not unmapped_outputs
    result = {
        "passed": len(bosses) == 10 and len(actions) == 208 and not any(missing.values()) and expected_source_gaps and not any(parity["changed_counts"].values()),
        "evidence_type": "Static imported APK serialization and transitive dependency resolution; no APK execution or render validation.",
        "provenance": behavior["provenance"],
        "bosses": [{"id": enemy["id"], "group": enemy["group"], "actions": sum(action["group"] == enemy["group"] for action in actions)} for enemy in bosses],
        "actions": len(actions),
        "reachable_counts": {kind: len(identifiers) for kind, identifiers in seen.items()},
        "reachable_ids": {kind: sorted(identifiers) for kind, identifiers in seen.items()},
        "missing_dependencies": missing,
        "missing_action_targets": missing_actions,
        "unmapped_ai_outputs": unmapped_outputs,
        "commands_after_action_duration": outside_timeline,
        "fresh_source_parity": {key: parity[key] for key in ("apk_sha256", "action_count", "ai_graph_count", "closure_counts", "closure_ids", "changed_counts", "changed_keys", "source_raw_differences")},
        "scope": "Enabled events/hits in every Boss action, AI buff predicates/tasks and all cumulative Boss EX difficulty roots. References use the production format-aware importer. Missing action targets are explicitly retained source gaps. requested_by_ai denotes a serialized OP_AIAction producer; a helper route is not proof of an existing terminal attack. Missing targets retain their authored helper idle fallback.",
    }
    output = ROOT / "reports/boss-ability-source.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    summary = {key: result[key] for key in ["passed", "actions", "reachable_counts", "missing_dependencies", "missing_action_targets", "unmapped_ai_outputs", "commands_after_action_duration"]}
    summary["fresh_source_parity"] = {key: value for key, value in result["fresh_source_parity"].items() if key != "closure_ids"}
    print(json.dumps(summary, indent=2))
    raise SystemExit(0 if result["passed"] else 1)


if __name__ == "__main__":
    main()
