"""Recover monster startup actions from exact APK MonsterActionCfg TextAssets."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from inspect_camp_progression import manifest_records

APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, help='Optional decoded manifest cache; verified against the APK')
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--audit', action='store_true')
    args = parser.parse_args()
    with args.apk.open('rb') as stream:
        apk_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    if apk_sha != APK_SHA256:
        raise ValueError('Monster startup rules require the audited 1061664.apk')
    combat = json.loads((args.project / 'assets/data/combat.json').read_text())
    expected = {str(enemy['id']): enemy for enemy in combat['enemies']}
    action_keys = {action['key'] for action in combat['actions']}
    enemies = {}
    with zipfile.ZipFile(args.apk) as archive:
        manifest_members = [name for name in archive.namelist() if name.startswith('assets/yoo/DefaultPackage/DefaultPackage_') and name.endswith('.bytes')]
        assert len(manifest_members) == 1, 'Expected one package manifest'
        manifest_member = manifest_members[0]
        manifest_bytes = archive.read(manifest_member)
        manifest_sha = hashlib.sha256(manifest_bytes).hexdigest()
        if args.manifest:
            assert manifest_sha == json.loads(args.manifest.read_text())['manifest_sha256'], 'Manifest cache does not match APK'
        _, all_bundles = manifest_records(manifest_bytes)
        bundles = [bundle for bundle in all_bundles if bundle['name'].endswith('actionenginecfg_unit_monster.bundle')]
        assert len(bundles) == 1, 'Expected one MonsterActionCfg bundle'
        bundle = bundles[0]
        member = 'assets/yoo/DefaultPackage/' + bundle['hash'] + '.bundle'
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
            'apk_sha256': apk_sha,
            'manifest_member': manifest_member,
            'manifest_sha256': manifest_sha,
            'bundle_name': bundle['name'],
            'bundle_member': member,
            'bundle_sha256': hashlib.sha256(payload).hexdigest(),
            'validation': 'All %d IDs match combat.enemies. Every nonempty FirstAct/BossAct exists in the imported action group; source group spelling is checked case-insensitively and retained per entry.' % len(enemies),
            'native_semantics': 'reports/boss-health-native-static.json',
        },
        'enemies': dict(sorted(enemies.items(), key=lambda row: int(row[0]))),
    }
    output = args.project / 'assets/data/monster_behavior.json'
    if args.audit:
        assert json.loads(output.read_text()) == result, 'Runtime startup data differs from the APK'
    else:
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'path': str(output), 'enemies': len(enemies), 'first_actions': sorted({row['first_action'] for row in enemies.values()}), 'shark': enemies['52002']}))


if __name__ == '__main__':
    main()
