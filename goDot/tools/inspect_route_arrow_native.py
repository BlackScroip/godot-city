"""Verify the selected APK's arrow generation and presentation instructions."""

import argparse
import json
from pathlib import Path
import struct

import inspect_map_selection_native as native


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    native.SELECTION = {
        "RogueRunManager": ["GenerateNodeConnections(", "GenerateRoadMap("],
        "RoadMapNodeData": ["get_IsReachable_"],
        "RoadMapData": ["CheckDirection("],
        "ATPanel_RoadMapSelect": ["CreateARoadMapNode("],
        "Slot_RoadMapNode": ["SwitchLineDisplay()", "UpdateUIInfo()"],
        "ATPanel_RegionMapSelect": ["UpdateSlotLines()"],
        "Slot_RegionNode": ["SetLineDisplay("],
    }
    result = native.inspect(args.apk, args.native, args.stubs,
                            "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323")
    table = args.native.read_bytes()[0x12F2038:0x12F2042]
    result["slot_state_dispatch"] = {
        "file_offset": "0x12f2038", "bytes": table.hex(), "branch_base_va": "0x2fb97e4",
        "targets": {name: hex(0x2FB97E4 + offset * 4) for name, offset in zip(
            ("NoReachable", "Passed", "Cur", "NextReachable", "AfterReachable"),
            struct.unpack("<5H", table))},
    }
    result["limitations"][-1] = "Responsive Godot geometry is a port adaptation, not observed Android runtime behavior."
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(result["methods"]),
                      "apk_sha256": result["apk_sha256"]}))
