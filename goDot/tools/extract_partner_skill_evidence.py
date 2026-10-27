"""Extract partner skill metadata from the supplied APK's manifest-bound bundles."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


def extract(apk, output, destination):
    wanted = {"AttackData", "MonsterPartnerData"}
    tables, sources = {}, {}
    with zipfile.ZipFile(apk) as archive:
        manifest = next(n for n in archive.namelist() if n.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(manifest))
        chosen = {a["address"]: a for a in assets if a["address"] in wanted and "/MasterCfg/" in a["path"]}
        for index in sorted({a["bundle"] for a in chosen.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in chosen:
                    continue
                asset = obj.read()
                raw = asset.m_Script
                raw = raw.decode("utf-8-sig") if isinstance(raw, bytes) else raw.lstrip("\ufeff")
                tables[asset.m_Name] = json.loads(raw)
                sources[asset.m_Name] = {"member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(), "path_id": str(obj.path_id), "asset": chosen[asset.m_Name]["path"]}
    if wanted - tables.keys():
        raise ValueError("Missing tables: " + str(wanted - tables.keys()))
    attacks = {int(r["id"]): r for r in tables["AttackData"]}
    rows = []
    for partner in tables["MonsterPartnerData"]:
        if not str(partner.get("attack_id", "")):
            continue
        skill = attacks[int(partner["attack_id"])]
        rows.append({"id": int(partner["id"]), "attack_id": int(skill["id"]), "name": skill["name"], "description": skill["description"], "icon": skill["skill_icon_name"], "action": skill["entry_action_id"], "cost": int(skill["sp"]), "cooldown": int(skill["cd"]) / 1000.0})
    output.mkdir(parents=True, exist_ok=True)
    for name, table in tables.items():
        (output / (name + ".json")).write_text(json.dumps(table, ensure_ascii=False, indent=2) + "\n")
    provenance = {"apk": str(apk.resolve()), "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(), "manifest": manifest, "tables": sources, "skill_count": len(rows)}
    (output / "provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
    destination.write_text(json.dumps({"schema": 1, "source_apk_sha256": provenance["apk_sha256"], "skills": rows}, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(json.dumps({"output": str(destination), "skill_count": len(rows), "provenance": str(output / "provenance.json")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    extract(args.apk, args.output, args.destination)
