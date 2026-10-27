"""Retain bounded fashion ownership and bonus evidence from the selected APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import inspect_new_camp_native as audit


def inspect(apk, native, stubs):
    with apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505":
        raise ValueError("The address stubs require the supplied 1061664.apk")
    payload = native.read_bytes()
    with zipfile.ZipFile(apk) as archive:
        if archive.read("lib/arm64-v8a/libil2cpp.so") != payload:
            raise ValueError("Native bytes do not match the selected APK")
    audit.SELECTION = {"GameDataModel_AT": [
        "CalculateFashionBonus(", "IsCoreOwned(", "IsOwned(",
        "IsFashionAvailableForCurrentUser(", "Refresh_FashionConfigList(",
        "GetEquippedAvailableFashionId(",
    ]}
    audit.SELECTED_OFFSETS = set()
    result = audit.inspect(native, stubs)
    for method in result["methods"]:
        offset = int(method["file_offset"], 16)
        method["bytes"] = payload[offset:offset + method["length"]].hex()
        method["stub_sha256"] = hashlib.sha256(Path(method["stub"]).read_bytes()).hexdigest()
    result["apk_sha256"] = digest
    result["limitations"] = [
        "Static ARM64 and matching address declarations; the original APK was not executed.",
        "Payment receipts, server entitlements and platform purchase execution are not observed.",
    ]
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk, args.native, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(result["methods"])}))
