"""Bounded ARM64 camp audit using address stubs matching the supplied ELF."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM


SELECTION = {
    "ATGameManager": ["MonsterWork_", "AddMonsterWorkProgress", "RefreshMonsterWorkProgress", "CalcMonsterWorkOfflineProgress", "CheckEnterNewDay", "ForceRefreshAllDailyData", "GetCurrentTime_Sec_Internet"],
    "TimerManager": ["CheckIsNewDay", "GetCurrentTime_Sec", "CheckTargetDateTimeIsNextDayFromNowDateTime", "GetNextDayRefreshData_DateTime"],
    "TimeSwitch": ["SecondSwitchToFirstDateTime"],
    "GameDataModel_AT": ["bool Research(int id)", "bool BuyMeal()", "get_OrderLimitCount", "get_CatMealLevel", "CheckSelectedNeedMaterialsAndGold", "CompletePurchased", "ClearInvalidMeal"],
    "CatMealData": ["GetGold", "GetNextLevelGold", "GetNeedMaterials", "GetNextLevelNeedMaterials", "get_CheckUnlock"],
    "MonsterWorkData": ["GetCostTiem", "GetQueueMaxCount", "GetCompletedQueueCount", "GetDailyClaimLimit", "CalcClaimPlan", "GetCostMaterials", "GetCostMaterialData"],
    "ATPanel_MonsterWork": ["GetList", "RegisterItem", "OpenPopLevelUpPanel", "UpdateUIInfo", "SelectSlot"],
    "EnvUnit_Special_MonsterWork": ["RegisterItem"],
    "RogueMainCityManager": ["SetSpecialEnvUnitUnlockState", "UpgradeMainCityLevel", "TryUnlockMainCityDecoration", "IsMainCityDecorationUnlocked", "IsMainCityDecorationOptionUnlocked", "GetMainCityDecorationUnlockData", "TryChangeMainCityDecoration", "GetMaxMainCityLevel", "GetCurrentDecorationId", "EnsureMainCityDecorationData"],
    "MainCityDecorateSystem": ["GetTargetDecorationId", "LoadDecoration", "Refresh(EMainCityDecorateType"],
    "RogueStableData": ["get_CurMainCityLevel"],
    "ATPanel_CatMealMenu": ["EatMeal", "Research", "LevelUp", "Select", "UpdateUIInfo"],
}
SELECTED_OFFSETS = {0x2D8F298, 0x2D8F37C, 0x2D01E2C, 0x2D0376C, 0x2D04954, 0x2D04F2C, 0x2D053E8, 0x2D05674, 0x2D06344}


def inspect(native_path, stubs):
    data = native_path.read_bytes()
    phoff = struct.unpack_from("<Q", data, 32)[0]
    entsize, count = struct.unpack_from("<HH", data, 54)
    segments = []
    for i in range(count):
        typ, flags, off, va, pa, filesz, memsz, align = struct.unpack_from("<IIQQQQQQ", data, phoff + i * entsize)
        if typ == 1:
            segments.append((off, off + filesz, va))

    def virtual(offset):
        return next(va + offset - lo for lo, hi, va in segments if lo <= offset < hi)

    pattern = re.compile(r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]\s*(?:\[[^\n]+\]\s*)+([^\n]+)')
    symbols, selected = {}, []
    for file in sorted(stubs.rglob("*.cs")):
        for off, length, declaration in pattern.findall(file.read_text()):
            offset, length = int(off, 16), int(length, 16)
            try:
                address = virtual(offset)
            except StopIteration:
                continue
            symbols[address] = file.stem + "." + declaration.strip()
            if offset in SELECTED_OFFSETS or any(term in declaration for term in SELECTION.get(file.stem, [])):
                selected.append((file, offset, length, declaration.strip(), address))
    decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    methods, seen = [], set()
    for file, offset, length, declaration, address in selected:
        if offset in seen:
            continue
        seen.add(offset)
        instructions = []
        for ins in decoder.disasm(data[offset:offset + length], address):
            row = {"offset": hex(offset + ins.address - address), "va": hex(ins.address), "op": ins.mnemonic, "args": ins.op_str}
            if ins.mnemonic in ("b", "bl") and ins.op_str.startswith("#"):
                row["callee"] = symbols.get(int(ins.op_str[1:], 16), "")
            instructions.append(row)
        methods.append({"class": file.stem, "declaration": declaration, "stub": str(file), "file_offset": hex(offset), "va": hex(address), "length": length, "instructions": instructions})
    return {"native_sha256": hashlib.sha256(data).hexdigest(), "source": str(native_path), "stubs": str(stubs), "evidence_type": "static ARM64 disassembly; no original runtime executed", "methods": methods}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.native, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": result["native_sha256"], "methods": len(result["methods"])}))
