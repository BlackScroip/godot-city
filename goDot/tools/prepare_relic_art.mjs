import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => JSON.parse(fs.readFileSync(path.join(root, 'assets/data', `${name}.json`), 'utf8'));
const abilities = new Map(read('AbilityItems').map(row => [Number(row.ID), row]));
const poolIds = new Set([20002, 21003, 20201, 20202, 20203, 30100]);
const subIds = new Set(read('ItemPoolData').filter(row => poolIds.has(row.id)).flatMap(row => row.sub_data_id_list.split(',').map(Number)));
const lootIds = new Set(read('ItemPoolSubData').filter(row => subIds.has(row.id)).flatMap(row => row.item_id_list_str.split(',').map(Number)));

const subjects = {
  '自制匕首': 'Rough hand-ground iron dagger, wooden handle bound in frayed linen, cold glint on the blade.',
  '魔法长刀': 'Long curved steel blade with faint flowing blue magical veins, leather hilt.',
  '以德服人': 'Heavy squared wooden club with visible wood grain and a single carved Chinese character 理.',
  '新生枝叶': 'Two fresh succulent green leaves sprouting from a tiny stem, dewdrops and faint natural glow.',
  '冒险木盾': 'Small round wooden shield with nailed iron reinforcements and light scratches.',
  '迅捷之靴': 'Light adventurer leather boot with a tied feather, a subtle wisp of wind below the sole.',
  '吞噬者之徽': 'Dark teal metal badge carved as an open ravenous monster mouth.',
  '近卫者之剑': 'Standard silver single-handed guard sword with a cross-shaped hilt.',
  '枯竭魔法导石': 'Dull grey magic crystal with deep cracks and almost extinguished inner light.',
  '训练用木剑': 'Worn rounded wooden training sword with soft leather padding.',
  '宝石收藏家': 'Little leather pouch decorated with several rough colorful gemstone chips.',
  '小伙伴': 'Tiny endearing mud-clay companion figurine, simple face, stubby body.',
  '锈蚀手甲': 'Rusty fingerless iron gauntlet, stiff articulated knuckles and worn straps.',
  '宝石口袋': 'Bulging burlap gem pouch with colored crystal light peeking out of the seam.',
  '陶罐猎手': 'Small practical hammer for smashing clay pots, chipped metal head and short wooden handle.',
  '充能法杖': 'Short wooden magic staff topped with a charged glowing crystal.',
  '史莱姆伙伴': 'Cute translucent blue jelly slime companion with tiny bubbles inside, two simple eyes.',
  '闪电法杖': 'Scorched black wooden wand entwined with small golden electric arcs.',
  '泉水宝瓶': 'Clear small glass bottle containing sparkling fresh spring water, cork stopper.',
  '见习冒险之剑': 'Freshly sharpened novice steel shortsword, non-slip leather-wrapped grip.',
  '迷宫宝珠项链': 'Necklace with a single stone orb carved with a clear labyrinth pattern.',
  '充能战甲': 'Light leather chest armor with faint electric currents and a small charged central clasp.',
  '友谊之证': 'Two complementary half-heart copper friendship pendants joined together, soft glow.',
  '小众收藏家': 'Exquisite violet trinket box, lid slightly open revealing curious little collectibles.',
  '不屈之剑': 'Battle-worn slightly bent iron sword, stubborn upright silhouette and bright intact cutting edge.',
  '力大砖飞': 'Single extremely heavy rectangular brick with deeply carved magical runes.',
  '破损冒险靴': 'Ancient dusty leather boot with a worn-through sole and torn seams.',
  '商店兑换卷': 'Old paper exchange voucher with charred edges and a faded mysterious red seal.',
  '破碎剑刃': 'Broken ancient sword blade fragment with green verdigris around the fracture.',
  '商业契约': 'Ancient parchment commercial contract with unreadable lost glyphs and a dried dark-red seal.',
  '地图残卷': 'Torn rolled parchment map of an unknown continent, burnt dark edges.',
  '破损斗篷': 'Tattered black adventurer cloak full of holes with faint starlight in the fabric.',
  '黄金手杖': 'Ancient golden walking cane, faded gemstone pommel and lost-civilization carvings.',
  '冒险口袋': 'Bulging old cloth adventurer pouch with a subtly glowing dimensional opening.',
  '枯竭的复苏宝石': 'Black obsidian resurrection gem with an extinguished ember inside.',
  '平庸之力': 'Plain exceptionally heavy rough grey stone, no magical energy, strong grounded silhouette.',
  '冒险巨剑': 'Very large old chipped steel greatsword covered in battle notches.',
  '复生之血': 'Ancient crystal vial containing warm dark crimson blood, sealed brass stopper.',
  '领主试炼徽章': 'Scratched golden noble family crest badge with an engraved heraldic shield.',
  '破旧炼精釜': 'Small mottled ancient bronze alchemy cauldron with dried potion residue.',
  '皮糙肉厚': 'Thick folded ancient beast hide with a faint earthy protective glow.',
  '加急物流': 'Worn wooden delivery parcel engraved with a spatial teleportation circle.',
  '口袋置换': 'Two worn twin cloth pouches connected by a small dark dimensional vortex.',
  '原初试剂': 'Sealed clear glass vial of colorless primordial liquid with faint chaotic suspended motes.',
  '牺牲匕首': 'Ancient sacrificial dagger, dark crimson blade, worn ceremonial bronze hilt.',
  '不朽冰锥': 'Sharp eternal glacial ice spike with deep blue core and tiny cold mist.',
  '命运齿轮': 'Ancient brass clockwork gear with fine engraved concentric mechanisms.',
  '强敌置换': 'Mysterious stone disc carved with two interlocking dimensional portal symbols.',
  '错误宝石': 'Translucent magical crystal with dislocated impossible geometric facets inside.',
  '厚积薄发': 'Very thick old ordinary notebook with heavy pages and a subtle compressed magical glow.',
  '禁咒匕首': 'Cursed short dagger entwined with thin black smoke, dark red edge and thorn-shaped hilt.',
  '绝望面具': 'Pale twisted theatrical mask silently crying, dark hollow eyes and fine cracks.',
  '凋零花朵': 'Single withered black flower with curled petals and a faint sickly violet aura.',
  '晦暗金币': 'Tarnished haunted gold coin engraved with a weeping face.',
  '污秽龙鳞甲': 'Corrupted dragon-scale chest armor with dark oily ooze between jagged scales.',
  '灾厄羽毛': 'Single ominous black feather with fine drifting shadow wisps.',
  '斗士水杯': 'Cracked old bronze fighter cup with a dried poisonous purple residue inside.',
  '腐败面包': 'Hard dark loaf of bread covered in patches of green mold.',
  '失控魔杖': 'Twisted unstable wand ejecting a few dangerous jagged magical sparks.',
  '黑暗石牌': 'Black stone tablet carved with cursed glyphs, frosty edges.',
  '腐败王冠': 'Corrupted crown constructed from twisted thorns and small ancient bones.',
  '不公天平': 'Crooked unbalanced bronze scales with one lowered pan and a dark red droplet.',
  '诡异蘑菇': 'Poisonous violet-spotted mushroom with an eerie eye marking on its cap.',
  '怪异手甲': 'Bone gauntlet with unnaturally long inward-curving claw fingers.',
  '魔女的宝物': 'Small ornate witch treasure box entwined with black hair and faint purple vapor.',
  '魔力饥渴': 'Hollow pitch-black ring absorbing tiny motes of surrounding magical light.',
  '踟蹰不前': 'Heavy rusty chain twisting like a clinging vine around an ankle shackle.',
  '口袋漏洞': 'Torn cloth money pouch with a large hole in the bottom and one falling coin.',
  '过期零食': 'Spoiled wrapped candy with an unsettling smiling emblem on its paper wrapper.',
  '限制镣铐': 'Heavy connected iron ankle shackles suppressing magic with a sickly green glow.',
  '折光匕首': 'Pure white short dagger refracting a small rainbow glint along the sharp edge.',
  '庆典面具': 'White smiling festival mask with fine golden trim and soft holy light.',
  '新生花朵': 'Fresh white lily covered with morning dew, gentle healing glow.',
  '华丽金币': 'Pristine ornate gold coin with a radiant protective sacred emblem.',
  '水晶龙鳞甲': 'Flawless transparent dragon-crystal chest armor with flowing white inner light.',
  '风灵羽毛': 'Single pristine white angel feather with a delicate curling breeze.',
  '冠军水杯': 'Pure gold victory trophy cup filled with clear holy water.',
  '新鲜面包': 'Fresh golden-white bread loaf, soft scored crust and tiny steam wisps.',
  '雷霆权杖': 'Sacred pure white staff with gold fittings and restrained righteous blue lightning.',
  '祝福石牌': 'White glowing stone tablet engraved with a sacred protection symbol.',
  '高贵王冠': 'Noble pure gold crown with a single large brilliant clean blue sapphire.',
  '绝对天平': 'Perfectly balanced symmetrical golden scales of justice with sacred light.',
  '光辉蘑菇': 'Warm luminous pearl-white mushroom driving back tiny shadow wisps.',
  '异界手甲': 'Sleek pure white gauntlet with flowing astral silver lines and a star-shaped gem.',
  '王女的宝物': 'Exquisite royal crystal music box with gold fittings and a faint pure glow.',
  '魔力旋涡': 'Clear translucent circular water vortex, calm flowing clean blue magical energy.',
  '健步如飞': 'Light leather boot with a luminous air magic circle at its sole and wind trails.',
  '口袋宝库': 'Pristine enchanted treasure pouch with a neatly glowing golden dimensional opening.',
  '人气零食': 'Beautiful wrapped healing candy in bright clean gold-and-pink paper.',
  '贤者之环': 'Thin floating golden wisdom halo with fine sacred runes.',
  '奇幻烤肉': 'Large glistening roasted fantasy meat steak on a bone skewer, tiny colorful magical aroma.',
  '神秘药汤': 'Small skull-shaped cauldron filled with bubbling mysterious violet potion.',
  '活力炼金釜': 'Stone alchemy pot engraved with monster totems, bubbling primordial green liquid.',
  '原初物质': 'Amorphous glossy living gel core with soft multicolored primordial light.',
  '精灵飞羽': 'Long elegant high-elf feather with flowing wispy wind filaments along the edges.',
  '大骨棒': 'Massive primitive club made from an ancient giant beasts polished thigh bone.',
};

const series = [
  ['风行者围巾|风行者战盔|风行者战靴', 'Turquoise windwalker fabric, feather embroidery, light bronze fittings and subtle breeze.', 'flowing gauze scarf|light winged bronze helmet|high soft leather boot with wind rune'],
  ['幽影小刀|幽影飞镖|幽影之刃', 'Matte black and deep violet shadow assassin gear, fine sharp silhouette and thin shadow haze.', 'small dark dagger|triangular returning throwing dart|long assassin dagger partly wrapped in shadow'],
  ['生命药泥|药师柴刀|恢复配方', 'Practical forest herbalist equipment, natural green herbs and warm worn wood.', 'open jar of thick green herbal paste|crescent-shaped herbalists machete|aged parchment herbal formula with herb sketch'],
  ['森林匕首|森林短弓|森林长靴|森林魔法戒|森林荆棘盾|森之项链', 'Natural forest craft, vines, moss, dark wood, bone and soft green details.', 'bone knife with vine-bound handle|flexible green branch shortbow|silent soft hide boot|wooden finger ring with luminous moss|hardwood round shield rimmed with thorns|necklace of pinecone and dried flower petals'],
  ['护卫头盔|战损皮甲|部落之盾|战甲护符', 'Rugged tribal protection gear, beast teeth, thick leather and worn iron.', 'heavy guard helmet|battle-scarred leather chest armor|tribal wooden shield with beast-tooth trim|armor-shaped protective amulet'],
  ['镶金大棍|赤红长棍|符文躯壳', 'Arcane tribal artifacts with fine mystical inlay, rich wood and dark red fabric.', 'large gold-inlaid wooden club|long crimson fighting staff|hollow robe-like rune armor shell'],
  ['侍从勋章|侍从链锤|侍从战靴|守护之徽', 'Silver-white loyal knight attendant equipment, neat blue straps and understated heraldry.', 'loyalty medal|chain flail with silver head|armored squire boot|engraved protective heraldic badge'],
  ['凶兽断角|战狂能量剑|战争护符', 'Savage battle relic with dark metal, bone, crimson energy and aggressive form.', 'broken fierce beast horn|crimson-energy berserker sword|war amulet with battle insignia'],
  ['商人信物|商人账本|商人古董|狂热之戒', 'Merchant gold and aged brass, refined engraved surfaces and rich jewel accents.', 'merchant guild seal token|leather-bound account ledger with coin clasp|small ornate antique amphora|ornate fanatics ring with bright red gemstone'],
  ['诡异魔刀|恶魔镰刀|恶魔骑士枪', 'Demonic horned weapon design with abyssal purple, dark crimson steel and subtle evil energy.', 'eerie curved magic blade|demon scythe|demon knights long lance'],
  ['风灵双头刃|风岭部落弓|风羽佩剑|风羽侍从袍', 'Light azure-teal wind spirit equipment, elegant feather patterns and fine swirling air.', 'double-ended blade|wind-tribe curved bow|feathered slim sword|feather-trimmed attendants robe'],
  ['铁血战斧|铁血戒指|铁血木盾', 'Heavy rugged forged iron, red leather bindings, thick functional edges.', 'heavy battle axe|forged iron finger ring|iron-banded wooden shield'],
  ['刺客匕首|刺客斗篷|刺客靴子', 'Stealth assassin equipment in matte black leather and shadow blue steel.', 'slender assassin dagger|hooded assassin cloak|silent assassin boot'],
  ['无畏战盾|无畏之剑|无畏项链', 'Fearless warrior golden armor motifs, thick edges and unwavering protective heraldry.', 'large battle shield|broad sword|armored pendant necklace'],
  ['士兵长枪|士兵手套|士兵护戒', 'Practical imperial soldier issue equipment, clean steel with restrained red-and-brass details.', 'long infantry spear|pair of military leather gloves with steel plates|protective soldier ring'],
  ['狂暴护符|狂暴卷轴|狂暴战斧', 'Berserker weaponry with hot ember cracks, flame motifs and enraged crimson iron.', 'rage amulet|rolled rage spell scroll|massive brutal battle axe'],
  ['魔力之源|魔力项链|魔力手套', 'Pure blue arcane crystal energy in polished silver mounts, clean luminous facets.', 'arcane energy crystal core|blue crystal pendant necklace|sorcerers glove with crystal fittings'],
  ['岩之史莱姆|花之史莱姆|熔岩史莱姆', 'Cute rounded elemental slime creature, clear simple eyes and dimensional jelly silhouette.', 'grey rocky slime with little stone plates|green flower slime with a blooming blossom|red-orange molten lava slime with basalt crust'],
  ['米诺陶诺斯之斧|米诺陶诺斯之手|米诺陶诺斯之角', 'Minotaur giant beast relic, huge bones, rugged iron and thick hide.', 'massive minotaur battle axe|minotaur armored fist gauntlet|curved minotaur horn'],
  ['勇者之剑|勇者之盾|勇者之盔', 'Classic heroic equipment in clean gold, silver and royal blue, sacred justice details.', 'heroic straight sword|heroic kite shield|heroic knight helmet'],
  ['吟唱者之杖|吟唱者之帽|吟唱者之符纹', 'Scholar-bard equipment, purple and gold cloth, elegant musical and arcane engravings.', 'singers magic staff|soft scholarly pointed hat|parchment rune with a clear musical sigil'],
  ['冰龙之牙|冰龙之爪|冰龙之鳞片', 'Ancient ice dragon material, translucent icy blue with cold white mist and frosted edges.', 'large sharp dragon fang|curved dragon talon|single dragon scale'],
  ['战损民兵头盔|生锈骑士头盔|精英骑士头盔', 'Medieval steel helmet with readable visor and fine crafted silhouette.', 'dented militia helmet with broken rim|rusty closed knight helmet|polished elite knight helmet with restrained crest'],
  ['学院作业|学徒笔记|讲师课本', 'Magic academy stationery, warm parchment, ink diagrams and restrained magical annotations.', 'homework parchment with ink corrections|small apprentices notebook|thick lecturers textbook'],
  ['巨魔的钢盔|巨魔的盾牌|巨魔的镣铐', 'Oversized crude troll forged iron, rusty rough surface and brutal heavy rivets.', 'huge trolls steel helmet|heavy trolls shield|massive trolls shackles'],
  ['异界之刃|异界之心|异界植株|异界宝瓶', 'Deep astral violet, void tendril patterns and tiny starfield details, powerful otherworldly artifact.', 'otherworldly blade|faceted otherworldly heart|small curling alien plant|ornate void potion bottle'],
  ['闪耀手甲|闪耀宝珠|闪耀史莱姆|闪耀指环', 'Brilliant golden translucent crystal, refined bright facets and restrained sparkling highlights.', 'crystal gauntlet|perfectly round crystal orb|small cute crystal slime|faceted crystal finger ring'],
  ['牺牲之符|守护回响|金甲余晖|命运馈赠', 'Ancient engraved gold and sacred warm light, refined ceremonial material.', 'sacrificial talisman|protective echo bell|golden armor remnant glowing at dusk|sealed gift of fate with intricate bow'],
  ['梦之匙|梦之尘|梦之心|梦之莲', 'Dreamlike pink-violet crystal and small curling wisps of magical haze.', 'ornate dream key|tiny vial of sparkling dream dust|translucent dream heart|delicate crystal lotus'],
  ['海之怒|海妖之泪|深海珊瑚|海之声', 'Deep ocean blue and aquamarine jewel tones, flowing water shapes and tiny bubbles.', 'furious cresting wave captured in an orb|single tear-shaped aquamarine jewel|branched deep-sea coral|spiral resonating conch shell'],
  ['白银制裁|白银长枪|白银圆盾|白银配剑', 'Pure polished high-grade silver with sharp crisp specular highlights, noble restrained engraving.', 'silver judgement warhammer|silver long spear|silver round shield|silver side sword'],
  ['烈焰仪式剑|烈阳卷轴|破碎烈焰石|熔炉之心', 'Crimson magma, glowing orange fissures and flowing fire runes on dark metal.', 'ceremonial fire sword|sunfire spell scroll|broken flame crystal|molten furnace heart core'],
  ['永夜王爵剑|永夜权杖|永夜卷轴|永夜守护者', 'Refined black and antique gold with tiny night-star inlays, aristocratic dark fantasy.', 'night dukes sword|night royal scepter|night spell scroll|armored night guardian figurine'],
  ['风翼龙火炮|风翼卷轴|风翼龙断角|风翼龙之泪', 'Teal dragon scales and swirling pale wind, crafted dragon relic details.', 'small dragon-scale hand cannon|wind dragon scroll|broken wind dragon horn|dragon tear-shaped teal gemstone'],
  ['惩戒之徽|惩戒水晶|惩戒匕首|惩戒符文剑', 'Sacred judgement artifact with sharp white-and-gold cross motifs and refined radiant edges.', 'judgement badge|judgement crystal|judgement dagger|engraved judgement rune sword'],
  ['雷霆之力|雷霆卷轴|雷霆水晶|雷霆鳞甲|雷霆之花', 'Deep blue storm energy, small bright electric arcs and sharp silver-blue details.', 'compact lightning energy core|storm spell scroll|storm crystal|lightning scale chest armor|lightning flower with crystalline petals'],
  ['天界彩虹弓|天之箭|天界秘石|天使斗篷', 'Holy heavenly feather motifs, pearl-white gold and restrained rainbow reflections.', 'rainbow celestial bow|single celestial arrow|mysterious celestial gemstone|angel feather cloak'],
  ['星火之燧|星火之风|星火之油|星火之薪', 'Warm glowing embers and tiny leaping sparks on practical adventurer objects.', 'small firestriker flint|tiny swirling ember breeze|corked bottle of fire oil|bundle of enchanted firewood'],
  ['潮汐权杖|潮汐海螺|潮汐之珠|潮汐锚链', 'Deep ocean blue, flowing wave contours and silver marine fittings.', 'tidal scepter|spiral tidal conch|round tidal pearl|heavy tidal anchor chain'],
  ['精灵树苗|精灵沙|精灵泉水|万物之灵', 'Crystal-clear natural green and soft fairy dust, pristine luminous natural material.', 'small elven sapling|vial of sparkling fairy sand|bottle of pure elven spring water|tiny cosmic orb gathering many colors of living light'],
  ['猎人项圈|猎人地图|猎人陷阱|猎人行囊', 'Practical hunter leather, beast teeth and worn brass, restrained utilitarian craftsmanship.', 'tooth-trimmed hunting collar|rolled hunting map|open compact metal hunting trap|well-stocked leather hunter backpack'],
];
for (const [names, style, objects] of series) {
  names.split('|').forEach((name, index) => { subjects[name] = `${objects.split('|')[index]}. ${style}`; });
}

const colors = {1: ['green', '#55bd72'], 2: ['blue', '#4b9fe8'], 3: ['purple', '#af70e3'], 4: ['orange', '#ed9a40'], 5: ['red', '#e85c61']};
const common = 'Simplified hand-painted 2D fantasy RPG inventory icon, readable at 48 pixels. Chunky compact silhouette, bold dark outline, few broad painted shading planes, modest highlights, no photorealistic texture or microdetail. Object centered and fully visible, occupying 72 percent of square. Dark charcoal slate tile with thin flat rarity-colored rim, subtly rounded corners, no ornamental metal corner caps. Natural material colors distinct from rarity rim. No text, labels, numbers, stars or watermark.';
const items = read('LootData').filter(row => lootIds.has(row.id) && !row.is_admin_only).map(row => {
  const ability = abilities.get(row.ability_item_id);
  const [color, hex] = colors[ability.Rare];
  if (!subjects[ability.Name]) throw new Error(`Missing art direction: ${ability.Name}`);
  return {id: row.id, name: ability.Name, type: row.loot_type, rarity: ability.Rare, color, hex,
    path: `res://assets/art_generated/relics/relic_${row.id}.png`,
    subject: subjects[ability.Name],
    prompt: `${common} Item: ${ability.Name}. Subject: ${subjects[ability.Name]} RARITY: ${ability.Rare} star, ${color.toUpperCase()} rim ${hex}; restrained ${color} inner edge glow.`};
});
if (items.length !== 243) throw new Error(`Expected 243 relics; got ${items.length}`);
const order = ['普通遗物', '套装遗物', '强化遗物', '旧日遗物', '诅咒遗物', '净化遗物', '怪物支援通用遗物'];
items.sort((a, b) => a.rarity - b.rarity || order.indexOf(a.type) - order.indexOf(b.type));
items.forEach((item, index) => { item.cell = {column: index % 27, row: Math.floor(index / 27)}; });
const sheetPrompt = [
  'Use case: stylized-concept. Create ONE production sprite atlas for a 2D fantasy RPG. Exactly 243 different small relic icons laid out as a strict regular matrix of 27 columns and 9 rows. Every cell is square and identical. Canvas 3456 x 1152 pixels, each cell exactly 128 x 128 pixels. This is a technical spritesheet to be sliced on the uniform grid. No margins, headers, legends, titles or footer. Do not change row or column counts. No empty cells, no spanning cells. Each cell contains exactly one item. Each row has exactly 27 tiles.',
  'STYLE: match the user reference: simple charming hand-painted game inventory icons with thick dark contours, broad 3-tone shading, slightly chunky silhouettes, softly worn muted natural colors. Tiny 48-pixel icon detail level, never highly detailed realistic concept art. Material suggested by only a few highlights. Dark grey-blue square tile fills, very thin simple colored border with subtly rounded corners. The grid gutters are uniform 4-pixel ivory lines spanning the entire canvas, straight and evenly spaced. Icons centered fully inside tiles with 12-percent padding; no overlapping tiles. No ornate metal frame, no photographic texture, no large glowing clouds, no lettering or labels.',
  'BORDER RARITY KEY (strictly follow each item): G = GREEN #55bd72, B = BLUE #4b9fe8, P = PURPLE #af70e3, O = ORANGE #ed9a40, R = RED #e85c61. Only the thin border signals rarity: the object retains its own normal colors. In particular red rarity does not turn holy items or silver blades red. Cursed and purified items both have RED borders but completely different dark versus white-and-gold object designs.',
  'EXACT CELL CONTENTS BELOW: read each ROW left-to-right. Bracket codes are instructions only, never print them. Render all 243 subjects in the precise provided order.',
  ...Array.from({length: 9}, (_, row) => `ROW ${row + 1}: ` + items.slice(row * 27, (row + 1) * 27).map((item, column) => `${column + 1}) [${{green:'G',blue:'B',purple:'P',orange:'O',red:'R'}[item.color]}] ${item.name}: ${item.subject}`).join(' ; ')),
  'Final technical check: exactly 27 equal columns by 9 equal rows, 243 single centered icons, colored simple rims, ivory separator grid. Simplified small painted inventory sprites matching the supplied reference, not detailed standalone illustrations.'
].join('\n\n');
const directory = path.join(root, 'assets/art_generated/relics');
fs.mkdirSync(directory, {recursive: true});
fs.writeFileSync(path.join(directory, 'manifest.json'), JSON.stringify({generator: 'built-in imagegen spritesheet', reference: 'User supplied simplified inventory atlas reference and per-item art brief', sheet: {columns: 27, rows: 9, source: 'relic-atlas-source.png'}, rarity_colors: colors, common_prompt: common, items}, null, 2) + '\n');
fs.writeFileSync(path.join(directory, 'atlas-prompt.txt'), sheetPrompt + '\n');
console.log(JSON.stringify({items: items.length, output: directory, counts: Object.fromEntries([1,2,3,4,5].map(rarity => [rarity, items.filter(item => item.rarity === rarity).length]))}));
