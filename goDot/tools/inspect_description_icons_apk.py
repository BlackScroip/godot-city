"""Audit the description icon inputs directly against the supplied APK."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


ROOT = Path(__file__).resolve().parents[1]
REA_EVIDENCE = "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323"
TABLES = ("WeaponData", "AttackData", "CharaTalentAwakeTreeData",
          "RelationshipAmplifyData", "LocalizationData_SingleKeyword")


def audit(apk, export):
    report = {
        "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
        "rea_inventory_evidence_id": REA_EVIDENCE,
        "evidence_type": "Static APK ZIP, Unity TextAsset and TMP sprite asset decoding; original APK not executed",
        "tables": {}, "skills": [], "errors": [],
    }
    values = {}
    with zipfile.ZipFile(apk) as archive:
        manifest = next(name for name in archive.namelist()
                        if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        payload = archive.read(manifest)
        report["manifest"] = {"member": manifest, "sha256": hashlib.sha256(payload).hexdigest()}
        assets, bundles = manifest_records(payload)
        selected = [row for row in assets if row["address"] in TABLES]
        for index in sorted({row["bundle"] for row in selected}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in TABLES:
                    continue
                name = obj.peek_name()
                data = json.loads(obj.read().m_Script)
                values[name] = data
                source = {"member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(),
                          "path_id": str(obj.path_id), "rows": len(data)}
                if name != "AttackData":
                    local_path = ROOT / ("assets/ui/talent_view/specinfo.json"
                                         if name == "LocalizationData_SingleKeyword" else "assets/data/" + name + ".json")
                    local = json.loads(local_path.read_text())
                    fields = ["key", "text_cn", "text_cht", "text_en", "text_jp"] if name.startswith("Localization") else ["id", "description", "effect_description"]
                    by_id = {str(row.get("key", row.get("id"))): row for row in data}
                    mismatches = [{"id": row.get("key", row.get("id")), "field": field}
                                  for row in local for field in fields if field in row
                                  and row[field] != by_id.get(str(row.get("key", row.get("id"))), {}).get(field)]
                    source.update(local_rows=len(local), fields_compared=fields, local_catalog_differences=mismatches)
                    if (mismatches and name not in ("WeaponData", "RelationshipAmplifyData")) or len(local) != len(data):
                        report["errors"].append(name + " differs from packaged description corpus")
                report["tables"][name] = source
        atlas_asset = next(row for row in assets if row["address"] == "spriteatlas_bufftext_group")
        member = "assets/yoo/DefaultPackage/" + bundles[atlas_asset["bundle"]]["hash"] + ".bundle"
        payload = archive.read(member)
        obj = next(obj for obj in UnityPy.load(payload).objects
                   if obj.type.name == "MonoBehaviour" and obj.peek_name() == atlas_asset["address"])
        atlas = obj.read_typetree()
        glyphs = {row["m_Index"]: row for row in atlas["m_SpriteGlyphTable"]}
        characters = [{"name": row["m_Name"], "scale": row["m_Scale"],
                       "glyph_index": row["m_GlyphIndex"], "metrics": glyphs[row["m_GlyphIndex"]]["m_Metrics"]}
                      for row in atlas["m_SpriteCharacterTable"]]
        mapping = json.loads((ROOT / "assets/ui/talent_view/inline_map.json").read_text())
        wanted = set(re.findall(r'<sprite\s+name="([^"]+)"',
                                " ".join(str(v) for row in values["LocalizationData_SingleKeyword"] for v in row.values())))
        names = {row["name"] for row in characters}
        report["tmp_atlas"] = {
            "member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(),
            "path_id": str(obj.path_id), "name": atlas["m_Name"], "character_count": len(characters),
            "mapped_keyword_sprites": len(mapping), "keyword_sprites_absent_from_atlas": sorted(wanted - names),
            "mapped_sprites_absent_from_atlas": sorted(set(mapping) - names), "characters": characters,
        }
    display_source = {name: {str(row["id"]): {field: row[field] for field in ("name", "description", "effect_description") if field in row}
                            for row in values[name]}
                      for name in ("WeaponData", "AttackData", "RelationshipAmplifyData")}
    display_path = ROOT / "assets/ui/talent_view/description_sources.json"
    if export:
        display_path.write_text(json.dumps(display_source, ensure_ascii=False, indent=2) + "\n")
    actual_display = json.loads(display_path.read_text()) if display_path.exists() else {}
    report["presentation_source"] = {
        "resource": "res://assets/ui/talent_view/description_sources.json",
        "matches_packaged_fields": actual_display == display_source,
        "rows": {name: len(rows) for name, rows in display_source.items()},
        "scope": "Presentation text only; existing gameplay tables and numeric behavior remain separate.",
    }
    if actual_display != display_source:
        report["errors"].append("Presentation description fields differ from APK")
    combat = json.loads((ROOT / "assets/data/combat.json").read_text())
    attacks = {int(row["id"]): row for row in values["AttackData"]}
    for fighter in combat["characters"]:
        for index, skill in enumerate(fighter["skills"]):
            source_id = int(skill["id"]) if int(skill["id"]) else int(fighter["skills"][0]["id"])
            matches = actual_display.get("AttackData", {}).get(str(source_id), {}).get("description") == attacks[source_id]["description"]
            report["skills"].append({"character_id": fighter["id"], "slot": index,
                                     "attack_id": source_id, "display_description_matches_apk": matches,
                                     "legacy_catalog_description_matches_apk": skill["description"] == attacks[source_id]["description"]})
            if not matches: report["errors"].append("Character skill description differs: " + str(source_id))
    dialogue = json.loads((ROOT / "assets/data/dialogue.json").read_text())
    lines = [line["Text"] for story in dialogue["Stories"] for line in story["Lines"]]
    lines.extend(row["Text"] for row in dialogue["SimpleTalk"])
    report["dialogue_corpus"] = {
        "scope": "Existing recovered Chinese dialogue corpus; source inventory/provenance remains assets/ui/dialogue/source.json",
        "lines": len(lines), "sprite_tags": sum(len(re.findall(r"<sprite[^>]*>", line)) for line in lines),
        "semantic_tags": sum(len(re.findall(r"<#specinfo=[^>]*>", line)) for line in lines),
        "color_tags": dict(Counter(tag for line in lines for tag in re.findall(r"<color=[^>]*>", line))),
    }
    report["limitations"] = [
        "Table and text equality establish static source identity, not observation of original APK runtime.",
        "TMP atlas metrics are recorded for provenance; this audit does not assert identical text shaping between Unity and Godot.",
        "Three keyword sprite names are absent from the packaged TMP atlas too; they retain explicit fallback instead of invented aliases.",
        "Image pixels are checked by tests/source_inline_icons_apk_audit.py; Godot layout is checked by tests/description_inline_icons_test.gd.",
    ]
    report["passed"] = not report["errors"]
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT.parent / "1061664.apk")
    parser.add_argument("--export", action="store_true", help="Recover only the presentation description fields from the APK")
    args = parser.parse_args()
    report = audit(args.apk, args.export)
    output = ROOT / "reports/description-icons-apk-audit-20261028.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "tables": len(report["tables"]), "skills": len(report["skills"]),
                      "tmp_characters": report["tmp_atlas"]["character_count"], "errors": report["errors"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
