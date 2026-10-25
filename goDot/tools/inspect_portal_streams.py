#!/usr/bin/env python3
"""Record original particle streams and sampler settings for portal/altar effects."""
import hashlib
import json
from pathlib import Path
import zipfile
import UnityPy

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads(Path('/private/tmp/city-charge-assets/manifest.json').read_text())
names = {'24102301_fx_env_maincityprotal', '24040202_fx_env_protal_entrance', '25040703_fx_other_spritesaltar'}
assets = [a for a in manifest['assets'] if a['address'] in names]
env = UnityPy.Environment()
bundles = []
with zipfile.ZipFile(ROOT / 'com.teamelo.dungeonchasers.apk') as archive:
    for i in sorted({i for a in assets for i in [a['bundle'], *a['deps']]}):
        member = 'assets/yoo/DefaultPackage/' + manifest['bundles'][i]['hash'] + '.bundle'
        raw = archive.read(member)
        env.load_file(raw, name=member)
        bundles.append({'member': member, 'sha256': hashlib.sha256(raw).hexdigest()})
objects = {(o.assets_file.name, o.path_id): o for o in env.objects}

def resolve(obj, ptr):
    if not ptr or not ptr.get('m_PathID'): return None
    i = ptr['m_FileID']
    filename = obj.assets_file.name if not i else obj.assets_file.externals[i-1].path.rsplit('/',1)[-1]
    return objects.get((filename, ptr['m_PathID']))

result = {'bundles': bundles, 'renderers': [], 'materials': []}
for obj in env.objects:
    if obj.type.name not in ('Material', 'ParticleSystemRenderer', 'ParticleSystem'): continue
    tree = obj.read_typetree()
    source = f'{obj.assets_file.name}:{obj.path_id}'
    if obj.type.name == 'Material':
        name = tree.get('m_Name', '')
        if not any(n in name for n in ('maincityprotal', 'entrance', 'altar', 'glowlight', 'glowsoft', 'glow_1')): continue
        slots = []
        for key, value in tree['m_SavedProperties']['m_TexEnvs']:
            texture = resolve(obj, value['m_Texture'])
            if texture:
                t = texture.read_typetree()
                slots.append({'property': key, 'name': t['m_Name'], 'source': f'{texture.assets_file.name}:{texture.path_id}', 'settings': t.get('m_TextureSettings')})
        result['materials'].append({'name': name, 'source': source, 'textures': slots})
    else:
        go = resolve(obj, tree['m_GameObject'])
        name = go.read_typetree()['m_Name'] if go else ''
        data = {k:v for k,v in tree.items() if 'stream' in k.lower() or 'custom' in k.lower()}
        if obj.type.name == 'ParticleSystemRenderer':
            data['materials'] = [resolve(obj,p).read_typetree()['m_Name'] for p in tree.get('m_Materials',[]) if resolve(obj,p)]
        if data:
            result['renderers'].append({'name': name, 'type': obj.type.name, 'source': source, 'data': data})
out = ROOT / 'goDot/reports/camp-portal-stream-sampler-evidence.json'
out.write_text(json.dumps(result, indent=2, allow_nan=True) + '\n')
print(out)
