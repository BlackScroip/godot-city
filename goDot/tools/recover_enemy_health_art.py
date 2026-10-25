"""Recover the elite health-bar insignia from the supplied APK and YooAsset manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', type=Path, required=True)
parser.add_argument('--manifest', type=Path, required=True)
parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'assets/ui/enemy')
args = parser.parse_args()
manifest = json.loads(args.manifest.read_text())
asset = next(row for row in manifest['assets'] if row['address'] == 'icon_nodeicon_trapchallenge')
member = 'assets/yoo/DefaultPackage/' + manifest['bundles'][asset['bundle']]['hash'] + '.bundle'
with zipfile.ZipFile(args.apk) as archive:
    payload = archive.read(member)
    environment = UnityPy.load(payload)
    sprite = next(obj for obj in environment.objects if obj.type.name == 'Sprite' and obj.peek_name() == asset['address'])
    args.output.mkdir(parents=True, exist_ok=True)
    sprite.read().image.save(args.output / 'elite.png')
    evidence = {
        'apk_sha256': hashlib.file_digest(args.apk.open('rb'), 'sha256').hexdigest(),
        'manifest_sha256': manifest['manifest_sha256'],
        'member': member,
        'bundle_sha256': hashlib.sha256(payload).hexdigest(),
        'sprite': asset['address'],
        'sprite_path_id': str(sprite.path_id),
        'prefab': 'Box_EnemyState_Elite',
        'prefab_image_sprite_path_id': '8134934211269375171',
        'basis': 'Exact Image.m_Sprite reference in elite prefab, matching the supplied white/purple-eye insignia screenshot.',
        'limitation': 'Static serialized artwork, not a runtime observation. Godot bar geometry and damage-follow timing are reconstructed.',
    }
    (args.output / 'provenance.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence))
