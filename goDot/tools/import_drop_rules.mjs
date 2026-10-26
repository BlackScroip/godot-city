import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = process.argv[2] ?? '/private/tmp/city-new-progression-evidence/new';
const filename = path.join(project, 'assets/data/RogueConfigData.json');
const config = JSON.parse(fs.readFileSync(filename, 'utf8'));
const original = JSON.parse(fs.readFileSync(path.join(source, 'RogueConfigData.json'), 'utf8'));
const fields = Object.keys(original).filter(key => /Drop|TreasureBox|RecoverItemLootPool|ArmorItemLootPool|AbilityItemLootPool|LootInactive|SelectTalentIfMax/.test(key));
for (const key of fields) config[key] = original[key];
fs.writeFileSync(filename, JSON.stringify(config) + '\n');
console.log(JSON.stringify({sourceApk: 'ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505', importedFields: fields}));
