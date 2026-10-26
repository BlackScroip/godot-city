"""Inspect source pickup scatter/follow behavior without executing the APK."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records
import inspect_new_camp_native as native


native.SELECTION = {
    "EnvUnitPickUpable": ["EnvUnitPickUpable(", "<Init>b__7_0", "Init(", "InitAnim", "LateUpdate", "OnDispose"],
    "EnvUnitPickUpableProperty": ["EnvUnitPickUpableProperty(", "Deserialize"],
    "RogueRoomManager": ["GenerateResLootEnvUnit", "AddResLootDelay"],
    "ResLootData": ["get_EnvUnitResId"],
    "BattleManager_Rogue": ["CreatePickUpableEnvUnit"],
}
native.SELECTED_OFFSETS = {0x5EBA3D0, 0x5EBA1D8, 0x5EBA218, 0x33153FC, 0x3311DF0}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def string_mapping(data, metadata):
    program_offset = struct.unpack_from("<Q", data, 32)[0]
    entry_size, count = struct.unpack_from("<HH", data, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", data, program_offset + index * entry_size) for index in range(count)]

    def file_offset(address):
        return next(offset + address - va for kind, flags, offset, va, physical, size, memory, alignment in segments if kind == 1 and va <= address < va + size)

    section_offset = struct.unpack_from("<Q", data, 40)[0]
    entry_size, count = struct.unpack_from("<HH", data, 58)
    pointers = {101: 0x65C6BE0, 102: 0x65C6BC8}
    relocations = {}
    for index in range(count):
        section = struct.unpack_from("<IIQQQQIIQQ", data, section_offset + index * entry_size)
        if section[1] != 4:
            continue
        for location in range(section[4], section[4] + section[5], section[9] or 24):
            target, info, addend = struct.unpack_from("<QQq", data, location)
            if target in pointers.values():
                relocations[target] = (location, info, addend)
    literal_entries, literal_entries_size, literal_data, literal_data_size = struct.unpack_from("<4I", metadata, 8)
    result = []
    for resource_type, pointer in pointers.items():
        relocation_offset, info, carrier_va = relocations[pointer]
        carrier_offset = file_offset(carrier_va)
        encoded = struct.unpack_from("<Q", data, carrier_offset)[0]
        assert encoded >> 29 == 5, hex(encoded)
        literal_index = (encoded & 0x1FFFFFFF) >> 1
        entry_offset = literal_entries + literal_index * 8
        length, location = struct.unpack_from("<II", metadata, entry_offset)
        value = metadata[literal_data + location:literal_data + location + length].decode("utf-8")
        result.append({"resource_type": resource_type, "env_id": value,
                       "global_pointer_va": hex(pointer), "relocation_file_offset": hex(relocation_offset),
                       "relocation_info": hex(info), "carrier_va": hex(carrier_va),
                       "carrier_file_offset": hex(carrier_offset), "encoded_usage": hex(encoded),
                       "metadata_literal_index": literal_index, "metadata_entry_offset": hex(entry_offset),
                       "metadata_text_offset": hex(literal_data + location)})
    return {"switch_file_offset": "0x12f1f9e", "switch_bytes": data[0x12F1F9E:0x12F1F9E + 8].hex(), "mappings": result}


def configs(apk, env_ids):
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        payload = archive.read(manifest_name)
        assets, bundles = manifest_records(payload)
        selected = {"EnvUnitCfg_[" + ident + "]": next(asset for asset in assets if asset["address"] == "EnvUnitCfg_[" + ident + "]") for ident in env_ids}
        result = {"manifest": {"member": manifest_name, "sha256": sha(payload)}, "items": {}}
        for index in sorted({asset["bundle"] for asset in selected.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in selected:
                    continue
                asset = obj.read()
                text = asset.m_Script
                if isinstance(text, bytes):
                    text = text.decode("utf-8-sig")
                parsed = json.loads(text)
                result["items"][parsed["EnvUnitData"]["ID"]] = {
                    "source_asset": selected[asset.m_Name], "bundle_member": member,
                    "bundle_sha256": sha(payload), "path_id": str(obj.path_id),
                    "text_sha256": sha(text.encode("utf-8")), "data": parsed}
        return result


def inspect(apk, native_path, metadata_path, stubs):
    result = native.inspect(native_path, stubs)
    data, metadata = native_path.read_bytes(), metadata_path.read_bytes()
    result["apk_sha256"] = hashlib.file_digest(apk.open("rb"), "sha256").hexdigest()
    result["metadata_sha256"] = sha(metadata)
    result["resource_string_mapping"] = string_mapping(data, metadata)
    result["configs"] = configs(apk, [entry["env_id"] for entry in result["resource_string_mapping"]["mappings"]])
    result["raw_constants"] = []
    for offset, length, description in (
        (0x1288C60, 2, "constructor: active pickup time, pickup speed scale"),
        (0x1287E18, 1, "delayed InitAnim ticker and jump destination Y"),
        (0x1287FE0, 1, "animation duration adjustment to active pickup time"),
        (0x1287DAC, 1, "jumpPower random minimum"),
        (0x1287E78, 1, "jumpPower random maximum"),
        (0x1287F10, 1, "normalization epsilon"),
    ):
        raw = data[offset:offset + 4 * length]
        result["raw_constants"].append({"file_offset": hex(offset), "bytes": raw.hex(), "float32_values": struct.unpack("<" + "f" * length, raw), "description": description})
    names = {"EnvUnitPickUpable", "EnvUnitPickUpableProperty", "EnvUnitPickUpableSettingProperty", "ResLootData", "EResLootType"}
    result["declarations"] = [{"path": str(path), "sha256": sha(path.read_bytes()), "text": path.read_text()} for path in sorted(stubs.rglob("*.cs")) if path.stem in names]
    result["interpretation"] = {
        "scatter": {"starts_after_spawn_seconds": 0.1, "direction": "UnityEngine.Random.onUnitSphere, retain x/z only", "random_scalar_range": [2, 5], "jump_power_range": [0.8, 1.2], "jump_count": 2, "duration_seconds": 0.7, "destination_y": 0.1, "snapping": False},
        "follow": {"eligible_after_spawn_seconds_strictly_greater_than": 1, "range_101_and_102": 99, "once_started_keeps_following_outside_range": True, "speed_expression": "1 + 30 * clamp(follow_elapsed_seconds, 0, 5)", "initial_speed": 1, "acceleration": 30, "maximum_speed": 151, "collect_distance_inclusive": 0.5, "distance_dimension": "3D world transform positions; sampled before movement"},
        "split": {"101_target_count": "N < 10 ? 1 : min(floor(N / 10), 5)", "102_target_count": "N < 3 ? 1 : min(floor(N / 3), 4)", "each_value": "max(1, floor(N / target_count))", "remainder": "A separate remainder entity can make total entity count target_count + 1", "non_sync": "Does not split; schedules AddResLootDelay with 2 seconds"},
    }
    result["limitations"] = ["Static native and package evidence only; original APK not executed.", "Exact Unity DOTween path/curve presentation is distinct from a reconstruction's chosen motion approximation.", "Hardcoded native ranges and string-global addresses apply only to the recorded native SHA-256."]
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk, args.native, args.metadata, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": result["native_sha256"], "methods": len(result["methods"]), "configs": list(result["configs"]["items"])}))
