"""Copy source UI artwork by exact config reference; retain provenance."""
import hashlib
import json
from pathlib import Path
import shutil
import re

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'goDot/assets'
SOURCE = ROOT / 'RecoveredUnity/ExportedProject/Assets/_00002_Resource'
ALL_SOURCE = ROOT / 'RecoveredUnity/ExportedProject/Assets'
if not SOURCE.is_dir():
    raise SystemExit('RecoveredUnity source is unavailable; retained resource_map.json and copied artwork were not changed.')
import yaml
from PIL import Image
OUT = ASSETS / 'ui/catalog'
OUT.mkdir(parents=True, exist_ok=True)
index = {}
for path in sorted(SOURCE.rglob('*.png')):
    index.setdefault(path.stem, path)
sprites = {path.stem: path for path in sorted(SOURCE.rglob('*.asset'))}
textures = {}
for path in ALL_SOURCE.rglob('*.png.meta'):
    match = re.search(r'^guid: (\w+)$', path.read_text(), re.M)
    if match:
        textures[match[1]] = Path(str(path)[:-5])

def recover_sprite(name, target):
    path = sprites.get(name)
    if not path:
        return None
    try:
        document = yaml.safe_load('\n'.join(path.read_text().splitlines()[3:]))
        sprite = document.get('Sprite', {})
        rd = sprite.get('m_RD', {})
        texture = textures.get(rd.get('texture', {}).get('guid'))
        rect = rd.get('textureRect', {})
        if not texture or not rect or ((int(rd.get('settingsRaw', 0)) >> 2) & 15):
            return None
        im = Image.open(texture).convert('RGBA')
        x, y, w, h = [int(round(rect.get(k, 0))) for k in ('x', 'y', 'width', 'height')]
        if w <= 0 or h <= 0 or x < 0 or y < 0 or x+w > im.width or y+h > im.height:
            return None
        im.crop((x, im.height-y-h, x+w, im.height-y)).save(target)
        return path
    except (ValueError, OSError, yaml.YAMLError):
        return None
mapping = {}
missing = []
records = []
for path in sorted((ASSETS / 'data').glob('*.json')):
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        continue
    for row in data:
        if not isinstance(row, dict):
            continue
        for field, value in row.items():
            if not isinstance(value, str) or not any(word in field.lower() for word in ('icon', 'sprite', 'artwork')):
                continue
            if not value or value in mapping:
                continue
            source = index.get(value)
            name = hashlib.sha256(value.encode()).hexdigest()[:16] + '.png'
            target = OUT / name
            recovered = recover_sprite(value, target) if not source else None
            if recovered:
                source = recovered
            if source:
                if not recovered:
                    shutil.copy2(source, target)
                mapping[value] = 'res://assets/ui/catalog/' + name
                records.append({'key': value, 'source': str(source.relative_to(ROOT)), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
            else:
                missing.append({'table': path.stem, 'id': row.get('id'), 'field': field, 'key': value})
(ASSETS / 'ui/resource_map.json').write_text(json.dumps(mapping, ensure_ascii=False, indent=2))
(ROOT / 'goDot/reports/style-asset-audit.json').write_text(json.dumps({'originals': records, 'unresolved': missing}, ensure_ascii=False, indent=2))
# Resize generated artwork only; preserve the exact original and alpha.
generated = ASSETS / 'art_generated'
for name, size in [('panel', 1024), ('heavy', 256), ('rune', 512)]:
    source = generated / 'originals' / (name + '-v1.png')
    if source.exists():
        im = Image.open(source).convert('RGBA')
        im.thumbnail((size, size), Image.Resampling.LANCZOS)
        im.save(generated / (name + '-v1.png'))
print(json.dumps({'copied_original_icons': len(mapping), 'unresolved_references': len(missing)}))
