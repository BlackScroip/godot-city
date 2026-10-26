#!/usr/bin/env python3
"""Retain APK-bound native monster hit-state, consumption and tenacity evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zipfile

from inspect_hit_feedback_native import APK_SHA, NATIVE_SHA, NATIVE_MEMBER, METADATA_MEMBER, retained_method


NAMESPACE = "Assembly-CSharp/Teamelo/ActionEngine/"
METHODS = {
    "RoleUnit": ["SetHitAndUpMove", "AddAccTenacity", "UpdateTenacity", "RecoverTenacityPerSec", "OnActionStart", "Update", "GetAttribute"],
    "Monster": ["SetHitAndUpMove", "InitRuntimeAttributes", "OnArmorBeBreak", "GetAttribute"],
    "MonsterProperty": ["Deserialize", "MonsterProperty"],
    "ActionProperty": ["ActionProperty", "Deserialize"],
    "ActionStatus": ["SetHitAndUpMove", "OnActionStart", "GetLocalTimeScale", "Reset"],
    "ActionInterrupt_CheckHitAction": ["CheckInterrupt"],
    "PropertyName": ["PropertyName"],
}
REFERENCES = {
    "monster_type": 0x65B8C58,
    "player_type": 0x65C5850,
    "back_low": 0x65D0428,
    "back_high": 0x65D0438,
    "fly": 0x65D0430,
    "down": 0x65D0440,
    "empty_string": 0x65AC9D0,
    "can_hit_key": 0x65D7F00,
}
FINDINGS = [
    {"id": "monster-native-type-route", "kind": "observation", "methods": ["RoleUnit.SetHitAndUpMove"], "detail": "The two type-check GOT references decode to the Monster and Player byvalTypeIndex entries in the APK metadata. While IsWeakTime is true, Monster reaches ActionStatus.SetHitAndUpMove with isRotateToAtkDir=true, Player with false. Nonweak hits do not enter this displacement/state path."},
    {"id": "authored-tenacity-fields", "kind": "observation", "methods": ["Monster.InitRuntimeAttributes", "RoleUnit.GetAttribute"], "detail": "Monster.InitRuntimeAttributes copies MonsterProperty.BaseTenacity(+0x78), BaseTenacityAccReduce(+0x7c), BaseWeakTime(+0x80) into UnitRuntimeStatus +0x238/+0x23c/+0x248. Attribute98 adds current ActionProperty.StableValue(+0x38) to BaseTenacity. Attribute94 adds current ActionProperty.WeightAddValue(+0x3c) to BaseWeight. Attribute99 reads BaseTenacityAccReduce. Attribute101 reads BaseWeakTime. Current action extra tenacity belongs to the threshold; source config BaseTenacity is not the complete threshold when an action adds tenacity."},
    {"id": "hit-state-setting", "kind": "observation", "methods": ["ActionStatus.SetHitAndUpMove"], "detail": "After push resistance and the zero-weight fallback, upperPower<weight writes PropertyName.sHitAction_String='hit_1' only if abs(effectivePush)/weight>=float32(0.1). upperPower>=weight clears horizontal push timers and writes 'hit_2'. This examined setter never writes 'hitfly' or 'hitdown'; those states cannot be inferred merely from upperPower being positive."},
    {"id": "hit-interrupt-predicate", "kind": "observation", "methods": ["ActionInterrupt_CheckHitAction.CheckInterrupt"], "detail": "Reads PropertyContext.GetProperty(PropertyName.sHitAction_String), extracts string, and returns OR of ('hit_1' and Behit_BackLow), ('hit_2' and Behit_BackHigh), ('hitfly' and Behit_Fly), ('hitdown' and Behit_Down). The predicate itself does not clear the property."},
    {"id": "hit-state-consumption", "kind": "observation", "methods": ["RoleUnit.OnActionStart", "ActionStatus.OnActionStart"], "detail": "ActionStatus.OnActionStart first invokes RoleUnit.OnActionStart virtually. RoleUnit.OnActionStart checks the entered ActionProperty.ActionState(+0x40)==EActionState.BeHit(6); only this branch writes string.Empty to sHitAction_String. A system route with state1004 does not consume the hit property. Clearing on every action entry or upon checking an interrupt would change this behavior."},
    {"id": "hit-layer-separate", "kind": "observation", "methods": ["Monster.SetHitAndUpMove"], "detail": "On accepted hits that remain nonweak, Monster.SetHitAndUpMove selects source normal/special BeHitBlend layer weights and plays the authored layer1 animation. It does not change the active action here; visual hit blending is not an attack interruption."},
    {"id": "tenacity-clock", "kind": "observation", "methods": ["RoleUnit.Update", "RoleUnit.UpdateTenacity"], "detail": "Metadata identifies UpdateTenacity virtual slot66 and AddAccTenacity slot68. The native Il2CppClass vtable starts at+0x138, so their function offsets are+0x558 and+0x578. RoleUnit.Update calls +0x558 at VA0x31640e8 with its retained fTick(s8), after only mIsPause(+0x20) applies a0.001 scale. It does not multiply this argument by mStopTickScale; the action local clock is a separate path. Upstream fTick/battle-time ownership is outside this bounded report."},
    {"id": "elite-break-is-armor-presentation", "kind": "observation", "methods": ["Monster.OnArmorBeBreak", "MonsterProperty.MonsterProperty"], "detail": "Metadata editor annotation describes EliteBreakEnable as enabling elite armor-zero break presentation. OnArmorBeBreak's elite branch requires EnemyType1, first-armor-break flag, EliteBreakEnable and a matching authored action before PreChangeAction. The native constructor does not initialize the bool, so absent serialized EliteBreakEnable retains false. The field is not used as a general tenacity immunity flag in the examined hit setter."},
    {"id": "action-can-hit-default", "kind": "observation", "methods": ["ActionProperty.ActionProperty", "ActionProperty.Deserialize", "ActionStatus.Reset"], "detail": "ActionProperty constructor writes0x0101 at+0x4c, so mCanBeHit(+0x4d) defaults true. Deserialize binds the CanHit key to this byte and passes defaultValue=true to JsonHelper.ReadBool. ActionStatus.Reset copies this byte into ActionStatus.CanBeHit(+0x11), which gates RoleUnit.GetCantBeHurtType. Legacy serialized CanBeHurt is not this field."},
]


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--lib", type=Path, required=True)
    parser.add_argument("--global-metadata", type=Path, required=True)
    parser.add_argument("--metadata-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "reports/monster-hit-rules-native-static.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("This native report requires the audited APK")
    native, metadata = args.lib.read_bytes(), args.global_metadata.read_bytes()
    with zipfile.ZipFile(args.apk) as archive:
        if sha(native) != NATIVE_SHA or sha(archive.read(NATIVE_MEMBER)) != NATIVE_SHA:
            raise ValueError("Native library does not match the APK")
        if metadata != archive.read(METADATA_MEMBER):
            raise ValueError("Metadata does not match the APK")
    phoff = struct.unpack_from("<Q", native, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", native, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", native, phoff + i * phentsize) for i in range(phnum)]

    def file_at(va):
        return next(row[2] + va - row[3] for row in segments if row[0] == 1 and row[3] <= va < row[3] + row[5])

    def virtual_at(offset):
        return next(row[3] + offset - row[2] for row in segments if row[0] == 1 and row[2] <= offset < row[2] + row[5])

    shoff = struct.unpack_from("<Q", native, 40)[0]
    shentsize, shnum = struct.unpack_from("<HH", native, 58)
    relocations = {}
    for section_index in range(shnum):
        section = struct.unpack_from("<IIQQQQIIQQ", native, shoff + section_index * shentsize)
        if section[1] != 4:
            continue
        for off in range(section[4], section[4] + section[5], 24):
            va, info, addend = struct.unpack_from("<QQq", native, off)
            if va in REFERENCES.values():
                if info != 1027:
                    raise ValueError("Expected an R_AARCH64_RELATIVE reference")
                relocations[va] = {"file_offset": hex(off), "bytes": native[off:off + 24].hex(), "type": info, "addend": addend}
    sanity, version = struct.unpack_from("<II", metadata)
    if sanity != 0xFAB11BAF or version != 31:
        raise ValueError("Expected audited metadata version31")
    literals, literal_bytes, literal_data, literal_data_bytes = struct.unpack_from("<IIII", metadata, 8)
    strings, string_bytes = struct.unpack_from("<II", metadata, 0x18)
    type_defs, type_bytes = struct.unpack_from("<II", metadata, 0xA0)
    method_defs, method_bytes = struct.unpack_from("<II", metadata, 0x30)
    if type_bytes % 88 or method_bytes % 36:
        raise ValueError("Unexpected metadata record sizes")

    def read_string(index):
        end = metadata.index(b"\0", strings + index, strings + string_bytes)
        return metadata[strings + index:end].decode("utf-8")

    references = {}
    for label, va in REFERENCES.items():
        relocation = relocations[va]
        encoded_off = file_at(relocation["addend"])
        encoded = struct.unpack_from("<Q", native, encoded_off)[0]
        kind, index = (encoded >> 29) & 7, (encoded >> 1) & 0x0FFFFFFF
        result = {"got_va": hex(va), "relocation": relocation, "encoded_file_offset": hex(encoded_off), "encoded": hex(encoded), "kind": kind, "index": index}
        if not encoded & 1:
            raise ValueError("Expected an encoded metadata usage")
        if kind == 5:
            if index * 8 >= literal_bytes:
                raise ValueError("Invalid metadata literal index")
            entry = literals + index * 8
            length, data_index = struct.unpack_from("<II", metadata, entry)
            if data_index + length > literal_data_bytes:
                raise ValueError("Invalid metadata literal data")
            raw = metadata[literal_data + data_index:literal_data + data_index + length]
            result.update({"metadata_table_offset": hex(entry), "metadata_data_offset": hex(literal_data + data_index), "bytes": raw.hex(), "utf8": raw.decode("utf-8")})
        elif kind == 1:
            matches = []
            for ordinal in range(type_bytes // 88):
                off = type_defs + ordinal * 88
                name, namespace, byval = struct.unpack_from("<III", metadata, off)
                if byval == index:
                    matches.append({"type_definition_index": ordinal, "metadata_offset": hex(off), "bytes": metadata[off:off + 88].hex(), "name": read_string(name), "namespace": read_string(namespace), "byval_type_index": byval})
            if len(matches) != 1:
                raise ValueError("Nonunique metadata type identity")
            result["type_definition"] = matches[0]
        else:
            raise ValueError("Unexpected metadata usage kind")
        references[label] = result
    methods, metadata_sources = [], {}
    for cls, names in METHODS.items():
        relative = NAMESPACE + cls + ".cs"
        source = (args.metadata_root / relative).read_bytes()
        metadata_sources[relative] = {"sha256": sha(source)}
        for name in names:
            method = retained_method(source.decode("utf-8"), name, "")
            off, length = method.pop("offset"), method["length"]
            va = virtual_at(off)
            command = ["xcrun", "llvm-objdump", "--disassemble", "--start-address=" + hex(va), "--stop-address=" + hex(va + length), str(args.lib)]
            methods.append(dict(method, method=cls + "." + name, metadata_source=relative, file_offset=hex(off), virtual_address=hex(va), code_sha256=sha(native[off:off + length]), assembly=subprocess.check_output(command, text=True)))
    slots = []
    for ordinal in range(method_bytes // 36):
        off = method_defs + ordinal * 36
        name, declaring_type = struct.unpack_from("<II", metadata, off)
        flags, iflags, slot, count = struct.unpack_from("<HHHH", metadata, off + 28)
        if declaring_type == 4435 and read_string(name) in ("AddAccTenacity", "UpdateTenacity", "UpdateSpecialState"):
            slots.append({"method": read_string(name), "metadata_offset": hex(off), "bytes": metadata[off:off + 36].hex(), "virtual_slot": slot, "class_vtable_function_offset": hex(0x138 + slot * 16)})
    report = {
        "schema": 1, "apk_sha256": APK_SHA, "member": NATIVE_MEMBER,
        "member_sha256": NATIVE_SHA, "metadata_member_sha256": sha(metadata),
        "evidence_type": "static ARM64 and IL2CPP metadata; no execution observed",
        "references": references, "method_slots": slots, "metadata_sources": metadata_sources,
        "methods": methods, "findings": FINDINGS,
        "limitations": [
            "No runtime playthrough or animation motion was observed.",
            "No claim that the threshold is only BaseTenacity: current action StableValue and buff modifiers can change it.",
            "Native hit setter does not establish producers for hitfly/hitdown, nor upstream battle fTick policy.",
            "All timing values and metadata offsets are bound to the supplied APK hash.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"methods": len(methods), "references": {key: value.get("utf8", value.get("type_definition", {}).get("name")) for key, value in references.items()}, "virtual_slots": slots}))


if __name__ == "__main__":
    main()
