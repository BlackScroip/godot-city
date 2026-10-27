"""Bounded static adventure event audit of the supplied APK's ARM64 library."""

import argparse
import json
from pathlib import Path

import inspect_new_camp_native as native


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    native.SELECTION = {
        "RogueRoomManager": ["AdventureEvent", "OldDay"],
        "RogueRunManager": ["CheckSelectCharaTalentAndLoot", "SelectLootByRandom"],
        "ATGameManager": ["bool Check(UnlockData", "bool Check(EUnlockConditionType"],
        "ATPanel_AdventureEvent": [""],
        "RogueAdvantureEventProperty_Gamble": ["bool Check()"],
        "RogueAdvantureEventProperty_Select": ["bool CheckSuccess()"],
        "RogueAdvantureEventData": ["GetAddAppearChanceDic"],
        "NodeData": ["get_NodeLevel()"],
        "RoadMapData": ["GetMapId()"],
        "UnlockData": ["Check", "9101", "9102"],
    }
    native.SELECTED_OFFSETS = set()
    result = native.inspect(args.native, args.stubs)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": result["native_sha256"], "methods": len(result["methods"])}))
