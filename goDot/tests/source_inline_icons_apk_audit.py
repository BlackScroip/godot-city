#!/usr/bin/env python3
"""Independently compare mapped PNG pixels with Sprites decoded from the APK.

Run from the project root:
  env PYTHONPATH=/private/tmp/city-event-pydeps python3 tests/source_inline_icons_apk_audit.py

The APK is parsed as a ZIP/Unity asset bundle; no target code is executed.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import io
import json
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

import UnityPy
from PIL import Image


FOCUS_NAMES = (
    "buff_zhongji",
    "buff_zhuorejianqi",
    "buff_jianxin",
    "buff_gongjili",
    "buff_putonggongji",
)
KNOWN_UNRESOLVED = (
    "buff_longhunnengliang",
    "buff_sikadizhinunengliang",
    "buff_sishenbiaoji",
)
EXPECTED_MAPPED_COUNT = 87


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def image_record(image: Image.Image) -> dict:
    return {
        "size": list(image.size),
        "mode": image.mode,
        "rgba_sha256": sha256_bytes(image.convert("RGBA").tobytes()),
    }


def compare_pixels(source: Image.Image, local: Image.Image) -> dict:
    if source.size != local.size:
        return {"exact_match": False, "mismatched_pixels": None}
    source_bytes = source.convert("RGBA").tobytes()
    local_bytes = local.convert("RGBA").tobytes()
    changed = sum(
        source_bytes[offset : offset + 4] != local_bytes[offset : offset + 4]
        for offset in range(0, len(source_bytes), 4)
    )
    return {
        "exact_match": source_bytes == local_bytes,
        "mismatched_pixels": changed,
        "max_channel_delta": max(
            (abs(left - right) for left, right in zip(source_bytes, local_bytes)),
            default=0,
        ),
    }


def audit(project_root: Path, apk_path: Path) -> dict:
    map_path = project_root / "assets/ui/talent_view/inline_map.json"
    provenance_path = project_root / "assets/ui/talent_view/inline-provenance.json"
    mapping = json.loads(map_path.read_text(encoding="utf-8"))
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    source_entries = defaultdict(list)
    for entry in provenance["sprites"]:
        source_entries[entry["name"]].append(entry)

    actual_apk_sha256 = sha256_file(apk_path)
    integrity_errors = []
    if actual_apk_sha256 != provenance["apk_sha256"]:
        integrity_errors.append("APK SHA-256 differs from provenance")
    if len(mapping) != EXPECTED_MAPPED_COUNT:
        integrity_errors.append(f"Expected {EXPECTED_MAPPED_COUNT} mapped icons, got {len(mapping)}")
    if set(mapping) != set(source_entries):
        integrity_errors.append("Map and provenance Sprite names differ")

    members = {}
    environments = {}
    indexed_objects = {}
    bundle_sprite_names = set()
    referenced_members = defaultdict(set)
    for entry in provenance["sprites"]:
        referenced_members[entry["member"]].add(entry["bundle_sha256"])
    keyword_table = provenance.get("keyword_table", {})
    if keyword_table:
        referenced_members[keyword_table["member"]].add(keyword_table["bundle_sha256"])

    records = []
    with zipfile.ZipFile(apk_path) as archive:
        for member, expected_hashes in sorted(referenced_members.items()):
            payload = archive.read(member)
            actual_hash = sha256_bytes(payload)
            hash_match = expected_hashes == {actual_hash}
            members[member] = {
                "bytes": len(payload),
                "sha256": actual_hash,
                "provenance_sha256": sorted(expected_hashes),
                "hash_match": hash_match,
            }
            if not hash_match:
                integrity_errors.append(f"Referenced member SHA-256 mismatch: {member}")
            if any(entry["member"] == member for entry in provenance["sprites"]):
                environment = UnityPy.load(payload)
                environments[member] = environment
                by_id = defaultdict(list)
                for obj in environment.objects:
                    by_id[str(obj.path_id)].append(obj)
                    if obj.type.name == "Sprite":
                        bundle_sprite_names.add(obj.peek_name())
                indexed_objects[member] = by_id
                members[member]["object_types"] = dict(
                    sorted(Counter(obj.type.name for obj in environment.objects).items())
                )

        for name, output in sorted(mapping.items()):
            record = {"name": name, "output": output}
            records.append(record)
            try:
                entries = source_entries[name]
                if len(entries) != 1:
                    raise ValueError(f"Expected one provenance entry, got {len(entries)}")
                entry = entries[0]
                record["member"] = entry["member"]
                record["path_id"] = entry["path_id"]
                if output != entry["output"]:
                    raise ValueError("Map output differs from provenance output")
                objects = indexed_objects[entry["member"]][entry["path_id"]]
                if len(objects) != 1 or objects[0].type.name != "Sprite":
                    raise ValueError("Provenance path ID does not uniquely identify a Sprite")
                sprite = objects[0].read()
                if sprite.m_Name != name:
                    raise ValueError(f"Sprite name mismatch: {sprite.m_Name!r}")
                source_image = sprite.image.convert("RGBA")
                record["source"] = image_record(source_image)
                record["source"]["sprite_name"] = sprite.m_Name
                record["source"]["serialized_file"] = sprite.assets_file.name
                record["source"]["sprite_rect"] = {
                    key: getattr(sprite.m_Rect, key) for key in ("x", "y", "width", "height")
                }
                if not output.startswith("res://"):
                    raise ValueError("Mapped output is not a project resource")
                local_path = (project_root / output.removeprefix("res://")).resolve()
                if not local_path.is_relative_to(project_root):
                    raise ValueError("Mapped output escapes the project root")
                with Image.open(local_path) as local_image:
                    record["local"] = image_record(local_image)
                    record["local"]["file_sha256"] = sha256_file(local_path)
                    record["comparison"] = compare_pixels(source_image, local_image)
                encoded = io.BytesIO()
                source_image.save(encoded, format="PNG")
                record["source"]["reencoded_png_sha256"] = sha256_bytes(encoded.getvalue())
                record["comparison"]["png_encoding_identical"] = (
                    record["source"]["reencoded_png_sha256"] == record["local"]["file_sha256"]
                )
                record["status"] = "exact_match" if record["comparison"]["exact_match"] else "mismatch"
            except Exception as error:
                record["status"] = "error"
                record["error"] = f"{type(error).__name__}: {error}"

    counts = Counter(record["status"] for record in records)
    passed = not integrity_errors and counts["exact_match"] == len(mapping)
    return {
        "schema_version": 1,
        "evidence_type": "Static APK ZIP and Unity Sprite decoding; no APK runtime executed",
        "method": "UnityPy Sprite.image recovery, then exact width/height and row-major RGBA byte comparison including fully transparent pixels",
        "limitations": [
            "Verifies stored PNG assets against decoded source Sprites, not runtime scaling, text layout, materials, or tint.",
            "Reencoded PNG hashes are informational; exactness is determined by dimensions and RGBA bytes, independent of PNG compression or metadata.",
            "Known unresolved names are checked only against the referenced Sprite bundle; this audit does not reconstruct or inspect the TMP atlas or Chinese description usage.",
        ],
        "tools": {"UnityPy": importlib.metadata.version("UnityPy"), "Pillow": importlib.metadata.version("Pillow")},
        "apk": {"path": str(apk_path), "sha256": actual_apk_sha256, "provenance_sha256": provenance["apk_sha256"]},
        "inputs": {
            "map": {"path": str(map_path), "sha256": sha256_file(map_path)},
            "provenance": {"path": str(provenance_path), "sha256": sha256_file(provenance_path)},
        },
        "members": members,
        "summary": {
            "passed": passed,
            "mapped_icons": len(mapping),
            "provenance_sprites": len(provenance["sprites"]),
            "exact_matches": counts["exact_match"],
            "mismatches": counts["mismatch"],
            "errors": counts["error"],
            "integrity_errors": integrity_errors,
        },
        "focus": {record["name"]: record for record in records if record["name"] in FOCUS_NAMES},
        "unresolved_names": {
            name: {"mapped": name in mapping, "present_in_referenced_sprite_bundle": name in bundle_sprite_names}
            for name in KNOWN_UNRESOLVED
        },
        "sprites": records,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    project_root = args.project_root.resolve()
    apk_path = (args.apk or project_root.parent / "1061664.apk").resolve()
    output = args.output or project_root / "reports/source-inline-icons-apk-audit-20261028.json"
    report = audit(project_root, apk_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(output), **report["summary"]}, indent=2))
    for name, record in report["focus"].items():
        print(f"{name}: {record['status']} {record.get('source', {}).get('size')} {record.get('source', {}).get('rgba_sha256')}")
    return 0 if report["summary"]["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
