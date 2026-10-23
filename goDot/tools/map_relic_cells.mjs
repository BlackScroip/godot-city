import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const directory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../assets/art_generated/relics');
const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
// Coordinates were checked against the generated sheet rather than its requested grid.
const rows = [
  '自制匕首|魔法长刀|以德服人|新生枝叶|冒险木盾|迅捷之靴|枯竭魔法导石|锈蚀手甲|充能法杖|泉水宝瓶|风行者围巾|风行者战盔|风行者战靴|生命药泥|药师柴刀|恢复配方|森林匕首|森林短弓|森林长靴|护卫头盔|战损皮甲|部落之盾|冒险口袋|铁血战斧|刺客匕首|无畏战盾|熔岩史莱姆|战损民兵头盔|精英骑士头盔|破旧炼精釜',
  '训练用木剑|宝石收藏家|小伙伴|宝石口袋|史莱姆伙伴|闪电法杖|充能战甲|幽影小刀|幽影飞镖|幽影之刃|镶金大棍|赤红长棍|符文躯壳|森林魔法戒|森林荆棘盾|森之项链|凶兽断角|战狂能量剑|战争护符|商人信物|商人账本|学徒笔记|复生之血|刺客斗篷|刺客靴子|无畏之剑|士兵长枪|花之史莱姆|学院作业|',
  '讲师课本|星火之燧||||猎人项圈|铁血戒指||||冰龙之爪||口袋置换|||||冒险巨剑|精灵树苗|||||精灵飞羽|神秘药汤|奇幻烤肉|活力炼金釜|原初物质||大骨棒',
  '吞噬者之徽|近卫者之剑|陶罐猎手|见习冒险之剑|小众收藏家|不屈之剑|侍从链锤|侍从勋章||侍从战靴|守护之徽|狂热之戒|恶魔镰刀|恶魔骑士枪||风岭部落弓|风羽佩剑|风羽侍从袍|铁血木盾|无畏项链|士兵手套|士兵护戒|狂暴护符|狂暴战斧|狂暴卷轴|魔力之源||魔力旋涡|米诺陶诺斯之角|深海珊瑚',
  '海妖之泪||海之声||白银制裁|白银长枪|白银圆盾|白银配剑|烈焰仪式剑|烈阳卷轴|熔炉之心|永夜王爵剑|永夜权杖|永夜卷轴|永夜守护者|风翼龙火炮|风翼卷轴|风翼龙断角|风翼龙之泪|惩戒之徽|惩戒水晶||惩戒符文剑||星火之油|星火之风|潮汐之珠|潮汐锚链||不朽冰锥',
  '迷宫宝珠项链|友谊之证|力大砖飞|异界之刃|异界之心|异界植株|异界宝瓶||||牺牲之符|守护回响|金甲余晖|命运馈赠|梦之匙|梦之尘|梦之心|梦之莲||猎人行囊|破损冒险靴|商店兑换卷|破碎剑刃|商业契约|地图残卷|破损斗篷|黄金手杖||命运齿轮|强敌置换',
  '|禁咒匕首|牺牲匕首|诡异蘑菇|加急物流||魔力饥渴|||||折光匕首|||||皮糙肉厚|||失控魔杖|污秽龙鳞甲|魔女的宝物|晦暗金币|光辉蘑菇|诡异魔刀|||口袋漏洞|过期零食|',
  '黑暗石牌||||怪异手甲|||踟蹰不前|||限制镣铐|天之箭|庆典面具|新生花朵|华丽金币||风灵羽毛|冠军水杯|新鲜面包|雷霆权杖|祝福石牌|高贵王冠|绝对天平||||健步如飞|口袋宝库|人气零食|',
];
const byName = new Map(manifest.items.map(item => [item.name, item]));
const assignments = {};
for (const [rowIndex, row] of rows.entries()) {
  const names = row.split('|');
  if (names.length !== 30) throw new Error(`Row ${rowIndex + 1}: ${names.length} columns`);
  for (const [columnIndex, name] of names.entries()) {
    if (!name) continue;
    const item = byName.get(name);
    if (!item || assignments[item.id]) throw new Error(`Invalid/duplicate: ${name}`);
    assignments[item.id] = {source: 'relic-atlas-source.png', row: rowIndex + 1, column: columnIndex + 1};
  }
}
fs.writeFileSync(path.join(directory, 'source-assignments.json'), JSON.stringify(assignments, null, 2) + '\n');
const missing = manifest.items.filter(item => !assignments[item.id]);
fs.writeFileSync(path.join(directory, 'missing-items.json'), JSON.stringify(missing, null, 2) + '\n');
console.log(JSON.stringify({mapped: Object.keys(assignments).length, missing: missing.length}));
for (const item of missing) console.log(`${item.id}: ${item.name} [${item.rarity}] ${item.subject}`);
