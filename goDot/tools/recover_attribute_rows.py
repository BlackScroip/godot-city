"""Project ordered native attribute-row declarations and recover their icons."""
import hashlib
import json
from pathlib import Path
import re
import zipfile
import UnityPy
from inspect_camp_progression import Reader, manifest_records

root = Path(__file__).resolve().parents[1]
native = json.loads((root / "reports/character-detail-native-20261027.json").read_text())
texts = json.loads((root / "assets/localization/original/keyed_zh_CN.json").read_text())
stubs = Path(native["stubs"]) / "Assembly-CSharp/Teamelo"
def enum(path):
    return {int(v): k for k, v in re.findall(r"\s+(\w+) = (\d+),", path.read_text())}
types = {"Battle": enum(stubs / "ActionEngine/EAttributeType.cs"), "Rogue": enum(stubs / "ProjectAT/ERogueAttributeType.cs")}
formats = enum(stubs / "ProjectAT/EAttrFormat.cs")
method = next(m for m in native["methods"] if "BuildDefaultConfig" in m["declaration"])
registers = {"xzr": 0, "wzr": 0}
rows = []
category = None
for ins in method["instructions"]:
    args, op = ins["args"], ins["op"]
    dest = args.split(",")[0]
    if "string" in ins:
        registers[dest] = ins["string"]
        if int(ins["offset"], 16) >= 0x2ea37bc and ins["string"].startswith("keyword_attributeDetail_Category_"):
            category = ins["string"]
    elif op == "adrp":
        registers.pop(dest, None)
    elif op == "mov":
        dest, src = args.split(", ")
        registers[dest] = int(src[1:], 0) if src.startswith("#") else registers.get(src)
    elif op == "ldr":
        match = re.fullmatch(r"(x\d+), \[(x\d+)\]", args)
        registers[dest] = registers.get(match[2]) if match else None
    if "static AttrRowConfig" in ins.get("callee", ""):
        kind = "Battle" if " Battle(" in ins["callee"] else "Rogue"
        key = registers.get("x0")
        assert isinstance(key, str) and key.startswith("keyword_attributeDetail_"), (ins, registers)
        row = {"key": key, "label": texts.get(key, key), "category_key": category, "category": texts.get(category, category),
               "source": kind, "property": types[kind][registers["w1"]], "type": registers["w1"],
               "format": formats[registers["w2"]], "baseSubtract": registers["w3"],
               "defaultText": registers.get("x4"), "maxText": registers.get("x5"),
               "help_key": registers.get("x6"), "help": texts.get(registers.get("x6"), ""), "native_offset": ins["offset"]}
        rows.append(row)

icons = next(m for m in native["methods"] if "ApplyDefaultIcons" in m["declaration"])
icon_guids = {}
registers = {}
for ins in icons["instructions"]:
    args, op = ins["args"], ins["op"]
    dest = args.split(",")[0]
    if "string" in ins: registers[dest] = ins["string"]
    elif op == "adrp": registers.pop(dest, None)
    elif op == "ldr":
        match = re.fullmatch(r"(x\d+), \[(x\d+)\]", args)
        registers[dest] = registers.get(match[2]) if match else None
    elif op == "mov":
        dest, src = args.split(", ")
        registers[dest] = registers.get(src)
    if op == "bl" and args == "#0x4877ee0":
        icon_guids[registers.get("x1")] = registers.get("x2")
semantic_icons = dict(zip(
    "Hp Atk Def CritRate CritDmg AtkSpeed MoveSpeed Skill1Charge Skill2Charge DodgeCharge Skill1ExtraUse Skill2ExtraUse DodgeExtraUse NormalAtkDmg HeavyAtkDmg DodgeAtkDmg Skill1Dmg Skill2Dmg AutoDodge HealAdd BossDmg EliteDmg ArmorBreak ShopDiscount FreePurchase GemFree MagicPointDrop GoldDrop FreeCoinDrop MaterialChance MagicLodeChance LowLootNormal LowLootElite LowLootBoss EventChance SpiritAltarChance MonsterAltarChance GemShopChance EliteRoomChance SpringRecover PotionRecover MonsterCharge MonsterDmg TalentUpgradeRate BossExtraDrop RoadMapVertical".split(),
    "shengmingzhi gongjili fangyuli baolv baoshang gongsu yidongsudu zhanjilengque baofajinengliang shanbilengque zhanjicishu zhanjicishu shanbicishu putonggongji zhongji shanbigongji zhanji baofaji shanbi shengminghuifu duilingzhushanghai jingyingzaochengshanghai pojiaxiaolv shangdianjiage shangdianmianfei baoshimianfei molijinghuadiaoluo jingbidiaoluo qicaijiejingdiaoluo sucaichuxiangailv kuangmaichuxian putongdiaoluo jingyingdiaoluo bossdiaoluoyiwugailv shijianchuxiangailv jinglingchuxiangailv guaiwuzhiyuanjitanchuxiangailv baoshishangrenchuxiangailv jingyingchuxiangailv quanshuihuifuxiaolv yaoshuihuifuxiaolv guaiwuzhiyuanchongneng guaiwuzhiyuanshanghai tianfushengjigailv bossdianjiage chuizhiyidong".split()))
out = root / "assets/ui/role_character"
mapping = json.loads((out / "resource_map.json").read_text())
recovered = []
with zipfile.ZipFile(root.parent / "1061664.apk") as archive:
    manifest_name = next(n for n in archive.namelist() if n.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes"))
    manifest = archive.read(manifest_name)
    assets, bundles = manifest_records(manifest)
    reader = Reader(manifest)
    reader.number("I")
    reader.string()
    for _ in range(3): reader.number("B")
    for _ in range(2): reader.number("i")
    for _ in range(4): reader.string()
    by_guid = {}
    for _ in range(reader.number("i")):
        address, path, guid = [reader.string() for _ in range(3)]
        reader.array(reader.string)
        bundle = reader.number("i")
        reader.array(lambda: reader.number("i"))
        by_guid[guid] = {"address": address, "path": path, "bundle": bundle}
    for row in rows:
        asset = by_guid.get(icon_guids.get(row["key"]))
        if not asset:
            candidate = "attribute_" + semantic_icons.get(row["key"].removeprefix("keyword_attributeDetail_"), "")
            asset = next((a for a in assets if a["address"] == candidate), None)
            if asset: row["icon_mapping"] = "semantic asset-name match; GUID mapping unresolved"
        row["icon"] = asset["address"] if asset else ""
        row["icon_guid"] = icon_guids.get(row["key"], "")
        if not asset or asset["address"] in mapping:
            continue
        member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
        payload = archive.read(member)
        for obj in UnityPy.load(payload).objects:
            if obj.type.name != "Sprite" or obj.peek_name() != asset["address"]:
                continue
            sprite = obj.read()
            filename = re.sub(r"[^A-Za-z0-9_.-]", "_", sprite.m_Name) + "_" + hashlib.sha256(sprite.m_Name.encode()).hexdigest()[:8] + ".png"
            destination = out / "attribute_detail" / filename
            sprite.image.save(destination)
            mapping[sprite.m_Name] = "res://assets/ui/role_character/attribute_detail/" + filename
            recovered.append({"name": sprite.m_Name, "member": member, "bundle_sha256": hashlib.sha256(payload).hexdigest(), "png_sha256": hashlib.sha256(destination.read_bytes()).hexdigest()})
last = None
ordered = []
for row in rows:
    if last and last != row["category"]:
        ordered.append({"separator": True})
    ordered.append(row)
    last = row["category"]
(out / "attribute_rows.json").write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n")
(out / "resource_map.json").write_text(json.dumps(mapping, indent=2) + "\n")
(out / "attribute-icons-provenance.json").write_text(json.dumps(recovered, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"rows": len(rows), "recovered_icons": len(recovered), "first": rows[:9]}, ensure_ascii=False))
