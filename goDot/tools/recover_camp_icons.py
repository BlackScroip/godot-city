"""Recover original construction and monster-work sprites from the supplied APK."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy
from PIL import Image, ImageDraw
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

from inspect_camp_progression import manifest_records


def digest(data):
    return hashlib.sha256(data).hexdigest()


def recover(apk, output):
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(n for n in archive.namelist() if n.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and n.endswith('.bytes'))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        lookup = {a['address']: a for a in assets}

        def read_bundle(index):
            name = 'assets/yoo/DefaultPackage/' + bundles[index]['hash'] + '.bundle'
            return name, archive.read(name)

        configs = {}
        config_sources = {}
        for name in ('RogueConfigData', 'MonsterWorkData'):
            member, payload = read_bundle(lookup[name]['bundle'])
            obj = next(o for o in UnityPy.load(payload).objects
                       if o.type.name == 'TextAsset' and o.peek_name() == name)
            text = obj.read().m_Script
            if isinstance(text, bytes):
                text = text.decode('utf-8-sig')
            configs[name] = json.loads(text)
            config_sources[name] = {'member': member, 'sha256': digest(payload),
                                    'path_id': str(obj.path_id)}

        building_names = sorted({n for b in configs['RogueConfigData']['MainCityDevelopDataList']
                                 for n in b['icon_name'].split('|') if n})
        jobs = []
        for job in configs['MonsterWorkData']:
            material = int(job['materia_id'])
            region = (material % 10000) // 100 if material > 9999 else 0
            jobs.append({'job_id': job['id'], 'material_id': material,
                         'icon': 'sprite_mosterwork_' + str(region)})
        names = sorted(set(building_names) | {j['icon'] for j in jobs})
        selected_bundles = sorted({lookup[name]['bundle'] for name in names})
        resources, records, images = {}, [], []
        for index in selected_bundles:
            member, payload = read_bundle(index)
            env = UnityPy.load(payload)
            sprites = {o.peek_name(): o for o in env.objects if o.type.name == 'Sprite'}
            for name in names:
                if lookup[name]['bundle'] != index:
                    continue
                obj = sprites[name]
                sprite = obj.read()
                picture = sprite.image.convert('RGBA')
                filename = name.replace(' ', '_') + '.png'
                target = output / filename
                picture.save(target)
                path = 'res://assets/ui/camp/' + filename
                resources[name] = path
                records.append({'name': name, 'path': path, 'source_asset': lookup[name]['path'],
                                'member': member, 'bundle_sha256': digest(payload),
                                'sprite_path_id': str(obj.path_id), 'width': picture.width,
                                'height': picture.height, 'png_sha256': digest(target.read_bytes()),
                                'alpha_bounds': picture.getchannel('A').getbbox()})
                images.append((name, picture))

        native = archive.read('lib/arm64-v8a/libil2cpp.so')
        off, size, va = 0x2D04358, 0x164, 0x2D08358
        instructions = [{'va': hex(i.address), 'mnemonic': i.mnemonic, 'operands': i.op_str}
                        for i in Cs(CS_ARCH_ARM64, CS_MODE_ARM).disasm(native[off:off + size], va)]
        metadata_name = 'assets/bin/Data/Managed/Metadata/global-metadata.dat'
        metadata = archive.read(metadata_name)
        literals_offset, literals_size, data_offset, data_size = struct.unpack_from('<4I', metadata, 8)
        literals = []
        for index in range(literals_size // 8):
            length, start = struct.unpack_from('<2I', metadata, literals_offset + index * 8)
            value = metadata[data_offset + start:data_offset + start + length].decode('utf-8', errors='replace')
            if 'mosterwork' in value:
                literals.append({'index': index, 'file_offset': data_offset + start, 'value': value})

    contact = Image.new('RGB', (6 * 220, ((len(images) + 5) // 6) * 190), '#253132')
    draw = ImageDraw.Draw(contact)
    for index, (name, picture) in enumerate(images):
        x, y = index % 6 * 220, index // 6 * 190
        preview = picture.copy()
        preview.thumbnail((160, 145))
        contact.paste(preview, (x + (220 - preview.width) // 2, y + 5), preview)
        label = name.replace('icon_maincitybulid_', 'build: ').replace('sprite_mosterwork_', 'work: ')
        draw.text((x + 8, y + 160), label, fill='white')
    contact.save(output / 'contact-sheet.png')
    provenance = {
        'apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
        'manifest': {'member': manifest_name, 'sha256': digest(manifest)},
        'config_sources': config_sources, 'sprites': records, 'jobs': jobs,
        'work_icon_rule': 'materia_id <= 9999: 0; otherwise floor((materia_id % 10000) / 100)',
        'work_icon_evidence': {'method': 'MonsterWorkData.GetIcon', 'file_offset': hex(off),
                               'length': size, 'va': hex(va), 'native_sha256': digest(native),
                               'instructions': instructions, 'metadata_member': metadata_name,
                               'metadata_sha256': digest(metadata), 'string_literals': literals},
        'limits': 'Static raw sprite extraction. Work icon mapping combines native arithmetic and matching metadata literals; no original runtime was launched. Contact sheet is a review montage, not a game asset.',
    }
    (output / 'resource_map.json').write_text(json.dumps(resources, indent=2) + '\n')
    (output / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(output), 'building_icons': len(building_names),
                      'jobs': len(jobs), 'unique_sprites': len(resources),
                      'all_nonblank': all(bool(r['alpha_bounds']) for r in records)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'assets/ui/camp')
    args = parser.parse_args()
    recover(args.apk, args.output)
