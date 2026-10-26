"""Retain the bounded native skill-slot evidence needed by the new actor."""

import json
from pathlib import Path
import struct

import inspect_new_camp_native as native


if __name__ == "__main__":
    native.SELECTION = {
        "Player": ["GetAttribute_Self", "InitRuntimeAttributes", "InitProperty"],
        "PlayerRuntimeStatus": ["SetByStaticStatus"],
        "AttackBattleData": ["AttackBattleData(", "GetMax", "GetCost", "GetCurCanUseCount", "GetCurRealCanUseCount", "void Update(float", "bool Use()", "bool CheckCurCd()", "bool CheckCurrentIsCanUse()"],
        "EvtCond_CheckBuffExist": ["bool Check(RoleUnit"],
        "CheckBuffExist": ["bool CheckBuff(RoleUnit"],
        "SBuffAddByOwnerBuffLayer": ["EvaluateAndAdd", "EvaluateGroup", "bool Init("],
    }
    native.SELECTED_OFFSETS = set()
    evidence = native.inspect(Path("/private/tmp/city-new-map-native/libil2cpp.so"),
                              Path("/private/tmp/city-new-map-addresses/DiffableCs/Assembly-CSharp"))
    data = Path(evidence["source"]).read_bytes()
    header = struct.unpack_from("<Q", data, 32)[0]
    stride, count = struct.unpack_from("<HH", data, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", data, header + index * stride) for index in range(count)]

    def file_offset(address):
        return next(row[2] + address - row[3] for row in segments if row[0] == 1 and row[3] <= address < row[3] + row[5])

    table_address, branch_base = 0x12F24A4, 0x315FFC8
    names = ["CurChargeValue", "CostSp", "CostSpAddRate", "ChargeSpeed", "MaxSp", "MaxSpAddRate", "ExtraUseCount"]
    evidence["skill_attribute_switch"] = [
        {"attribute": ident, "name": "SkillActive" + str(1 + (ident - 103) // 7) + names[(ident - 103) % 7],
         "table_file_offset": hex(file_offset(table_address) + (ident - 1) * 2),
         "target_file_offset": hex(file_offset(branch_base + 4 * struct.unpack_from("<H", data, file_offset(table_address) + (ident - 1) * 2)[0]))}
        for ident in range(103, 117)]
    evidence["skill_attribute_switch"] += [
        {"attribute": ident, "name": name,
         "table_file_offset": hex(file_offset(table_address) + (ident - 1) * 2),
         "target_file_offset": hex(file_offset(branch_base + 4 * struct.unpack_from("<H", data, file_offset(table_address) + (ident - 1) * 2)[0]))}
        for ident, name in [(153, "SkillDodgeCurCanUseTimes"),
                            (154, "SkillActive1CurCanUseTimes"),
                            (155, "SkillActive2CurCanUseTimes")]]
    evidence["skill_count_epsilon"] = {
        "va": "0x1287c1c", "file_offset": hex(file_offset(0x1287C1C)),
        "float32": struct.unpack_from("<f", data, file_offset(0x1287C1C))[0]}
    target = Path(__file__).resolve().parents[1] / "reports/new-apk-character8-native-evidence.json"
    target.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"path": str(target), "methods": len(evidence["methods"])}))
