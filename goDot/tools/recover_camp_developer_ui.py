"""Extract a camp prefab's sprite references and RectTransform layout."""

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


def sha(data):
    return hashlib.sha256(data).hexdigest()


def recover(apk, output, prefab='ATPanel_MainCityDeveloper', folder='developer'):
    target = output / folder
    target.mkdir(parents=True, exist_ok=True)
    env = UnityPy.Environment()
    sources = {}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(n for n in archive.namelist() if n.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and n.endswith('.bytes'))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        asset = next(a for a in assets if a['address'] == prefab)
        # Re-read the complete manifest record for dependencies; the shared reader
        # retains only the identity fields needed by the first investigation.
        from inspect_camp_progression import Reader
        reader = Reader(manifest)
        reader.number('I')
        reader.string()
        for _ in range(3): reader.number('B')
        for _ in range(2): reader.number('i')
        for _ in range(4): reader.string()
        deps = []
        for _ in range(reader.number('i')):
            address, path, guid = [reader.string() for _ in range(3)]
            reader.array(reader.string)
            bundle = reader.number('i')
            dependencies = reader.array(lambda: reader.number('i'))
            if address == asset['address']:
                deps = dependencies
        primary_objects = []
        for index in [asset['bundle'], *deps]:
            member = 'assets/yoo/DefaultPackage/' + bundles[index]['hash'] + '.bundle'
            payload = archive.read(member)
            loaded = env.load_file(payload)
            for cab in loaded.files.values():
                if not hasattr(cab, 'objects'):
                    continue
                sources[cab.name] = {'member': member, 'sha256': sha(payload)}
                if index == asset['bundle']:
                    primary_objects.extend(cab.objects.values())

    trees = {o.path_id: o.read_typetree() for o in primary_objects
             if o.type.name in ('GameObject', 'RectTransform', 'Transform', 'MonoBehaviour')}
    gos = {o.path_id: trees[o.path_id] for o in primary_objects if o.type.name == 'GameObject'}
    transforms = {o.path_id: trees[o.path_id] for o in primary_objects
                  if o.type.name in ('RectTransform', 'Transform')}
    by_go = {t['m_GameObject']['m_PathID']: tid for tid, t in transforms.items()}

    def hierarchy(tid):
        if not tid or tid not in transforms:
            return ''
        t = transforms[tid]
        name = gos.get(t['m_GameObject']['m_PathID'], {}).get('m_Name', '?')
        parent = hierarchy(t.get('m_Father', {}).get('m_PathID', 0))
        return parent + '/' + name if parent else name

    rows, sprite_records, exported, controllers, errors, texts = [], [], {}, [], [], []
    for obj in primary_objects:
        if obj.type.name != 'MonoBehaviour':
            continue
        tree = trees[obj.path_id]
        go_id = tree['m_GameObject']['m_PathID']
        tid = by_go.get(go_id)
        path = hierarchy(tid)
        rect = transforms.get(tid, {})
        if 'm_text' in tree or 'm_Text' in tree:
            texts.append({'path': path, 'text': tree.get('m_text', tree.get('m_Text')),
                          'rect': rect, 'font_size': tree.get('m_fontSize', tree.get('m_FontSize'))})
        if 'Content_DeveloperSlot' in tree:
            controllers.append({'path': path, 'path_id': str(obj.path_id), 'fields': tree})
        if 'm_Sprite' not in tree:
            continue
        row = {'path': path, 'game_object': str(go_id), 'active': gos.get(go_id, {}).get('m_IsActive'),
               'rect': rect, 'color': tree.get('m_Color'), 'image_type': tree.get('m_Type'),
               'preserve_aspect': tree.get('m_PreserveAspect'), 'sprite': None}
        pointer = tree['m_Sprite']
        if pointer['m_PathID']:
            try:
                sprite_obj = PPtr(**pointer, assetsfile=obj.assets_file).deref()
                sprite = sprite_obj.read()
                name = sprite.m_Name
                row['sprite'] = name
                if name not in exported:
                    picture = sprite.image.convert('RGBA')
                    stem = re.sub(r'[^A-Za-z0-9_.-]', '_', name)
                    if stem != name:
                        stem += '_' + sha(name.encode())[:10]
                    filename = stem + '.png'
                    destination = target / filename
                    picture.save(destination)
                    respath = 'res://assets/ui/camp/' + folder + '/' + filename
                    exported[name] = (respath, picture)
                    sprite_records.append({'name': name, 'path': respath, 'sprite_path_id': str(sprite_obj.path_id),
                                           'source': sources.get(sprite_obj.assets_file.name),
                                           'width': picture.width, 'height': picture.height,
                                           'border': sprite.read_typetree().get('m_Border') if hasattr(sprite, 'read_typetree') else sprite_obj.read_typetree().get('m_Border'),
                                           'png_sha256': sha(destination.read_bytes())})
            except Exception as error:
                errors.append({'path': path, 'pointer': pointer, 'error': str(error)})
        rows.append(row)
    layout = {'prefab': asset, 'source': sources[primary_objects[0].assets_file.name],
              'apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
              'images': rows, 'texts': texts, 'controller': controllers, 'sprites': sprite_records,
              'transforms': [{'path': hierarchy(tid), 'path_id': str(tid), 'data': t}
                             for tid, t in transforms.items()], 'errors': errors,
              'limit': 'Serialized initial prefab. Runtime texts and enabled states can differ. Unity coordinates use upward positive Y.'}
    (target / 'prefab-layout.json').write_text(json.dumps(layout, ensure_ascii=False, indent=2) + '\n')
    mapping_path = output / 'resource_map.json'
    mapping = json.loads(mapping_path.read_text()) if mapping_path.exists() else {}
    mapping.update({name: data[0] for name, data in exported.items()
                    if name not in mapping or '/camp/' + folder + '/' in mapping[name]})
    mapping_path.write_text(json.dumps(mapping, indent=2) + '\n')
    provenance_path = output / 'provenance.json'
    provenance = json.loads(provenance_path.read_text()) if provenance_path.exists() else {}
    provenance[folder + '_panel'] = {'layout': folder + '/prefab-layout.json',
                                     'source': layout['source'], 'sprites': sprite_records,
                                     'errors': errors}
    provenance_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    ordered = sorted(exported.items())
    contact = Image.new('RGB', (6 * 240, ((len(ordered) + 5) // 6) * 190), '#728382')
    draw = ImageDraw.Draw(contact)
    for i, (name, (respath, picture)) in enumerate(ordered):
        x, y = i % 6 * 240, i // 6 * 190
        preview = picture.copy()
        preview.thumbnail((220, 150))
        contact.paste(preview, (x + (240 - preview.width) // 2, y), preview)
        draw.text((x + 4, y + 154), name[:38], fill='black')
    contact.save(target / 'contact-sheet.png')
    print(json.dumps({'images': len(rows), 'sprites': len(sprite_records), 'errors': errors,
                      'layout': str(target / 'prefab-layout.json')}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'assets/ui/camp')
    parser.add_argument('--prefab', default='ATPanel_MainCityDeveloper')
    parser.add_argument('--folder', default='developer')
    args = parser.parse_args()
    recover(args.apk, args.output, args.prefab, args.folder)
