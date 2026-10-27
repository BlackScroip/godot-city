"""Read adventure event data and referenced configuration from the supplied APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


def row_id(row):
    return int(next((row[k] for k in ("id", "Id", "ID") if k in row), 0))


def ids(raw):
    return [int(token.split(":")[0]) for token in str(raw).replace("|", ",").split(",") if token.strip()]


def extract(apk, output, data_dir, apply_events, apply_dependencies):
    wanted = {"AdvantureEventData", "AbilityItems", "LootData", "Buffs", "DamageValues"}
    tables = {}
    sources = {}
    with zipfile.ZipFile(apk) as archive:
        manifest = next(n for n in archive.namelist() if n.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest))
        chosen = {a["address"]: a for a in assets if (a["address"] in wanted and "/MasterCfg/" in a["path"]) or a["address"].startswith(("AbilityItemCfg_", "BuffCfg_[", "DamageCfg_"))}
        for index in sorted({a["bundle"] for a in chosen.values()}):
            bundle = bundles[index]
            member = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in chosen:
                    continue
                value = obj.read()
                raw = value.m_Script
                if isinstance(raw, bytes):
                    raw = raw.decode("utf-8-sig")
                else:
                    raw = raw.lstrip("\ufeff")
                parsed = json.loads(raw)
                source = {"member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(), "path_id": str(obj.path_id), "asset": chosen[value.m_Name]["path"]}
                if value.m_Name in wanted:
                    tables[value.m_Name] = parsed
                    sources[value.m_Name] = source
                elif value.m_Name.startswith("AbilityItemCfg_"):
                    tables.setdefault("AbilityItems", []).append(parsed)
                    sources.setdefault("AbilityItems", {})[str(row_id(parsed))] = source
                elif value.m_Name.startswith("BuffCfg_["):
                    ident = int(value.m_Name.split("[")[1].rstrip("]"))
                    tables.setdefault("Buffs", []).append(dict(parsed, id=ident))
                    sources.setdefault("Buffs", {})[str(ident)] = source
                elif value.m_Name.startswith("DamageCfg_"):
                    for entry in parsed:
                        if int(entry.get("Level", 1)) != 1:
                            continue
                        ident = int(entry["DamageDefId"])
                        tables.setdefault("DamageValues", []).append(dict(entry, Id=ident))
                        sources.setdefault("DamageValues", {})[str(ident)] = source
    missing = wanted - tables.keys()
    if missing:
        raise ValueError("Missing APK tables: " + ", ".join(sorted(missing)))
    indexed = {name: {row_id(row): row for row in table} for name, table in tables.items()}
    required = {name: set() for name in wanted}
    required["AdvantureEventData"] = set(indexed["AdvantureEventData"])
    for event in tables["AdvantureEventData"]:
        data = event.get("TypeData", {})
        for option in data.get("OptionList", []) + data.get("GambleOptionList", []):
            for key, value in option.items():
                if "AbilityItemId" in key:
                    required["AbilityItems"].update(ids(value))
                elif "RogueLootItemId" in key:
                    required["LootData"].update(ids(value))
    for loot_id in required["LootData"]:
        required["AbilityItems"].add(int(indexed["LootData"][loot_id]["ability_item_id"]))
    for ability_id in required["AbilityItems"]:
        for key in ("AddBuff", "ModifyBuff"):
            required["Buffs"].update(ids(indexed["AbilityItems"][ability_id].get(key, "")))
    for buff_id in required["Buffs"]:
        for level in indexed["Buffs"][buff_id].get("BuffData", {}).get("BuffSettingDataList", []):
            if int(level.get("DamageDefId", 0)):
                required["DamageValues"].add(int(level["DamageDefId"]))
    output.mkdir(parents=True, exist_ok=True)
    differences = {}
    for name, selected in required.items():
        current = {row_id(row): row for row in json.loads((data_dir / (name + ".json")).read_text())}
        rows = [indexed[name][i] for i in sorted(selected)]
        (output / (name + ".json")).write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")
        differences[name] = {"missing": sorted(selected - current.keys()), "different": sorted(i for i in selected & current.keys() if current[i] != indexed[name][i]), "referenced_count": len(selected)}
    sources = {name: {str(i): sources[name][str(i)] for i in required[name]} if name in ("AbilityItems", "Buffs", "DamageValues") else sources[name] for name in wanted}
    provenance = {"apk": str(apk.resolve()), "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(), "manifest": manifest, "tables": sources, "differences_before_import": differences}
    previous_path = output / "provenance.json"
    if previous_path.exists():
        previous = json.loads(previous_path.read_text())
        if previous.get("apk_sha256") == provenance["apk_sha256"]:
            provenance["differences_before_import"] = previous["differences_before_import"]
    previous_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
    if apply_events:
        (data_dir / "AdvantureEventData.json").write_text(json.dumps(tables["AdvantureEventData"], ensure_ascii=False, separators=(",", ":")) + "\n")
    if apply_dependencies:
        for name in wanted - {"AdvantureEventData"}:
            path = data_dir / (name + ".json")
            rows = json.loads(path.read_text())
            changed = set(differences[name]["different"])
            if not changed and not differences[name]["missing"]:
                continue
            rows = [indexed[name][row_id(row)] if row_id(row) in changed else row for row in rows]
            rows.extend(indexed[name][i] for i in differences[name]["missing"])
            path.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(json.dumps({"output": str(output), "differences": differences}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--apply-events", action="store_true")
    parser.add_argument("--apply-dependencies", action="store_true")
    args = parser.parse_args()
    extract(args.apk, args.output, args.data_dir, args.apply_events, args.apply_dependencies)
