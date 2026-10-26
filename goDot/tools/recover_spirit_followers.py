#!/usr/bin/env python3
"""Recover exact spirit prefab bindings and particle media from the supplied APK."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

import UnityPy


PROJECT = Path(__file__).resolve().parents[1]


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=PROJECT)
    args = parser.parse_args()
    project = args.project.resolve()
    manifest = json.loads(args.manifest.read_text())
    assets = {a["address"]: a for a in manifest["assets"]}
    selected = {name: a for name, a in assets.items() if name.startswith(
        ("AbilityItemCfg_", "BuffCfg_[", "SummonUnitCfg_["))}
    records, sources = {}, {}
    with zipfile.ZipFile(args.apk) as archive:
        for index in sorted({a["bundle"] for a in selected.values()}):
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in selected:
                    continue
                item = obj.read()
                raw = item.m_Script
                raw = raw if isinstance(raw, bytes) else raw.encode("utf-8", "surrogateescape")
                records[item.m_Name] = json.loads(raw.decode("utf-8-sig"))
                sources[item.m_Name] = {"address": item.m_Name,
                    "asset": assets[item.m_Name]["path"], "bundle": member,
                    "bundle_sha256": digest(payload), "path_id": str(obj.path_id),
                    "json_sha256": digest(raw)}
    followers = {}
    for name, value in records.items():
        if not name.startswith("SummonUnitCfg_["):
            continue
        raw = value["SummonUnitData"]
        prefab = raw.get("Prefab", "").removesuffix(".prefab").lower()
        if not prefab.startswith("summonunit_sprite_"):
            continue
        if prefab not in assets:
            raise ValueError("Missing exact follower address: " + prefab)
        followers[str(raw["ID"])] = {"prefab": prefab, "raw": raw,
            "type": value["SummonUnitType"], "source": sources[name]}

    def initial_followers(buff_id, visited, chain):
        if not buff_id or buff_id in visited:
            return []
        visited.add(buff_id)
        name = "BuffCfg_[" + buff_id + "]"
        if name not in records:
            return []
        value = records[name]
        raw = value["BuffData"]
        chain.append(sources[name])
        result = []
        if value["BuffType"] == "EBT_SpecialAddSummonUnit":
            for setting in raw.get("BuffSettingDataList", []):
                summon = str(setting.get("AddSummonUnitDef", {}).get("AddSummonUnitId", ""))
                if summon in followers and summon not in result:
                    result.append(summon)
        for child in raw.get("InitAddTargetBuffIdList", []):
            result.extend(initial_followers(str(child), visited, chain))
        return result

    abilities = {}
    for name, raw in records.items():
        if not name.startswith("AbilityItemCfg_"):
            continue
        chain = [sources[name]]
        summons = []
        roots = [raw.get("ModifyBuff", ""), raw.get("AddBuff", "")]
        for combined in raw.get("CombineDataList", []):
            if combined.get("CombineDataType") == "NormalModifyBuff":
                roots.append(combined.get("Data", {}).get("ModifyBuff", ""))
        for buff in roots:
            summons.extend(initial_followers(buff, set(), chain))
        if summons:
            abilities[int(raw["ID"])] = {"summons": sorted(set(summons)), "source_chain": chain, "raw": raw}
    loot_path = project / "assets/data/LootData.json"
    bindings = {str(row["id"]): {"ability": row["ability_item_id"],
        **abilities[row["ability_item_id"]]} for row in json.loads(loot_path.read_text())
        if row.get("ability_item_id") in abilities}
    names = sorted({record["prefab"] for record in followers.values()})
    if not names or not bindings:
        raise ValueError("Missing source follower prefabs or loot bindings")
    output = project / "assets/spirit_followers"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="city-spirit-") as directory:
        selection = Path(directory) / "assets.json"
        selection.write_text(json.dumps(names))
        subprocess.run([sys.executable, str(project / "tools/export_environment_effects.py"),
            "--apk", str(args.apk), "--manifest", str(args.manifest),
            "--asset-list", str(selection), "--output-directory", str(output),
            "--report", str(output / "extraction.json")], check=True)
    catalog_path = output / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    catalog.update({"schema": 1, "followers": followers, "loot_bindings": bindings,
        "ability_bindings": abilities,
        "unmapped_abilities": sorted(set(abilities) - {row["ability"] for row in bindings.values()}),
        "loot_table_sha256": digest(loot_path.read_bytes()),
        "limitations": ["Static APK prefab and configuration recovery; no original runtime capture",
            "Godot particle and shader approximations retain the exported source limitations",
            "FollowOwner_LineQueue spacing and speed use serialized values; its native path algorithm is not reproduced"]})
    catalog_path.write_text(json.dumps(catalog, separators=(",", ":")) + "\n")
    print(json.dumps({"followers": len(followers), "loot_bindings": len(bindings),
        "unmapped_abilities": catalog["unmapped_abilities"],
        "particle_layers": sum(value["particle_systems"] for value in catalog["effects"].values())}))


if __name__ == "__main__":
    main()
