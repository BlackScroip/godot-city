"""Build lossless, indexed runtime descriptors without changing source catalogs."""

import argparse
import hashlib
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def archive(records):
    output = io.BytesIO()
    output.write(b"[")
    ranges = {}
    for key, value in records.items():
        if ranges:
            output.write(b",")
        raw = encode(value)
        ranges[key] = [output.tell(), len(raw)]
        output.write(raw)
    output.write(b"]\n")
    data = output.getvalue()
    for key, value in records.items():
        start, length = ranges[key]
        assert json.loads(data[start:start + length]) == value, key
    return data, ranges


def build(check=False):
    source = ROOT / "assets/combat_presentation"
    catalog_raw = (source / "catalog.json").read_bytes()
    materials_raw = (source / "materials.json").read_bytes()
    catalog = json.loads(catalog_raw)
    materials = json.loads(materials_raw)
    effects_data, effects_ranges = archive(catalog["effects"])
    materials_data, materials_ranges = archive(materials)
    # Keep the existing metadata view; particle module dictionaries are decoded
    # from the archive only when preparing the corresponding effect.
    index = {key: value for key, value in catalog.items() if key not in ("effects", "material_properties")}
    index["effects"] = {}
    for key, definition in catalog["effects"].items():
        header = {field: value for field, value in definition.items() if field != "layers"}
        header["layers"] = [{}] if definition.get("layers") else []
        header["_runtime_descriptor"] = key
        index["effects"][key] = header
    index["_runtime_descriptors"] = {
        "schema": 1,
        "effects_path": "res://assets/combat_presentation/runtime/effects.json",
        "materials_path": "res://assets/combat_presentation/runtime/materials.json",
        "material_library": "res://assets/combat_presentation/materials.json",
        "effects": effects_ranges,
        "materials": materials_ranges,
        "source_catalog_sha256": hashlib.sha256(catalog_raw).hexdigest(),
        "source_materials_sha256": hashlib.sha256(materials_raw).hexdigest(),
        "effects_sha256": hashlib.sha256(effects_data).hexdigest(),
        "materials_sha256": hashlib.sha256(materials_data).hexdigest(),
    }
    output = source / "runtime"
    files = {"catalog.json": encode(index) + b"\n", "effects.json": effects_data, "materials.json": materials_data}
    if not check:
        output.mkdir(exist_ok=True)
    for name, data in files.items():
        path = output / name
        if check:
            if not path.is_file() or path.read_bytes() != data:
                raise SystemExit(f"Stale runtime descriptors: {path}; run {Path(__file__).name}")
        else:
            path.write_bytes(data)
    return {"effects": len(effects_ranges), "materials": len(materials_ranges), "deep_equal_records": len(effects_ranges) + len(materials_ranges), "index_bytes": len(files["catalog.json"]), "archive_bytes": len(effects_data) + len(materials_data), "checked": check, "source_catalog_sha256": hashlib.sha256(catalog_raw).hexdigest(), "source_materials_sha256": hashlib.sha256(materials_raw).hexdigest()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    print(json.dumps(build(args.check)))
