"""Recover the October adventure preparation prefab's original UI sprites.

Requires UnityPy, Pillow and inspect_camp_progression dependencies. This is
static extraction and does not launch the Android game.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr
from PIL import Image, ImageDraw

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


TARGETS = ('ATPanel_RogueLevelDifficulty', 'ATBox_RogueDifficultyHeat')


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def output_stem(name):
    readable = re.sub(r'[^A-Za-z0-9]+', '_', name).strip('_').lower()
    if readable and len(readable) > len(name) / 2:
        return readable[:80]
    return 'sprite_' + digest(name.encode())[:12]


def recover(apk, output, evidence):
    output.mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    resources, sprite_records, prefab_records, previews = {}, [], [], []
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and name.endswith('.bytes'))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        lookup = {asset['address']: asset for asset in assets}
        pending, indices = [], set()
        for name in TARGETS:
            dependencies, bundle_dependencies = package_dependencies(manifest, name)
            pending.extend([lookup[name]['bundle'], *dependencies])
        while pending:
            index = pending.pop()
            if index in indices:
                continue
            indices.add(index)
            pending.extend(bundle_dependencies[index])
        env, sources, primary = UnityPy.Environment(), {}, {}
        for index in sorted(indices):
            bundle = bundles[index]
            member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
            payload = archive.read(member)
            loaded = env.load_file(payload)
            objects = []
            for cab in loaded.files.values():
                if not hasattr(cab, 'objects'):
                    continue
                sources[cab.name] = {'member': member, 'bundle_name': bundle['name'],
                                     'bundle_hash': bundle['hash'], 'sha256': digest(payload)}
                objects.extend(cab.objects.values())
            for name in TARGETS:
                if lookup[name]['bundle'] == index:
                    primary[name] = objects

        seen, sprite_resources, name_owners = set(), {}, {}
        for name in TARGETS:
            objects = primary[name]
            transforms, game_objects = {}, {}
            for obj in objects:
                if obj.type.name in ('Transform', 'RectTransform'):
                    tree = obj.read_typetree()
                    transforms[str(tree['m_GameObject']['m_PathID'])] = tree
                elif obj.type.name == 'GameObject':
                    game_objects[str(obj.path_id)] = obj.read_typetree()

            def hierarchy(go_id):
                go_id = str(go_id)
                go_name = game_objects.get(go_id, {}).get('m_Name', '')
                transform = transforms.get(go_id)
                if not transform:
                    return go_name
                father = transform['m_Father']
                if not father['m_PathID']:
                    return go_name
                parent = PPtr(**father, assetsfile=objects[0].assets_file).deref()
                parent_id = parent.read_typetree()['m_GameObject']['m_PathID']
                return hierarchy(parent_id) + '/' + go_name

            images, texts, controllers = [], [], []
            for obj in objects:
                if obj.type.name != 'MonoBehaviour':
                    continue
                tree = obj.read_typetree()
                go_id = tree.get('m_GameObject', {}).get('m_PathID', 0)
                path = hierarchy(go_id)
                pointer = tree.get('m_Sprite')
                if pointer and pointer['m_PathID']:
                    sprite_obj = PPtr(**pointer, assetsfile=obj.assets_file).deref()
                    sprite = sprite_obj.read()
                    source = sources[sprite_obj.assets_file.name]
                    key = (source['member'], str(sprite_obj.path_id))
                    if key in sprite_resources:
                        resource = sprite_resources[key]
                        filename = Path(resource).name
                    else:
                        stem = output_stem(sprite.m_Name)
                        if sprite.m_Name in name_owners and name_owners[sprite.m_Name] != key:
                            stem += '_' + digest(str(key).encode())[:8]
                        filename = stem + '.png'
                        resource = 'res://assets/ui/prepare/' + filename
                        sprite_resources[key] = resource
                        name_owners.setdefault(sprite.m_Name, key)
                    images.append({'object_path': path, 'component_path_id': str(obj.path_id),
                                   'sprite': sprite.m_Name, 'resource': resource,
                                   'color': tree.get('m_Color'), 'image_type': tree.get('m_Type'),
                                   'enabled': tree.get('m_Enabled'),
                                   'rect_transform': transforms.get(str(go_id))})
                    if key in seen:
                        continue
                    seen.add(key)
                    picture = sprite.image.convert('RGBA')
                    target = output / filename
                    picture.save(target)
                    if sprite.m_Name in resources and resources[sprite.m_Name] != resource:
                        resources[sprite.m_Name + '#' + str(sprite_obj.path_id)] = resource
                    else:
                        resources[sprite.m_Name] = resource
                    sprite_records.append({'name': sprite.m_Name, 'path': resource,
                                           'source': source, 'sprite_path_id': str(sprite_obj.path_id),
                                           'sprite_rect': sprite_obj.read_typetree()['m_Rect'],
                                           'border': sprite_obj.read_typetree().get('m_Border'),
                                           'width': picture.width, 'height': picture.height,
                                           'png_sha256': digest(target.read_bytes()),
                                           'alpha_bounds': picture.getchannel('A').getbbox()})
                    previews.append((filename[:-4], picture))
                elif 'm_Text' in tree or 'm_text' in tree:
                    texts.append({'object_path': path, 'text': tree.get('m_Text', tree.get('m_text')),
                                  'component_path_id': str(obj.path_id),
                                  'font_size': tree.get('m_fontSize', tree.get('m_FontData', {}).get('m_FontSize')),
                                  'color': tree.get('m_Color'),
                                  'rect_transform': transforms.get(str(go_id))})
                elif not set(tree).issubset({'m_GameObject', 'm_Enabled', 'm_Script', 'm_Name',
                                             'm_EditorClassIdentifier'}):
                    controllers.append({'object_path': path, 'path_id': str(obj.path_id), 'fields': tree})
            record = {'address': name, 'source_asset': lookup[name]['path'],
                      'source': sources[objects[0].assets_file.name],
                      'images': images, 'texts': texts, 'controllers': controllers}
            prefab_records.append(record)
            (evidence / (name + '.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
            roots = [row for row in controllers if row['object_path'] == name]
            (evidence / (name + '.root-controller.json')).write_text(
                json.dumps(roots, ensure_ascii=False, indent=2) + '\n')
            layout = [{'path_id': go_id, 'object_path': hierarchy(go_id),
                       'active': game_objects[go_id].get('m_IsActive'),
                       'rect': {key: value for key, value in transform.items()
                                if key not in ('m_Children', 'm_GameObject', 'm_Father')}}
                      for go_id, transform in transforms.items() if go_id in game_objects]
            (evidence / (name + '.layout.json')).write_text(
                json.dumps(layout, ensure_ascii=False, indent=2) + '\n')

    provenance = {
        'apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
        'manifest': {'member': manifest_name, 'sha256': digest(manifest)},
        'prefabs': [{'address': row['address'], 'source_asset': row['source_asset'],
                     'source': row['source'], 'image_count': len(row['images'])}
                    for row in prefab_records],
        'sprites': sprite_records,
        'limits': 'Raw prefab-referenced sprites. Runtime text, portraits and selected weapon icons can be assigned dynamically.',
    }
    (output / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    (output / 'resource_map.json').write_text(json.dumps(resources, ensure_ascii=False, indent=2) + '\n')
    contact = Image.new('RGB', (5 * 240, ((len(previews) + 4) // 5) * 190), '#34433b')
    draw = ImageDraw.Draw(contact)
    for index, (label, picture) in enumerate(previews):
        x, y = index % 5 * 240, index // 5 * 190
        preview = picture.copy()
        preview.thumbnail((220, 150))
        contact.paste(preview, (x + (240 - preview.width) // 2, y + 5), preview)
        draw.text((x + 6, y + 160), label[:32], fill='white')
    contact.save(output / 'contact-sheet.png')
    print(json.dumps({'sprites': len(sprite_records), 'output': str(output),
                      'prefabs': {row['address']: {'images': len(row['images']), 'texts': len(row['texts']),
                                                  'controllers': len(row['controllers'])}
                                  for row in prefab_records}}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'assets/ui/prepare')
    parser.add_argument('--evidence', type=Path, default=Path('/private/tmp/city-new-progression-evidence'))
    args = parser.parse_args()
    recover(args.apk, args.output, args.evidence)
