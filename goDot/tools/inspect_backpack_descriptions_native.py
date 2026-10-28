"""Retain bounded APK-native evidence for ability description runtime values."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

import inspect_new_camp_native as native


def inspect(binary, stubs, apk):
    with zipfile.ZipFile(apk) as archive:
        member = archive.read("lib/arm64-v8a/libil2cpp.so")
        metadata = archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat")
    if hashlib.sha256(member).hexdigest() != hashlib.sha256(binary.read_bytes()).hexdigest():
        raise ValueError("Native input does not match the supplied APK")
    native.SELECTION.clear()
    native.SELECTED_OFFSETS.clear()
    native.SELECTION.update({
        "AbilityItem_RogueNormal": ["CaculateEffectFactor", "ModifyAddBuffToPlayer"],
        "AbilityItem_RogueCombine": ["CaculateEffectFactor"],
        "AbilityItemLootData": ["GetDisplayEffectLayer", "GetDisplayBuffId", "GetBuffLayer", "get_IsCostAfterGet", "get_StarNum"],
        "AbilityItemRecordProgressData": ["get_CurLayer"],
        "ATGameManager": ["ReplaceBuffStr"],
        "RogueInGameInventory": ["GetLootCount", "GetAllLootDataList"],
        "BattleGlobalSysAttribute_Rogue": ["GetAttribute(ERogueAttributeType", "<GetAttribute>b__13_"],
    })
    native.SELECTED_OFFSETS.update({0x2FC8F5C, 0x2FC12CC, 0x2FC4988, 0x2FC4D30, 0x2FC56EC, 0x2FC583C, 0x2FC6310, 0x2FC63F0})
    result = native.inspect(binary, stubs)
    _resolve_strings(result, member, metadata)
    result["apk_sha256"] = hashlib.sha256(apk.read_bytes()).hexdigest()
    result["native_member"] = "lib/arm64-v8a/libil2cpp.so"
    return result


def _resolve_strings(result, data, metadata):
    program_offset = struct.unpack_from("<Q", data, 32)[0]
    program_size, program_count = struct.unpack_from("<HH", data, 54)
    programs = [struct.unpack_from("<IIQQQQQQ", data, program_offset + index * program_size) for index in range(program_count)]

    def offset(address):
        return next(start + address - virtual for kind, flags, start, virtual, physical, size, memory, align in programs if kind == 1 and virtual <= address < virtual + size)

    section_offset = struct.unpack_from("<Q", data, 40)[0]
    section_size, section_count = struct.unpack_from("<HH", data, 58)
    relocations = {}
    for index in range(section_count):
        section = struct.unpack_from("<IIQQQQIIQQ", data, section_offset + index * section_size)
        if section[1] != 4:
            continue
        for cursor in range(section[4], section[4] + section[5], section[9] or 24):
            target, info, addend = struct.unpack_from("<QQq", data, cursor)
            relocations[target] = addend
    entries, entries_size, strings, strings_size = struct.unpack_from("<4I", metadata, 8)
    decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    decoder.detail = True
    for method in result["methods"]:
        registers = {}
        start = int(method["file_offset"], 16)
        decoded = decoder.disasm(data[start:start + method["length"]], int(method["va"], 16))
        for instruction, decoded_instruction in zip(method["instructions"], decoded):
            arguments = instruction["args"]
            match = re.fullmatch(r"(x\d+), \[(x\d+), #(0x[0-9a-f]+)\]", arguments)
            if instruction["op"] == "ldr" and match and match[2] in registers:
                try:
                    address = registers[match[2]] + int(match[3], 0)
                    encoded = struct.unpack_from("<Q", data, offset(relocations[address]))[0]
                    if encoded >> 29 == 5:
                        index = (encoded & 0x1FFFFFFF) >> 1
                        length, location = struct.unpack_from("<II", metadata, entries + 8 * index)
                        instruction["string"] = metadata[strings + location:strings + location + length].decode()
                except (KeyError, StopIteration):
                    pass
            for register in decoded_instruction.regs_access()[1]:
                registers.pop(decoded_instruction.reg_name(register).replace("w", "x"), None)
            if instruction["op"] == "adrp":
                register, value = arguments.split(", #")
                registers[register] = int(value, 0)
            elif instruction["op"] in ("bl", "blr"):
                for index in range(19):
                    registers.pop(f"x{index}", None)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    report = inspect(arguments.native, arguments.stubs, arguments.apk)
    arguments.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(arguments.output), "methods": len(report["methods"]), "native_sha256": report["native_sha256"]}))
