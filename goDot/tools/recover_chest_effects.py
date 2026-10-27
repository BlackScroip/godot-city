#!/usr/bin/env python3
"""Recover chest prefab transforms and particle resources from the selected APK."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zipfile

import UnityPy

from inspect_camp_progression import Reader


ROOT = Path(__file__).resolve().parents[2]
APK_SHA = 'ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505'
NATIVE_SHA = '86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944'


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def evidence_json(value):
    if isinstance(value, float) and not math.isfinite(value):
        return 'NaN' if math.isnan(value) else 'Infinity' if value > 0 else '-Infinity'
    if isinstance(value, dict):
        return {k: evidence_json(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [evidence_json(v) for v in value]
    return value


def package_manifest(payload):
    reader = Reader(payload)
    reader.number('I')
    reader.string()
    for _ in range(3):
        reader.number('B')
    for _ in range(2):
        reader.number('i')
    header = [reader.string() for _ in range(4)]
    assets = []
    for _ in range(reader.number('i')):
        address, path, guid = [reader.string() for _ in range(3)]
        tags = reader.array(reader.string)
        bundle = reader.number('i')
        deps = reader.array(lambda: reader.number('i'))
        assets.append(dict(address=address, path=path, guid=guid, tags=tags,
                           bundle=bundle, deps=deps))
    bundles = []
    for _ in range(reader.number('i')):
        name = reader.string()
        flags = reader.number('I')
        bundle_hash, crc = reader.string(), reader.string()
        size, encrypted = reader.number('q'), reader.number('B')
        tags = reader.array(reader.string)
        deps = reader.array(lambda: reader.number('i'))
        bundles.append(dict(name=name, hash=bundle_hash, crc=crc, size=size,
                            flags=flags, encrypted=encrypted, tags=tags, deps=deps))
    assert reader.offset == len(payload)
    return dict(header=header, assets=assets, bundles=bundles)


def native_evidence(apk, native_path, metadata_path, stubs, output):
    import inspect_new_camp_native as native_tools

    native_tools.SELECTION = {
        'EnvUnitAbilityItemTreasureBox': [
            'InitByManager', 'SwitchTreasureBoxAnim', 'Update', 'OnDispose'],
        'EnvUnitAbilityItemTreasureBoxProperty': ['Deserialize', 'TreasureBoxProperty('],
    }
    native_tools.SELECTED_OFFSETS = set()
    native, metadata = native_path.read_bytes(), metadata_path.read_bytes()
    assert digest(native) == NATIVE_SHA, 'This bounded native audit requires the selected APK native version'
    with zipfile.ZipFile(apk) as archive:
        assert digest(native) == digest(archive.read('lib/arm64-v8a/libil2cpp.so'))
        assert metadata == archive.read('assets/bin/Data/Managed/Metadata/global-metadata.dat')
    result = native_tools.inspect(native_path, stubs)
    for method in result['methods']:
        offset, length = int(method['file_offset'], 16), method['length']
        method['code_sha256'] = digest(native[offset:offset + length])
        method['stub_sha256'] = digest(Path(method['stub']).read_bytes())
    result.update(apk_sha256=hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
                  metadata_sha256=digest(metadata))
    phoff = struct.unpack_from('<Q', native, 32)[0]
    entsize, count = struct.unpack_from('<HH', native, 54)
    segments = [struct.unpack_from('<IIQQQQQQ', native, phoff + i * entsize)
                for i in range(count)]

    def file_offset(va):
        return next(s[2] + va - s[3] for s in segments
                    if s[0] == 1 and s[3] <= va < s[3] + s[5])

    slots = set()
    for method in result['methods']:
        previous = None
        for instruction in method['instructions']:
            if instruction['op'] == 'adrp':
                match = re.fullmatch(r'(x\d+), #0x([0-9a-f]+)', instruction['args'])
                if match:
                    previous = (match[1], int(match[2], 16))
            elif instruction['op'] == 'ldr':
                match = re.fullmatch(r'x\d+, \[(x\d+), #0x([0-9a-f]+)\]', instruction['args'])
                if match and previous and match[1] == previous[0]:
                    slots.add(previous[1] + int(match[2], 16))
                previous = None
            else:
                previous = None
    shoff = struct.unpack_from('<Q', native, 40)[0]
    entsize, count = struct.unpack_from('<HH', native, 58)
    relocations = {}
    for i in range(count):
        section = struct.unpack_from('<IIQQQQIIQQ', native, shoff + i * entsize)
        if section[1] != 4:
            continue
        for off in range(section[4], section[4] + section[5], section[9]):
            target, info, addend = struct.unpack_from('<QQq', native, off)
            if target in slots and info == 1027:
                relocations[target] = (off, addend)
    sanity, version, table, table_size, data, data_size = struct.unpack_from('<6I', metadata)
    assert sanity == 0xFAB11BAF and version == 31
    literals = []
    for slot, (reloc, carrier) in sorted(relocations.items()):
        encoded = struct.unpack_from('<Q', native, file_offset(carrier))[0]
        if (encoded >> 29) & 7 != 5 or encoded & 1 != 1:
            continue
        index = (encoded >> 1) & 0xFFFFFFF
        assert index * 8 < table_size
        size, index_data = struct.unpack_from('<II', metadata, table + index * 8)
        assert index_data + size <= data_size
        raw = metadata[data + index_data:data + index_data + size]
        literals.append(dict(slot_va=hex(slot), relocation_file_offset=hex(reloc),
                             carrier_va=hex(carrier), encoded=hex(encoded), literal_index=index,
                             metadata_file_offset=hex(data + index_data), utf8=raw.decode('utf-8')))
    result['string_literals'] = literals
    result['metadata_declarations'] = [{
        'path': str(path), 'sha256': digest(path.read_bytes()), 'text': path.read_text()}
        for path in sorted(stubs.rglob('*.cs')) if path.stem in {
            'EnvUnitAbilityItemTreasureBox', 'EnvUnitAbilityItemTreasureBoxProperty',
            'ETreasureBoxType'}]
    result['limitations'] = ['Static ARM64 disassembly and metadata; no APK runtime observed.',
                             'Curse_Final rendering index normalization does not establish reward equivalence.']
    result['observations'] = [
        dict(id='curse-final-rendering-alias', method='InitByManager',
             file_range='0x31255c4-0x31255d4', va_range='0x31295c4-0x31295d4',
             detail='TreasureType4 selects rendering index3; other type values keep their index.'),
        dict(id='opening-effect-and-animation', method='<InitByManager>b__2',
             file_range='0x31267ac-0x312693c', va_range='0x312a7ac-0x312a93c',
             detail='Selects TypePrefabOpenFxList using the normalized index, plays the world-position effect, plays OpenSound, calls SwitchTreasureBoxAnim(true) and sets IsDisapper.'),
        dict(id='opening-animation-identity', method='SwitchTreasureBoxAnim',
             file_range='0x3125c5c-0x3125c7c', va_range='0x3129c5c-0x3129c7c',
             detail='Calls Animation.Play with literal anim_treasurebox_openthendisappear.'),
        dict(id='disappearance-delay', method='Update',
             file_range='0x3125b80-0x3125bb4', va_range='0x3129b80-0x3129bb4',
             detail='While IsDisapper is true, accumulates deltaTime and disposes when mDisapperTimer >= property.DisapperTime.'),
    ]
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(dict(native_evidence=str(output), methods=len(result['methods']),
                          string_count=len(literals)), ensure_ascii=False), flush=True)


def recover(apk, output, evidence_path, export_effects):
    prefabs = {}
    with zipfile.ZipFile(apk) as archive:
        member = next(n for n in archive.namelist() if n.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and n.endswith('.bytes'))
        payload = archive.read(member)
        manifest = package_manifest(payload)
        identity = dict(apk=str(apk), apk_sha256=hashlib.file_digest(
            apk.open('rb'), 'sha256').hexdigest(),
            manifest_member=member, manifest_sha256=digest(payload),
            manifest_header=manifest['header'])
        assert identity['apk_sha256'] == APK_SHA, 'This recovery is bound to the selected 1061664.apk version'
        config_asset = next(a for a in manifest['assets'] if a['address'] == 'EnvUnitCfg_[19001]')
        config_bundle = manifest['bundles'][config_asset['bundle']]
        config_member = 'assets/yoo/DefaultPackage/' + config_bundle['hash'] + '.bundle'
        config_payload = archive.read(config_member)
        config_obj = next(o for o in UnityPy.load(config_payload).objects
                          if o.type.name == 'TextAsset' and o.peek_name() == config_asset['address'])
        config_text = config_obj.read().m_Script
        if isinstance(config_text, bytes):
            config_text = config_text.decode('utf-8-sig')
        config = dict(address=config_asset['address'], path=config_asset['path'],
                      bundle_member=config_member, bundle_sha256=digest(config_payload),
                      text_sha256=digest(config_text.encode('utf-8')), data=json.loads(config_text))
        selected = [a for a in manifest['assets']
                    if a['address'].startswith('EnvUnit_TreasureBox_')]
        indices = set()
        pending = [i for a in selected for i in [a['bundle'], *a['deps']]]
        while pending:
            index = pending.pop()
            if index not in indices:
                indices.add(index)
                pending.extend(manifest['bundles'][index]['deps'])
        env = UnityPy.Environment()
        by_bundle, sources = {}, {}
        for index in sorted(indices):
            bundle = manifest['bundles'][index]
            bundle_member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
            raw = archive.read(bundle_member)
            loaded = env.load_file(raw, name=bundle_member)
            by_bundle[index] = [o for cab in loaded.files.values() if hasattr(cab, 'objects')
                                for o in cab.objects.values()]
            for cab in loaded.files.values():
                if hasattr(cab, 'objects'):
                    sources[cab.name] = dict(member=bundle_member, bundle_name=bundle['name'],
                                             bundle_hash=bundle['hash'], sha256=digest(raw),
                                             unity_version=str(cab.unity_version))
        objects = {(o.assets_file.name, o.path_id): o for o in env.objects}
        cache = {}

        def key(obj):
            return (obj.assets_file.name, obj.path_id)

        def tree(obj):
            if obj is None:
                return {}
            if key(obj) not in cache:
                cache[key(obj)] = obj.read_typetree()
            return cache[key(obj)]

        def resolve(obj, ref):
            if not ref or not ref.get('m_PathID'):
                return None
            file_id = ref.get('m_FileID', 0)
            filename = obj.assets_file.name if not file_id else obj.assets_file.externals[
                file_id - 1].path.rsplit('/', 1)[-1]
            return objects.get((filename, ref['m_PathID']))

        def source(obj):
            return '%s:%s' % key(obj)

        def pointer_name(obj, ref):
            other = resolve(obj, ref)
            if other is None:
                return None
            result = dict(type=other.type.name, source=source(other),
                          name=tree(other).get('m_Name', ''))
            if other.type.name in ('Transform', 'RectTransform'):
                go = resolve(other, tree(other).get('m_GameObject'))
                result['game_object'] = tree(go).get('m_Name', '')
            return result

        for asset in selected:
            bundle_objects = by_bundle[asset['bundle']]
            root = None
            for obj in bundle_objects:
                if obj.type.name == 'AssetBundle':
                    for path, entry in dict(tree(obj).get('m_Container', [])).items():
                        if path.lower() == asset['path'].lower():
                            root = resolve(obj, entry['asset'])
            if root is None:
                raise ValueError('Missing prefab: ' + asset['address'])
            nodes = []

            def walk(go, path, inherited_active):
                data = tree(go)
                path = path + [data['m_Name']]
                active = inherited_active and bool(data.get('m_IsActive', True))
                components = [resolve(go, c.get('component', c)) for c in data.get('m_Component', [])]
                components = [c for c in components if c]
                tr_obj = next(c for c in components if c.type.name in ('Transform', 'RectTransform'))
                tr = tree(tr_obj)
                record = dict(path='/'.join(path), name=data['m_Name'], source=source(go),
                              own_active=bool(data.get('m_IsActive', True)), active=active,
                              position=tr.get('m_LocalPosition'), rotation=tr.get('m_LocalRotation'),
                              scale=tr.get('m_LocalScale'), components=[])
                for component in components:
                    if component == tr_obj:
                        continue
                    component_tree = tree(component)
                    record['components'].append(dict(type=component.type.name, source=source(component)))
                    if component.type.name == 'MonoBehaviour':
                        fields = {k: v for k, v in component_tree.items() if not k.startswith('m_')}
                        pointers = {k: pointer_name(component, v) for k, v in fields.items()
                                    if isinstance(v, dict) and 'm_PathID' in v}
                        record['components'][-1].update(fields=fields, pointers=pointers)
                    elif component.type.name in ('Animator', 'ParticleSystemRenderer'):
                        record['components'][-1]['enabled'] = component_tree.get('m_Enabled')
                    elif component.type.name == 'ParticleSystem':
                        record['components'][-1].update(play_on_awake=component_tree.get('playOnAwake'),
                                                        looping=component_tree.get('looping'))
                    elif component.type.name == 'Animation':
                        clips = []
                        for reference in component_tree.get('m_Animations', []):
                            clip = resolve(component, reference)
                            clip_tree = tree(clip)
                            clips.append(dict(source=source(clip), name=clip_tree.get('m_Name'),
                                              curves={k: v for k, v in clip_tree.items() if
                                                      'Curve' in k or k in ('m_Events', 'm_AnimationClipSettings',
                                                                           'm_ClipBindingConstant')}))
                        record['components'][-1].update(animation_data=component_tree, clips=clips)
                nodes.append(record)
                for child in tr.get('m_Children', []):
                    child_tr = resolve(tr_obj, child)
                    walk(resolve(child_tr, tree(child_tr)['m_GameObject']), path, active)

            walk(root, [], True)
            prefabs[asset['address']] = dict(address=asset['address'], asset_path=asset['path'],
                                            source_root=source(root), source=sources[root.assets_file.name],
                                            nodes=nodes)
    output.parent.mkdir(parents=True, exist_ok=True)
    evidence = dict(**identity, config=config, prefabs=prefabs,
                    limitations=['Static package extraction; original app was not executed.',
                                 'Curse_Final has no distinct addressed prefab; native rendering-index normalization is retained separately.'])
    evidence_path.write_text(json.dumps(evidence_json(evidence), ensure_ascii=False,
                                       indent=2, allow_nan=False) + '\n')
    if export_effects:
        names = {n['name'] for p in prefabs.values() for n in p['nodes']
                 if '_fx_' in n['name']}
        names.update(a['address'] for a in manifest['assets']
                     if a['address'].startswith('2405060') and 'treasurebox' in a['address'])
        names.update(config['data']['EnvUnitData']['TypePrefabAppearFxList'])
        names &= {a['address'] for a in manifest['assets']}
        ambient_sources = {}
        for prefab in prefabs.values():
            ambient = next((n for n in prefab['nodes']
                            if '/Box_Effect/' in n['path'] and '_fx_' in n['name']), None)
            if ambient:
                ambient_sources[ambient['name']] = next(
                    a for a in selected if a['address'] == prefab['address'])
        for asset in manifest['assets']:
            if asset['address'] not in names:
                continue
            # Serialized chest instances remove pickup-icon children from the
            # reusable ambient prefab; export their actual embedded subtree.
            if asset['address'] in ambient_sources:
                chest_asset = ambient_sources[asset['address']]
                asset.update(path=chest_asset['path'], bundle=chest_asset['bundle'],
                             deps=list(chest_asset['deps']), subroot=asset['address'])
            deps, pending = set(asset['deps']), list(asset['deps'])
            while pending:
                dependency = pending.pop()
                for child in manifest['bundles'][dependency]['deps']:
                    if child not in deps:
                        deps.add(child)
                        pending.append(child)
            asset['deps'] = sorted(deps)
        with tempfile.TemporaryDirectory(prefix='city-selected-chest-') as temporary:
            temporary = Path(temporary)
            manifest_path, asset_list = temporary / 'manifest.json', temporary / 'effects.json'
            manifest_path.write_text(json.dumps(manifest))
            asset_list.write_text(json.dumps(sorted(names)))
            subprocess.run([sys.executable, str(Path(__file__).with_name('export_environment_effects.py')),
                            '--apk', str(apk), '--manifest', str(manifest_path),
                            '--asset-list', str(asset_list), '--output-directory', str(output.parent / 'chest'),
                            '--report', str(evidence_path.with_name('chest-particle-extraction.json'))], check=True)
        catalog = json.loads((output.parent / 'chest/catalog.json').read_text())
        config_data = config['data']['EnvUnitData']
        qualities = ('Normal', 'Unusual', 'Luxury', 'Curse')
        chests = {}
        for index, quality in enumerate(qualities):
            prefab = prefabs[config_data['TypePrefabList'][index]]
            box = next(n for n in prefab['nodes'] if n['name'] == 'Box_Effect')
            ambient = next(n for n in prefab['nodes']
                           if n['path'].startswith(box['path'] + '/') and '_fx_' in n['name'])
            chain = [n for n in prefab['nodes'] if n['path'].startswith(box['path']) and
                     (n['path'] == ambient['path'] or ambient['path'].startswith(n['path'] + '/'))]
            chests[quality] = dict(prefab=prefab['address'], ambient_effect=ambient['name'],
                                  ambient_transform_chain=[{k: n[k] for k in
                                                            ('position', 'rotation', 'scale')} for n in chain],
                                  ambient_active=ambient['active'],
                                  open_effect=config_data['TypePrefabOpenFxList'][index],
                                  appear_effect=config_data['TypePrefabAppearFxList'][index],
                                  open_hides_ambient_at_seconds=0.0,
                                  disappear_time_seconds=config_data['DisapperTime'],
                                  prefab_source=prefab['source'])
        chests['Curse_Final'] = dict(chests['Curse'], rendering_alias='Curse',
                                    native_normalization_file_offset='0x31255c4-0x31255d4')
        catalog.update(source_manifest={k: identity[k] for k in
                                      ('manifest_member', 'manifest_sha256', 'manifest_header')},
                       chests=chests, evidence_resource='res://reports/' + evidence_path.name)
        output.write_text(json.dumps(catalog, separators=(',', ':'), ensure_ascii=False) + '\n')
        print(json.dumps(dict(effects=sorted(names), output=str(output), evidence=str(evidence_path))))
    else:
        for name, prefab in prefabs.items():
            print(name, json.dumps([n for n in prefab['nodes'] if n['name'] == 'Box_Effect' or
                                   '_fx_' in n['name']], ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, default=ROOT / '1061664.apk')
    parser.add_argument('--output', type=Path, default=ROOT / 'goDot/assets/environment_effects/chest_catalog.json')
    parser.add_argument('--evidence', type=Path, default=ROOT / 'goDot/reports/chest-prefab-source.json')
    parser.add_argument('--export-effects', action='store_true')
    parser.add_argument('--native', type=Path)
    parser.add_argument('--metadata', type=Path)
    parser.add_argument('--stubs', type=Path)
    parser.add_argument('--native-only', action='store_true')
    args = parser.parse_args()
    if args.native:
        if not args.metadata or not args.stubs:
            parser.error('--native requires --metadata and --stubs')
        native_evidence(args.apk, args.native, args.metadata, args.stubs,
                        args.evidence.with_name('chest-native-source.json'))
    if not args.native_only:
        recover(args.apk, args.output, args.evidence, args.export_effects)
