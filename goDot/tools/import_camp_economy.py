"""Apply bounded camp/economic data from compare_camp_apks.py evidence.

Keeps project-only fields and unrelated combat/presentation configuration.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import zipfile


FULL_TABLES = {"SubAchieveData", "AchieveData", "UnlockData", "MonsterWorkData"}
FIELDS = {
	"CharData": {"available_state", "no_discount_origin_price", "need_unlock_materials", "unlock_data_id", "is_cash_only_unlock"},
    "MonsterPartnerData": {"unlock_need_kill_count", "is_admin_only"},
    "WeaponData": {"unlock_mineral_mat_count"},
    "CharaTalentAwakeTreeData": {"active_need_awake_point", "unlock_need_material_list", "is_enabled", "is_admin_mode"},
}
CONFIG_KEYS = {"MainCityDecorationDataList", "MainCityDecorationSlotList",
               "MaxLootInactiveLimit", "LootInactiveUpgradeCost"}
APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")


def reference_ids(value):
    values = value if isinstance(value, list) else [value]
    return {token for item in values if isinstance(item, (str, int))
            for token in re.split(r"[|,]", str(item))
            if token.isdecimal() and int(token) > 0}


def awakening_references(value):
    from import_region_combat import walk
    result = {kind: set() for kind in ("ability", "buff", "summon", "damage")}
    for item in walk(value):
        for key, child in item.items():
            key = key.lower()
            if key in ("initcleartargetbuffidlist", "delbuffidlist"):
                continue
            kind = "ability" if "abilityitem" in key and "id" in key else (
                "buff" if "buff" in key and ("id" in key or key in ("addbuff", "modifybuff")) else (
                "summon" if "summon" in key and "id" in key else (
                "damage" if "damage" in key and "id" in key else None)))
            if kind:
                result[kind].update(reference_ids(child))
    return result


def extract_awakening_abilities(apk, wanted):
    import UnityPy
    from inspect_camp_progression import manifest_records
    with apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA256:
            raise ValueError("Awakening dependencies require the audited APK")
    values, sources = {}, {}
    with zipfile.ZipFile(apk) as archive:
        manifests = [name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes")]
        if len(manifests) != 1:
            raise ValueError("Expected one YooAsset manifest")
        assets, bundles = manifest_records(archive.read(manifests[0]))
        selected = [row for row in assets if row["address"].startswith("AbilityItemCfg_")]
        asset_sources = {row["address"]: row["path"] for row in selected}
        for index in sorted({row["bundle"] for row in selected}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset":
                    continue
                asset = obj.read()
                if asset.m_Name not in asset_sources:
                    continue
                text = asset.m_Script
                text = text.decode("utf-8-sig") if isinstance(text, bytes) else text.lstrip("\ufeff")
                row = json.loads(text)
                ident = str(row["ID"])
                values[ident] = row
                sources[ident] = {"source_asset": asset_sources[asset.m_Name], "member": member,
                                  "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                                  "path_id": obj.path_id, "text_sha256": hashlib.sha256(text.encode()).hexdigest()}
    missing = wanted - values.keys()
    if missing:
        raise ValueError("Missing awakening abilities: " + str(sorted(missing)))
    return values, sources


def awakening_buff(raw, damage):
    from import_region_combat import buff
    row = buff(raw)
    data = raw["BuffData"]
    settings = (data.get("BuffSettingDataList", []) or [{}])[0]
    if row["type"] == "EBT_SpecialSetState":
        row.update({"setState": True, "freezeTime": settings.get("ForzenTime", 0) / 1000.0,
                    "godTime": settings.get("GodTime", 0) / 1000.0,
                    "slowTime": settings.get("RetardTime", 0) / 1000.0,
                    "slowScale": settings.get("RetardScale", 1)})
    if row["type"] == "EBT_SpecialTriggerRangeDamage":
        coefficients = damage.get(str(settings.get("DamageDefId", 0)), [])
        coefficient = next((value for value in coefficients if value.get("Level", 1) == 1), coefficients[0] if coefficients else {})
        multiplier = coefficient.get("DamageMulValue", 0) / 1000.0
        fixed = coefficient.get("DamageFixValue", 0)
        row.update({"interval": settings.get("TriggerTimeCd", 1000) / 1000.0,
                    "selfOnlyDamage": bool(data.get("EffectToSelf", False)) and settings.get("EffectRadius", 0) <= 0,
                    "multiplier": multiplier, "fixedDamage": fixed})
        if not row["selfOnlyDamage"]:
            target = settings.get("BuffTrigger_AddToAttackee", {})
            target_buffs = [{"id": str(target["BuffTriggerId"]), "layers": target.get("BuffAddLayer", 1)}] if target.get("BuffTriggerId") else []
            row["area"] = {"radius": settings.get("EffectRadius", 0), "sameCamp": data.get("TargetIsSelfCamp", False),
                "includeSelf": data.get("EffectToSelf", False), "enableDamage": data.get("EnableDamage", False),
                "addAfterHit": data.get("IsAddBuffAfterHit", False), "damageId": settings.get("DamageDefId", 0),
                "attribute": coefficient.get("DamageAttribType", "None"), "element": coefficient.get("DamageType", "None"),
                "actType": coefficient.get("DamageActType", "Other"), "multiplier": multiplier, "fixedDamage": fixed,
                "critical": coefficient.get("EnableCriticle", False), "targetBuffs": target_buffs,
                "push": settings.get("PushPower", 0), "upper": settings.get("UpperPower", 0), "tenacity": settings.get("AccTenacity", 0)}
    return row


def import_awakening(args, tables):
    from import_region_combat import hit, packed, walk
    nodes = tables["CharaTalentAwakeTreeData"]["data"]
    old_nodes = json.loads((args.data / "CharaTalentAwakeTreeData.json").read_text())
    node_ids = {int(row["id"]) for row in old_nodes}
    roots = {str(row["ability_item_id"]) for row in nodes}
    abilities, ability_sources = extract_awakening_abilities(args.apk, roots)
    raw = json.loads((args.combat_evidence / "raw-catalog.json").read_text())
    provenance = json.loads((args.combat_evidence / "provenance.json").read_text())
    if provenance["apk_sha256"] != APK_SHA256:
        raise ValueError("Combat dependency evidence is from another APK")
    context_consumers = {}
    for key, value in raw.items():
        kind = "buff" if key.startswith("BuffCfg_[") else "summon" if key.startswith("SummonUnitCfg_[") else None
        if kind is None:
            continue
        ident = key.split("[")[1].rstrip("]")
        for item in walk(value):
            for name, contexts in item.items():
                if "PropertyContext" not in name or not isinstance(contexts, str):
                    continue
                for context in contexts.split("|"):
                    if context:
                        context_consumers.setdefault(context, set()).add((kind, ident))
    all_damage = {}
    for key, value in raw.items():
        if key.startswith("DamageCfg_"):
            for row in value:
                all_damage.setdefault(str(row["DamageDefId"]), []).append(row)
    required = {kind: set() for kind in ("ability", "buff", "summon", "damage")}
    pending = [("ability", ident) for ident in sorted(roots, key=int)]
    missing = {kind: [] for kind in required}
    required_contexts = set()
    while pending:
        kind, ident = pending.pop()
        if ident in required[kind]:
            continue
        required[kind].add(ident)
        key = {"buff": "BuffCfg_", "summon": "SummonUnitCfg_"}.get(kind, "") + "[" + ident + "]"
        row = abilities.get(ident) if kind == "ability" else all_damage.get(ident) if kind == "damage" else raw.get(key)
        if row is None:
            missing[kind].append(ident)
            continue
        for child_kind, identifiers in awakening_references(row).items():
            pending.extend((child_kind, child) for child in identifiers - required[child_kind])
        if kind == "buff" and row.get("BuffType") == "EBT_EditorPropertyContext":
            for settings in row.get("BuffData", {}).get("BuffSettingDataList", []):
                for name in ("Name", "Name2", "Name3"):
                    context = settings.get(name, "")
                    if context:
                        required_contexts.add(context)
                        pending.extend(context_consumers.get(context, set()))
    if any(missing.values()):
        raise ValueError("Unresolved awakening references: " + packed(missing))

    combat_path = args.data / "combat.json"
    combat = json.loads(combat_path.read_text())
    additions = Counter()
    domain_rows = {}
    domain_keys = {"AbilityItems": "ID", "Buffs": "id", "DamageValues": "Id"}
    for table in domain_keys:
        domain_rows[table] = json.loads((args.data / (table + ".json")).read_text())
    indices = {table: {str(row[key]) for row in domain_rows[table]} for table, key in domain_keys.items()}
    for ident in sorted(required["ability"], key=int):
        if ident not in indices["AbilityItems"]:
            domain_rows["AbilityItems"].append(abilities[ident])
            additions["abilities"] += 1
    for ident in sorted(required["buff"], key=int):
        if ident not in indices["Buffs"]:
            domain_rows["Buffs"].append(dict(raw["BuffCfg_[" + ident + "]"], id=int(ident)))
            additions["domain_buffs"] += 1
    for ident in sorted(required["damage"], key=int):
        if ident not in indices["DamageValues"]:
            row = next((value for value in all_damage[ident] if value.get("Level", 1) == 1), all_damage[ident][0])
            domain_rows["DamageValues"].append(dict(row, Id=int(ident)))
            additions["domain_damage"] += 1
    buff_ids = {str(row["id"]) for row in combat["buffs"]}
    summon_ids = {str(row["id"]) for row in combat["summons"]}
    added_buffs = []
    for ident in sorted(required["buff"], key=int):
        if ident in buff_ids:
            continue
        key = "BuffCfg_[" + ident + "]"
        row = awakening_buff(raw[key], all_damage)
        row["apk_source"] = provenance["assets"][key]
        combat["buffs"].append(row)
        added_buffs.append(row)
        additions["combat_buffs"] += 1
    for ident in sorted(required["damage"], key=int):
        if ident not in combat["damage_definitions"]:
            combat["damage_definitions"][ident] = all_damage[ident]
            additions["combat_damage"] += 1
    for ident in sorted(required["summon"], key=int):
        if ident in summon_ids:
            continue
        key = "SummonUnitCfg_[" + ident + "]"
        value = raw[key]
        combat["summons"].append({"id": ident, "type": value["SummonUnitType"],
            "lifetime": value["SummonUnitData"].get("Duration", 0),
            "interval": value["SummonUnitData"].get("TriggerDuration", 99),
            "hit": hit(value["SummonUnitData"], combat["damage_definitions"]),
            "raw": packed(value), "raw_data": value["SummonUnitData"], "apk_source": provenance["assets"][key]})
        additions["combat_summons"] += 1

    source_old = json.loads(args.evidence.read_text())["old"]["tables"]["CharaTalentAwakeTreeData"]["data"]
    source_old_ids = {int(row["id"]) for row in source_old}
    report = {"schema": 1, "apk_sha256": APK_SHA256, "node_count": len(nodes),
        "added_node_ids": [int(row["id"]) for row in nodes if int(row["id"]) not in node_ids],
        "new_vs_previous_apk_node_ids": [int(row["id"]) for row in nodes if int(row["id"]) not in source_old_ids],
        "admin_node_ids": [int(row["id"]) for row in nodes if row.get("is_admin_mode", False)],
        "required": {kind: sorted(values, key=int) for kind, values in required.items()},
        "added": dict(additions), "ability_sources": {ident: ability_sources[ident] for ident in required["ability"]},
        "context_consumers": {context: sorted(context_consumers.get(context, set())) for context in sorted(required_contexts)},
        "added_buff_types": dict(Counter(row["type"] for row in added_buffs)),
        "limitations": ["Dependency closure does not establish every native combat behavior.",
                        "Preexisting ability, buff, damage, summon and action records are preserved."]}
    if args.audit_awakening:
        print(packed(report))
        return
    report_path = args.data.parent.parent / "reports/new-apk-awakening-import.json"
    if report_path.exists():
        previous_report = json.loads(report_path.read_text())
        if previous_report.get("apk_sha256") == APK_SHA256:
            report["initial_import"] = previous_report.get("initial_import", {
                "added_node_ids": previous_report.get("added_node_ids", []),
                "added": previous_report.get("added", {})})
    if "initial_import" not in report:
        report["initial_import"] = {"added_node_ids": report["added_node_ids"], "added": report["added"]}
    for table, rows in domain_rows.items():
        write(args.data / (table + ".json"), rows)
    write(args.data / "CharaTalentAwakeTreeData.json", nodes)
    write(combat_path, combat)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    manifest_path = args.data / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    for table in ("CharaTalentAwakeTreeData", *domain_rows):
        path = args.data / (table + ".json")
        entry = manifest["tables"][table]
        entry.update({"rows": len(json.loads(path.read_text())), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                      "source": "APK 1061664: bounded awakening nodes and missing dependency merge",
                      "evidence": {"report": "reports/new-apk-awakening-import.json", "preserve_existing_dependencies": True}})
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(packed({key: value for key, value in report.items() if key not in ("ability_sources", "required")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--combat-evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    parser.add_argument("--awakening-only", action="store_true")
    parser.add_argument("--audit-awakening", action="store_true")
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text())
    if evidence["new"]["sha256"] != "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505":
        raise ValueError("Review importer selection before using a different package")
    tables = evidence["new"]["tables"]
    if args.awakening_only or args.audit_awakening:
        if args.apk is None:
            parser.error("--apk is required for awakening dependency import")
        import_awakening(args, tables)
        raise SystemExit(0)
    for name in sorted(FULL_TABLES):
        write(args.data / (name + ".json"), tables[name]["data"])
    for name, fields in FIELDS.items():
        path = args.data / (name + ".json")
        rows = json.loads(path.read_text())
        source = {str(row["id"]): row for row in tables[name]["data"]}
        for row in rows:
            new = source.get(str(row["id"]), {})
            for key in fields:
                if key in new:
                    row[key] = new[key]
        write(path, rows)
    config_path = args.data / "RogueConfigData.json"
    config = json.loads(config_path.read_text())
    for key in CONFIG_KEYS:
        config[key] = tables["RogueConfigData"]["data"][key]
    write(config_path, config)
    material_path = args.data / "MaterialData.json"
    materials = json.loads(material_path.read_text())
    for row in materials:
        if int(row["id"]) == 504:
            row["description"] = next(r["description"] for r in tables["MaterialData"]["data"] if int(r["id"]) == 504)
    write(material_path, materials)
    manifest_path = args.data / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    for name in sorted(FULL_TABLES | FIELDS.keys() | {"RogueConfigData", "MaterialData"}):
        payload = (args.data / (name + ".json")).read_bytes()
        rows = json.loads(payload)
        entry = manifest["tables"][name]
        entry["rows"] = len(rows) if isinstance(rows, list) else 1
        entry["sha256"] = hashlib.sha256(payload).hexdigest()
        entry["source"] = "APK 1061664 (" + evidence["new"]["sha256"] + "): camp/economy audit"
        entry["evidence"] = {"report": "reports/new-apk-camp-config-evidence.json", "fields": "all" if name in FULL_TABLES else sorted(CONFIG_KEYS) if name == "RogueConfigData" else sorted(FIELDS.get(name, {"504/description"}))}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"full_tables": sorted(FULL_TABLES), "updated_fields": {k: sorted(v) for k, v in FIELDS.items()}, "config_keys": sorted(CONFIG_KEYS)}))
