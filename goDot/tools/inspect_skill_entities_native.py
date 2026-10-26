"""Retain bounded current-APK attack-entity lifecycle disassembly."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import inspect_new_camp_native as native_audit

APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
SELECTION = {
    "AttackEntity": ["public AttackEntity(", "public virtual bool Update(", "OnDispose()"],
    "FrameEntity": ["public FrameEntity(", "public override bool Update(", "CheckShouldHit(",
                    "ExcuteSearchTarget()", "public void OnDead()", "GetModify_AddRangePercent()"],
    "AttackHit": ["UpdateEntity(", "public AttackEntity CreateAttackEntity("],
}


def inspect(apk, native, stubs):
    with apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("Unexpected source APK")
    data = native.read_bytes()
    if hashlib.sha256(data).hexdigest() != NATIVE_SHA:
        raise ValueError("Unexpected native library")
    with zipfile.ZipFile(apk) as archive:
        if hashlib.sha256(archive.read("lib/arm64-v8a/libil2cpp.so")).hexdigest() != NATIVE_SHA:
            raise ValueError("Extracted library differs from the supplied APK")
    native_audit.SELECTION = SELECTION
    native_audit.SELECTED_OFFSETS = set()
    evidence = native_audit.inspect(native, stubs)
    for method in evidence["methods"]:
        offset = int(method["file_offset"], 16)
        method["bytes"] = data[offset:offset + method["length"]].hex()
        method["stub_sha256"] = hashlib.sha256(Path(method["stub"]).read_bytes()).hexdigest()
    evidence["apk_sha256"] = APK_SHA
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk, args.native, args.stubs)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"methods": len(result["methods"]), "native_sha256": result["native_sha256"]}))
