#!/usr/bin/env python3
"""Apply reviewed English repairs before translating the other offline catalogs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

import complete_localization as catalog
from localization_static import expand_static
from translate_localization_offline import normalize_notation, replacement_characters, values_match


REVIEWED = {
    "分割线四": "Divider IV",
    "%.1f万": "%.1f ten thousand",
    "当前无法交互": "Cannot interact right now",
    "未支持的净化条件": "Unsupported purification condition",
    "关卡内无法更改。": "Cannot be changed during a stage.",
    "重铸三日月弓": "Reforge the Crescent Moon Bow",
    "三日月弓": "Crescent Moon Bow",
    "我觉得我们还需要一个优质宿舍，三十人一间怎么样？": "I think we still need a decent dormitory. How about thirty people per room?",
    "增加<color=#e99f0d>刷新奖励</color>的机会。": "Gain more chances to refresh rewards.",
    "【风行者】<br>每有1点<#specinfo=yidongsudu>的加成，+1%<#specinfo=gongjili>。": "Windrunner\nFor every 1 point of bonus Movement Speed, gain +1% Attack Power.",
    '提升少许获得高级<#LocalizationId="keyword_MonsterPartnerSkill">怪物支援技</LocalizationId>的概率。': "Slightly increases the chance of obtaining advanced Monster Support Skills.",
    '进一步提升少许获得高级<#LocalizationId="keyword_MonsterPartnerSkill">怪物支援技</LocalizationId>的概率。': "Further increases the chance of obtaining advanced Monster Support Skills slightly.",
    "无法看到节点类型。": "Node types are hidden.",
    "魔力归零": "Magic is depleted",
    "需要三个同类增幅及金币": "Requires three Amplifications of the same type and Gold",
    "持有魔物精华大于1万。": "Hold more than 1 ten thousand Monster Essences.",
    "概率随机时增加至两次判定机会。": "You get two chances when making random chance checks.",
    "虽然还有露娜她们，但现在各地迷宫四起，还不是休息的时候。": "Luna and the others are still here, but dungeons are appearing everywhere. This is no time to rest.",
    "但想要攻略迷宫，这样可是不行的，可要亲自来噢，顺便挑两件遗物走。": "That will not do if you want to explore the dungeon. Come in person, and pick out two Relics while you are here.",
    "释放时获得<#specinfo=jianyi>，使出如雷霆震怒般的三板斧。": "Gain Fortitude when casting, then unleash a thunderous triple axe strike.",
    "受到致命伤害时，将生命值锁定在20%，并在1秒内分四段恢复共40%最大生命值。": "Upon taking fatal damage, HP is locked at 20%, then a total of 40% Max HP is restored in four intervals over 1 second.",
    "被怪物普通攻击命中后，每秒损失1点生命值，持续约5秒。": "After being hit by a monster's Normal Attack, lose 1 HP per second for about 5 seconds.",
    "【勇者】<br>受伤后，<#specinfo=putonggongji>伤害+40%，持续5秒，最多可叠加4层。": "Hero\nAfter taking damage, Normal Attack damage +40% for 5 seconds, stacking up to 4 times.",
    "【勇者】<br>使用<#specinfo=zhanji>后，<#specinfo=putonggongji>提升100%伤害，持续5秒。": "Hero\nAfter using Skill, Normal Attack damage increases by 100% for 5 seconds.",
    "【勇者】<br>获得100%<#specinfo=fangyuli>加成，累计受到超过50点伤害后失效，<#specinfo=lengque>10秒。": "Hero\nGain 100% Defense. The bonus expires after taking over 50 total damage. Cooldown: 10 seconds.",
    "【勇者】<br><#specinfo=putonggongji>的<#specinfo=baojilv>+10%，<#specinfo=baojishanghai>+25%。": "Hero\nNormal Attack gains +10% Critical Chance and +25% Critical Damage.",
    "<#specinfo=shengmingzhi>大于30%且身边存在敌人时每秒对自身造成1点伤害。": "While HP is above 30% and enemies are nearby, deal 1 damage to yourself per second.",
    '击败1次<#LocalizationId="EnemyData_Name_33001">幻影鹿王·尤尼可</LocalizationId>。': "Defeat Unico, the Phantom Deer King, 1 time.",
    "<#specinfo=longhunshiqi>状态下每秒提升<#specinfo=gongjili>，退出<#specinfo=longhunshiqi>状态后每1秒降低1层效果。": "During Dragon Soul Pact, Attack Power increases every second. After leaving Dragon Soul Pact, lose 1 stack every 1 second.",
    "【进阶闪电之舞】<br>每隔2秒获得1层充能，当附近有敌人时消耗1层充能，引动<#specinfo=shandian>对附近3名敌人造成伤害，每道造成90%<#specinfo=gongjili>伤害，间隔1.5秒。": "Advanced Lightning Dance\nGain 1 charge every 2 seconds. When enemies are nearby, consume 1 charge to strike 3 nearby enemies with Lightning, each dealing 90% Attack Power damage. Interval: 1.5 seconds.",
    "迷宫出现了【星火之燧】强化遗物<br><#specinfo=putonggongji>命中时获得<color=#ffba42>【星火】</color>，每层+2%<#specinfo=gongjili>，最大叠加20层。": "The enhanced Relic [Spark Flint] appears in the dungeon.\nNormal Attack hits grant Spark, providing +2% Attack Power per stack, up to 20 stacks.",
    "【需要白银制裁】<br>攻击<#specinfo=pojia>状态下的敌人，有15%概率掉落<#specinfo=hujia>片，拾取后获得10点<#specinfo=hujia>，该效果有10秒<#specinfo=lengque>时间。": "Requires Silver Judgment\nAttacking enemies affected by Armor Break has a 15% chance to drop an Armor fragment. Picking it up grants 10 Armor. Cooldown: 10 seconds.",
    "拥有至少5层<#specinfo=jianxin>时，使用<#specinfo=baofaji>将消耗所有<#specinfo=jianxin>额外触发1次<color=#f28e00>【爆炎】</color>造成大量伤害。<br>每1层<#specinfo=jianxin>都会使<#specinfo=baofaji>伤害+10%。": "When you have at least 5 stacks of Sword Heart, using Burst Skill consumes all Sword Heart stacks to trigger 1 additional Blazing Explosion, dealing massive damage.\nEach 1 stack of Sword Heart grants +10% Burst Skill damage.",
    "累计20次<color=#e99f0d>暴击</color>后，在前方降下<color=#33a3dc>冰矛</color>攻击敌人，冷却5秒。<color=#33a3dc>冰矛</color>每段造成20%<#specinfo=gongjili>的伤害，对命中的<#specinfo=baojishanghai>增加30%，持续5秒。": "After 20 Critical Hits, drop an Ice Spear in front to attack enemies. Cooldown: 5 seconds. Each hit of Ice Spear deals 20% Attack Power damage. Critical Damage against enemies hit increases by 30% for 5 seconds.",
    "【需要雷霆之力】<br><#specinfo=shandian>造成伤害可以回复10点<#specinfo=baofajinengliang>，该效果有10秒<#specinfo=lengque>时间，<#specinfo=lengque>期间<#specinfo=shandian>造成伤害可以使该<#specinfo=lengque>时间-1秒。": "Requires Thunder Power\nLightning damage restores 10 Burst Skill Energy. Cooldown: 10 seconds. During this Cooldown, dealing Lightning damage changes the remaining Cooldown by -1 second.",
    "<color=#fdb933>增益</color>层数高于20层时，使用<#specinfo=putonggongji>、<#specinfo=zhongji>、<#specinfo=shanbigongji>有5%概率在目标位置造成<color=#33a3dc>水爆炸</color>，造成500%<#specinfo=gongjili>的伤害，冷却5秒。": "When Buff stacks exceed 20, using Normal Attack, Heavy Attack, or Dodge Attack has a 5% chance to create a Water Explosion at the target location, dealing 500% Attack Power damage. Cooldown: 5 seconds.",
    "<color=#fdb933>增益</color>层数高于20层时，使用<#specinfo=putonggongji>、<#specinfo=zhongji>、<#specinfo=shanbigongji>有10%概率在目标位置造成<color=#33a3dc>水爆炸</color>，造成800%<#specinfo=gongjili>的伤害，冷却5秒。": "When Buff stacks exceed 20, using Normal Attack, Heavy Attack, or Dodge Attack has a 10% chance to create a Water Explosion at the target location, dealing 800% Attack Power damage. Cooldown: 5 seconds.",
    "【融合精灵】<br>每移动20米，在脚下生成一片<color=#c98a4b>【泥石流】</color>，持续6秒，每0.5秒造成20%<#specinfo=gongjili>伤害，并附加<#specinfo=chaoshi>；<#specinfo=shanbigongji>或<#specinfo=zhongji>命中<color=#c98a4b>【泥石流】</color>中的敌人时，附加3层<#specinfo=zhongshang>。": "Fusion Spirit\nEvery 20 meters moved creates a Mudslide beneath your feet for 6 seconds. It deals 20% Attack Power damage every 0.5 seconds and applies Wet. Hitting enemies in the Mudslide with Dodge Attack or Heavy Attack applies 3 stacks of Deep Wound.",
    '<color=#c60c0c>【诅咒】</color><br>无法看到节点类型。<br>进入下一个<#LocalizationId="Keyword_Region">区域</LocalizationId>后净化，获得更强的路线选择能力。<color=#fdd033>（当前进度：<#backpack_progress>）</color>': "[Curse]\nNode types are hidden.\nPurified upon entering the next Region, granting a stronger route selection ability. (Current progress: <#backpack_progress>)",
}

AMPLIFICATION_NAMES = {
    "体力": "Stamina", "元素": "Elemental", "光明": "Light", "全能": "Versatile",
    "冒险": "Adventure", "冰霜": "Frost", "商贾": "Merchant", "坚韧": "Fortitude",
    "复苏": "Revival", "大招": "Burst Skill", "天赋": "Talent", "奇遇": "Encounter",
    "守护": "Protection", "寻材": "Material Finding", "幸运": "Luck", "急速": "Haste",
    "怪物": "Monster", "战利": "Loot", "技能": "Skill", "抗性": "Resistance",
    "护盾": "Shield", "探索": "Exploration", "支援": "Support", "攻击": "Attack",
    "普攻": "Normal Attack", "暗影": "Shadow", "暴伤": "Critical Damage",
    "暴击": "Critical Chance", "治愈": "Healing", "洞见": "Insight", "火焰": "Fire",
    "灵巧": "Dexterity", "物攻": "Physical Attack", "狂战": "Berserker", "猎手": "Hunter",
    "猎王": "Hunt King", "生命": "HP", "疾风": "Gale", "矿工": "Miner",
    "破盾": "Shield Breaking", "移速": "Movement Speed", "精华": "Essence",
    "精炼": "Refinement", "蓄能": "Energy Storage", "遗物": "Relic", "采集": "Gathering",
    "重击": "Heavy Attack", "闪避": "Dodge", "防御": "Defense", "雷电": "Lightning",
    "韧性": "Tenacity", "风行": "Windrunner", "首领": "Boss", "魔力": "Magic",
}
EQUIPMENT_NAMES = {
    "以德服人": "Virtuous Persuasion", "侍从勋章": "Squire's Medal", "侍从战靴": "Squire's Boots",
    "侍从链锤": "Squire's Flail", "充盈魔法导石": "Charged Magic Stone", "冒险木盾": "Adventurer's Wooden Shield",
    "冰龙之爪": "Ice Dragon's Claw", "冰龙之牙": "Ice Dragon's Fang", "冰龙之骨": "Ice Dragon's Bone",
    "冰龙之鳞片": "Ice Dragon's Scale", "凶兽断角": "Broken Beast Horn", "勇者之剑": "Hero's Sword",
    "勇者之护符": "Hero's Amulet", "勇者之盔": "Hero's Helmet", "勇者之盾": "Hero's Shield",
    "卫士长手斧": "Guard Captain's Hand Axe", "吞噬者之徽": "Devourer's Emblem", "吟唱者之帽": "Chanter's Hat",
    "吟唱者之杖": "Chanter's Staff", "吟唱者之秘法书": "Chanter's Arcane Tome", "吟唱者之符纹": "Chanter's Rune",
    "商人信物": "Merchant's Token", "商人古董": "Merchant's Antique", "商人的神秘口袋": "Merchant's Mysterious Pouch",
    "商人账本": "Merchant's Ledger", "学徒笔记": "Apprentice's Notes", "学院作业": "Academy Assignment",
    "守护之徽": "Guardian's Emblem", "巨魔的棒槌": "Troll's Club", "巨魔的盾牌": "Troll's Shield",
    "巨魔的钢盔": "Troll's Steel Helmet", "巨魔的镣铐": "Troll's Shackles", "幽影之刃": "Shadow Blade",
    "幽影小刀": "Shadow Knife", "幽影斗篷": "Shadow Cloak", "幽影飞镖": "Shadow Dart",
    "恢复配方": "Recovery Formula", "恶魔镰刀": "Demon Scythe", "恶魔骑士枪": "Demon Knight's Lance",
    "战争护符": "War Amulet", "战场愤怒之戒": "Battlefield Fury Ring", "战场护卫巨剑": "Battlefield Guard's Greatsword",
    "战损民兵头盔": "Battered Militia Helmet", "战损皮甲": "Battered Leather Armor", "战狂能量剑": "Berserker's Energy Sword",
    "战甲护符": "Armor Amulet", "护卫头盔": "Guard Helmet", "教授法书": "Professor's Spellbook",
    "新生枝叶": "New Sprout", "枯竭魔法导石": "Depleted Magic Stone", "森之项链": "Forest Necklace",
    "森林之羽手杖": "Forest Feather Cane", "森林匕首": "Forest Dagger", "森林王战甲": "Forest King's Armor",
    "森林短弓": "Forest Shortbow", "森林荆棘盾": "Forest Thorn Shield", "森林长靴": "Forest Boots",
    "森林魔法戒": "Forest Magic Ring", "狂热之戒": "Fervor Ring", "生命之源": "Source of Life",
    "生命吞噬之戒": "Life Devouring Ring", "生命药泥": "Healing Poultice", "生锈骑士头盔": "Rusty Knight Helmet",
    "禁卫骑士头盔": "Royal Guard Knight Helmet", "符文躯壳": "Runic Shell", "米诺陶诺斯之心": "Minotaur's Heart",
    "米诺陶诺斯之手": "Minotaur's Hand", "米诺陶诺斯之斧": "Minotaur's Axe", "米诺陶诺斯之角": "Minotaur's Horn",
    "精英骑士头盔": "Elite Knight Helmet", "自制匕首": "Homemade Dagger", "药师柴刀": "Apothecary's Machete",
    "讲师课本": "Lecturer's Textbook", "诡异魔刀": "Eerie Magic Blade", "赤红长棍": "Crimson Staff",
    "迅捷之靴": "Boots of Swiftness", "近卫者之剑": "Guardsman's Sword", "近卫骑士之刃": "Guard Knight's Blade",
    "部落之盾": "Tribal Shield", "镶金大棍": "Gold Inlaid Club", "风岭部落弓": "Windridge Tribal Bow",
    "风灵双头刃": "Wind Spirit's Twin Blade", "风羽佩剑": "Windfeather Saber", "风羽侍从袍": "Windfeather Squire's Robe",
    "风羽骑士剑": "Windfeather Knight's Sword", "风行者之戒": "Windrunner's Ring", "风行者围巾": "Windrunner's Scarf",
    "风行者战盔": "Windrunner's Helmet", "风行者战靴": "Windrunner's Boots", "魔法长刀": "Magic Longblade",
    "魔王大剑": "Demon King's Greatsword", "黄金符文棍": "Golden Runic Staff",
}
PART_NAMES = {
    "修复泉水": "Repair Fountain", "冒险之旅": "Adventure Journey", "原型装备": "Prototype Equipment",
    "星光杂货铺": "Starlight General Store", "节点类型": "Node Types", "迷宫快递": "Dungeon Delivery",
    "钓鱼的史莱姆王": "The Fishing Slime King",
    "老主顾": "Regular Customer", "公会支援": "Guild Support", "森林素材收集": "Forest Material Collection",
    "沙漠素材收集": "Desert Material Collection", "矿洞素材收集": "Cavern Material Collection", "雪原素材收集": "Snowfield Material Collection",
}
ROMAN = dict(zip("一二三四五六七八九十", ("I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X")))
ROMAN.update(dict(zip("壹贰叁肆伍", ("I", "II", "III", "IV", "V"))))


def reviewed_translations(sources, additional=None):
    recorded = catalog.read_json(catalog.CATALOGS / "reviewed/en.json")
    recorded.update(additional or {})
    reviewed = {source: target for source, target in REVIEWED.items() if source in sources}
    for source, target in EQUIPMENT_NAMES.items():
        if source in sources:
            reviewed[source] = target
        if source + "强化" in sources:
            reviewed[source + "强化"] = target + " Enhancement"
    for source in sources:
        match = re.fullmatch(r"(.+)增幅·([壹贰叁肆伍])", source)
        if match and match[1] in AMPLIFICATION_NAMES:
            reviewed[source] = AMPLIFICATION_NAMES[match[1]] + " Amplification " + ROMAN[match[2]]
        match = re.fullmatch(r"增幅共鸣·([壹贰叁肆伍])", source)
        if match:
            reviewed[source] = "Amplification Resonance " + ROMAN[match[1]]
        match = re.fullmatch(r"(.+)[·：]其([一二三四五六七八九十])", source)
        if match and match[1] in PART_NAMES:
            reviewed[source] = PART_NAMES[match[1]] + " " + ROMAN[match[2]]
        match = re.fullmatch(r"觉醒之力·([壹贰叁肆伍])", source)
        if match:
            reviewed[source] = "Awakening Power " + ROMAN[match[1]]
        match = re.fullmatch(r"信物骑枪lv(\d+)", source)
        if match:
            reviewed[source] = "Token Lance Lv" + match[1]
        if source.startswith("<#specinfo=baofaji>充能需求量减少50%，且能直接打出第三段攻击。<br>|\r\n"):
            opening = "Burst Skill charge requirement is reduced by 50%, and it starts directly with the third attack."
            frost = " The third attack of Burst Skill converts 20 stacks of Frostbite to trigger Ice Shatter."
            tiers = [opening, opening + frost]
            for damage in (240, 480, 720):
                tiers.append(opening + frost + " The third attack of Burst Skill deals additional damage equal to " + str(damage) + "% Defense.")
            tiers[-1] += " Enemies damaged by the third attack of Burst Skill permanently take 30% more Burst Skill damage."
            reviewed[source] = "\n|\r\n".join(tiers)
    reviewed.update(recorded)
    return reviewed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reviewed-file", type=Path, action="append", default=[])
    args = parser.parse_args()
    sources = catalog.read_json(catalog.CATALOGS / "sources.json")
    _, supplemental = catalog.load_catalogs("en")
    normalized_sources = {}
    for source, target in supplemental.items():
        previous = target
        target = normalize_notation(expand_static(source), target, "en")
        if "冒险家" in expand_static(source):
            if "冒险家公会" in expand_static(source):
                target = re.sub(r"(?i)\bAdventure (?:Home Office|Communion|Chamber)\b", "Adventurers' Guild", target)
            target = re.sub(r"(?i)\bAdventur(?:e|a) (?:famil(?:y|ies)|homes?|house)\b", "Adventurer", target)
        if "攻击速度" in expand_static(source):
            target = target.replace("Attack Speeed", "Attack Speed")
        if "冷却" in expand_static(source):
            target = re.sub(r"(?i)(?:Courttown|Coolown|Coldtown|Colddown|Cooldtown)", "Cooldown", target)
            target = target.replace("SkillCooldown", "Skill Cooldown")
        if "普通攻击" in expand_static(source):
            target = target.replace("Northal Attack", "Normal Attack")
        if "暴击" in expand_static(source):
            for wrong, correct in (("Creative Chance", "Critical Chance"), ("Creative Damage", "Critical Damage"),
                                   ("Critifical Damage", "Critical Damage"), ("Clitial Hit", "Critical Hit")):
                target = target.replace(wrong, correct)
        if "龙魂誓契" in expand_static(source):
            target = target.replace("Dragon Sooul Pact", "Dragon Soul Pact")
        if re.search(r"\d米", source):
            target = target.replace("Rice", "meters")
        if target != previous:
            normalized_sources[source] = sources.get(source, [])
        supplemental[source] = target
    additional = {}
    for path in args.reviewed_file:
        additional.update(catalog.read_json(path))
    if any(source not in sources for source in additional):
        raise ValueError("A reviewed English source is absent from the collected catalog")
    reviewed = reviewed_translations(sources, additional)
    for source, target in reviewed.items():
        error = catalog.validate(source, target, "en")
        if error or not values_match(expand_static(source), target) or replacement_characters(target):
            raise ValueError(f"Invalid reviewed English: {source!r}: {error}")
        supplemental[source] = target
    if additional:
        recorded = catalog.read_json(catalog.CATALOGS / "reviewed/en.json")
        recorded.update(additional)
        catalog.write_json(catalog.CATALOGS / "reviewed/en.json", recorded)
    catalog.write_json(catalog.CATALOGS / "supplemental/en.json", supplemental)
    normalized_path = Path("/tmp/city-localization-normalized-english-sources.json")
    normalized = catalog.read_json(normalized_path)
    normalized.update(normalized_sources)
    catalog.write_json(normalized_path, normalized)
    print(json.dumps({"reviewed": len(reviewed), "normalized": len(normalized_sources), "supplemental": len(supplemental)}))


if __name__ == "__main__":
    main()
