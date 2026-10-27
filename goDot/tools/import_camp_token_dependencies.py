"""Refresh token rows and add only missing dependencies from audited APK 1061664."""

import argparse
import hashlib
import json
from pathlib import Path

import compare_camp_apks
from import_camp_economy import APK_SHA256, awakening_buff, awakening_references, extract_awakening_abilities, write
from import_region_combat import hit, packed, walk


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--combat-evidence", type=Path, required=True)
    args = parser.parse_args()
    compare_camp_apks.TABLES = {"RelationshipTokenData", "MaterialData"}
    evidence = compare_camp_apks.extract(args.apk)
    if evidence["sha256"] != APK_SHA256:
        raise ValueError("Unexpected APK")
    data = args.project / "assets/data"
    tokens = evidence["tables"]["RelationshipTokenData"]["data"]
    existing_abilities = {str(row["ID"]) for row in json.loads((data / "AbilityItems.json").read_text())}
    roots = {str(row["abilityitem_id"]) for row in tokens} - existing_abilities
    abilities, ability_sources = extract_awakening_abilities(args.apk, roots)
    raw = json.loads((args.combat_evidence / "raw-catalog.json").read_text())
    provenance = json.loads((args.combat_evidence / "provenance.json").read_text())
    if provenance["apk_sha256"] != APK_SHA256:
        raise ValueError("Unexpected combat evidence")
    damages, contexts = {}, {}
    for name, value in raw.items():
        if name.startswith("DamageCfg_"):
            for row in value:
                damages.setdefault(str(row["DamageDefId"]), []).append(row)
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
    pending = [("ability", ident) for ident in roots]
    while pending:
        kind, ident = pending.pop()
        if ident in required[kind]:
            continue
        required[kind].add(ident)
        name = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
        value = abilities.get(ident) if kind == "ability" else damages.get(ident) if kind == "damage" else raw.get(name)
        if value is None:
            raise ValueError("Missing dependency: " + kind + " " + ident)
        for child_kind, identifiers in awakening_references(value).items():
            pending.extend((child_kind, child) for child in identifiers - required[child_kind])
        if kind == "buff" and value.get("BuffType") == "EBT_EditorPropertyContext":
            for settings in value["BuffData"].get("BuffSettingDataList", []):
                for key in ("Name", "Name2", "Name3"):
                    pending.extend(contexts.get(settings.get(key, ""), set()))
    rows = {name: json.loads((data / (name + ".json")).read_text()) for name in ("RelationshipTokenData", "MaterialData", "AbilityItems", "Buffs", "DamageValues")}
    token_diff = compare_camp_apks.differences(rows["RelationshipTokenData"], tokens)
    rows["RelationshipTokenData"] = tokens
    material_ids = {int(row["id"]) for row in rows["MaterialData"]}
    token_material_ids = {int(row["material_id"]) for row in tokens}
    rows["MaterialData"].extend(row for row in evidence["tables"]["MaterialData"]["data"] if int(row["id"]) in token_material_ids - material_ids)
    added = {}
    for name, kind, key in (("AbilityItems", "ability", "ID"), ("Buffs", "buff", "id"), ("DamageValues", "damage", "Id")):
        current = {str(row[key]) for row in rows[name]}
        added[name] = sorted(required[kind] - current, key=int)
        for ident in added[name]:
            if kind == "ability":
                value = abilities[ident]
            elif kind == "buff":
                value = dict(raw["BuffCfg_[" + ident + "]"], id=int(ident))
            else:
                value = dict(next((row for row in damages[ident] if row.get("Level", 1) == 1), damages[ident][0]), Id=int(ident))
            rows[name].append(value)
    combat = json.loads((data / "combat.json").read_text())
    for ident in required["damage"] - combat["damage_definitions"].keys():
        combat["damage_definitions"][ident] = damages[ident]
    for kind, plural in (("buff", "buffs"), ("summon", "summons")):
        existing = {str(row["id"]) for row in combat[plural]}
        added["combat_" + plural] = sorted(required[kind] - existing, key=int)
        for ident in added["combat_" + plural]:
            name = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
            source = raw[name]
            if kind == "buff":
                value = awakening_buff(source, damages)
            else:
                value = {"id": ident, "type": source["SummonUnitType"], "lifetime": source["SummonUnitData"].get("Duration", 0), "interval": source["SummonUnitData"].get("TriggerDuration", 99), "hit": hit(source["SummonUnitData"], combat["damage_definitions"]), "raw": packed(source), "raw_data": source["SummonUnitData"]}
            value["apk_source"] = provenance["assets"][name]
            combat[plural].append(value)
    report = {"apk_sha256": APK_SHA256, "added": added, "token_diff": token_diff, "token_count": len(tokens), "material_ids_added": sorted(token_material_ids - material_ids), "required": {kind: sorted(ids, key=int) for kind, ids in required.items()}, "ability_sources": {ident: ability_sources[ident] for ident in required["ability"]}, "tables": evidence["tables"], "limitations": ["Existing combat records preserved; static dependency closure does not prove runtime equivalence."]}
    for name, values in rows.items():
        write(data / (name + ".json"), values)
    write(data / "combat.json", combat)
    manifest_path = data / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    for name, values in rows.items():
        manifest["tables"][name].update({"rows": len(values), "sha256": hashlib.sha256((data / (name + ".json")).read_bytes()).hexdigest(), "source": "APK 1061664: token table and missing dependency closure", "evidence": {"report": "reports/camp-token-dependency-import.json", "preserve_existing_dependencies": True}})
    write(manifest_path, manifest)
    (args.project / "reports/camp-token-dependency-import.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"token_count": len(tokens), "added_counts": {name: len(ids) for name, ids in added.items()}, "material_ids_added": report["material_ids_added"]}))


if __name__ == "__main__":
    main()
