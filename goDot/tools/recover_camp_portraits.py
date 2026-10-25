"""Recover original camp portraits, material icons and interaction symbols."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import manifest_records


def digest(data):
    return hashlib.sha256(data).hexdigest()


def recover(apk, output):
    target = output / 'portraits'
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(n for n in archive.namelist() if n.startswith(
            'assets/yoo/DefaultPackage/DefaultPackage_') and n.endswith('.bytes'))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        config_asset = next(a for a in assets if a['address'] == 'TextPrintersConfiguration')
        config_member = 'assets/yoo/DefaultPackage/' + bundles[config_asset['bundle']]['hash'] + '.bundle'
        config_payload = archive.read(config_member)
        config_env = UnityPy.load(config_payload)
        config_object = next(o for o in config_env.objects if o.type.name == 'MonoBehaviour'
                             and o.read_typetree().get('m_Name') == 'TextPrintersConfiguration')
        config = config_object.read_typetree()
        printer_evidence = {'member': config_member, 'sha256': digest(config_payload),
                            'path_id': str(config_object.path_id),
                            'default_printer_id': config['DefaultPrinterId'],
                            'default_metadata': config['DefaultMetadata']}
        selected = [a for a in assets if a['address'].startswith(('sprite_materialicon_', 'sprite_conversation_'))
                    or (a['address'].startswith('characterillustration_')
                        and a['address'].endswith('_normal'))]
        records, mapping = [], {}
        for index in sorted({a['bundle'] for a in selected}):
            member = 'assets/yoo/DefaultPackage/' + bundles[index]['hash'] + '.bundle'
            payload = archive.read(member)
            env = UnityPy.load(payload)
            sprites = {o.peek_name(): o for o in env.objects if o.type.name == 'Sprite'}
            for asset in selected:
                if asset['bundle'] != index:
                    continue
                name = asset['address']
                obj = sprites[name]
                sprite = obj.read()
                image = sprite.image.convert('RGBA')
                destination = target / (name + '.png')
                image.save(destination)
                path = 'res://assets/ui/camp/portraits/' + destination.name
                mapping[name] = path
                records.append({'name': name, 'path': path, 'source_asset': asset['path'],
                                'member': member, 'bundle_sha256': digest(payload),
                                'sprite_path_id': str(obj.path_id), 'width': image.width,
                                'height': image.height, 'alpha_bounds': image.getchannel('A').getbbox(),
                                'png_sha256': digest(destination.read_bytes())})
    evidence = {'apk_sha256': hashlib.file_digest(apk.open('rb'), 'sha256').hexdigest(),
                'manifest_sha256': digest(manifest), 'sprites': records,
                'text_printer_configuration': printer_evidence,
                'limit': 'Raw packaged sprites. Names identify assets, not evidence of runtime use.'}
    (target / 'provenance.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    mapping_path = output / 'resource_map.json'
    all_mapping = json.loads(mapping_path.read_text()) if mapping_path.exists() else {}
    all_mapping.update({name: path for name, path in mapping.items() if name not in all_mapping})
    mapping_path.write_text(json.dumps(all_mapping, indent=2) + '\n')
    print(json.dumps({'count': len(records), 'output': str(target),
                      'all_nonblank': all(r['alpha_bounds'] for r in records)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'assets/ui/camp')
    args = parser.parse_args()
    recover(args.apk, args.output)
