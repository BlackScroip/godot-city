import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const destination = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../assets/data');
const projectRoot = path.resolve(destination, '../../..');
const source = path.join(projectRoot, 'OfflineUnity/Assets/Systems/Resources/SystemsData');
fs.mkdirSync(destination, { recursive: true });
const tables = {};
for (const filename of fs.readdirSync(source).filter(name => name.endsWith('.json')).sort()) {
  const text = fs.readFileSync(path.join(source, filename), 'utf8').replace(/^\uFEFF/, '');
  const data = JSON.parse(text);
  fs.writeFileSync(path.join(destination, filename), JSON.stringify(data));
  tables[path.basename(filename, '.json')] = {
    rows: Array.isArray(data) ? data.length : 1,
    sha256: crypto.createHash('sha256').update(text).digest('hex'),
    source: path.relative(projectRoot, path.join(source, filename)),
  };
}
fs.writeFileSync(path.join(destination, 'manifest.json'), JSON.stringify({ version: 1, tables }, null, 2));
console.log(`Prepared ${Object.keys(tables).length} self-contained system tables.`);
