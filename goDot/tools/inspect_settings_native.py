"""Retain bounded settings ARM64 disassembly from the selected APK version."""

import argparse
import json
from pathlib import Path

import inspect_new_camp_native as native


native.SELECTION = {
    "ATPanel_Option": ["RegisterItem", "InitSelf", "ApplyGlobalBrightness", "SetAutoPickupBit"],
    "PlayerPrefsConfig_AT": ["PlayerPrefsConfig_AT()", "LoadGameOption", "ResetCustomAttackArea"],
    "ATPanel_Guide": ["RegisterItem", "InitSelf", "SetOption"],
    "ATPanel_GuideSub": ["InitSelf", "ChangePage", "RegisterItem"],
    "GuideData": ["get_HeadTexts", "get_TailTexts", "get_Pages", "get_MiddleImages"],
    "UrlHelper": ["UrlHelper()"],
    "ATGameManager": ["ApplyDodgeAttackBuff", "IsDodgeAttackDisabled", "RefreshDodgeAutoChainBuffByTarget", "ApplyBloom", "ApplyDepthOfField", "ATGameManager()", "QualityRenderScaleOf"],
    "Panel_PlayerBattleCtrl": ["UpdateAutoAttack", "AutoPick", "AutoPickup"],
    "EventCameraFade": ["DoCameraFade"],
    "BattleCameraMgr": ["SetCameraFadeOffset"],
    "CameraFlashLight": ["EnableEffect", "ResolveFlashLightColor"],
}
native.SELECTED_OFFSETS = set()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = native.inspect(args.native, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": result["native_sha256"], "methods": len(result["methods"])}))
