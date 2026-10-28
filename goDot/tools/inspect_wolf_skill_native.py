#!/usr/bin/env python3
"""Retain bounded APK native evidence for wolf effect scale and summon events."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import inspect_new_camp_native as native_tools


ROOT = Path(__file__).resolve().parents[2]
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--native", type=Path, default=Path("/private/tmp/city-new-map-native/libil2cpp.so"))
    parser.add_argument("--stubs", type=Path, default=Path("/private/tmp/city-new-map-addresses/DiffableCs"))
    parser.add_argument("--output", type=Path, default=ROOT / "goDot/reports/wolf-skill-native-source.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("Unexpected source APK")
    data = args.native.read_bytes()
    if hashlib.sha256(data).hexdigest() != NATIVE_SHA:
        raise ValueError("Unexpected native library")
    with zipfile.ZipFile(args.apk) as archive:
        if data != archive.read("lib/arm64-v8a/libil2cpp.so"):
            raise ValueError("Extracted library differs from the supplied APK")
    native_tools.SELECTION = {
        "EventPlayEffect": ["PlayEffect(RoleUnit", "<PlayEffect>b__0"],
        "RoleUnit": ["GetCustomAttribute("],
        "SBuffGenerationMonster": ["Init(", "OnEffect()"],
        "EventSetCustomPropertyInt32": ["Execute(RoleUnit"],
        "MultiPointEmitComponent": ["MultiPointEmitComponent(", "Update(float", "IsDead()", "CalcStartPosition("],
        "PlayEffectTriggerByRoleUnitDef": ["PlayEffectTrigger(RoleUnit", "PlayEffectTrigger_Queued(", "OnEffectCreated|0", "SetupEffectAfterCreate("],
    }
    native_tools.SELECTED_OFFSETS = set()
    report = native_tools.inspect(args.native, args.stubs)
    for method in report["methods"]:
        offset = int(method["file_offset"], 16)
        method["code_sha256"] = hashlib.sha256(data[offset:offset + method["length"]]).hexdigest()
        method["stub_sha256"] = hashlib.sha256(Path(method["stub"]).read_bytes()).hexdigest()
    phoff = struct.unpack_from("<Q", data, 32)[0]
    entsize, count = struct.unpack_from("<HH", data, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", data, phoff + index * entsize) for index in range(count)]
    constant_va = 0x1288234
    constant_offset = next(row[2] + constant_va - row[3] for row in segments if row[0] == 1 and row[3] <= constant_va < row[3] + row[5])
    report.update(apk_sha256=APK_SHA, constant={"va": hex(constant_va), "file_offset": hex(constant_offset),
        "float32": struct.unpack_from("<f", data, constant_offset)[0], "bytes": data[constant_offset:constant_offset + 4].hex()},
        observed_scale_equation="Scale multiplier starts at 1.0, adds each pipe-separated custom attribute multiplied by 0.001, and multiplies all three existing localScale axes.",
        source_attribute_note="kuangbao-100 is the literal level-1 custom attribute name in BuffCfg_[41300101], with value 100. It is not an arithmetic expression.",
        rea_evidence_ids=["ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c", "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323"],
        limitations=["Static disassembly and serialized source evidence only; no original APK runtime execution.", "REA IDs identify the selected APK inventory and inspection; this bounded native report is separately bound to its exact SHA-256."])
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"methods": len(report["methods"]), "constant": report["constant"], "native_sha256": NATIVE_SHA}))


if __name__ == "__main__":
    main()
