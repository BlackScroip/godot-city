"""Recover the supplied APK's bounded gem merchant transaction rules."""

import argparse
import json
from pathlib import Path
import re
import struct

import inspect_new_camp_native as native


native.SELECTION = {
    "EnvUnit_Special_GemShopMan": [""],
    "RogueRoomManager": ["GetTradeWithGemShopManNeedMagicPoint", "TradeWithGemShopMan", "BuildGemWithColorMultiplier"],
}
native.SELECTED_OFFSETS = set()


def reset_callers(native_path, stubs):
    data = native_path.read_bytes()
    phoff = struct.unpack_from("<Q", data, 32)[0]
    entsize, count = struct.unpack_from("<HH", data, 54)
    calls = []
    for i in range(count):
        typ, flags, off, va, _, length, _, _ = struct.unpack_from("<IIQQQQQQ", data, phoff + i * entsize)
        if typ != 1 or not flags & 1:
            continue
        for index, (instruction,) in enumerate(struct.iter_unpack("<I", data[off:off + length - length % 4])):
            if instruction & 0xfc000000 != 0x94000000:
                continue
            displacement = instruction & 0x03ffffff
            if displacement & 0x02000000:
                displacement -= 0x04000000
            if va + index * 4 + displacement * 4 == 0x3150c40:
                calls.append({"file_offset": off + index * 4, "va": hex(va + index * 4)})
    pattern = re.compile(r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]\s*(?:\[[^\n]+\]\s*)+([^\n]+)')
    for stub in stubs.rglob("*.cs"):
        for off, length, declaration in pattern.findall(stub.read_text()):
            start, length = int(off, 16), int(length, 16)
            for call in calls:
                if start <= call["file_offset"] < start + length:
                    call.update({"class": stub.stem, "declaration": declaration.strip(), "method_offset": hex(start)})
                    native.SELECTED_OFFSETS.add(start)
    for call in calls:
        call["file_offset"] = hex(call["file_offset"])
    return calls


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    callers = reset_callers(args.native, args.stubs)
    result = native.inspect(args.native, args.stubs)
    result["reset_callers"] = callers
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": result["native_sha256"], "methods": len(result["methods"])}))
