"""Retain bounded hit-counter instructions from the supplied APK's ARM64 image."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import inspect_new_camp_native as native


native.SELECTION = {
    "Box_HitCount": ["Awake", "HideBox", "ShowBox", "SetHitCount", "SetHitLevel", "UpdateHitCountInfoBox", "FixedUpdate", "AddBattleTime", "SetTotalDamage", "FormatShortDamage"],
    "Panel_PlayerBattleCtrl": ["ReceiveHitCountUpdate", "UpdateHitCountInfoBox"],
    "BattleManager": ["ChangeHitCount", "UpdateHitCount", "ClearHitCount"],
    "BattleGlobalSysAtrribute_Common": ["Reset", "BattleGlobalSysAtrribute_Common"],
}
native.SELECTED_OFFSETS = set()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rea-inventory-evidence", required=True)
    args = parser.parse_args()
    with zipfile.ZipFile(args.apk) as archive:
        if archive.read("lib/arm64-v8a/libil2cpp.so") != args.native.read_bytes():
            raise ValueError("The supplied native image does not match the APK")
        metadata_sha256 = hashlib.sha256(archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat")).hexdigest()
    result = native.inspect(args.native, args.stubs)
    result["apk_sha256"] = hashlib.file_digest(args.apk.open("rb"), "sha256").hexdigest()
    result["rea_inventory_evidence"] = args.rea_inventory_evidence
    result["global_metadata_sha256"] = metadata_sha256
    result["metadata_source_sha256"] = {
        str(path.relative_to(args.stubs)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted({Path(method["stub"]) for method in result["methods"]})
    }
    result["limits"] = ["Ordinary-shell static disassembly, not REA native Evidence or runtime observation.",
                        "Address stubs supply method and field names; conclusions require native instructions."]
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(result["methods"])}))
