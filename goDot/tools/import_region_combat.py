#!/usr/bin/env python3
"""Merge exact October APK region combat records into the runtime catalog.

Input JSON is the bounded Unity TextAsset/NodeCanvas extraction. Existing
unrelated combat records are retained; every imported dependency keeps its raw
source data and packaged identity for later runtime parity work.
"""

import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REGION_ENEMIES = [11006, 13002, 22003, 23002, 110011, 110012, 110021, 110022,
    110031, 110041, 110051, 120011, 120021, 120031, 410011, 410021, 410031,
    410041, 420011, 420021, 33002]
BUFF_KEYS = re.compile(r"^(BuffTriggerId|InitAddTargetBuffIdList|InitClearTargetBuffIdList|AddBuffIDList|DelBuffIDList|FailedTriggerBuffId|ModifyBuffId|ModifyBuffReplaceId|SyncSourceBuffId|LastingTimeSyncTargetBuffId|BuffScoureId|BeMutiplyBuffId|BuffId|BuffIdList|CheckAttackerBuffId|CheckAttackeeBuffId|CheckEnemyBuffId|AddBuff|ModifyBuff|buff_list|PassiveBuffList)$", re.I)
SUMMON_KEYS = re.compile(r"^(AddSummonUnitId|ModifyTargetSummonUnitToOtherSummonUnitId|SummonIdList|SummonUnitIdList|OriginSummonUnitId)$", re.I)
DAMAGE_KEYS = re.compile(r"^(DamageDefId|DamageId|CheckDamageDefId|CheckDamageDefId2|CheckDamageDefId3|ModifyDamageDefId)$", re.I)


def load(path):
    return json.loads(Path(path).read_text())


def packed(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def extract_apk(args):
    import UnityPy
    from inspect_camp_progression import manifest_records

    args.evidence.mkdir(parents=True, exist_ok=True)
    table_folder = args.actor_index.parent
    (table_folder / "actors").mkdir(parents=True, exist_ok=True)
    with args.apk.open("rb") as stream:
        apk_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    provenance = {"apk_sha256": apk_hash, "assets": {}}
    table_provenance = {"apk_sha256": apk_hash, "tables": {}}
    records, tables, actors = {}, {}, {}
    with zipfile.ZipFile(args.apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        provenance["manifest"] = table_provenance["manifest"] = manifest_name
        assets, bundles = manifest_records(archive.read(manifest_name))
        wanted = {asset["address"]: asset for asset in assets if asset["address"] in ("EnemyData", "EnemyNumericalConfigData")
            or asset["address"].startswith("MonsterActionCfg_")
            or any(part in asset["path"] for part in ("/ActionEngineCfg/Action/", "/ActionEngineCfg/Buff/", "/ActionEngineCfg/SummonUnit/", "/ActionEngineCfg/DamageCfg/", "/NodeCanvasRes/AI/"))}
        for index in sorted({asset["bundle"] for asset in wanted.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name not in ("TextAsset", "MonoBehaviour"):
                    continue
                name = obj.peek_name()
                if name not in wanted:
                    continue
                source = {"source_asset": wanted[name]["path"], "bundle": member,
                    "bundle_sha256": hashlib.sha256(payload).hexdigest(), "path_id": str(obj.path_id)}
                if obj.type.name == "TextAsset":
                    text = obj.read().m_Script
                    if isinstance(text, bytes):
                        text = text.decode("utf-8-sig")
                    value = json.loads(text.lstrip("\ufeff"))
                else:
                    tree = obj.read_typetree()
                    if not tree.get("_serializedGraph"):
                        continue
                    value = json.loads(tree["_serializedGraph"])
                if name.startswith("MonsterActionCfg_") or name in ("EnemyData", "EnemyNumericalConfigData"):
                    path = table_folder / ("actors" if name.startswith("MonsterActionCfg_") else "") / (name + ".json")
                    path.write_text(packed(value) + "\n")
                    table_provenance["tables"][name] = {"path": str(path), "member": member,
                        "sha256": source["bundle_sha256"], "source_asset": source["source_asset"], "path_id": source["path_id"]}
                    if name.startswith("MonsterActionCfg_"):
                        actors[int(value["ID"])] = (name, value)
                    else:
                        tables[name] = value
                else:
                    records[name], provenance["assets"][name] = value, source
    joined = []
    for row in tables["EnemyData"]:
        name, actor = actors[row["id"]]
        joined.append({"id": row["id"], "name": row["name"], "rank": row["enemy_rate"],
            "hp": row["hp"], "atk": row["atk"], "difficulty": row["difficulty"],
            "actor": actor, "new_to_project_enemy_data": row["id"] in REGION_ENEMIES,
            "enemy_source": table_provenance["tables"]["EnemyData"],
            "actor_source": table_provenance["tables"][name]})
    args.actor_index.write_text(packed({"manifest": provenance["manifest"], "new_enemy_ids": REGION_ENEMIES, "enemies": joined}) + "\n")
    (args.evidence / "raw-catalog.json").write_text(packed(records) + "\n")
    (args.evidence / "provenance.json").write_text(packed(provenance) + "\n")
    (table_folder / "combat-provenance.json").write_text(packed(table_provenance) + "\n")


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def references(value):
    result = {"buff": set(), "summon": set(), "damage": set()}
    for item in walk(value):
        for key, val in item.items():
            kind = "buff" if BUFF_KEYS.fullmatch(key) else "summon" if SUMMON_KEYS.fullmatch(key) else "damage" if DAMAGE_KEYS.fullmatch(key) else None
            if kind:
                for ident in val if isinstance(val, list) else [val]:
                    if type(ident) in (str, int) and str(ident) not in ("", "0") and not str(ident).startswith("-"):
                        result[kind].add(str(ident))
    return result


def conditions(values):
    return [{"type": row.get("ConditionType", ""), "buff": str(row.get("BuffId", "")),
             "exists": row.get("CheckExist", row.get("IsExist", False)),
             "layers": row.get("CheckLayerCount", 0), "compare": row.get("CompareType", ""),
             "property": row.get("PropertyName", ""), "value": row.get("Value", ""),
             "raw": packed(row)} for row in values]


def event(row):
    raw = row["EventData"]
    addition = raw.get("AddBuffData", {})
    summon = raw.get("AddSummonUnitDef", {})
    return {"type": row["EventType"], "time": row["TriggerTime"] / 1000.0,
            "duration": row["Duration"] / 1000.0, "enabled": row.get("Enabled", True),
            "all": row.get("CheckAllCondition", True), "conditions": conditions(row.get("Conditions", [])),
            "anim": raw.get("AnimName", ""), "buff": str(addition.get("BuffTriggerId", "")),
            "layers": addition.get("BuffAddLayer", 0), "move": raw.get("CustomSpeed", 0),
            "summon": str(summon.get("AddSummonUnitId", "")),
            "offset": summon.get("InitPosOffset", {}).get("z", 0),
            "target": raw.get("ActionID", ""),
            "unconditionalInterrupt": row["EventType"] == "EET_Interrupt" and not raw.get("Conditions", []),
            "raw": packed(raw)}


def hit(raw, damage, row=None):
    row = row or {}
    entity, emit, motion = [raw.get(key, {}) for key in ("EntityProperty", "EmitProperty", "MotionAnimatorProperty")]
    damage_id = int(raw.get("DamageDefId", 0))
    rows = damage.get(str(damage_id), [])
    coefficient = next((value for value in rows if value.get("Level", 1) == 1), rows[0] if rows else {})
    box = entity.get("ModelBoxColliderSize", entity.get("Size", {}))
    size = entity.get("EffectTriggerDef", {}).get("Scale", {})
    radius = entity.get("Radius", 0) or size.get("x", 0)
    width = box.get("x", 0) or radius * 2 or 1
    length = box.get("z", 0) or radius * 2 or motion.get("Distance", 0) or 1
    attacker, attackee = [], []
    for feedback in raw.get("FeedbackList", []):
        if feedback.get("FeedbackType") == "EHT_HitAddBuff":
            for key, target in (("AddBuff_ToAttacker", attacker), ("AddBuff_ToAttackee", attackee)):
                buff = feedback.get(key, {})
                if buff.get("BuffTriggerId"):
                    target.append({"id": str(buff["BuffTriggerId"]), "layers": buff.get("BuffAddLayer", 1)})
    return {"time": row.get("TriggerTime", 0) / 1000.0,
            "enabled": row.get("Enabled", True), "all": row.get("CheckAllCondition", True),
            "conditions": conditions(row.get("Conditions", [])), "damageId": damage_id,
            "multiplier": coefficient.get("DamageMulValue", 0) / 1000.0,
            "fixedDamage": coefficient.get("DamageFixValue", 0),
            "attribute": coefficient.get("DamageAttribType", "None" if damage_id <= 0 else "Unknown"),
            "element": coefficient.get("DamageType", "None" if damage_id <= 0 else "Unknown"),
            "critical": coefficient.get("EnableCriticle", False), "width": width, "length": length,
            "offset": emit.get("EmitOffset", {}).get("z", 0),
            "shape": entity.get("ColliderType", "Fan" if raw.get("EntityType") == "EET_FrameFan" else "Cube"),
            "projectile": raw.get("EntityType") == "EET_Physical", "speed": motion.get("Speed", 0),
            "lifetime": entity.get("CheckTime", motion.get("MaxLifetime", .1)),
            "count": emit.get("Num", 1), "interval": emit.get("Interval", 0),
            "charge": raw.get("RecoverSkillCharge", 0), "targetBuffs": attackee, "ownerBuffs": attacker,
            "raw": packed(raw), "summon": "", "actType": coefficient.get("DamageActType", "")}


def buff(raw):
    value = raw["BuffData"]
    settings = value.get("BuffSettingDataList", [{}]) or [{}]
    first = settings[0]
    interval = first.get("TriggerTime", value.get("TriggerTime", 1000)) / 1000.0
    result = {"id": str(value["ID"]), "type": raw["BuffType"], "name": value.get("Name_EDT", ""),
              "maxLayers": value.get("MaxLayerNum", 1),
              "duration": value.get("Duration", -1) / 1000.0 if value.get("Duration", -1) >= 0 else -1,
              "initial": value.get("InitAddTargetBuffIdList", []), "modify": value.get("ModifyBuffId", ""),
              "modifyLayers": value.get("ModifyAddLayer", 0), "interval": interval,
              "multiplier": 0, "fixedDamage": 0, "raw": packed(raw), "raw_data": value,
              "stats": [{"attribute": row["Attr"], "value": row["AddValue"]} for row in first.get("BuffDataList", [])],
              "healPercent": first.get("MaxHpPercentChange", 0), "clear": value.get("InitClearTargetBuffIdList", []),
              "keepDuration": value.get("AddLayerDurationModifyType") == "Keep",
              "firstDelay": value.get("FirstValidDelayTime", 1000) / 1000.0, "triggers": []}
    if value.get("SyncSourceBuffId"):
        result["syncSource"] = value["SyncSourceBuffId"]
    return result


def merge(args):
    combat = load(args.project / "assets/data/combat.json")
    raw = load(args.evidence / "raw-catalog.json")
    provenance = load(args.evidence / "provenance.json")
    index = load(args.actor_index)
    selected = [row for row in index["enemies"] if row["id"] in index["new_enemy_ids"]]
    groups = {row["actor"]["ActionGroup"] for row in selected}
    trial_actor = load(args.actor_index.parent / "actors/MonsterActionCfg_[900999].json")
    groups.add(trial_actor["ActionGroup"])
    combat.setdefault("special_actors", {})["900999"] = trial_actor
    selected_actions = {key: value for key, value in raw.items() if isinstance(value, dict) and "ActId" in value and Path(provenance["assets"][key]["source_asset"]).parent.name in groups}
    all_damage = {}
    for key, value in raw.items():
        if key.startswith("DamageCfg_"):
            for row in value:
                all_damage.setdefault(str(row["DamageDefId"]), []).append(row)
    required = {"buff": set(), "summon": set(), "damage": set()}
    queue = list(selected_actions.values()) + [row["actor"] for row in selected] + [trial_actor]
    difficulty_rows = load(args.project / "assets/data/RogueLevelDifficultyInfluencerData.json")
    difficulty_buff_roots = sorted({ident.strip() for row in difficulty_rows if not row.get("IsDisable", False)
        for ident in str(row.get("BuffId", "")).split("|") if ident.strip() not in ("", "0")}, key=int)
    queue.append({"BuffId": difficulty_buff_roots})
    for value in queue:
        for kind, ids in references(value).items():
            for ident in sorted(ids - required[kind]):
                required[kind].add(ident)
                key = {"buff": "BuffCfg_", "summon": "SummonUnitCfg_", "damage": "DamageCfg_"}[kind] + "[" + ident + "]"
                if kind != "damage" and key in raw:
                    queue.append(raw[key])
    old = {kind: {str(row["id"]): row for row in combat[plural]} for kind, plural in (("buff", "buffs"), ("summon", "summons"))}
    missing = {kind: sorted(ident for ident in ids if ident not in (all_damage if kind == "damage" else old[kind]) and ({"buff": "BuffCfg_", "summon": "SummonUnitCfg_", "damage": "DamageCfg_"}[kind] + "[" + ident + "]") not in raw) for kind, ids in required.items()}
    damage = copy.deepcopy(combat["damage_definitions"])
    for ident in required["damage"]:
        if ident in all_damage:
            damage[ident] = all_damage[ident]
    combat["damage_definitions"] = damage
    counts = Counter()
    for kind, plural in (("buff", "buffs"), ("summon", "summons")):
        for ident in sorted(required[kind], key=int):
            key = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
            if key not in raw:
                continue
            value = raw[key]
            if ident in old[kind] and "apk_source" not in old[kind][ident] and json.loads(old[kind][ident]["raw"]) == value:
                continue
            normalized = buff(value) if kind == "buff" else {
                "id": ident, "type": value["SummonUnitType"],
                "lifetime": value["SummonUnitData"].get("Duration", 0),
                "interval": value["SummonUnitData"].get("TriggerDuration", 99),
                "hit": hit(value["SummonUnitData"], damage),
                "raw": packed(value), "raw_data": value["SummonUnitData"]}
            normalized["apk_source"] = provenance["assets"][key]
            old[kind][ident] = normalized
            counts[kind] += 1
        combat[plural] = list(old[kind].values())
    actions = {row["key"]: row for row in combat["actions"]}
    for key, value in selected_actions.items():
        group = Path(provenance["assets"][key]["source_asset"]).parent.name
        action_key = group + "/" + value["ActId"]
        actions[action_key] = {"key": action_key, "group": group, "id": value["ActId"],
            "name": value.get("Name_EDT", ""), "duration": value["TotalTime"] / 1000.0,
            "speed": value["PlaySpeed"], "events": [event(row) for row in value.get("Events", []) + value.get("Interrupts", [])],
            "hits": [hit(row["EventData"], damage, row) for row in value.get("AttackDefs", [])],
            "source": provenance["assets"][key]["source_asset"], "apk_source": provenance["assets"][key]}
    combat["actions"] = list(actions.values())
    enemies = {row["id"]: row for row in combat["enemies"]}
    for row in selected:
        actor = row["actor"]
        ai = raw[actor["StartupAI"]]
        ai_actions, hp_conditions = [], []
        for item in walk(ai.get("nodes", [])):
            if item.get("valueA", {}).get("_name") == "OP_AIAction" and item.get("valueB", {}).get("_value") and ".Actions." in item.get("$type", ""):
                ai_actions.append(item["valueB"]["_value"])
            if item.get("$type", "").endswith(".NCCondition_RoleUnit_CheckAttribute") and item.get("CheckAttribute") == 3:
                hp_conditions.append(item)
        group = actor["ActionGroup"]
        enemy_actions = [action["id"] for action in actions.values() if action["group"] == group and (any(h["enabled"] for h in action["hits"]) or any(e["enabled"] and e["type"] in ("EET_AddSummonUnit", "EET_MonsterGeneration") for e in action["events"]))]
        enemies[row["id"]] = {"id": row["id"], "name": row["name"], "rank": row["rank"],
            "hp": row["hp"], "attack": row["atk"], "difficulty": row["difficulty"],
            "prefab": actor["Prefab"], "group": group, "ai": actor["StartupAI"],
            "speed": actor["MoveSpeed"], "cooldown": actor["AttackCD"], "actions": enemy_actions,
            "ai_source": provenance["assets"][actor["StartupAI"]]["source_asset"],
            "ai_action_ids": list(dict.fromkeys(ai_actions)), "ai_hp_conditions": hp_conditions,
            "behavior": "combat", "phase_rules": [],
            "phase_evidence": "Exact serialized NodeCanvas graph retained. Runtime scheduler interprets its predicates and assignments; native task parity is unverified.",
            "apk_source": {"enemy": row["enemy_source"], "actor": row["actor_source"]}}
        combat["ai_graphs"][actor["StartupAI"]] = ai
    combat["enemies"] = list(enemies.values())
    combat["missingDamageIds"] = sorted(set(combat.get("missingDamageIds", [])) - {int(ident) for ident in damage})
    report = {"schema": 1, "apk_sha256": provenance["apk_sha256"], "manifest": provenance["manifest"],
        "enemy_ids": [row["id"] for row in selected], "action_groups": sorted(groups),
        "actions": len(selected_actions), "required_dependencies": {key: sorted(value, key=int) for key, value in required.items()},
        "difficulty_buff_roots": difficulty_buff_roots,
        "changed_dependencies": dict(counts), "missing_dependencies": missing,
        "new_enemy_actions": {str(row["id"]): enemies[row["id"]]["actions"] for row in selected},
        "evidence_type": "Static exact APK TextAsset and NodeCanvas serialization",
        "limitations": ["Original native AI task scheduling and custom shader rendering remain unverified."]}
    # The shipped lava mage action contains this unresolved damage ID. Preserve
    # the source defect explicitly instead of fabricating a damage coefficient.
    known_source_gaps = {"buff": [], "summon": [], "damage": ["444100311"]}
    report["known_source_gaps"] = known_source_gaps
    if any(set(missing[kind]) - set(known_source_gaps[kind]) for kind in missing):
        raise ValueError("Missing region combat references: " + packed(missing))
    (args.project / "assets/data/combat.json").write_text(packed(combat) + "\n")
    manifest_path = args.project / "assets/data/manifest.json"
    table_manifest = load(manifest_path)
    source_tables = load(args.actor_index.parent / "combat-provenance.json")["tables"]
    for name in ("EnemyData", "EnemyNumericalConfigData"):
        value = load(args.actor_index.parent / (name + ".json"))
        if isinstance(value, dict):
            value = [value]
        payload = (packed(value) + "\n").encode()
        (args.project / "assets/data" / (name + ".json")).write_bytes(payload)
        table_manifest["tables"][name] = {"rows": len(value), "sha256": hashlib.sha256(payload).hexdigest(),
            "source": "APK:" + provenance["manifest"] + ":" + name,
            "apk_sha256": provenance["apk_sha256"], "apk_source": source_tables[name]}
    manifest_path.write_text(json.dumps(table_manifest, ensure_ascii=False, indent=2) + "\n")
    (args.project / "reports/region-combat-import.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(packed({"enemies": len(enemies), "new_enemies": len(selected), "actions": len(selected_actions), "changed_dependencies": dict(counts), "missing": missing}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "goDot")
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    parser.add_argument("--actor-index", type=Path, default=Path("/private/tmp/city-new-map-evidence/enemy-actor-index.json"))
    parser.add_argument("--apk", type=Path, help="Extract fresh static evidence from this APK before merging")
    arguments = parser.parse_args()
    if arguments.apk:
        extract_apk(arguments)
    merge(arguments)
