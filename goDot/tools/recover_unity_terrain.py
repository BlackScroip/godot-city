#!/usr/bin/env python3
"""Decode authored camp/forest T2M controls and layer maps from the supplied APK."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import UnityPy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    objects, environments, provenance, terrains, layers = {}, [], [], {}, {}
    chosen = [b for b in manifest['bundles'] if b['id'] in (5497, 5500) or
              re.search(r'terrain_terraindata_(envdesignmap_maincity|levelmap_101)', b['name'])]
    with zipfile.ZipFile(args.apk) as archive:
        for bundle in chosen:
            member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
            raw = archive.read(member)
            env = UnityPy.load(raw)
            environments.append(env)
            provenance.append({'id': bundle['id'], 'member': member,
                               'sha256': hashlib.sha256(raw).hexdigest()})
            for obj in env.objects:
                if obj.type.name not in ('Texture2D', 'Material', 'TerrainData', 'TerrainLayer'):
                    continue
                objects[obj.path_id] = (obj, bundle['id'])
                if obj.type.name == 'TerrainData':
                    data = obj.read_typetree()
                    height = data['m_Heightmap']
                    scale, resolution = height['m_Scale'], height['m_Resolution']
                    terrains[data['m_Name']] = {
                        'path_id': obj.path_id, 'bundle': bundle['id'],
                        'size': [scale['x'] * (resolution - 1), scale['y'], scale['z'] * (resolution - 1)],
                        'splat_database': data['m_SplatDatabase']}
                if obj.type.name == 'TerrainLayer':
                    layers[str(obj.path_id)] = obj.read_typetree()
    exported = {}

    def texture(ref):
        ident = ref['m_PathID']
        if not ident:
            return None
        if ident not in exported:
            obj, bundle = objects[ident]
            data = obj.read()
            filename = 'texture_' + str(ident) + '.png'
            data.image.save(args.output / filename)
            exported[ident] = {'path': 'res://assets/environment_recovered/terrain/' + filename,
                              'name': data.m_Name, 'width': data.m_Width, 'height': data.m_Height,
                              'path_id': ident, 'bundle': bundle,
                              'sha256': hashlib.sha256((args.output / filename).read_bytes()).hexdigest()}
        return exported[ident]

    materials = {}
    for ident, (obj, bundle) in objects.items():
        if obj.type.name != 'Material':
            continue
        data = obj.read_typetree()
        props = data['m_SavedProperties']
        floats, colors, textures = map(dict, (props['m_Floats'], props['m_Colors'], props['m_TexEnvs']))
        if '_T2M_Layer_Count' not in floats:
            continue
        count = int(floats['_T2M_Layer_Count'])
        material = {'path_id': ident, 'bundle': bundle, 'shader': data['m_Shader'],
                    'layer_count': count, 'layers': [], 'controls': [],
                    'height_blend': floats.get('_T2M_EnableHeightBlend', 0),
                    'terrain': terrains.get(data['m_Name'].removesuffix(' Splatmap'))}
        for index in range(count):
            prefix = '_T2M_Layer_' + str(index)
            transform = colors[prefix + '_uvScaleOffset']
            uv = [transform[k] for k in 'rgba']
            material['layers'].append({'diffuse': texture(textures[prefix + '_Diffuse']['m_Texture']),
                'normal': texture(textures[prefix + '_NormalMap']['m_Texture']),
                'unity_uv_scale_offset': uv,
                'godot_uv_scale_offset': [uv[0], uv[1], uv[2], 1 - uv[1] - uv[3]],
                'tint': [colors[prefix + '_ColorTint'][k] for k in 'rgba'],
                'normal_scale': floats.get(prefix + '_NormalScale', 1)})
        for index in range((count + 3) // 4):
            material['controls'].append(texture(textures['_T2M_SplatMap_' + str(index)]['m_Texture']))
        materials[data['m_Name']] = material
    result = {'materials': materials, 'textures': list(exported.values()),
              'terrain_layers': layers, 'bundles': provenance,
              'uv_contract': 'Control texture uses GLB UV. Layer texture uses UV * godot_uv_scale_offset.xy + zw. Converter flips mesh V and UnityPy image decoding flips pixel rows; transformed V offset is 1 - Unity scale.y - Unity offset.y.',
              'method': 'Direct serialized APK T2M material texture references and UV transforms; PNGs are UnityPy image decoding only. No generated pixels or recoloring.'}
    (args.output / 'materials.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'materials': len(materials), 'textures': len(exported), 'bundles': len(chosen),
                      'output': str(args.output / 'materials.json')}))


if __name__ == '__main__':
    main()
