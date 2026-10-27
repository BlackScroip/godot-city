#!/usr/bin/env python3
"""Retain exact static evidence for the current APK's spirit modifier formulas."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zipfile

from inspect_combat_timing_native import APK_SHA, MEMBER, NATIVE_SHA, sha


METHODS = [
    ("RoleAttributeInfluence.GetInfluenceMultiplier", 0x30DAD90, 0x12C),
    ("RoleAttributeInfluence.Apply", 0x30DAED0, 0x1A4),
    ("RoleAttributeInfluence.Deserialize", 0x30DB074, 0x2BC),
    ("RoleAttributeInfluence.ctor", 0x30DB5C4, 0x20),
    ("SpiritSpecInfoModifier.Apply", 0x30DB870, 0x174),
    ("SpiritSpecInfoModifier.GetMultiplier", 0x30DB9E4, 0x8),
    ("SpiritSpecInfoModifier.Deserialize", 0x30DB9EC, 0x328),
    ("SpiritSpecInfoModifier.ToAttribute", 0x30DB330, 0x18),
    ("SBuffModifyAttackDef.ModifyAttackHit_Val", 0x3059C18, 0x158),
    ("SBuffModifyCombatResult.ModifyDamageCaculate", 0x305E4E8, 0x3BC),
    ("SBuffModifyCombatResult.applyModifyDamageCaculateType", 0x305E8A4, 0x7C),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--lib", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "reports/spirit-modifiers-native.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("Unexpected APK hash")
    native = args.lib.read_bytes()
    with zipfile.ZipFile(args.apk) as archive:
        if sha(archive.read(MEMBER)) != NATIVE_SHA or sha(native) != NATIVE_SHA:
            raise ValueError("Native library differs from the APK member")
    phoff = struct.unpack_from("<Q", native, 32)[0]
    size, count = struct.unpack_from("<HH", native, 54)
    segments = []
    for index in range(count):
        kind, flags, offset, virtual, _, filesz, memsz, alignment = struct.unpack_from("<IIQQQQQQ", native, phoff + index * size)
        if kind == 1:
            segments.append({"offset": offset, "virtual": virtual, "filesz": filesz, "memsz": memsz, "flags": flags, "alignment": alignment})
    methods = []
    for name, offset, length in METHODS:
        segment = next(row for row in segments if row["offset"] <= offset and offset + length <= row["offset"] + row["filesz"])
        virtual = segment["virtual"] + offset - segment["offset"]
        command = ["xcrun", "llvm-objdump", "--disassemble", "--start-address=%#x" % virtual, "--stop-address=%#x" % (virtual + length), str(args.lib)]
        methods.append({"method": name, "file_offset": hex(offset), "virtual_address": hex(virtual), "length": length,
            "exact_bytes": native[offset:offset + length].hex(), "code_sha256": sha(native[offset:offset + length]),
            "command": command, "assembly": subprocess.check_output(command, text=True)})
    report = {"schema": 1, "evidence_type": "Ordinary-shell static ARM64 disassembly; not REA Evidence and not runtime observation",
        "apk_sha256": APK_SHA, "member": MEMBER, "member_sha256": NATIVE_SHA, "load_segments": segments,
        "address_source": "Cpp2IL DiffableCs Address.Offset; virtual addresses independently mapped through ELF64 PT_LOAD",
        "methods": methods, "findings": [
            {"id": "additive-influences", "type": "observation", "detail": "SpiritSpecInfoModifier.Apply(base,caster) returns base plus the sum of Influence.Apply(0,caster). Each enabled finite influence contributes PerMille * bounded(attribute/1000). GetMultiplier delegates to Apply(1,caster). The supplied base is not multiplied by that contribution."},
            {"id": "influence-bounds", "type": "observation", "detail": "For SpiritTrigger through SpiritCount (attribute IDs157..161), bounds always apply even when UseMinMultiplier/UseMaxMultiplier are false. Otherwise the flags select finite or infinite bounds. Bounds are sorted; default finite limits are0 and5. Disabled, zero-weight, non-finite, missing-owner and recursive attribute reads leave the supplied base unchanged."},
            {"id": "legacy-fields", "type": "observation", "detail": "The SpiritSpecInfoModifier legacy Parameter/PerMille/MinMultiplier/MaxMultiplier property adapter uses its first RoleAttributeInfluence. Parameter maps Trigger/Enhance/Range/Duration/Count to attribute IDs157..161. New Influences rows and legacy objects therefore share the same additive arithmetic."},
            {"id": "wolf-emit-modifier", "type": "observation", "detail": "SBuffModifyAttackDef.ModifyAttackHit_Val's ModifyEmit_Num branch reads the int setting at+0x28 and multiplies it by the current buff layer count at+0x9c before converting to float. The fresh wolf buff41300112 adds10 emissions per layer to matching AttackDef41300151."},
            {"id": "combat-modifier-layers", "type": "observation", "detail": "SBuffModifyCombatResult.ModifyDamageCaculate starts both its base and extra calculation multipliers from this buff's own layer count at+0x9c (VA0x3062570 and0x3062738), then multiplies configured attackee and attacker buff layers. Its helper uses that multiplier in an integer multiply-add. General wound800511 therefore contributes10 per mille per current wound layer; the spirit's separate2 per mille per wound also applies."}],
        "limitations": ["Static code and configuration establish the formula; no APK execution was observed.", "Native cycle logging is represented by the existing domain attribute recursion guard; no target process was attached."]}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"methods": len(methods), "output": str(args.output)}))


if __name__ == "__main__":
    main()
