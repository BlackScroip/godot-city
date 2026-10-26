"""Retain selected sprites from recover_camp_developer_ui.py's mall export."""

import argparse
import json
from pathlib import Path
import shutil


NAMES = [
    "16", "30", "ATPanel_Mall_Luna", "Icon_BlessingMode",
    "Icon_BlessingModePlus", "Icon_BlessingModeBreak", "免广告", "商城", "客服",
    "商店按钮_底", "暗色按钮", "购买按钮", "特权", "白星标", "背景装饰环",
    "迷宫特权标题cn", "祝福模式标题cn", "祝福模式Pluscn", "祝福模式Breakcn",
    "退出按钮", "货币_底", "金宝箱", "木宝箱", "铁宝箱", "提示点", "须知",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    source = json.loads((args.source / "prefab-layout.json").read_text())
    args.destination.mkdir(parents=True, exist_ok=True)
    mapping, sprites = {}, []
    for sprite in source["sprites"]:
        if sprite["name"] not in NAMES:
            continue
        filename = Path(sprite["path"]).name
        shutil.copyfile(args.source / filename, args.destination / filename)
        record = dict(sprite)
        record["path"] = "res://assets/ui/mall/" + filename
        sprites.append(record)
        mapping[sprite["name"]] = record["path"]
    assert len(mapping) == len(NAMES)
    (args.destination / "resource_map.json").write_text(
        json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
    vip_texts = [t for t in source["texts"] if "/Model_VIP/" in t["path"]]
    provenance = {
        "apk_sha256": source["apk_sha256"], "prefab": source["prefab"],
        "source": source["source"], "sprites": sprites, "vip_initial_texts": vip_texts,
        "limit": source["limit"],
        "display_precedence": "Actual MallTradeData quote and RogueConfigData override prefab initial text.",
    }
    (args.destination / "provenance.json").write_text(
        json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"sprites": len(sprites), "output": str(args.destination)}))


if __name__ == "__main__":
    main()
