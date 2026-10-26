// Normalize the October APK tables while retaining authored scene marker data.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = process.argv[2] ?? '/private/tmp/city-new-map-evidence';
const read = name => JSON.parse(fs.readFileSync(path.join(source, name), 'utf8'));
const target = path.join(project, 'assets/data/campaign.json');
const campaign = JSON.parse(fs.readFileSync(target, 'utf8'));
const previous = new Map([...campaign.Nodes, ...campaign.SpecialStages].map(row => [row.Id, row]));
const types = {1: 'Shop', 2: 'Battle', 3: 'Rest', 5: 'Treasure', 11: 'Event', 12: 'Entrance', 13: 'Curse', 14: 'TreasureTrial'};
const vector = value => Object.fromEntries(['X', 'Y', 'Z'].map((key, index) => [key, Number(String(value ?? '0,0,0').split(',')[index] ?? 0)]));
const normalize = row => {
  const attributes = row.AttributeSet ?? {};
  const rule = row.GenerateRule;
  const stage = Number(attributes.StageId);
  const old = previous.get(row.Id) ?? [...previous.values()].find(item => item.StageId === stage);
  const envPath = path.join(source, 'environments', `EnvCfg_[${stage}].json`);
  const env = fs.existsSync(envPath) ? JSON.parse(fs.readFileSync(envPath, 'utf8')) : {};
  const forced = [];
  const addSpawns = (items, group) => {
    for (const spawn of items ?? []) forced.push({EnemyId: spawn.ForceEnemyId, SpawnIndex: spawn.ForceEnemySpawnIdx, Wave: spawn.ForceSpawnWave, Group: group});
  };
  addSpawns(attributes.ForceSpawnDataList, 0);
  for (const group of attributes.ForceSpawnGroupList ?? []) addSpawns(group.SpawnDataList, group.GroupIndex);
  return {
    ...old, Id: row.Id, Name: row.Name, StageId: stage, EnvironmentId: stage,
    SceneName: env.EnvSceneName ?? old?.SceneName ?? `LevelMap_${stage}`,
    Region: rule.NodeLevel, Type: row.Type,
    Flow: row.IsFirstOrFinal === 2 ? 'Boss' : types[row.Type] ?? old?.Flow ?? 'Event',
    FirstOrFinal: row.IsFirstOrFinal, MinDifficulty: rule.ActiveDifficultyLevel_Min,
    MaxDifficulty: rule.ActiveDifficultyLevel_Max, MinDepth: rule.MinDepthAtLevel,
    MaxDepth: rule.MaxDepthAtLevel, MaxAppearTime: rule.MaxAppearTime,
    AppearChance: rule.AppearChance, Priority: rule.GeneratePriority,
    CanConnect: rule.IsCanConnectivity, RequireItems: rule.RequireItemList ?? [],
    WaveMin: attributes.waveCountMin ?? 0, WaveMax: attributes.waveCountMax ?? 0,
    EnemyTypeMin: attributes.enemyTypeCountMin ?? 0, EnemyTypeMax: attributes.enemyTypeCountMax ?? 0,
    EliteTypeMin: attributes.eliteTypeCountMin ?? 0, EliteTypeMax: attributes.eliteTypeCountMax ?? 0,
    MaxEnemyDifficulty: attributes.MaxDifficulty ?? 0,
    RandomEnemies: attributes.EnableRandomEnemyCreate ?? false,
    ManualEnemies: attributes.EnableManualEnemyCreate ?? false,
    EnemyIds: attributes.EnemyIdList ?? [], ForcedSpawns: forced,
    FightType: attributes.FightType ?? '', FightData: attributes.FightData ?? {},
    ...(row.Type === 14 ? {TrialData: attributes} : {}),
    EnemyClass: attributes.RoomEnemyType ?? '', FinalBoss: attributes.IsFinalBoss ?? false,
    Lighting: attributes.EnableLightSettingOverrideFileName ?? '', Music: attributes.BGMPrefabName ?? '',
    TalkGroup: row.SimpleTalkGroupId ?? 0, TalkDelay: row.SimpleTalkDelayTime ?? 0,
    IncrementOptions: row.IncrementOptions ?? '0', IconName: row.IconName ?? '',
    PlayerStart: env.PlayerInitPos ? vector(env.PlayerInitPos) : old?.PlayerStart ?? {X: 0, Y: 0, Z: 0},
    PlayerRotation: env.PlayerInitRotate ? vector(env.PlayerInitRotate) : old?.PlayerRotation ?? {X: 0, Y: 0, Z: 0},
    CameraX: env.CameraInitRotate_X ?? old?.CameraX ?? 45,
    CameraY: env.CameraInitRotate_Y ?? old?.CameraY ?? -45,
    SpawnPoints: env.SpawnPointDataList?.map(point => ({Id: point.Id, Position: vector(point.InitPos), Rotation: vector(point.InitRotate)})) ?? old?.SpawnPoints ?? [],
  };
};
const raw = read('NodeData.json');
const active = raw.filter(row => row.IsActive && row.GenerateRule && row.GenerateRule.NodeLevel > 0);
campaign.Nodes = active.map(normalize);
const ids = new Set(campaign.Nodes.map(row => row.Id));
campaign.SpecialStages = campaign.SpecialStages.filter(row => !ids.has(row.Id));
// Retired rooms remain addressable for old checkpoints without entering new pools.
for (const old of previous.values()) if (!ids.has(old.Id) && !campaign.SpecialStages.some(row => row.Id === old.Id)) campaign.SpecialStages.push(old);
const world = read('RegionMapData.json').find(row => row.IsActive);
const areas = world.ModuleList.flatMap(module => module.SlotList.filter(slot => slot.NodeLevel > 0).map(slot => ({Id: slot.NodeLevel, Name: slot.Name, MiddleColumns: 5, MaxRows: slot.NodeLevel === 5 ? 1 : 3})));
campaign.Areas = areas;
for (const region of campaign.Regions) region.Name = areas.find(area => area.Id === region.Id).Name;
campaign.Source = {version: '2026-10-09', apk_sha256: 'ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505', node_table_sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(source, 'NodeData.json'))).digest('hex')};
fs.writeFileSync(target, JSON.stringify(campaign) + '\n');
console.log(JSON.stringify({nodes: campaign.Nodes.length, special: campaign.SpecialStages.length, areas: campaign.Areas, unsupportedFlows: active.filter(row => !types[row.Type] && row.IsFirstOrFinal !== 2).map(row => [row.Id, row.Type])}));
