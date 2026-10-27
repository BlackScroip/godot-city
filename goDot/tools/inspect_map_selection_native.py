"""Retain APK-verified static map selection and horizontal positioning evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import inspect_new_camp_native as native_audit


APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
SELECTION = {
    "ATPanel_RoadMapSelect": [
        "InitSelf()", "ScrollToTargetPosition()", "CreateARoadMapNode(",
        "<CreateARoadMapNode>b__0()", "SelectMapRoad()", "SelectMapNode(",
        "MoveNext()", "<InitAllRoadMapNode>b__40_",
    ],
    "ATPanel_RegionMapSelect": [
        "InitSelf()", "ScrollToCurrentModule()", "OnSlotClick(",
        "OnConfirm()", "CaculateSlotState(",
    ],
    "RegionSlotData": ["get_IsDataReady()"],
    "RogueRunManager": ["StartRegionRouteRun("],
    "RogueRoomManager": ["AdvanceRegionRoute("],
    "RoadMapData": ["GetActivatingNode()", "<GetActivatingNode>b__0("],
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inspect(apk, native_path, stubs, rea_evidence):
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != APK_SHA:
        raise ValueError("Expected the user-supplied APK identity")
    native = native_path.read_bytes()
    with zipfile.ZipFile(apk) as archive:
        if digest(native) != NATIVE_SHA or archive.read("lib/arm64-v8a/libil2cpp.so") != native:
            raise ValueError("Native image differs from the selected APK")
        metadata_sha = digest(archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat"))
    native_audit.SELECTION = SELECTION
    native_audit.SELECTED_OFFSETS = set()
    evidence = native_audit.inspect(native_path, stubs)
    for method in evidence["methods"]:
        offset = int(method["file_offset"], 16)
        method["bytes"] = native[offset:offset + method["length"]].hex()
        method["stub_sha256"] = digest(Path(method["stub"]).read_bytes())
    evidence.update({
        "apk": str(apk), "apk_sha256": apk_sha,
        "metadata_sha256": metadata_sha,
        "rea_inventory_evidence": rea_evidence,
        "limitations": [
            "Static ARM64 observations only; the APK was not executed.",
            "Recovered Cpp2IL declarations supply identities and file offsets, not original method bodies.",
            "REA supplies archive identity and inventory; instruction decoding is a separate local Capstone analysis.",
            "Godot resize preservation is a port design choice, not observed Unity runtime behavior.",
        ],
    })
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--rea-evidence", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk, args.native, args.stubs, args.rea_evidence)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(result["methods"]), "apk_sha256": result["apk_sha256"]}))
