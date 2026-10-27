"""Retain static character detail methods and resolve metadata string pointers."""
import json
from pathlib import Path
import re
import struct
import zipfile
import inspect_new_camp_native as audit

audit.SELECTION = {
    "ATGameManager": ["GetCharaStatusLevelModify", "CharaToNextLevelNeed", "ExcuteCharaUpgradeAndBreakUp"],
    "ATPanel_CharaLevelUp": ["InitStateValue", "InitSlot"],
    "ATPanel_AttributeDetail": ["ApplyDefaultIcons", "BuildDefaultConfig", "FormatValue", "GetRowValue", "FormatRate", "FormatPercent", "BuildValueWithDetail", "CalcLowLootFinalChance"],
    "GameDataFormula": ["ConvertPriceDiscountRate"],
}
audit.SELECTED_OFFSETS = set()
root = Path(__file__).resolve().parents[2]
native = Path("/private/tmp/city-new-map-native/libil2cpp.so")
data = native.read_bytes()
with zipfile.ZipFile(root / "1061664.apk") as archive:
    assert archive.read("lib/arm64-v8a/libil2cpp.so") == data
    metadata = archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat")
phoff = struct.unpack_from("<Q", data, 32)[0]
entsize, count = struct.unpack_from("<HH", data, 54)
segments = [struct.unpack_from("<IIQQQQQQ", data, phoff + i * entsize) for i in range(count)]
def offset(va):
    return next(o + va - v for kind, flags, o, v, p, size, mem, align in segments if kind == 1 and v <= va < v + size)
shoff = struct.unpack_from("<Q", data, 40)[0]
entsize, count = struct.unpack_from("<HH", data, 58)
relocs = {}
for i in range(count):
    section = struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * entsize)
    if section[1] == 4:
        for j in range(section[4], section[4] + section[5], section[9] or 24):
            target, info, addend = struct.unpack_from("<QQq", data, j)
            relocs[target] = addend
entries, entries_size, strings, strings_size = struct.unpack_from("<4I", metadata, 8)
result = audit.inspect(native, Path("/private/tmp/city-new-map-addresses/DiffableCs"))
for method in result["methods"]:
    registers = {}
    for ins in method["instructions"]:
        args = ins["args"]
        if ins["op"] == "adrp":
            reg, value = args.split(", #")
            registers[reg] = int(value, 0)
        match = re.fullmatch(r"(x\d+), \[(x\d+), #(0x[0-9a-f]+)\]", args)
        if ins["op"] == "ldr" and match and match[2] in registers:
            address = registers[match[2]] + int(match[3], 0)
            try:
                encoded = struct.unpack_from("<Q", data, offset(relocs[address]))[0]
                if encoded >> 29 == 5:
                    index = (encoded & 0x1fffffff) >> 1
                    length, location = struct.unpack_from("<II", metadata, entries + 8 * index)
                    ins["string"] = metadata[strings + location:strings + location + length].decode()
            except (KeyError, StopIteration):
                pass
out = root / "goDot/reports/character-detail-native-20261027.json"
out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"output": str(out), "methods": len(result["methods"])}))
