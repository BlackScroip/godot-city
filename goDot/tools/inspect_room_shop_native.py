"""Recover bounded shop state transitions from the supplied Android build."""

import argparse
import json
from pathlib import Path

import inspect_new_camp_native as native


native.SELECTION = {
    "ATGameManager": ["GetShopSaveRes", "SaveResToShopByCostRemainTime"],
    "ATPanel_Shop": ["CalculateSealMagicPoint", "ExecuteSeal", "IsSealableLootType", "RefreshSealRelics", "RegisterItem>b__72_7", "UpdateUIInfo"],
    "RogueInGameInventory": ["SealLoot", "GetSealed", "IsSealed"],
    "RogueRoomManager": ["GenerateDefaultTradeDataList", "RefreshShopByCostRefreshTime", "ApplyShopOfferPriceChange", "RefreshShopTradeList", "ShopOffer", "ShopBuy", "OpenShop"],
    "RogueInGameShopTradeData": ["GetOriginalPrice", "GetBuyMarkupPercent", "get_PriceChangePercent", "GetPriceAddRate", "GetStaticBasePriceAddRate", "GetStaticPlayerPriceAddRate", "ConsumeSlotOffer", "PayBuy", "FreeBuy"],
}
native.SELECTED_OFFSETS = {0x2FC4D30, 0x2FC583C, 0x2FCC2E8}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = native.inspect(args.native, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": result["native_sha256"], "methods": len(result["methods"])}))
