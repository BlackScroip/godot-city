#!/usr/bin/env python3
"""Recover exact water properties and masks from the shipped Unity bundles."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import UnityPy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    source = json.loads(args.evidence.read_text())
    materials = {k: v for k, v in source['materials'].items()
                 if v['shader']['m_PathID'] == -4698155739361515650}
    result = {'materials': materials, 'textures': {}, 'shader': {}, 'bundles': [],
              'method': 'Static APK serialized material and shader property parsing. Texture decoding only.',
              'limitations': ['Property descriptions recovered from shader metadata; full compiled shading formula not recovered.',
                             'Null river foam sampler uses shader default black. Runtime depth/color buffers are not packaged textures.']}
    with zipfile.ZipFile(args.apk) as archive:
        for member in ('assets/yoo/DefaultPackage/0b2f3bd3a74fa0db64005df35d45b576.bundle',
                       'assets/yoo/DefaultPackage/01d05fe4e913bf05e1f641ca64d58c8e.bundle'):
            raw = archive.read(member)
            result['bundles'].append({'member': member, 'sha256': hashlib.sha256(raw).hexdigest()})
            env = UnityPy.load(raw)
            needed = {t['m_Texture']['m_PathID'] for m in materials.values() for t in m['textures'].values()}
            for obj in env.objects:
                if obj.type.name == 'Shader' and obj.path_id == -4698155739361515650:
                    data = obj.read_typetree()['m_ParsedForm']
                    result['shader'] = {'name': data['m_Name'], 'properties': data['m_PropInfo']['m_Props'],
                        'render_states': [{'tags': sub.get('m_Tags'),
                                           'passes': [p['m_State'] for p in sub['m_Passes']]}
                                          for sub in data['m_SubShaders']]}
                if obj.type.name == 'Texture2D' and obj.path_id in needed:
                    data = obj.read()
                    file = args.output / ('texture_' + str(obj.path_id) + '.png')
                    data.image.save(file)
                    result['textures'][str(obj.path_id)] = {
                        'name': data.m_Name, 'path': 'res://assets/environment_recovered/water/' + file.name,
                        'width': data.m_Width, 'height': data.m_Height,
                        'sha256': hashlib.sha256(file.read_bytes()).hexdigest()}
    descriptions = {p['m_Name']: p['m_Description'] for p in result['shader']['properties']}
    for material in materials.values():
        material['named_values'] = {descriptions[k]: v for values in (material['floats'], material['colors'])
                                    for k, v in values.items() if k in descriptions}
        material['bound_textures'] = {k: result['textures'].get(str(t['m_Texture']['m_PathID']), t['m_Texture'])
                                      for k, t in material['textures'].items() if t['m_Texture']['m_PathID']}
    (args.output / 'materials.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'materials': len(materials), 'textures': len(result['textures']), 'shader': result['shader']['name']}))


if __name__ == '__main__':
    main()
