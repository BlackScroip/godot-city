"""Recover bounded ARM64 evidence for battle guidance, JP, and ultimate SP."""

import argparse
import hashlib
import json
from pathlib import Path
import struct

import inspect_new_camp_native as native


native.SELECTION = {
    "AttackBattleData": ["AttackBattleData(", "AddSp(", "AddCD(", "CheckCurrentIsCanUse", "GetCostSpFillAmout", "GetMaxSPFillAmout", "GetCurCanUseCount", "GetCurRealCanUseCount", "GetMaxCanUseCount", "Update(", "Use("],
    "AttackHit": ["ProcessHitUnit"],
    "Box_BattleCharaInspector": ["UpdateSkill1State", "UpdateSkill2State"],
    "GameDataFormula": ["CalcChargeSpeedBonus"],
    "Panel_PlayerBattleCtrl": ["RegisterActSkillUIUpdate", "ExcuteSkillSlotUpdateData", "UpdateCharaInspector", "UpdateGizmoTips_EnterDoor", "UpdateGizmoTips_Monster", "UpdateGizmoTipsArea"],
    "Panel_PlayerBattleCtrl_BattleSysWnd": ["UpdateCustomStateBarDisplay"],
    "Player": ["ChangeSkillSp", "UpdateSkillData"],
    "SBuffChargeSkillSp": ["Charge(", "Init("],
    "SBuffChargeSkillSpSettingsData": ["get_ChargeCount", "get_ChargePercent", "get_ReduceCooldown", "get_ReduceCooldownPercent"],
    "SpecialStateBar_Buff": ["UpdateDisplay", "SetSingleSlotDisplay"],
}
native.SELECTED_OFFSETS = set()


def inspect(native_path, stubs):
    result = native.inspect(native_path, stubs)
    data = native_path.read_bytes()
    result["constants"] = []
    for offset, code, description in (
        (0x128809C, "f", "Charge-speed formula denominator constant"),
        (0x1288234, "f", "Per-thousand conversion multiplier"),
        (0x1287C14, "f", "Exit target squared-distance zero threshold"),
        (0x12893D8, "d", "Exit viewport inner minimum"),
        (0x1288460, "d", "Exit viewport inner maximum"),
        (0x1287E70, "f", "Exit radius multiplier before multiplying 0.5"),
        (0x12882B4, "f", "Exit guide fade-in seconds"),
    ):
        raw = data[offset:offset + struct.calcsize(code)]
        result["constants"].append({"file_offset": hex(offset), "bytes": raw.hex(), "type": "float32" if code == "f" else "float64", "value": struct.unpack("<" + code, raw)[0], "description": description})
    table_offset, base_address = 0x12F242F, 0x30EA8A0
    raw = data[table_offset:table_offset + 9]
    result["sp_color_switch"] = {
        "method": "Panel_PlayerBattleCtrl.RegisterActSkillUIUpdate",
        "source_field": "AttackData.ElementType at +0x24",
        "table_file_offset": hex(table_offset),
        "bytes": raw.hex(),
        "base_va": hex(base_address),
        "entries": [{"element_type": index + 1, "target_va": hex(base_address + value * 4)} for index, value in enumerate(raw)],
        "interpretation": "Fire/Water/Wind/Thunder/Light/Dark/Ice use color indexes 0/1/2/3/4/5/6; other types use white. CharData.ActiveSkill2MaxSpFx can override this default.",
    }
    names = {"AttackData", "AttackBattleData", "AttackDefProperty", "AttackHit", "AttackType", "CharActiveSkill2MaxSpFx", "CombatResultData", "EDamageType", "Panel_PlayerBattleCtrl", "PlayerControll_SkillActSlotBase", "SBuffChargeSkillSpSettingsData", "SpecialStateBar_Buff"}
    result["declaration_sources"] = []
    for path in sorted(stubs.rglob("*.cs")):
        if path.stem in names:
            payload = path.read_bytes()
            result["declaration_sources"].append({"source": str(path), "sha256": hashlib.sha256(payload).hexdigest(), "contents": payload.decode("utf-8")})
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    evidence = inspect(args.native, args.stubs)
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": evidence["native_sha256"], "method_count": len(evidence["methods"])}))
