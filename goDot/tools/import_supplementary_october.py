#!/usr/bin/env python3
"""Merge source-backed missing October loot and its combat dependencies."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import zipfile

from import_camp_economy import APK_SHA256, awakening_buff, awakening_references, write
from import_region_combat import hit, packed, walk


ROOTS = [20255, 20256, 20257, 20265, 20266, 20267, 20320, 20330, 20340,
         20350, 20600, 20601, 20602, 20610, 20611, 20612, 20613, 21180,
         21181, 21182, 21183, 23160, 23161, 23162, 23163, 23164]
TABLES = ("LootData", "ItemPoolSubData", "ItemPoolData", "UnlockData")


def load(path):
    return json.loads(path.read_text())


def extract_abilities(apk, manifest):
    import UnityPy

    selected = {row["address"]: row for row in manifest["assets"]
                if row["address"].startswith("AbilityItemCfg_")}
    records, sources = {}, {}
    with zipfile.ZipFile(apk) as archive:
        for index in sorted({row["bundle"] for row in selected.values()}):
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in selected:
                    continue
                asset = obj.read()
                text = asset.m_Script
                text = text.decode("utf-8-sig") if isinstance(text, bytes) else text.lstrip("\ufeff")
                row = json.loads(text)
                ident = str(row["ID"])
                records[ident] = row
                sources[ident] = {"source_asset": selected[asset.m_Name]["path"],
                    "bundle": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                    "path_id": str(obj.path_id), "decoded_sha256": hashlib.sha256(text.encode()).hexdigest()}
    return records, sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--table-evidence", type=Path, required=True)
    parser.add_argument("--combat-evidence", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--audit", action="store_true")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA256:
            raise ValueError("This bounded import requires the audited APK")
    table_provenance = load(args.table_evidence / "provenance.json")
    provenance = load(args.combat_evidence / "provenance.json")
    if table_provenance["apk_sha256"] != APK_SHA256 or provenance["apk_sha256"] != APK_SHA256:
        raise ValueError("Evidence belongs to another APK")
    source_tables = {}
    for name in TABLES:
        path = args.table_evidence / (name + ".json")
        if hashlib.sha256(path.read_bytes()).hexdigest() != table_provenance["tables"][name]["decoded_sha256"]:
            raise ValueError("Changed decoded source table: " + name)
        source_tables[name] = load(path)
    abilities, ability_sources = extract_abilities(args.apk, load(args.manifest))
    raw = load(args.combat_evidence / "raw-catalog.json")
    all_damage = {}
    contexts = {}
    for name, value in raw.items():
        if name.startswith("DamageCfg_"):
            for row in value:
                all_damage.setdefault(str(row["DamageDefId"]), []).append(row)
        kind = "buff" if name.startswith("BuffCfg_[") else "summon" if name.startswith("SummonUnitCfg_[") else None
        if kind is None:
            continue
        ident = name.split("[")[1].rstrip("]")
        for item in walk(value):
            for key, text in item.items():
                if "PropertyContext" in key and isinstance(text, str):
                    for context in text.split("|"):
                        if context:
                            contexts.setdefault(context, set()).add((kind, ident))
    required = {kind: set() for kind in ("ability", "buff", "summon", "damage")}
    pending = [("ability", str(ident)) for ident in ROOTS]
    while pending:
        kind, ident = pending.pop()
        if ident in required[kind]:
            continue
        required[kind].add(ident)
        name = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
        value = abilities.get(ident) if kind == "ability" else all_damage.get(ident) if kind == "damage" else raw.get(name)
        if value is None:
            raise ValueError("Unresolved source dependency: " + kind + " " + ident)
        for child_kind, ids in awakening_references(value).items():
            pending.extend((child_kind, child) for child in ids - required[child_kind])
        if kind == "buff" and value.get("BuffType") == "EBT_EditorPropertyContext":
            for settings in value["BuffData"].get("BuffSettingDataList", []):
                for key in ("Name", "Name2", "Name3"):
                    pending.extend(contexts.get(settings.get(key, ""), set()))

    data = args.project / "assets/data"
    combat = load(data / "combat.json")
    changes = Counter()
    rows = {name: load(data / (name + ".json")) for name in (*TABLES, "AbilityItems", "Buffs", "DamageValues")}
    added_ids = {}
    updated_pools = []
    for name in TABLES:
        current = {int(row["id"]): row for row in rows[name]}
        source = {int(row["id"]): row for row in source_tables[name]}
        if name == "ItemPoolData":
            if set(current) != set(source):
                raise ValueError("Review unexpected pool IDs")
            for ident, row in source.items():
                changed_keys = {key for key, value in row.items() if current[ident].get(key) != value}
                if changed_keys - {"sub_data_id_list"}:
                    raise ValueError("Review unexpected pool changes: " + str(ident))
                if changed_keys:
                    current[ident]["sub_data_id_list"] = row["sub_data_id_list"]
                    updated_pools.append(ident)
            changes[name] = len(updated_pools)
            continue
        if name == "UnlockData":
            if any(current.get(ident) != row for ident, row in source.items()):
                raise ValueError("Review existing source gates before merging: " + name)
            continue
        added_ids[name] = [ident for ident in source if ident not in current]
        if name == "LootData" and set(added_ids[name]) - set(ROOTS):
            raise ValueError("Unexpected missing loot outside the bounded selection")
        rows[name].extend(source[ident] for ident in added_ids[name])
        changes[name] = len(added_ids[name])
    for name, kind, key in (("AbilityItems", "ability", "ID"), ("Buffs", "buff", "id"), ("DamageValues", "damage", "Id")):
        current = {str(row[key]) for row in rows[name]}
        for ident in sorted(required[kind] - current, key=int):
            if kind == "ability":
                value = abilities[ident]
            elif kind == "buff":
                value = dict(raw["BuffCfg_[" + ident + "]"], id=int(ident))
            else:
                source = next((row for row in all_damage[ident] if row.get("Level", 1) == 1), all_damage[ident][0])
                value = dict(source, Id=int(ident))
            rows[name].append(value)
            changes[name] += 1
    for ident in sorted(required["damage"] - combat["damage_definitions"].keys(), key=int):
        combat["damage_definitions"][ident] = all_damage[ident]
        changes["combat_damage"] += 1
    for kind, plural in (("buff", "buffs"), ("summon", "summons")):
        current = {str(row["id"]) for row in combat[plural]}
        for ident in sorted(required[kind] - current, key=int):
            name = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
            source = raw[name]
            if kind == "buff":
                value = awakening_buff(source, all_damage)
            else:
                value = {"id": ident, "type": source["SummonUnitType"],
                    "lifetime": source["SummonUnitData"].get("Duration", 0),
                    "interval": source["SummonUnitData"].get("TriggerDuration", 99),
                    "hit": hit(source["SummonUnitData"], combat["damage_definitions"]),
                    "raw": packed(source), "raw_data": source["SummonUnitData"]}
            value["apk_source"] = provenance["assets"][name]
            combat[plural].append(value)
            changes["combat_" + plural] += 1
    source_loot = {int(row["id"]): row for row in source_tables["LootData"]}
    source_subs = {int(row["id"]): row for row in source_tables["ItemPoolSubData"]}
    related_subs = {ident: row for ident, row in source_subs.items()
        if any(int(token) in ROOTS for token in row["item_id_list_str"].split(",") if token.isdecimal())}
    pools = {str(row["id"]): [int(token) for token in str(row["sub_data_id_list"]).split(",")
        if token.isdecimal() and int(token) in related_subs] for row in source_tables["ItemPoolData"]}
    report = {"schema": 1, "apk_sha256": APK_SHA256, "loot_ids": ROOTS,
        "added": dict(changes), "added_ids": added_ids, "updated_pool_ids": updated_pools,
        "required": {kind: sorted(ids, key=int) for kind, ids in required.items()},
        "loot_rows": {str(ident): source_loot[ident] for ident in ROOTS},
        "item_pool_sub_rows": related_subs, "pool_membership": {key: ids for key, ids in pools.items() if ids},
        "ability_sources": {ident: ability_sources[ident] for ident in sorted(required["ability"], key=int)},
        "table_sources": {name: table_provenance["tables"][name] for name in TABLES},
        "limitations": ["Source rows with no packaged pool entry retain no invented pool entry.",
            "Existing ability, buff, summon, damage and action records are preserved.",
            "Static source dependency recovery does not establish complete original runtime parity."]}
    report_path = args.project / "reports/supplementary-october-import.json"
    if report_path.exists():
        previous = load(report_path)
        if previous.get("apk_sha256") == APK_SHA256:
            report["initial_import"] = previous.get("initial_import", {"added": previous["added"], "added_ids": previous["added_ids"]})
    report.setdefault("initial_import", {"added": report["added"], "added_ids": report["added_ids"]})
    if not args.audit:
        changed_tables = ("LootData", "ItemPoolSubData", "ItemPoolData", "AbilityItems", "Buffs", "DamageValues")
        for name in changed_tables:
            write(data / (name + ".json"), rows[name])
        write(data / "combat.json", combat)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        manifest_path = data / "manifest.json"
        manifest = load(manifest_path)
        for name in changed_tables:
            path = data / (name + ".json")
            manifest["tables"][name].update({"rows": len(rows[name]),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "source": "APK 1061664: missing supplementary loot and source dependency merge",
                "evidence": {"report": "reports/supplementary-october-import.json", "preserve_existing_dependencies": True}})
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(packed({"added": report["added"], "required_counts": {kind: len(ids) for kind, ids in required.items()},
        "added_ids": added_ids, "pool_membership": report["pool_membership"]}))


if __name__ == "__main__":
    main()
