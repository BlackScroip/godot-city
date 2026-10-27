#!/usr/bin/env python3
"""Audit or refresh the ten Boss groups from the exact October APK catalog.

The default is read-only for combat.json. --apply reloads the current catalog,
recompiles the complete source dependency closure and replaces it atomically.
Unrelated combat records are retained. No APK execution is claimed.
"""

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile

from import_camp_economy import awakening_buff
from import_region_combat import event, hit, packed, references, walk


ROOT = Path(__file__).resolve().parents[1]
APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
EX_BUFFS = ["45400001", "45400002", "45400003", "45400004", "45400005", "45400006", "45400010"]


def difference_paths(previous, current, prefix=""):
    if isinstance(previous, dict) and isinstance(current, dict):
        paths = []
        for key in sorted(previous.keys() | current.keys()):
            path = prefix + "/" + key
            paths.extend([path] if key not in previous or key not in current else
                         difference_paths(previous[key], current[key], path))
        return paths
    if isinstance(previous, list) and isinstance(current, list):
        paths = [prefix + "/length"] if len(previous) != len(current) else []
        for index, (old, new) in enumerate(zip(previous, current)):
            paths.extend(difference_paths(old, new, prefix + "/" + str(index)))
        return paths
    return [] if previous == current else [prefix or "/"]


def action_source_rows(action):
    return [{key: row.get(key) for key in ("type", "time", "duration", "enabled", "all")}
            | {"conditions": [json.loads(condition["raw"]) for condition in row.get("conditions", [])],
               "raw": json.loads(row.get("raw", "{}"))}
            for row in action["events"] + action["hits"]]


def source_data(catalog, raw, provenance):
    if provenance.get("apk_sha256") != APK_SHA256:
        raise ValueError("Boss evidence must be extracted from the audited October APK")
    bosses = [row for row in catalog["enemies"] if row.get("rank") == "Boss"]
    groups = {row["group"].lower(): row["group"] for row in bosses}
    actions = {}
    for key, value in raw.items():
        if not isinstance(value, dict) or "ActId" not in value:
            continue
        source_group = Path(provenance["assets"][key]["source_asset"]).parent.name
        if source_group.lower() in groups:
            group = groups[source_group.lower()]
            action_key = group + "/" + value["ActId"]
            if action_key in actions:
                raise ValueError("Duplicate source action: " + action_key)
            actions[action_key] = (key, group, value)
    if len(bosses) != 10 or len(groups) != 10 or len(actions) != 208:
        raise ValueError("Expected ten Boss groups with 208 complete source actions")
    current_actions = {row["key"] for row in catalog["actions"] if row["group"].lower() in groups}
    if current_actions != actions.keys():
        raise ValueError("Boss action inventory differs: " + packed({
            "missing": sorted(actions.keys() - current_actions),
            "extra": sorted(current_actions - actions.keys())}))
    damage = {}
    for key, value in raw.items():
        if key.startswith("DamageCfg_"):
            for row in value:
                damage.setdefault(str(row["DamageDefId"]), []).append(row)
    graphs = {boss["ai"]: raw[boss["ai"]] for boss in bosses}
    queue = [value for _, _, value in actions.values()] + list(graphs.values())
    queue.append({"BuffId": EX_BUFFS})
    for graph in graphs.values():
        for value in walk(graph):
            for key, child in value.items():
                if key in ("BuffId", "CheckBuffId") and isinstance(child, dict):
                    queue.append({"BuffId": child.get("_value", "")})
    required = {kind: set() for kind in ("buff", "summon", "damage")}
    missing = {kind: [] for kind in required}
    while queue:
        for kind, identifiers in references(queue.pop()).items():
            for ident in identifiers - required[kind]:
                required[kind].add(ident)
                key = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
                value = damage.get(ident) if kind == "damage" else raw.get(key)
                if value is None:
                    missing[kind].append(ident)
                else:
                    queue.append(value)
    if any(missing.values()):
        raise ValueError("Unresolved fresh Boss dependencies: " + packed(missing))
    return bosses, actions, graphs, damage, required


def refresh(catalog, raw, provenance):
    bosses, actions, graphs, damage, required = source_data(catalog, raw, provenance)
    expected = copy.deepcopy(catalog)
    changes = {kind: {} for kind in ("actions", "ai_graphs", "buffs", "summons", "damage_definitions")}
    raw_changes = {kind: [] for kind in ("actions", "ai_graphs", "buffs", "summons", "damage_definitions")}

    def record(kind, ident, previous, current, previous_raw, current_raw):
        paths = difference_paths(previous, current)
        if paths:
            changes[kind][ident] = paths
        if previous_raw != current_raw:
            raw_changes[kind].append(ident)

    for ident in sorted(required["damage"], key=int):
        previous = catalog["damage_definitions"].get(ident)
        record("damage_definitions", ident, previous, damage[ident], previous, damage[ident])
        expected["damage_definitions"][ident] = damage[ident]
    for kind, plural, data_key in (("buff", "buffs", "BuffData"), ("summon", "summons", "SummonUnitData")):
        rows = {str(row["id"]): row for row in expected[plural]}
        for ident in sorted(required[kind], key=int):
            key = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
            value = raw[key]
            normalized = awakening_buff(value, damage) if kind == "buff" else {
                "id": ident, "type": value["SummonUnitType"],
                "lifetime": value[data_key].get("Duration", 0),
                "interval": value[data_key].get("TriggerDuration", 99),
                "hit": hit(value[data_key], damage),
                "raw": packed(value), "raw_data": value[data_key]}
            normalized["apk_source"] = provenance["assets"][key]
            previous = rows.get(ident)
            previous_raw = json.loads(previous.get("raw", "{}")) if previous else None
            record(plural, ident, previous, normalized, previous_raw, value)
            rows[ident] = normalized
        expected[plural] = list(rows.values())
    rows = {row["key"]: row for row in expected["actions"]}
    for action_key, (source_key, group, value) in actions.items():
        normalized = {"key": action_key, "group": group, "id": value["ActId"],
            "name": value.get("Name_EDT", ""), "duration": value["TotalTime"] / 1000.0,
            "speed": value["PlaySpeed"],
            "events": [event(row) for row in value.get("Events", []) + value.get("Interrupts", [])],
            "hits": [hit(row["EventData"], damage, row) for row in value.get("AttackDefs", [])],
            "source": provenance["assets"][source_key]["source_asset"],
            "apk_source": provenance["assets"][source_key]}
        previous = rows[action_key]
        old_raw = action_source_rows(previous)
        new_raw = action_source_rows(normalized)
        record("actions", action_key, previous, normalized, old_raw, new_raw)
        rows[action_key] = normalized
    expected["actions"] = list(rows.values())
    for key, graph in graphs.items():
        previous = catalog["ai_graphs"].get(key)
        record("ai_graphs", key, previous, graph, previous, graph)
        expected["ai_graphs"][key] = graph
    report = {"schema": 2, "apk_sha256": provenance["apk_sha256"],
        "evidence_type": "Static packaged source comparison and recompilation; no original APK execution.",
        "scope": "All events, interrupts and hit rows (including disabled rows) in all 208 actions across ten Boss groups; complete source AI graphs, AI BuffId/CheckBuffId parameters, seven cumulative Boss EX roots, and recursive fresh-source buff/summon/damage references. All reachable buff/summon runtime fields are recompiled, removing obsolete derived triggers.",
        "bosses": [{"id": row["id"], "group": row["group"]} for row in bosses],
        "action_count": len(actions), "ai_graph_count": len(graphs),
        "closure_counts": {kind: len(ids) for kind, ids in required.items()},
        "closure_ids": {kind: sorted(ids, key=int) for kind, ids in required.items()},
        "changed_counts": {kind: len(rows) for kind, rows in changes.items()},
        "changed_keys": {kind: sorted(rows) for kind, rows in changes.items()},
        "source_raw_differences": {kind: sorted(ids) for kind, ids in raw_changes.items()},
        "changed_field_paths": changes}
    return expected, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    raw = json.loads((args.evidence / "raw-catalog.json").read_text())
    provenance = json.loads((args.evidence / "provenance.json").read_text())
    if provenance["apk_sha256"] != APK_SHA256:
        raise ValueError("Boss evidence must be extracted from the audited October APK")
    combat_path = args.project / "assets/data/combat.json"
    before = combat_path.read_bytes()
    catalog = json.loads(before)
    expected, report = refresh(catalog, raw, provenance)
    report["applied"] = args.apply
    report["source_catalog_sha256"] = hashlib.sha256((args.evidence / "raw-catalog.json").read_bytes()).hexdigest()
    report["combat_before_sha256"] = hashlib.sha256(before).hexdigest()
    if args.apply:
        if combat_path.read_bytes() != before:
            raise RuntimeError("combat.json changed while preparing refresh; rerun from the latest file")
        payload = (packed(expected) + "\n").encode()
        with tempfile.NamedTemporaryFile(dir=combat_path.parent, prefix=".boss-refresh-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(payload)
        try:
            if combat_path.read_bytes() != before:
                raise RuntimeError("combat.json changed before atomic replacement; rerun")
            os.replace(temporary, combat_path)
        finally:
            temporary.unlink(missing_ok=True)
        _, after_report = refresh(json.loads(combat_path.read_bytes()), raw, provenance)
        report["remaining_changed_counts"] = after_report["changed_counts"]
        if any(after_report["changed_counts"].values()):
            raise ValueError("Boss source refresh is not idempotent")
        report["combat_after_sha256"] = hashlib.sha256(payload).hexdigest()
    report_path = args.project / "reports/boss-source-refresh.json"
    if report_path.exists():
        previous = json.loads(report_path.read_text())
        if previous.get("schema") == report["schema"] and previous.get("apk_sha256") == APK_SHA256 and (
                previous.get("applied", False) or "initial_audit" in previous):
            report["initial_audit"] = previous.get("initial_audit", {
                key: previous[key] for key in ("changed_counts", "changed_keys", "source_raw_differences")})
    if args.apply and "initial_audit" not in report:
        report["initial_audit"] = {
            key: report[key] for key in ("changed_counts", "changed_keys", "source_raw_differences")}
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ("applied", "action_count", "ai_graph_count", "closure_counts", "changed_counts", "source_raw_differences")}, indent=2))


if __name__ == "__main__":
    main()
