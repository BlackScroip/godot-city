"""Recover the packaged route-selection atlas with source identities.

Requires UnityPy and the dependencies of inspect_camp_progression. This reads
the APK statically; it does not launch the original game.
"""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr
from PIL import Image, ImageDraw

from inspect_camp_progression import Reader, manifest_records


FILENAMES = {
    '\u672a\u9009\u8def\u5f84\uff08\u659c\uff09': 'path_diagonal_unavailable',
    '\u53ef\u9009\u8def\u5f84\uff08\u659c\uff09': 'path_diagonal_available',
    '\u5730\u56fe\u8282\u70b92': 'node_2',
    '\u5730\u56fe\u8282\u70b9_\u9009\u4e2d\u6846': 'node_selected_frame',
    '\u672a\u9009\u8def\u5f84': 'path_unavailable',
    'b': 'node_background',
    '\u7bad\u5934_\u53f3(\u6fc0\u6d3b)': 'arrow_right_active',
    '\u5df2\u9009\u623f\u95f4': 'room_passed',
    '\u8d70\u8fc7\u8def\u5f84': 'path_passed',
    '\u7bad\u5934_\u4e0b': 'arrow_down',
    '\u53ef\u9009\u8def\u5f84': 'path_available',
    '\u5730\u56fe\u8282\u70b91': 'node_1',
    '\u5730\u56fe\u8282\u70b9_\u5f53\u524d': 'node_current',
    '\u53ef\u9009\u623f\u95f4': 'room_available',
    '\u8d70\u8fc7\u8def\u5f84\uff08\u659c\uff09': 'path_diagonal_passed',
    '\u7bad\u5934_\u53f3(\u672a\u6fc0\u6d3b)': 'arrow_right_inactive',
    '\u7bad\u5934_\u53f3\u4e0a(\u6fc0\u6d3b)': 'arrow_up_right_active',
    '\u7bad\u5934_\u53f3\u4e0a(\u672a\u6fc0\u6d3b)': 'arrow_up_right_inactive',
    '\u7bad\u5934_\u4e0a': 'arrow_up',
}

WORLD_FILENAMES = {
    '\u5c01\u9b54\u56fe\u6807': 'world_seal',
    '\u672a\u77e5\u56fe\u6807': 'world_unknown',
    '\u68ee\u6797\u56fe\u6807': 'world_forest',
    '\u6c99\u6f20\u56fe\u6807': 'world_desert',
    '\u6d77\u5c9b\u56fe\u6807': 'world_island',
    '\u7194\u5ca9\u56fe\u6807': 'world_lava',
    '\u77ff\u573a\u56fe\u6807': 'world_mine',
    '\u8425\u5730\u56fe\u68073': 'world_camp',
    '\u96ea\u5c71\u56fe\u6807': 'world_snow',
    **{'Bg' + str(index): 'world_background_' + str(index) for index in range(8)},
}

WORLD_WIDGET_FILENAMES = {
    '\u573a\u666fui\u5e95\u7eb9': 'world_node_frame',
    '\u573a\u666fui\u5e95\u7eb9_active': 'world_node_frame_active',
    '\u9501\u5934': 'world_lock',
    'buff_LockHP': 'world_unopen',
    '\u672a\u9009\u8def\u5f84\uff08\u659c\uff09_1': 'world_path_dotted',
    '\u672a\u9009\u8def\u5f84\uff08\u659c\uff09_2': 'world_path_cross',
    '\u8d70\u8fc7\u8def\u5f84\uff08\u659c\uff09_1': 'world_path_dotted_passed',
}


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def package_dependencies(manifest, target):
    reader = Reader(manifest)
    reader.number('I')
    reader.string()
    for _ in range(3):
        reader.number('B')
    for _ in range(2):
        reader.number('i')
    for _ in range(4):
        reader.string()
    asset_deps = None
    for _ in range(reader.number('i')):
        address, path, guid = [reader.string() for _ in range(3)]
        reader.array(reader.string)
        reader.number('i')
        dependencies = reader.array(lambda: reader.number('i'))
        if address == target:
            asset_deps = dependencies
    bundle_deps = []
    for _ in range(reader.number('i')):
        reader.string()
        reader.number('I')
        reader.string()
        reader.string()
        reader.number('q')
        reader.number('B')
        reader.array(reader.string)
        bundle_deps.append(reader.array(lambda: reader.number('i')))
    if asset_deps is None:
        raise ValueError('Asset not found: ' + target)
    return asset_deps, bundle_deps


def node_state_layout(objects):
    def deref(pointer, owner):
        return PPtr(**pointer, assetsfile=owner.assets_file).deref()

    def transform_sprites(transform):
        tree = transform.read_typetree()
        game_object = deref(tree['m_GameObject'], transform)
        go_tree = game_object.read_typetree()
        result = []
        for component in go_tree['m_Component']:
            obj = deref(component['component'], game_object)
            if obj.type.name != 'MonoBehaviour':
                continue
            sprite_pointer = obj.read_typetree().get('m_Sprite')
            if sprite_pointer and sprite_pointer['m_PathID']:
                sprite = deref(sprite_pointer, obj)
                result.append({'game_object': go_tree['m_Name'], 'sprite': sprite.peek_name(),
                               'sprite_path_id': str(sprite.path_id)})
        for child in tree.get('m_Children', []):
            result.extend(transform_sprites(deref(child, transform)))
        return result

    for obj in objects:
        if obj.type.name != 'MonoBehaviour':
            continue
        tree = obj.read_typetree()
        if 'stateArray_NoReachable' not in tree:
            continue
        states = {key: [sprite for pointer in pointers
                        for sprite in transform_sprites(deref(pointer, obj))]
                  for key, pointers in tree.items() if key.startswith('stateArray_')}
        return {'controller_path_id': str(obj.path_id), 'states': states,
                'selected': transform_sprites(deref(tree['box_Selected'], obj))}
    raise ValueError('ATSlot_RoadMapNode state controller not found')


def recover(apk, output):
    output.mkdir(parents=True, exist_ok=True)
    env = UnityPy.Environment()
    sources = {}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(n for n in archive.namelist() if n.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and n.endswith('.bytes'))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        asset = next(a for a in assets if a['address'] == 'SpriteAtlas_RoadMapSelect')
        node_asset = next(a for a in assets if a['address'] == 'ATSlot_RoadMapNode')
        asset_deps, bundle_deps = package_dependencies(manifest, asset['address'])
        node_deps, _ = package_dependencies(manifest, node_asset['address'])
        pending = [asset['bundle'], *asset_deps, node_asset['bundle'], *node_deps]
        indices = set()
        while pending:
            index = pending.pop()
            if index not in indices:
                indices.add(index)
                pending.extend(bundle_deps[index])
        node_objects = []
        for index in sorted(indices):
            bundle = bundles[index]
            member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
            payload = archive.read(member)
            loaded = env.load_file(payload)
            for cab in loaded.files.values():
                if hasattr(cab, 'objects'):
                    sources[cab.name] = {'member': member, 'bundle_name': bundle['name'],
                                         'bundle_hash': bundle['hash'], 'sha256': sha(payload)}
                    if index == node_asset['bundle']:
                        node_objects.extend(cab.objects.values())

    atlas_obj = next(o for o in env.objects if o.type.name == 'SpriteAtlas'
                     and o.peek_name() == asset['address'])
    atlas = atlas_obj.read()
    records, resources, previews = [], {}, []
    for name, pointer in zip(atlas.m_PackedSpriteNamesToIndex, atlas.m_PackedSprites):
        sprite_obj = pointer.deref()
        sprite = sprite_obj.read()
        if sprite.m_Name != name:
            raise ValueError('Atlas sprite identity mismatch: ' + name)
        picture = sprite.image.convert('RGBA')
        filename = FILENAMES[name] + '.png'
        target = output / filename
        picture.save(target)
        resources[name] = 'res://assets/ui/route/' + filename
        records.append({'name': name, 'path': resources[name],
                        'sprite_path_id': str(sprite_obj.path_id),
                        'source': sources[sprite_obj.assets_file.name],
                        'sprite_rect': sprite_obj.read_typetree()['m_Rect'],
                        'width': picture.width, 'height': picture.height,
                        'png_sha256': sha(target.read_bytes()),
                        'alpha_bounds': picture.getchannel('A').getbbox()})
        previews.append((FILENAMES[name], picture))

    provenance = {
        'apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
        'manifest': {'member': manifest_name, 'sha256': sha(manifest)},
        'atlas': {'address': asset['address'], 'path': asset['path'],
                  'path_id': str(atlas_obj.path_id),
                  'source': sources[atlas_obj.assets_file.name]},
        'node_prefab': {'address': node_asset['address'], 'path': node_asset['path'],
                        'source': sources[node_objects[0].assets_file.name],
                        **node_state_layout(node_objects)},
        'sprites': records,
        'limits': 'Static raw atlas recovery. Names do not establish runtime state. '
                  'This package predates the supplied October world-map screenshot; '
                  'the recovered atlas contains room cards and paths, not world-region icons.'}
    (output / 'resource_map.json').write_text(json.dumps(resources, ensure_ascii=False, indent=2) + '\n')
    (output / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    contact = Image.new('RGB', (5 * 280, 4 * 180), '#31423c')
    draw = ImageDraw.Draw(contact)
    for index, (name, picture) in enumerate(previews):
        x, y = index % 5 * 280, index // 5 * 180
        preview = picture.copy()
        preview.thumbnail((260, 140))
        contact.paste(preview, (x + (280 - preview.width) // 2, y + 5), preview)
        draw.text((x + 6, y + 151), name, fill='white')
    contact.save(output / 'contact-sheet.png')
    print(json.dumps({'sprites': len(records), 'output': str(output)}))


def recover_world(apk, output):
    """Add October world art without replacing the recovered August atlas."""
    output.mkdir(parents=True, exist_ok=True)
    records, resources, previews = [], {}, []
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(n for n in archive.namelist() if n.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and n.endswith('.bytes'))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        lookup = {asset['address']: asset for asset in assets}
        names = [name for name in WORLD_FILENAMES if name in lookup]
        if not names:
            raise ValueError('This package has no world-region art')
        for index in sorted({lookup[name]['bundle'] for name in names}):
            bundle = bundles[index]
            member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
            payload = archive.read(member)
            env = UnityPy.load(payload)
            sprites = {obj.peek_name(): obj for obj in env.objects if obj.type.name == 'Sprite'}
            for name in names:
                if lookup[name]['bundle'] != index:
                    continue
                obj = sprites[name]
                sprite = obj.read()
                picture = sprite.image.convert('RGBA')
                filename = WORLD_FILENAMES[name] + '.png'
                target = output / filename
                picture.save(target)
                path = 'res://assets/ui/route/' + filename
                resources[name] = path
                records.append({'name': name, 'path': path, 'source_asset': lookup[name]['path'],
                                'source': {'member': member, 'bundle_name': bundle['name'],
                                           'bundle_hash': bundle['hash'], 'sha256': sha(payload)},
                                'sprite_path_id': str(obj.path_id),
                                'sprite_rect': obj.read_typetree()['m_Rect'],
                                'width': picture.width, 'height': picture.height,
                                'png_sha256': sha(target.read_bytes()),
                                'alpha_bounds': picture.getchannel('A').getbbox()})
                previews.append((WORLD_FILENAMES[name], picture))

        widget_resources, widget_records, widget_previews, prefab = recover_world_widgets(
            archive, assets, bundles, manifest, output)
        resources.update(widget_resources)
        records.extend(widget_records)
        previews.extend(widget_previews)

    provenance_path = output / 'provenance.json'
    provenance = json.loads(provenance_path.read_text()) if provenance_path.exists() else {}
    provenance['world_map'] = {
        'apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
        'manifest': {'member': manifest_name, 'sha256': sha(manifest)},
        'sprites': records,
        'region_prefab': prefab,
        'limits': 'Static raw world-region sprites and region preview backgrounds from the October package.'}
    provenance_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    mapping_path = output / 'resource_map.json'
    mapping = json.loads(mapping_path.read_text()) if mapping_path.exists() else {}
    mapping.update(resources)
    mapping_path.write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + '\n')
    contact = Image.new('RGB', (5 * 240, ((len(previews) + 4) // 5) * 190), '#31423c')
    draw = ImageDraw.Draw(contact)
    for index, (name, picture) in enumerate(previews):
        x, y = index % 5 * 240, index // 5 * 190
        preview = picture.copy()
        preview.thumbnail((220, 150))
        contact.paste(preview, (x + (240 - preview.width) // 2, y + 5), preview)
        draw.text((x + 6, y + 160), name, fill='white')
    contact.save(output / 'world-contact-sheet.png')
    print(json.dumps({'world_sprites': len(records), 'output': str(output)}))


def recover_world_widgets(archive, assets, bundles, manifest, output):
    asset = next(a for a in assets if a['address'] == 'ATPanel_RegionMapSelect')
    asset_deps, bundle_deps = package_dependencies(manifest, asset['address'])
    pending, indices = [asset['bundle'], *asset_deps], set()
    while pending:
        index = pending.pop()
        if index not in indices:
            indices.add(index)
            pending.extend(bundle_deps[index])
    env, sources, primary = UnityPy.Environment(), {}, []
    for index in sorted(indices):
        bundle = bundles[index]
        member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
        payload = archive.read(member)
        loaded = env.load_file(payload)
        for cab in loaded.files.values():
            if not hasattr(cab, 'objects'):
                continue
            sources[cab.name] = {'member': member, 'bundle_name': bundle['name'],
                                 'bundle_hash': bundle['hash'], 'sha256': sha(payload)}
            if index == asset['bundle']:
                primary.extend(cab.objects.values())
    resources, records, previews, references, seen = {}, [], [], [], set()
    prefab = {'address': asset['address'], 'path': asset['path'],
              'source': sources[primary[0].assets_file.name]}
    for obj in primary:
        if obj.type.name != 'MonoBehaviour':
            continue
        tree = obj.read_typetree()
        if 'mColumnNodeSpace' in tree:
            prefab.update(controller_path_id=str(obj.path_id), layout={key: tree[key] for key in (
                'mColumnNodeSpace', 'mLineNodeSpace', 'mMapMargin', 'mGroupSize', 'mExtraScrollWidth')})
        pointer = tree.get('m_Sprite')
        if not pointer or not pointer['m_PathID']:
            continue
        sprite_obj = PPtr(**pointer, assetsfile=obj.assets_file).deref()
        name = sprite_obj.peek_name()
        if name not in WORLD_WIDGET_FILENAMES:
            continue
        go = PPtr(**tree['m_GameObject'], assetsfile=obj.assets_file).read()
        reference = {'game_object': go.m_Name, 'sprite': name, 'color': tree.get('m_Color')}
        if reference not in references:
            references.append(reference)
        if name in seen:
            continue
        seen.add(name)
        sprite = sprite_obj.read()
        picture = sprite.image.convert('RGBA')
        filename = WORLD_WIDGET_FILENAMES[name] + '.png'
        target = output / filename
        picture.save(target)
        resources[name] = 'res://assets/ui/route/' + filename
        records.append({'name': name, 'path': resources[name],
                        'source': sources[sprite_obj.assets_file.name],
                        'sprite_path_id': str(sprite_obj.path_id),
                        'sprite_rect': sprite_obj.read_typetree()['m_Rect'],
                        'width': picture.width, 'height': picture.height,
                        'png_sha256': sha(target.read_bytes()),
                        'alpha_bounds': picture.getchannel('A').getbbox()})
        previews.append((WORLD_WIDGET_FILENAMES[name], picture))
    missing = set(WORLD_WIDGET_FILENAMES) - seen
    if missing:
        raise ValueError('Missing world widget sprites: ' + ', '.join(sorted(missing)))
    prefab['widget_image_references'] = references
    return resources, records, previews, prefab


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'assets/ui/route')
    parser.add_argument('--world-only', action='store_true',
                        help='Add world icons and backgrounds without replacing existing route art')
    args = parser.parse_args()
    if args.world_only:
        recover_world(args.apk, args.output)
    else:
        recover(args.apk, args.output)
