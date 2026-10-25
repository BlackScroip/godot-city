"""Recover monster startup actions from exact APK MonsterActionCfg TextAssets."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    combat = json.loads((args.project / 'assets/data/combat.json').read_text())
    expected = {str(enemy['id']): enemy for enemy in combat['enemies']}
    action_keys = {action['key'] for action in combat['actions']}
    bundles = [bundle for bundle in manifest['bundles'] if bundle['name'].endswith('actionenginecfg_unit_monster.bundle')]
    assert len(bundles) == 1, 'Expected one MonsterActionCfg bundle'
    bundle = bundles[0]
    member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
    enemies = {}
    with zipfile.ZipFile(args.apk) as archive:
        manifest_members = [name for name in archive.namelist() if name.startswith('assets/yoo/DefaultPackage/DefaultPackage_') and name.endswith('.bytes')]
        assert len(manifest_members) == 1, 'Expected one package manifest'
        manifest_member = manifest_members[0]
        assert hashlib.sha256(archive.read(manifest_member)).hexdigest() == manifest['manifest_sha256'], 'Manifest cache does not match APK'
        payload = archive.read(member)
        for obj in UnityPy.load(payload).objects:
            if obj.type.name != 'TextAsset':
                continue
            asset = obj.read()
            if not asset.m_Name.startswith('MonsterActionCfg_'):
                continue
            content = asset.m_Script
            if isinstance(content, str):
                content = content.encode('utf-8', errors='surrogateescape')
            raw = json.loads(content.decode('utf-8-sig'))
            enemy_id = str(raw['ID'])
            if enemy_id not in expected:
                continue
            assert enemy_id not in enemies, 'Duplicate MonsterActionCfg ID ' + enemy_id
            source_group = raw['ActionGroup']
            imported_group = expected[enemy_id]['group']
            assert source_group.lower() == imported_group.lower(), 'Monster action group mismatch ' + enemy_id
            first_action = raw['FirstAct']
            boss_action = raw['BossAct']
            for action in [first_action, boss_action]:
                assert not action or imported_group + '/' + action in action_keys, 'Missing startup action ' + enemy_id + '/' + action
            enemies[enemy_id] = {
                'first_action': first_action,
                'boss_action': boss_action,
                'boss_action_time': raw['BossActTime'],
                'provenance': {
                    'asset': asset.m_Name,
                    'path_id': str(obj.path_id),
                    'sha256': hashlib.sha256(content).hexdigest(),
                    'fields': ['FirstAct', 'BossAct', 'BossActTime'],
                    'source_action_group': source_group,
                    'imported_action_group': imported_group,
                },
            }
    assert set(enemies) == set(expected), 'Missing monster startup configuration'
    result = {
        'schema': 1,
        'provenance': {
            'evidence_type': 'Static APK UnityFS TextAsset extraction; no APK execution.',
            'apk_sha256': hashlib.file_digest(args.apk.open('rb'), 'sha256').hexdigest(),
            'manifest_member': manifest_member,
            'manifest_sha256': manifest['manifest_sha256'],
            'bundle_name': bundle['name'],
            'bundle_member': member,
            'bundle_sha256': hashlib.sha256(payload).hexdigest(),
            'validation': 'All 39 IDs match combat.enemies; action group spelling differs only in case for Chimera. Every nonempty FirstAct/BossAct exists in the imported action group, with source and imported names retained per entry.',
        },
        'enemies': dict(sorted(enemies.items(), key=lambda row: int(row[0]))),
    }
    output = args.project / 'assets/data/monster_behavior.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'path': str(output), 'enemies': len(enemies), 'first_actions': sorted({row['first_action'] for row in enemies.values()}), 'shark': enemies['52002']}))


if __name__ == '__main__':
    main()
