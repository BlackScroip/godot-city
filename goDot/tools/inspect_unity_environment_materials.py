#!/usr/bin/env python3
"""Read shipped Unity environment materials without changing game assets.

Requires UnityPy (available in /private/tmp/city-charge-pydeps) and the parsed
YooAsset manifest produced by the earlier APK investigation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    evidence = {'method': 'Static UnityPy serialized object parsing; not runtime observation',
                'apk': str(args.apk.resolve()), 'bundles': [], 'materials': {},
                'textures': {}, 'shaders': {}, 'duplicate_material_names': {}, 'limitations': [
                    'Serialized settings may include stale fields not active in shader variants.',
                    'No runtime lighting uniforms, scene lights or post-processing were sampled.']}
    with zipfile.ZipFile(args.apk) as archive:
        for bundle_id in (1, 5498, 5500, 5852):
            entry = manifest['bundles'][bundle_id]
            member = 'assets/yoo/DefaultPackage/' + entry['hash'] + '.bundle'
            raw = archive.read(member)
            evidence['bundles'].append({'id': bundle_id, 'member': member,
                                        'sha256': hashlib.sha256(raw).hexdigest()})
            env = UnityPy.load(raw)
            for obj in env.objects:
                if obj.type.name not in ('Material', 'Texture2D', 'Shader'):
                    continue
                data = obj.read_typetree()
                common = {'bundle': bundle_id, 'path_id': obj.path_id,
                          'serialized_file': obj.assets_file.name}
                if obj.type.name == 'Material':
                    props = data['m_SavedProperties']
                    material = dict(common,
                        shader=data['m_Shader'], keywords=data.get('m_ValidKeywords', []),
                        invalid_keywords=data.get('m_InvalidKeywords', []),
                        render_queue=data.get('m_CustomRenderQueue'),
                        disabled_passes=data.get('disabledShaderPasses'),
                        colors=dict(props['m_Colors']), floats=dict(props['m_Floats']),
                        textures=dict(props['m_TexEnvs']),
                        externals=[x.path for x in obj.assets_file.externals])
                    name = data['m_Name']
                    if name in evidence['materials']:
                        evidence['duplicate_material_names'].setdefault(name, []).append(material)
                    else:
                        evidence['materials'][name] = material
                elif obj.type.name == 'Texture2D':
                    evidence['textures'][str(obj.path_id)] = dict(common,
                        name=data['m_Name'], width=data['m_Width'], height=data['m_Height'],
                        format=data['m_TextureFormat'], mips=data['m_MipCount'],
                        color_space=data.get('m_ColorSpace'), settings=data['m_TextureSettings'])
                elif obj.path_id == -8143037723478795692:
                    parsed = data.get('m_ParsedForm', {})
                    evidence['shaders'][str(obj.path_id)] = dict(common,
                        name=parsed.get('m_Name', data.get('m_Name')),
                        properties=parsed.get('m_PropInfo'),
                        subshaders=parsed.get('m_SubShaders'),
                        platforms=data.get('platforms'))
    for mat in evidence['materials'].values():
        for tex in mat['textures'].values():
            ident = str(tex['m_Texture']['m_PathID'])
            if ident in evidence['textures']:
                tex['resolved'] = evidence['textures'][ident]
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'materials': len(evidence['materials']),
                      'textures': len(evidence['textures']), 'shaders': len(evidence['shaders'])}))


if __name__ == '__main__':
    main()
