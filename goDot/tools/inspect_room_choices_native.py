"""Bounded original ARM64 evidence for room altars and partner support skills."""

import argparse
import json
from pathlib import Path

import inspect_new_camp_native as native


def inspect(binary, stubs):
    native.SELECTION.clear()
    native.SELECTED_OFFSETS.clear()
    native.SELECTION.update({
        "MonsterPartnerSkillBattleData": ["public "],
        "Box_MonsterSupportSkill": ["RegisterBattleBtnDel", "b__12_"],
        "Player": ["GetAttribute_Self", "public override float GetAttribute(", "UpdateSkillData", "ChangeSkillSp", "UpdataMonsterPartnerSkill"],
        "LocalPlayer": ["OnMessagePlayerController", "CheckMonsterPartnerUse"],
        "RogueRunData": ["set_MonsterPartnerSp", "PlayerMaxHpDownModifyValue"],
        "BattleGlobalSysAttribute_Rogue": ["ApplyPlayerAttributeModify", "AddAttributeInternal", "GetAttribute("],
        "RogueInGameInventory": ["GenerateMonsterPartnerSelectOptionList", "ExcuteGetNewMosterPartnerSkill", "ExcuteGetCommonItem", "UpgradeMonsterPartnerSkill"],
        "RogueRoomManager": ["Msg_SacrificialAltar", "OnSelectRewardAbilityItemLoot", "Msg_MonsterPartnerSkillSelector", "OnSelectMonsterPartnerSkillSelector", "BattleLogicUpdate", "<BattleLogicUpdate>b__7_0"],
        "ATPanel_SelectCollection": ["InitAllSlot", "<RegisterItem>b__25_0", "<RegisterItem>b__25_4"],
        "RogueRunManager": ["IsFreeRefreshInFirstRoom", "CheckSelectCharaTalentAndLoot"],
        "GameDataFormula": ["CalcChargeSpeedBonus"],
        "SBuffChargeSkillSp": ["Charge(Player"],
        "AttackData": ["GetCurLevelDescript"],
        "RoadMapNodeData": ["get_IsFirstNode"],
        "SummonUnit_MonsterPartner": ["public override void Init(", "public override bool Update("],
    })
    native.SELECTED_OFFSETS.update({0x2D90F04, 0x30239DC, 0x2D35CC8})
    return native.inspect(binary, stubs)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.native, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": result["native_sha256"], "methods": len(result["methods"])}))
