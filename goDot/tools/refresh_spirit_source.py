#!/usr/bin/env python3
"""Refresh the 33 spirit abilities and their complete shipped APK dependencies."""

import argparse
import hashlib
import json
from pathlib import Path

from import_camp_economy import APK_SHA256, awakening_buff, awakening_references
from import_region_combat import hit, packed
from import_supplementary_october import extract_abilities


ROOTS = [20210, 20211, 20212, 20220, 20221, 20222, 20230, 20231, 20232,
         20240, 20241, 20242, 20250, 20251, 20252, 20255, 20256, 20257,
         20260, 20261, 20262, 20265, 20266, 20267, 20270, 20280, 20290,
         20300, 20310, 20320, 20330, 20340, 20350]


def load(path):
    return json.loads(path.read_text())


def differences(before, after, path=""):
    if before == after:
        return []
    if isinstance(before, dict) and isinstance(after, dict):
        result = []
        for key in sorted(before.keys() | after.keys()):
            result.extend(differences(before.get(key), after.get(key), path + "." + key))
        return result
    if isinstance(before, list) and isinstance(after, list) and len(before) == len(after):
        result = []
        for index, (old, new) in enumerate(zip(before, after)):
            result.extend(differences(old, new, path + "[%d]" % index))
        return result
    return [{"field": path.lstrip("."), "before": before, "source": after}]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--combat-evidence", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--audit", action="store_true")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA256:
            raise ValueError("The supplied APK differs from the audited 1061664.apk")
    provenance = load(args.combat_evidence / "provenance.json")
    if provenance["apk_sha256"] != APK_SHA256:
        raise ValueError("Combat evidence belongs to another APK")
    raw = load(args.combat_evidence / "raw-catalog.json")
    abilities, ability_sources = extract_abilities(args.apk, load(args.manifest))
    damages = {}
    for name, values in raw.items():
        if name.startswith("DamageCfg_"):
            for value in values:
                damages.setdefault(str(value["DamageDefId"]), []).append(value)
    required = {kind: set() for kind in ("ability", "buff", "summon", "damage")}
    pending = [("ability", str(ident)) for ident in ROOTS]
    while pending:
        kind, ident = pending.pop()
        if ident in required[kind]:
            continue
        required[kind].add(ident)
        name = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
        value = abilities.get(ident) if kind == "ability" else damages.get(ident) if kind == "damage" else raw.get(name)
        if value is None:
            raise ValueError("Unresolved spirit source dependency: %s %s" % (kind, ident))
        for child_kind, ids in awakening_references(value).items():
            pending.extend((child_kind, child) for child in ids - required[child_kind])

    data = args.project / "assets/data"
    combat = load(data / "combat.json")
    tables = {name: load(data / (name + ".json")) for name in ("AbilityItems", "Buffs", "DamageValues")}
    changes, ledger, source_assets = {}, [], {}
    for kind, plural in (("buff", "buffs"), ("summon", "summons")):
        current = {str(row["id"]): row for row in combat[plural]}
        changed = []
        for ident in sorted(required[kind], key=int):
            name = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
            source = raw[name]
            source_data = source["BuffData" if kind == "buff" else "SummonUnitData"]
            previous = current.get(ident, {}).get("raw_data")
            delta = differences(previous, source_data)
            if delta:
                changed.append(ident)
                ledger.append({"kind": kind, "id": ident, "differences": delta})
            if kind == "buff":
                normalized = awakening_buff(source, damages)
            else:
                normalized = {"id": ident, "type": source["SummonUnitType"],
                    "lifetime": source_data.get("Duration", 0), "interval": source_data.get("TriggerDuration", 99),
                    "hit": hit(source_data, damages), "raw": packed(source), "raw_data": source_data}
            normalized["apk_source"] = provenance["assets"][name]
            source_assets[name] = provenance["assets"][name]
            current[ident] = normalized
        combat[plural] = list(current.values())
        changes[kind] = changed
    for ident in sorted(required["damage"], key=int):
        previous = combat["damage_definitions"].get(ident)
        delta = differences(previous, damages[ident])
        if delta:
            ledger.append({"kind": "damage", "id": ident, "differences": delta})
        combat["damage_definitions"][ident] = damages[ident]
    changes["damage"] = [row["id"] for row in ledger if row["kind"] == "damage"]
    current_abilities = {}
    unrelated_abilities = []
    for row in combat["abilities"]:
        decoded = json.loads(row["raw"])
        ident = str(decoded.get("ID", ""))
        if ident in required["ability"]:
            current_abilities[ident] = row
        else:
            unrelated_abilities.append(row)
    for ident in sorted(required["ability"], key=int):
        previous = current_abilities.get(ident)
        delta = differences(json.loads(previous["raw"]) if previous else None, abilities[ident])
        if delta:
            ledger.append({"kind": "ability", "id": ident, "differences": delta})
        source = ability_sources[ident]
        current_abilities[ident] = {"source": source["source_asset"], "raw": packed(abilities[ident]), "apk_source": source}
    combat["abilities"] = unrelated_abilities + list(current_abilities.values())
    changes["ability"] = [row["id"] for row in ledger if row["kind"] == "ability"]
    for table, kind, key in (("AbilityItems", "ability", "ID"), ("Buffs", "buff", "id"), ("DamageValues", "damage", "Id")):
        current = {str(row[key]): row for row in tables[table]}
        for ident in sorted(required[kind], key=int):
            if kind == "ability":
                value = abilities[ident]
            elif kind == "buff":
                value = dict(raw["BuffCfg_[" + ident + "]"], id=int(ident))
            else:
                rows = damages[ident]
                value = dict(next((row for row in rows if row.get("Level", 1) <= 1), rows[0]), Id=int(ident))
            current[ident] = value
        tables[table] = list(current.values())
    report = {"schema": 1, "apk_sha256": APK_SHA256, "manifest": provenance["manifest"],
        "evidence_type": "Exact static APK TextAssets; no APK runtime observation",
        "root_abilities": ROOTS, "required": {kind: sorted(ids, key=int) for kind, ids in required.items()},
        "source_changes": changes, "differences": ledger, "source_assets": source_assets,
        "ability_sources": {ident: ability_sources[ident] for ident in sorted(required["ability"], key=int)},
        "scope": "Only the 33 spirit roots and their source dependency closure are replaced; unrelated data is preserved."}
    print(packed({"required": {key: len(ids) for key, ids in required.items()}, "changed": {key: len(ids) for key, ids in changes.items()}, "audit": args.audit}))
    if args.audit:
        return
    (data / "combat.json").write_text(packed(combat) + "\n")
    manifest_path = data / "manifest.json"
    manifest = load(manifest_path)
    for name, rows in tables.items():
        payload = (packed(rows) + "\n").encode()
        (data / (name + ".json")).write_bytes(payload)
        manifest["tables"][name] = {"rows": len(rows), "sha256": hashlib.sha256(payload).hexdigest(),
            "source": "APK 1061664: all 33 spirit abilities and complete dependencies",
            "apk_sha256": APK_SHA256, "evidence": {"report": "reports/spirit-source-refresh.json"}}
    manifest_path.write_text(packed(manifest) + "\n")
    (args.project / "reports/spirit-source-refresh.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
