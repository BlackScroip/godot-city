"""Compare normalized spawn data against TextAssets inside the supplied APK."""

import argparse
import hashlib
import json
import pathlib
import struct
import zipfile

import UnityPy


class Reader:
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def number(self, kind):
        result = struct.unpack_from('<' + kind, self.data, self.offset)[0]
        self.offset += struct.calcsize(kind)
        return result

    def string(self):
        length = self.number('H')
        result = self.data[self.offset:self.offset + length].decode('utf-8')
        self.offset += length
        return result

    def array(self, read):
        return [read() for _ in range(self.number('H'))]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', type=pathlib.Path, required=True)
parser.add_argument('--project', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
parser.add_argument('--report', type=pathlib.Path)
args = parser.parse_args()
source_records = []
texts = {}
with zipfile.ZipFile(args.apk) as apk:
    manifest_member = next(name for name in apk.namelist() if name.startswith('assets/yoo/DefaultPackage/DefaultPackage_') and name.endswith('.bytes'))
    raw_manifest = apk.read(manifest_member)
    reader = Reader(raw_manifest)
    reader.number('I')
    reader.string()
    for _ in range(3):
        reader.number('B')
    for _ in range(2):
        reader.number('i')
    for _ in range(4):
        reader.string()
    for _ in range(reader.number('i')):
        for _ in range(3):
            reader.string()
        reader.array(reader.string)
        reader.number('i')
        reader.array(lambda: reader.number('i'))
    bundles = []
    for index in range(reader.number('i')):
        name = reader.string()
        reader.number('I')
        digest = reader.string()
        reader.string()
        reader.number('q')
        reader.number('B')
        reader.array(reader.string)
        reader.array(lambda: reader.number('i'))
        bundles.append((name, digest))
    assert reader.offset == len(raw_manifest), 'Unexpected manifest layout'
    for name, digest in bundles:
        if not name.endswith(('actionenginecfg_env.bundle', 'mastercfg_atdata.bundle', 'mastercfg_luban_at.bundle')):
            continue
        member = next(path for path in apk.namelist() if path.endswith('/' + digest + '.bundle'))
        raw = apk.read(member)
        record = {'member': member, 'name': name, 'sha256': hashlib.sha256(raw).hexdigest(), 'text_assets': []}
        for obj in UnityPy.load(raw).objects:
            if obj.type.name != 'TextAsset':
                continue
            asset = obj.read()
            if not (asset.m_Name.startswith('EnvCfg_') or asset.m_Name in ('NodeData', 'RogueConfigData', 'EnemyData')):
                continue
            content = asset.m_Script
            if isinstance(content, str):
                content = content.encode('utf-8', errors='surrogateescape')
            texts[asset.m_Name] = json.loads(content.decode('utf-8-sig'))
            record['text_assets'].append({'name': asset.m_Name, 'path_id': obj.path_id, 'sha256': hashlib.sha256(content).hexdigest()})
        source_records.append(record)

campaign = json.loads((args.project / 'assets/data/campaign.json').read_text())
raw_nodes = {node['Id']: node for node in texts['NodeData']}
field_map = {'WaveMin': 'waveCountMin', 'WaveMax': 'waveCountMax', 'EnemyTypeMin': 'enemyTypeCountMin', 'EnemyTypeMax': 'enemyTypeCountMax', 'EliteTypeMin': 'eliteTypeCountMin', 'EliteTypeMax': 'eliteTypeCountMax', 'MaxEnemyDifficulty': 'MaxDifficulty', 'ManualEnemies': 'EnableManualEnemyCreate', 'RandomEnemies': 'EnableRandomEnemyCreate', 'EnemyIds': 'EnemyIdList'}
differences = []
normalizations = []
for node in campaign['Nodes']:
    raw = raw_nodes[node['Id']]['AttributeSet']
    for normalized, original in field_map.items():
        value = raw.get(original)
        if original == 'EnemyIdList' and value is not None:
            value = [enemy for enemy in value if enemy > 0]
            if value != raw[original]:
                normalizations.append({'node': node['Id'], 'field': original, 'removed_invalid_ids': [enemy for enemy in raw[original] if enemy <= 0]})
        if original in raw and node[normalized] != value:
            differences.append({'node': node['Id'], 'field': normalized})
    if raw.get('EnableManualEnemyCreate') is not None:
        forced = [{'EnemyId': spawn['ForceEnemyId'], 'SpawnIndex': spawn['ForceEnemySpawnIdx'], 'Wave': spawn['ForceSpawnWave'], 'Group': group['GroupIndex']} for group in raw.get('ForceSpawnGroupList', []) for spawn in group['SpawnDataList']]
        forced += [{'EnemyId': spawn['ForceEnemyId'], 'SpawnIndex': spawn['ForceEnemySpawnIdx'], 'Wave': spawn['ForceSpawnWave'], 'Group': 0} for spawn in raw.get('ForceSpawnDataList', [])]
        if sorted(forced, key=lambda x: json.dumps(x, sort_keys=True)) != sorted(node['ForcedSpawns'], key=lambda x: json.dumps(x, sort_keys=True)):
            differences.append({'node': node['Id'], 'field': 'ForcedSpawns'})

def vector(value):
    return dict(zip(('X', 'Y', 'Z'), map(float, value.split(','))))

environments = {}
for node in campaign['Nodes'] + campaign['SpecialStages']:
    raw = texts.get('EnvCfg_[%s]' % node['EnvironmentId'])
    if raw is None:
        differences.append({'node': node['Id'], 'field': 'MissingEnvCfg'})
        continue
    points = [{'Id': point['Id'], 'Position': vector(point['InitPos']), 'Rotation': vector(point['InitRotate'])} for point in raw.get('SpawnPointDataList', [])]
    environments[node['EnvironmentId']] = len(points)
    if points != node['SpawnPoints']:
        differences.append({'node': node['Id'], 'field': 'SpawnPoints'})

config = json.loads((args.project / 'assets/data/RogueConfigData.json').read_text())
for key in ('WaveDifficultyPatternList', 'EnemyRandomCreateDistanceToPlayerMin', 'EnemyRandomCreateDistanceToPlayerMax', 'DefaultEnemySpawnDelay'):
    if config[key] != texts['RogueConfigData'][key]:
        differences.append({'field': key})
if campaign['WavePatterns'] != texts['RogueConfigData']['WaveDifficultyPatternList']:
    differences.append({'field': 'Campaign.WavePatterns'})
enemies = json.loads((args.project / 'assets/data/EnemyData.json').read_text())
if enemies != texts['EnemyData']:
    differences.append({'field': 'EnemyData'})
report = {'schema': 1, 'apk': str(args.apk), 'apk_sha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(), 'manifest_member': manifest_member, 'manifest_sha256': hashlib.sha256(raw_manifest).hexdigest(), 'source_bundles': source_records, 'campaign_nodes_checked': len(campaign['Nodes']), 'special_stage_environments_checked': len(campaign['SpecialStages']), 'unique_environment_configs': len(environments), 'unique_spawn_points': sum(environments.values()), 'enemy_rows_checked': len(enemies), 'normalizations': normalizations, 'differences': differences, 'scope': 'Serialized configuration comparison only; no APK execution or Unity random sequence verification.'}
output = args.report or args.project / 'reports/apk-monster-spawn-data-audit.json'
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({key: report[key] for key in ('campaign_nodes_checked', 'unique_environment_configs', 'unique_spawn_points', 'enemy_rows_checked', 'differences')}))
raise SystemExit(1 if differences else 0)
