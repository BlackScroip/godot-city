#!/usr/bin/env python3
"""Recover only the newly available eighth character from the selected APK.

The actor and source evidence are independent outputs. The optional merge
updates only blade actions, actor 8, its missing dependencies and heavy entry;
all unrelated action and actor records retain their existing values.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import zipfile

import numpy as np
import UnityPy

from import_region_combat import buff, event, hit, packed, references
from inspect_camp_progression import manifest_records
from recover_region_actors import ActorExporter, APK, MANIFEST
from recover_region_environments import sha


ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "goDot"
REPORT = PROJECT / "reports/character8-import.json"


def load(path):
    return json.loads(path.read_text())


def extract_tables(archive, assets, bundles):
    wanted = {"CharData", "AttackData", "PlayerActionCfg_[25072902]"}
    selected = {row["address"]: row for row in assets if row["address"] in wanted}
    values, evidence = {}, {}
    for index in sorted({row["bundle"] for row in selected.values()}):
        member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
        payload = archive.read(member)
        for obj in UnityPy.load(payload).objects:
            if obj.type.name != "TextAsset" or obj.peek_name() not in wanted:
                continue
            text = obj.read().m_Script
            if isinstance(text, bytes):
                text = text.decode("utf-8-sig")
            name = obj.peek_name()
            values[name] = json.loads(text.lstrip("\ufeff"))
            evidence[name] = {"member": member, "bundle_sha256": sha(payload),
                              "path_id": str(obj.path_id), "source_asset": selected[name]["path"]}
    if values.keys() != wanted:
        raise ValueError("Missing exact character source tables")
    return values, evidence


def normalize_character(row, attacks):
    ids = [int(row[field]) for field in ("nor_attack_id", "dodge_attack_id", "active_skill_id1", "active_skill_id2")]
    source = {item["id"]: item for item in attacks}
    skills = []
    for index, ident in enumerate(ids):
        item = source[ident]
        action = "blade_atk1" if index == 0 else "blade_skill_dodge" if index == 1 else item["entry_action_id"]
        skills.append({"id": ident, "name": item["name"], "description": item["description"],
                       "action": action, "sp": item["sp"], "maxSp": item["max_sp"],
                       "cooldown": item["cd"] / 1000., "element": item["element_type"]})
    skills.append(dict(skills[0], id=0, name="Heavy attack", action="blade_satk_start"))
    return {"id": row["id"], "name": row["name"], "prefix": "blade", "hp": row["hp"],
            "attack": row["atk"], "defense": row["def"], "critRate": row["criti_rate"] / 1000.,
            "critMultiplier": row["criti_mult"] / 1000., "speed": row["move_speed"], "range": row["search_distance"],
            "jp": "800100", "passives": row["default_passive_buff_list_str"].split("|"),
            "combo": ["blade_atk" + str(index) for index in range(1, 5)], "skills": skills}


def build_payload(values, raw, provenance):
    character = normalize_character(next(row for row in values["CharData"] if row["id"] == 8), values["AttackData"])
    actions = {key: row for key, row in raw.items() if isinstance(row, dict) and "ActId" in row
               and (str(row["ActId"]).startswith("blade_") or str(row["ActId"]).startswith("skill_blade_"))}
    all_damage = {}
    for key, rows in raw.items():
        if key.startswith("DamageCfg_"):
            for row in rows:
                all_damage.setdefault(str(row["DamageDefId"]), []).append(row)
    required = {"buff": {"800000", "800100"}, "summon": set(), "damage": set()}
    queue = list(actions.values()) + [raw["BuffCfg_[800000]"], raw["BuffCfg_[800100]"]]
    for value in queue:
        for kind, identifiers in references(value).items():
            identifiers = {part.strip() for ident in identifiers for part in re.split(r"[|,;]", ident) if part.strip() and part.strip() != "0"}
            for ident in sorted(identifiers - required[kind]):
                required[kind].add(ident)
                key = {"buff": "BuffCfg_", "summon": "SummonUnitCfg_", "damage": "DamageCfg_"}[kind] + "[" + ident + "]"
                if kind != "damage" and key in raw:
                    queue.append(raw[key])
    result = {"character": character, "actions": [], "buffs": [], "summons": [], "damage_definitions": {}}
    missing = {kind: [] for kind in required}
    for key, value in actions.items():
        group = Path(provenance["assets"][key]["source_asset"]).parent.name
        result["actions"].append({"key": group + "/" + value["ActId"], "group": group, "id": value["ActId"],
            "name": value.get("Name_EDT", ""), "duration": value["TotalTime"] / 1000., "speed": value["PlaySpeed"],
            "events": [event(row) for row in value.get("Events", []) + value.get("Interrupts", [])],
            "hits": [hit(row["EventData"], all_damage, row) for row in value.get("AttackDefs", [])],
            "source": provenance["assets"][key]["source_asset"], "apk_source": provenance["assets"][key]})
    for kind, plural in (("buff", "buffs"), ("summon", "summons")):
        for ident in sorted(required[kind], key=int):
            key = ("BuffCfg_" if kind == "buff" else "SummonUnitCfg_") + "[" + ident + "]"
            if key not in raw:
                missing[kind].append(ident)
                continue
            value = raw[key]
            normalized = buff(value) if kind == "buff" else {"id": ident, "type": value["SummonUnitType"],
                "lifetime": value["SummonUnitData"].get("Duration", 0),
                "interval": value["SummonUnitData"].get("TriggerDuration", 99),
                "hit": hit(value["SummonUnitData"], all_damage), "raw": packed(value), "raw_data": value["SummonUnitData"]}
            if kind == "buff" and value["BuffData"].get("OnceReduceNumCount", 0) > 0:
                normalized["expiryLayers"] = value["BuffData"]["OnceReduceNumCount"]
            normalized["apk_source"] = provenance["assets"][key]
            result[plural].append(normalized)
    for ident in required["damage"]:
        if ident in all_damage:
            result["damage_definitions"][ident] = all_damage[ident]
        else:
            missing["damage"].append(ident)
    return result, required, missing, actions


def export_model(archive, manifest, assets, bundles, actor, apk_hash):
    name = actor["Prefab"].removesuffix(".prefab")
    exporter = ActorExporter(archive, manifest, assets, bundles, name)
    exporter.build()
    exporter.recover_animations()
    # Godot treats a trailing _loop as an import hint and removes it. Keep the
    # source state alias, but protect clip names from colliding with base clips.
    for animation in exporter.data.get("animations", []):
        if animation["name"].endswith("_loop"):
            animation["name"] += "_clip"
    for animation in exporter.animations:
        if animation["name"].endswith("_loop"):
            animation["name"] += "_clip"
    target = PROJECT / "assets/characters/character_8.glb"
    exporter.write(target)
    minimum = np.min(np.asarray([pair[0] for pair in exporter.bounds]), axis=0)
    maximum = np.max(np.asarray([pair[1] for pair in exporter.bounds]), axis=0)
    aliases = {item["source_name"].lower(): item["name"] for item in exporter.animations}
    defaults = {key: aliases.get(value, "") for key, value in {"idle": "blade@idle", "run": "blade@run", "attack": "blade@attack1"}.items()}
    if not all(defaults.values()):
        raise ValueError("Source actor is missing a basic animation state")
    metadata = {"id": 8, "path": "res://assets/characters/character_8.glb", "source": exporter.asset["path"],
                "source_sha256": sha(archive.read("assets/yoo/DefaultPackage/" + bundles[exporter.asset["bundle"]]["hash"] + ".bundle")),
                "source_apk_sha256": apk_hash, "apk_manifest": MANIFEST,
                "bounds": {"min": minimum.tolist(), "max": maximum.tolist(), "size": (maximum - minimum).tolist()},
                "nodes": len(exporter.data["nodes"]), "meshes": len(exporter.data["meshes"]), "skins": len(exporter.data["skins"]),
                "bytes": target.stat().st_size, "animations": exporter.animations, "default_animations": defaults,
                "unsupported": dict(exporter.unsupported), "bundle_sources": exporter.bundle_evidence,
                "rendering": "Exact source mesh, skin, textures and color; Unity custom shader approximated with PBR"}
    conversion = dict(metadata, renderer_sources=exporter.renderer_evidence, materials=exporter.material_sources,
                      failures=exporter.failures, evidence_type="static packaged prefab and controller curves")
    target.with_suffix(".conversion.json").write_text(json.dumps(conversion, ensure_ascii=False, indent=2) + "\n")
    catalog_path = PROJECT / "assets/catalog.json"
    catalog = load(catalog_path)
    catalog["characters"]["8"] = metadata
    catalog_path.write_text(packed(catalog) + "\n")
    return {"path": metadata["path"], "sha256": sha(target.read_bytes()), "meshes": metadata["meshes"],
            "skins": metadata["skins"], "animations": [{key: val for key, val in item.items() if key != "apk_sources"} for item in exporter.animations],
            "unsupported": metadata["unsupported"]}


def merge(payload, actions):
    path = PROJECT / "assets/data/combat.json"
    combat = load(path)
    before = copy.deepcopy(combat)
    old_actions = {row["key"]: row for row in combat["actions"]}
    changed = [row["key"] for row in payload["actions"] if old_actions.get(row["key"]) != row]
    for row in payload["actions"]:
        old_actions[row["key"]] = row
    combat["actions"] = list(old_actions.values())
    characters = {row["id"]: row for row in combat["characters"]}
    characters[8] = payload["character"]
    combat["characters"] = list(characters.values())
    changes, retained_differences, updated_expiry = {}, {}, []
    for plural in ("buffs", "summons"):
        current = {str(row["id"]): row for row in combat[plural]}
        changes[plural], retained_differences[plural] = [], []
        for row in payload[plural]:
            ident = str(row["id"])
            if ident not in current:
                current[ident] = row
                changes[plural].append(ident)
            elif current[ident].get("raw") != row.get("raw"):
                retained_differences[plural].append(ident)
            elif plural == "buffs" and "expiryLayers" in row and current[ident].get("expiryLayers") != row["expiryLayers"]:
                current[ident]["expiryLayers"] = row["expiryLayers"]
                updated_expiry.append(ident)
        combat[plural] = list(current.values())
    changes["damage_definitions"] = []
    for ident, rows in payload["damage_definitions"].items():
        if ident not in combat["damage_definitions"]:
            combat["damage_definitions"][ident] = rows
            changes["damage_definitions"].append(ident)
        elif combat["damage_definitions"][ident] != rows:
            retained_differences.setdefault("damage_definitions", []).append(ident)
    unrelated_before = {row["key"]: row for row in before["actions"] if row["key"] not in {item["key"] for item in payload["actions"]}}
    unrelated_after = {row["key"]: row for row in combat["actions"] if row["key"] not in {item["key"] for item in payload["actions"]}}
    if unrelated_before != unrelated_after:
        raise ValueError("An unrelated action changed")
    path.write_text(packed(combat) + "\n")
    heavy_path = PROJECT / "assets/data/heavy_attacks.json"
    heavy = load(heavy_path)
    heavy["entries"]["8"] = "blade_satk_start"
    for key, row in actions.items():
        if row["ActionStatus"] == "SAtk":
            heavy["actions"][row["ActId"]] = {"can_hit": row["CanHit"], "stable_value": row["StableValue"], "source_sha256": sha(packed(row).encode())}
    heavy.setdefault("actor_apk_sources", {})["8"] = MANIFEST
    heavy_path.write_text(json.dumps(heavy, ensure_ascii=False, indent=2) + "\n")
    return {"updated_blade_actions": changed, "added_dependencies": changes,
            "updated_source_expiry_layers": updated_expiry,
            "retained_existing_dependency_differences": retained_differences,
            "unrelated_actions_preserved": len(unrelated_before)}


def main(args):
    with args.apk.open("rb") as stream:
        apk_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    raw = load(args.evidence / "raw-catalog.json")
    provenance = load(args.evidence / "provenance.json")
    if provenance["apk_sha256"] != apk_hash:
        raise ValueError("Combat evidence belongs to a different APK")
    previous = load(REPORT) if REPORT.exists() else {}
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(MANIFEST)
        assets, bundles = manifest_records(manifest)
        values, evidence = extract_tables(archive, assets, bundles)
        payload, required, missing, actions = build_payload(values, raw, provenance)
        known_source_gaps = {"buff": ["800413"], "summon": [], "damage": []}
        if any(set(ids) - set(known_source_gaps[kind]) for kind, ids in missing.items()):
            raise ValueError("Unresolved character references: " + packed(missing))
        report = {"apk_sha256": apk_hash, "manifest": MANIFEST, "evidence_type": "static exact APK serialization; original runtime unobserved",
                  "source_tables": evidence, "actor": values["PlayerActionCfg_[25072902]"],
                  "character_source": next(row for row in values["CharData"] if row["id"] == 8),
                  "attack_sources": [row for row in values["AttackData"] if row["id"] in (160011, 180001, 180003, 180011, 180012)],
                  "required_dependencies": {kind: sorted(ids, key=int) for kind, ids in required.items()}, "missing_dependencies": missing,
                  "known_source_gaps": known_source_gaps,
                  "limitations": ["Original Unity shader and particle rendering are not pixel-identical.", "No original application runtime was executed."]}
        payload_path = PROJECT / "reports/character8-combat-payload.json"
        payload_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
        report["combat_payload"] = str(payload_path)
        if args.model:
            report["model"] = export_model(archive, manifest, assets, bundles, report["actor"], apk_hash)
        elif "model" in previous:
            report["model"] = previous["model"]
        if args.merge:
            report["merge"] = merge(payload, actions)
        elif "merge" in previous:
            report["merge"] = previous["merge"]
        REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(packed({"report": str(REPORT), "actions": len(payload["actions"]),
                      "dependencies": {key: len(value) for key, value in required.items()},
                      "model": report.get("model", {}).get("path"), "merge": report.get("merge")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=APK)
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    parser.add_argument("--model", action="store_true")
    parser.add_argument("--merge", action="store_true")
    main(parser.parse_args())
