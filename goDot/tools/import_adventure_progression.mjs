import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = process.argv[2] ?? '/private/tmp/city-new-progression-evidence/new';
const destination = path.join(project, 'assets/data');
const read = name => JSON.parse(fs.readFileSync(path.join(source, `${name}.json`), 'utf8'));
const manifestPath = path.join(destination, 'manifest.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const write = (name, value, rows, sourceName) => {
  const text = JSON.stringify(value) + '\n';
  fs.writeFileSync(path.join(destination, `${name}.json`), text);
  manifest.tables[name] = {
    rows,
    sha256: crypto.createHash('sha256').update(text).digest('hex'),
    source: sourceName,
  };
};
const influencers = read('RogueLevelDifficultyInfluencerData');
write('RogueLevelDifficultyInfluencerData', influencers, influencers.length,
  'DungeonChasers-2026-10-09/SystemsData/RogueLevelDifficultyInfluencerData.json');
const configPath = path.join(destination, 'RogueConfigData.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const latestConfig = read('RogueConfigData');
const keys = ['ChaosLevelRewardDict', 'ChaosLevelDropRateMulti', 'EnemyDropRelationshipTokenUpgradeItem_ByDifficulty', 'AmplifyDropByTierAndDifficulty'];
for (const key of keys) config[key] = latestConfig[key];
write('RogueConfigData', config, 1, 'OfflineUnity/SystemsData + DungeonChasers-2026-10-09 adventure progression');
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({influencers: influencers.length, updatedConfigKeys: keys}));
