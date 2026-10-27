"""Recover packaged localization tables without executing the original APK.

Requires UnityPy. The source APK contains four languages, so the other locale
files intentionally remain empty for the supplemental translation layer.
"""

import argparse
from collections import Counter
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

import UnityPy


LOCALES = {
    "zh_CN": "text_cn", "zh_TW": "text_cht", "en": "text_en",
    "ja": "text_jp", "ko": None, "id": None, "th": None, "vi": None,
    "de": None, "fr": None, "pt": None, "es": None, "ru": None,
}
PACKAGE_PREFIX = "assets/yoo/DefaultPackage/"
AUDITED_APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
REA_INVENTORY_EVIDENCE = "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323"
PLACEHOLDER = re.compile(
    r"&[A-Za-z]+\d+&|\{\d+(?::[^{}]*)?\}|"
    r"(?<!%)%(?:\d+\$)?[-+#0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[diouxXeEfFgGcs](?![A-Za-z])"
)
MARKUP = re.compile(r"<[^>]*>")
NUMBER = re.compile(r"[-+]?(?:\d+(?:\.\d+)?|\.\d+)")
SEMANTIC_TAG = re.compile(r"<#(specinfo|LocalizationId)=[\"']?([^>\"']+)[\"']?>")


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


class ManifestReader:
    """Read the current YooAsset manifest's length-prefixed records."""

    def __init__(self, payload):
        self.payload = payload
        self.offset = 0

    def number(self, fmt):
        value = struct.unpack_from("<" + fmt, self.payload, self.offset)[0]
        self.offset += struct.calcsize(fmt)
        return value

    def string(self):
        length = self.number("H")
        value = self.payload[self.offset:self.offset + length].decode("utf-8")
        self.offset += length
        return value

    def array(self, reader):
        return [reader() for _ in range(self.number("H"))]


def manifest_records(payload):
    # Same manifest layout audited by inspect_camp_progression; no native-code
    # dependency is needed to read these localization TextAssets.
    reader = ManifestReader(payload)
    reader.number("I")
    reader.string()
    for _ in range(3):
        reader.number("B")
    for _ in range(2):
        reader.number("i")
    for _ in range(4):
        reader.string()
    assets = []
    for _ in range(reader.number("i")):
        address, path, guid = [reader.string() for _ in range(3)]
        reader.array(reader.string)
        bundle = reader.number("i")
        reader.array(lambda: reader.number("i"))
        assets.append({"address": address, "path": path, "guid": guid, "bundle": bundle})
    bundles = []
    for _ in range(reader.number("i")):
        name = reader.string()
        reader.number("I")
        bundle_hash = reader.string()
        reader.string()
        reader.number("q")
        reader.number("B")
        reader.array(reader.string)
        reader.array(lambda: reader.number("i"))
        bundles.append({"name": name, "hash": bundle_hash})
    if reader.offset != len(payload):
        raise ValueError("YooAsset manifest layout does not match the audited format")
    return assets, bundles


def signature(text):
    return dict(sorted(Counter(PLACEHOLDER.findall(text)).items()))


def number_signature(text):
    plain = MARKUP.sub("", PLACEHOLDER.sub("", text))
    return dict(sorted(Counter(str(Decimal(value).normalize())
                               for value in NUMBER.findall(plain)).items()))


def semantic_signature(text, source_keys):
    terms = []
    for kind, key in SEMANTIC_TAG.findall(text):
        lookup = "<#specinfo=" + key + ">" if kind == "specinfo" else key
        value = MARKUP.sub("", source_keys.get(lookup, key))
        terms.append(re.sub(r"[^\w\u3400-\u9fff]", "", value).lower())
    return dict(sorted(Counter(terms).items()))


def priority(row):
    table, value = row
    preferred = {"LocalizationData_keyword": 0, "LocalizationData_SingleKeyword": 1}
    return preferred.get(table, 2), table, value["key"]


def recover(apk):
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    tables, rows = {}, []
    with zipfile.ZipFile(apk) as archive:
        members = [name for name in archive.namelist() if name.startswith(
            PACKAGE_PREFIX + "DefaultPackage_") and name.endswith(".bytes")]
        if len(members) != 1:
            raise ValueError("Expected one DefaultPackage manifest, found " + str(len(members)))
        manifest_member = members[0]
        manifest = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest)
        selected = {asset["address"]: asset for asset in assets
                    if asset["address"].startswith("LocalizationData_")}
        for index in sorted({asset["bundle"] for asset in selected.values()}):
            member = PACKAGE_PREFIX + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset":
                    continue
                asset = obj.read()
                if asset.m_Name not in selected:
                    continue
                script = asset.m_Script
                raw = script if isinstance(script, bytes) else script.encode("utf-8")
                values = json.loads(raw.decode("utf-8-sig"))
                if not isinstance(values, list) or any(not isinstance(row, dict)
                                                     or not isinstance(row.get("key"), str)
                                                     for row in values):
                    raise ValueError("Unexpected localization table layout: " + asset.m_Name)
                if asset.m_Name in tables:
                    raise ValueError("Duplicate packaged localization table: " + asset.m_Name)
                tables[asset.m_Name] = {
                    "manifest_asset": selected[asset.m_Name], "member": member,
                    "bundle_sha256": digest(payload), "text_asset_sha256": digest(raw),
                    "path_id": str(obj.path_id), "row_count": len(values),
                    "fields": sorted({field for row in values for field in row}),
                    "nonempty_values": {
                        locale: sum(isinstance(row.get(field), str) and bool(row[field])
                                    for row in values) if field else 0
                        for locale, field in LOCALES.items()
                    },
                }
                rows.extend((asset.m_Name, row) for row in values)
    missing = sorted(set(selected) - set(tables))
    if missing:
        raise ValueError("Missing packaged localization tables: " + ", ".join(missing))

    source_keys = {}
    for _, row in rows:
        key = row["key"]
        if key in source_keys:
            raise ValueError("Duplicate localization key: " + key)
        source_keys[key] = row["text_cn"] if isinstance(row.get("text_cn"), str) else ""
    source_maps = {locale: {} for locale in LOCALES}
    keyed_maps = {locale: {} for locale in LOCALES}
    excluded, content_excluded, conflicts = [], [], []
    for table, row in sorted(rows, key=priority):
        key = row["key"]
        source = row.get("text_cn")
        for locale, field in LOCALES.items():
            translation = row.get(field) if field else None
            if not isinstance(translation, str) or not translation:
                continue
            if source and signature(source) != signature(translation):
                excluded.append({
                    "table": table, "key": key, "locale": locale,
                    "source": source, "translation": translation,
                    "source_placeholders": signature(source),
                    "translation_placeholders": signature(translation),
                })
                continue
            if source:
                source_numbers, target_numbers = number_signature(source), number_signature(translation)
                source_terms = semantic_signature(source, source_keys)
                target_terms = semantic_signature(translation, source_keys)
                reasons = []
                if source_numbers != target_numbers:
                    reasons.append("numbers")
                if source_terms != target_terms:
                    reasons.append("semantic_tags")
                if reasons:
                    content_excluded.append({
                        "table": table, "key": key, "locale": locale,
                        "source": source, "translation": translation, "reasons": reasons,
                        "source_numbers": source_numbers, "translation_numbers": target_numbers,
                        "source_semantic_tags": source_terms, "translation_semantic_tags": target_terms,
                    })
                    continue
            keyed_maps[locale][key] = translation
            if not source:
                continue
            previous = source_maps[locale].get(source)
            if previous is not None and previous != translation:
                conflicts.append({"locale": locale, "source": source,
                                  "selected": previous, "alternative": translation,
                                  "alternative_key": key, "table": table})
            else:
                source_maps[locale][source] = translation

    report = {
        "evidence_type": "Static APK ZIP, YooAsset manifest and Unity TextAsset decoding",
        "apk": apk.name, "apk_sha256": apk_sha,
        "manifest_member": manifest_member, "manifest_sha256": digest(manifest),
        "unitypy_version": UnityPy.__version__, "table_count": len(tables),
        "row_count": len(rows), "source_key_count": len(source_keys),
        "source_string_count": len({value for value in source_keys.values() if value}),
        "available_original_locale_fields": {locale: field for locale, field in LOCALES.items() if field},
        "unavailable_original_locales": [locale for locale, field in LOCALES.items() if not field],
        "source_map_counts": {locale: len(mapping) for locale, mapping in source_maps.items()},
        "keyed_map_counts": {locale: len(mapping) for locale, mapping in keyed_maps.items()},
        "placeholder_mismatch_count": len(excluded),
        "excluded_placeholder_mismatches": excluded,
        "content_mismatch_count": len(content_excluded),
        "content_mismatch_reasons": dict(Counter(reason for row in content_excluded
                                                  for reason in row["reasons"])),
        "excluded_content_mismatches": content_excluded,
        "source_translation_conflict_count": len(conflicts),
        "source_translation_conflicts": conflicts,
        "source_conflict_selection": "keyword, then SingleKeyword, then alphabetical table and key; keyed maps preserve context",
        "tables": dict(sorted(tables.items())),
        "limitations": [
            "The original APK contains Simplified Chinese, Traditional Chinese, English and Japanese only.",
            "Empty and null original translations are omitted; no automatic fallback is presented as a translation.",
            "Translations with differing substitution placeholders are retained as evidence but excluded from runtime maps.",
            "Translations with differing visible numbers or semantic tag identities are retained as evidence but excluded from runtime maps.",
            "Semantic tag identities resolve through their original Simplified Chinese labels; absent target tags are conservatively rejected.",
            "Original translations may refer to older gameplay text; extraction does not assert linguistic accuracy.",
            "Markup, specinfo keys and LocalizationId references are preserved verbatim for the runtime renderer.",
            "The original application was not executed during this static resource recovery.",
        ],
    }
    if apk_sha == AUDITED_APK_SHA256:
        report["rea_inventory_evidence_id"] = REA_INVENTORY_EVIDENCE
    files = {locale + ".json": mapping for locale, mapping in source_maps.items()}
    files.update({"keyed_" + locale + ".json": mapping for locale, mapping in keyed_maps.items()})
    files["source_keys.json"] = source_keys
    files["source_report.json"] = report
    return files


def encode(value):
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main():
    project = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=project.parent / "1061664.apk")
    parser.add_argument("--output", type=Path, default=project / "assets/localization/original")
    parser.add_argument("--check", action="store_true", help="Verify generated assets without writing")
    args = parser.parse_args()
    files = recover(args.apk)
    if args.check:
        stale = [name for name, value in files.items()
                 if not (args.output / name).is_file()
                 or (args.output / name).read_text(encoding="utf-8") != encode(value)]
        if stale:
            raise SystemExit("Stale localization assets: " + ", ".join(stale))
    else:
        args.output.mkdir(parents=True, exist_ok=True)
        for name, value in files.items():
            (args.output / name).write_text(encode(value), encoding="utf-8")
    report = files["source_report.json"]
    print(json.dumps({"checked" if args.check else "written": str(args.output),
                      "tables": report["table_count"], "keys": report["source_key_count"],
                      "locale_entries": report["source_map_counts"],
                      "excluded_placeholder_mismatches": report["placeholder_mismatch_count"],
                      "excluded_content_mismatches": report["content_mismatch_count"],
                      "content_mismatch_reasons": report["content_mismatch_reasons"]},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
