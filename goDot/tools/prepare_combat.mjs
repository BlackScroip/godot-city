import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const destination = path.join(root, 'goDot');
const source = path.join(root, 'OfflineUnity/Assets');
fs.mkdirSync(path.join(destination, 'assets/data'), {recursive: true});
fs.mkdirSync(path.join(destination, 'reports'), {recursive: true});
const read = name => JSON.parse(fs.readFileSync(path.join(source, name), 'utf8'));
const write = (name, value) => fs.writeFileSync(path.join(destination, name), JSON.stringify(value) + '\n');
const combat = read('Combat/Resources/Combat/OriginalCombat.json');
const damageDirectory = path.join(root, 'RecoveredUnity/ExportedProject/Assets/_00002_Resource/ActionEngineCfg/DamageCfg/Group');
combat.damage_definitions = {};
if (fs.existsSync(damageDirectory)) {
  for (const name of fs.readdirSync(damageDirectory).filter(name => name.endsWith('.json')).sort()) {
    for (const row of JSON.parse(fs.readFileSync(path.join(damageDirectory, name), 'utf8'))) {
      (combat.damage_definitions[String(row.DamageDefId)] ??= []).push(row);
    }
  }
}
// Keep packaged identifiers, coefficients, and raw evidence alongside the normalized data.
for (const buff of combat.buffs) {
  try { buff.raw_data = JSON.parse(buff.raw).BuffData ?? {}; } catch { buff.raw_data = {}; }
}
for (const summon of combat.summons) {
  try { summon.raw_data = JSON.parse(summon.raw).SummonUnitData ?? {}; } catch { summon.raw_data = {}; }
}
const aiDirectory = path.join(root, 'RecoveredUnity/ExportedProject/Assets/_00002_Resource/NodeCanvasRes/AI');
const aiFiles = [...new Set(combat.enemies.map(row => path.join(aiDirectory, row.ai + '.asset')))].filter(filename => fs.existsSync(filename));
const rubyGraphReader = 'result={}; ARGV.each{|f| doc=YAML.safe_load(File.read(f).sub(/^--- !u!\\d+ &\\d+$/, "---")); result[File.basename(f,".asset")]=JSON.parse(doc["MonoBehaviour"]["_serializedGraph"])}; puts JSON.generate(result)';
combat.ai_graphs = JSON.parse(execFileSync('ruby', ['-rjson', '-ryaml', '-e', rubyGraphReader, ...aiFiles], {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}));
const walkObjects = (value, callback) => {
  if (!value || typeof value !== 'object') return;
  callback(value);
  for (const child of Object.values(value)) walkObjects(child, callback);
};
const phaseProfiles = {
  13001: [{phase: 1, hp_per_mille: 500, compare: 'less_equal', actions: ['roar'], attack_cooldown: 2, properties: {'BB_IsCurHpLess50%': true}}],
  23001: [{phase: 1, hp_per_mille: 600, compare: 'less', actions: ['attack3'], properties: {'BB_IsCurHpLess60%': true, 'BB_IsFlyState': true}}],
  33001: [
    {phase: 1, hp_per_mille: 800, compare: 'less_equal', actions: [], properties: {'BB_IsCurHPLess80%': true}},
    {phase: 2, hp_per_mille: 500, compare: 'less_equal', actions: ['roar', 'RoarAttack'], attack_cooldown: 2, properties: {'BB_IsCurHPLess50%': true}},
    {phase: 3, hp_per_mille: 300, compare: 'less_equal', actions: [], properties: {'BB_IsCurHPLess30%': true}},
  ],
  41002: [{phase: 1, hp_per_mille: 200, compare: 'less', actions: ['attack2']}],
  43001: [{phase: 1, hp_per_mille: 500, compare: 'less', actions: ['P2action'], attack_cooldown: 1.5}],
  52001: [{phase: 1, hp_per_mille: 500, compare: 'less_equal', actions: ['LastStand']}],
  53001: [
    {phase: 1, hp_per_mille: 800, compare: 'less_equal', actions: ['Fly2Origin', 'roar1']},
    {phase: 2, hp_per_mille: 500, compare: 'less_equal', actions: ['Fly2Origin', 'roar2']},
    {phase: 3, hp_per_mille: 200, compare: 'less_equal', actions: ['Fly2Origin', 'roar3']},
  ],
};
for (const enemy of combat.enemies) {
  const graph = combat.ai_graphs[enemy.ai];
  enemy.ai_source = path.relative(root, path.join(aiDirectory, enemy.ai + '.asset'));
  enemy.ai_action_ids = [];
  enemy.ai_hp_conditions = [];
  walkObjects(graph?.nodes ?? [], object => {
    if (object.valueA?._name === 'OP_AIAction' && object.valueB?._value && String(object.$type).includes('.Actions.')) enemy.ai_action_ids.push(object.valueB._value);
    if (String(object.$type).endsWith('.NCCondition_RoleUnit_CheckAttribute') && object.CheckAttribute === 3) enemy.ai_hp_conditions.push(object);
  });
  enemy.ai_action_ids = [...new Set(enemy.ai_action_ids)];
  enemy.behavior = !enemy.actions.length && enemy.ai_action_ids.includes('runaway') ? 'flee' : 'combat';
  enemy.phase_rules = phaseProfiles[enemy.id] ?? [];
  enemy.phase_evidence = 'Serialized NodeCanvas predicates and OP_AIAction assignments. Scheduler, simultaneous threshold ordering and action selection are offline reconstruction; native task bodies remain unverified.';
}
write('assets/data/combat.json', combat);
write('assets/data/campaign.json', read('Campaign/Resources/CampaignDatabase.json'));
write('assets/data/markers.json', read('Campaign/Resources/CampaignMarkers.json'));
const grouped = (items, key) => Object.fromEntries([...Map.groupBy(items, x => x[key])].map(([k,v]) => [k, v.map(x => x.id ?? x.key)]));
const typed = grouped(combat.buffs, 'type');
write('reports/combat_catalog.json', {
  schema: 1, provenance: 'OfflineUnity recovered APK coefficients; native formulas remain reconstructed',
  characters: combat.characters.map(c => c.id), enemies: combat.enemies.map(e => e.id),
  actions: combat.actions.length, buffs: combat.buffs.length, summons: combat.summons.length,
  damage_definition_rows: Object.values(combat.damage_definitions).flat().length,
  missing_damage_ids: combat.missingDamageIds,
  buff_types: Object.fromEntries(Object.entries(typed).map(([k,v]) => [k, v.length])),
  review_required_buff_ids: typed.Unknown ?? [],
  ai_graphs: Object.keys(combat.ai_graphs).length,
  noncombat_fleeing_enemies: combat.enemies.filter(row => row.behavior === 'flee').map(row => row.id),
  reconstructed: ['defense curve', 'input interruption windows', 'enemy action selection', 'summon motion', 'route sampling', 'random wave budget'],
});
const campaign = read('Campaign/Resources/CampaignDatabase.json');
write('reports/campaign_catalog.json', {
  schema: 1, nodes: campaign.Nodes.length, special_stages: campaign.SpecialStages.length,
  regions: campaign.Regions, supplemental_environments: campaign.SupplementalEnvironments.length,
  route_rooms: campaign.Regions.reduce((sum, r) => sum + r.MiddleColumns + 2, 0),
  difficulty_levels: 11, reconstruction: 'LCG deterministic weighted route and random enemy counts; original eligibility and forced spawns retained',
});
console.log(JSON.stringify({characters: combat.characters.length, enemies: combat.enemies.length, actions: combat.actions.length, buffs: combat.buffs.length, nodes: campaign.Nodes.length}));
write('reports/combat_enemy_coverage.json', {
  schema: 1, yaml_reader: 'Ruby standard-library Psych safe_load; JSON.parse for NodeCanvas graph scalar',
  methodology: 'Original serialized graphs retained intact in combat.ai_graphs. HP thresholds and phase actions are interpreted from serialized predicates and assignments. General AI priority, random weights, navigation, timing and native task implementations remain unverified.',
  enemies: combat.enemies.map(row => ({id: row.id, name: row.name, graph: row.ai, source: row.ai_source, graph_recovered: Boolean(combat.ai_graphs[row.ai]), behavior: row.behavior, actions: row.ai_action_ids, hp_predicates: row.ai_hp_conditions, phase_rules: row.phase_rules, implementation: row.phase_rules.length ? 'phase_thresholds_and_action_sequences_interpreted_attack_selection_reconstructed' : row.behavior === 'flee' ? 'flee_action_interpreted_world_navigation_required' : 'attack_timeline_interpreted_selection_reconstructed', native_parity: 'unverified'})),
});

// Static coverage is deliberately separate from observed behavioral assertions.
const nodes = new Map();
const roots = new Set();
const edges = new Map();
const incoming = new Map();
const invalid = [];
const addNode = (kind, id, value, sourcePath) => {
  const key = `${kind}:${id}`;
  nodes.set(key, {kind, id: String(id), value, source: sourcePath});
  edges.set(key, []);
  return key;
};
const parse = value => {
  try { return JSON.parse(value); } catch { return {}; }
};
for (const row of combat.buffs) addNode('buff', row.id, row.raw_data, `RecoveredUnity/ExportedProject/Assets/_00002_Resource/ActionEngineCfg/Buff/BuffCfg__${row.id}_.json`);
for (const row of combat.summons) addNode('summon', row.id, row.raw_data, `RecoveredUnity/ExportedProject/Assets/_00002_Resource/ActionEngineCfg/SummonUnit/SummonUnitCfg__${row.id}_.json`);
for (const row of combat.actions) addNode('action', row.key, row, row.source);
for (const row of combat.abilities) {
  const value = parse(row.raw);
  addNode('ability', value.ID, value, row.source);
}
for (const row of combat.characters) roots.add(addNode('character', row.id, row, 'OfflineUnity/Assets/Combat/Resources/Combat/OriginalCombat.json'));
for (const row of combat.enemies) roots.add(addNode('enemy', row.id, row, 'OfflineUnity/Assets/Combat/Resources/Combat/OriginalCombat.json'));
const reference = (from, kind, id, field, activates = true) => {
  if (id === '' || id == null || id === false || String(id) === '0' || (kind === 'damage' && Number(id) < 0)) return;
  if (Array.isArray(id)) {
    id.forEach((value, index) => reference(from, kind, value, `${field}[${index}]`, activates));
    return;
  }
  if (typeof id !== 'number' && typeof id !== 'string') return;
  for (const value of String(id).split(/[|,;]/).map(value => value.trim()).filter(Boolean)) {
    const to = `${kind}:${value}`;
    const edge = {to, field, activates};
    edges.get(from).push(edge);
    if (!incoming.has(to)) incoming.set(to, []);
    incoming.get(to).push({from, field, activates});
    if (!nodes.has(to) && kind !== 'damage') invalid.push({from, ...edge});
  }
};
const scan = (from, object, prefix = '') => {
  if (Array.isArray(object)) {
    object.forEach((value, index) => scan(from, value, `${prefix}[${index}]`));
    return;
  }
  if (!object || typeof object !== 'object') return;
  for (const [key, value] of Object.entries(object)) {
    const field = prefix ? `${prefix}.${key}` : key;
    const activates = !/Conditions|Check|DelBuff|ClearTarget|SyncSource|Scoure|SourceBuff|Required|BeMutiply/.test(field);
    if (/^(BuffTriggerId|InitAddTargetBuffIdList|InitClearTargetBuffIdList|AddBuffIDList|DelBuffIDList|FailedTriggerBuffId|ModifyBuffId|ModifyBuffReplaceId|SyncSourceBuffId|LastingTimeSyncTargetBuffId|BuffScoureId|BeMutiplyBuffId|BuffId|BuffIdList|CheckAttackerBuffId|CheckAttackeeBuffId|CheckEnemyBuffId|AddBuff|ModifyBuff|buff_list|default_passive_buff_list_str|passive_buff_list|PassiveBuffList)$/i.test(key)) reference(from, 'buff', value, field, activates);
    if (/^(AddAbilityItemId|ExtraAbilityItemIDList|ability_item_id|upgrade_abilityitem_id|abilityitem_id_list)$/i.test(key)) reference(from, 'ability', value, field, activates);
    if (/^(AddSummonUnitId|ModifyTargetSummonUnitToOtherSummonUnitId|SummonIdList|SummonUnitIdList|OriginSummonUnitId)$/i.test(key)) reference(from, 'summon', value, field, activates && key !== 'SummonUnitIdList' && key !== 'OriginSummonUnitId');
    if (/^(DamageDefId|DamageId|CheckDamageDefId|CheckDamageDefId2|CheckDamageDefId3|ModifyDamageDefId)$/i.test(key)) reference(from, 'damage', value, field, activates);
    if (value && typeof value === 'object') scan(from, value, field);
  }
};
for (const [key, node] of nodes) scan(key, node.value);
for (const row of combat.characters) {
  const key = `character:${row.id}`;
  reference(key, 'buff', row.passives, 'passives');
  reference(key, 'buff', row.jp, 'jp');
  for (const action of [...row.combo, ...row.skills.map(skill => skill.action)]) reference(key, 'action', `ActGroup_playerchara/${action}`, 'actions');
}
for (const row of combat.enemies) {
  for (const action of row.actions) reference(`enemy:${row.id}`, 'action', `${row.group}/${action}`, 'actions');
  for (const action of row.ai_action_ids) if (nodes.has(`action:${row.group}/${action}`)) reference(`enemy:${row.id}`, 'action', `${row.group}/${action}`, 'serialized_ai_actions');
}
for (const row of combat.actions) {
  const key = `action:${row.key}`;
  for (const [index, event] of row.events.entries()) {
    if (!event.enabled) continue;
    if (event.buff) reference(key, 'buff', event.buff, `events[${index}].buff`);
    if (event.summon) reference(key, 'summon', event.summon, `events[${index}].summon`);
    if (event.target && event.type === 'EET_Interrupt' && !event.target.startsWith('sys_')) reference(key, 'action', `${row.group}/${event.target}`, `events[${index}].target`);
  }
  for (const [index, hit] of row.hits.entries()) {
    if (!hit.enabled) continue;
    for (const application of [...hit.targetBuffs, ...hit.ownerBuffs]) reference(key, 'buff', application.id, `hits[${index}].buff`);
    reference(key, 'damage', hit.damageId, `hits[${index}].damageId`);
    if (hit.summon) reference(key, 'summon', hit.summon, `hits[${index}].summon`);
  }
}
const rootTables = ['LootData', 'CharTalentLevelData', 'WeaponData', 'TalentTreeLevelData', 'RelationshipAmplifyData', 'RelationshipTokenData', 'MonsterPartnerData', 'CatMealData', 'AdvantureEventData'];
for (const table of rootTables) {
  const filename = path.join(destination, 'assets/data', table + '.json');
  if (!fs.existsSync(filename)) continue;
  const rows = JSON.parse(fs.readFileSync(filename, 'utf8'));
  for (const [index, row] of (Array.isArray(rows) ? rows : Object.values(rows)).entries()) {
    if (!row || typeof row !== 'object' || row.is_admin_only) continue;
    const key = addNode('system', `${table}/${row.id ?? index}`, row, `goDot/assets/data/${table}.json`);
    roots.add(key);
    scan(key, row);
  }
}
for (const row of campaign.Nodes) {
  const key = addNode('stage', row.Id, row, 'goDot/assets/data/campaign.json');
  roots.add(key);
  scan(key, row);
}
const reached = new Map([...roots].map(key => [key, null]));
const queue = [...roots];
for (let index = 0; index < queue.length; index++) {
  for (const edge of edges.get(queue[index]) ?? []) {
    if (!edge.activates || reached.has(edge.to)) continue;
    reached.set(edge.to, queue[index]);
    queue.push(edge.to);
  }
}
const sourceCode = fs.readFileSync(path.join(destination, 'scripts/domain/combat.gd'), 'utf8');
const supportedAttributes = new Set(JSON.parse(sourceCode.match(/const SUPPORTED_ATTRIBUTES = (\[[^\n]+\])/)[1]));
const testFile = path.join(destination, 'reports/combat_test.json');
const testReport = fs.existsSync(testFile) ? JSON.parse(fs.readFileSync(testFile, 'utf8')) : {};
const damageIds = new Set(Object.keys(combat.damage_definitions));
const rawConditions = new Set(['ECT_None', 'ECT_CheckBuffCD', 'ECT_CheckBuffExist', 'ECT_CheckBuffHP', 'ECT_CheckBuffArmor', 'ECT_CheckHaveSheild', 'ECT_CheckBuffEnemyType', 'ECT_CheckActionType', 'ECT_CheckBuffChangeLayer', 'ECT_CheckBuffAddBuff', 'ECT_CheckBuffAddSummonUnit', 'ECT_CheckBuffCauseDamage', 'ECT_CheckBeInjured', 'ECT_CheckBuffKillMonster', 'ECT_CheckBuffDodgeSuccess', 'ECT_CheckEnemyAround', 'ECT_CheckPlayerMove', 'ECT_CheckBuffRoleUnitAttribute', 'ECT_CheckBuffCombos', 'ECT_CheckBuffRogueAttribute', 'ECT_CheckBuffReceiveMsg', 'ECT_CheckBuffBePushCollision', 'ECT_CheckBuffCauseHeal', 'ECT_CheckBeHeal']);
const adapters = {
  EBT_PlayEffect: ['visual effect and attachment'], EBT_SpecialAddSummonUnit: ['summon spatial behavior'],
  EBT_EditorPropertyContext: ['property consumers and original per-property formulas'],
  EBT_ModifyAttackDef: ['attack geometry and definition mutation'],
  EBT_SpecialAddRogueAttribute: ['permanent or run attribute mutation'],
  EBT_SpecialBuffGenerationMonster: ['world monster spawn'],
  EBT_SummonUnitModify: ['summon appearance and motion'],
  EBT_SpecialSendMsg: ['world and system message consumers'],
  EBT_SpecialChangeAction: ['action animation and hit geometry'],
  EBT_SpecialTriggerRangeDamage: ['world area target enumeration'],
};
const dependencyAdapters = {
  ECT_CheckEnemyAround: 'world EnemyDistances context', ECT_CheckPlayerMove: 'world move events',
  ECT_CheckBuffRogueAttribute: 'systems RogueAttributes context', ECT_CheckBuffReceiveMsg: 'systems message events',
  ECT_CheckBuffBePushCollision: 'world push collision events',
};
const entries = combat.buffs.map(buff => {
  const key = `buff:${buff.id}`;
  const raw = buff.raw_data;
  const reasons = [];
  const world = [...(adapters[buff.type] ?? [])];
  const conditions = [...new Set((raw.Conditions ?? []).map(condition => condition.ConditionType))];
  for (const condition of conditions) {
    if (!rawConditions.has(condition)) reasons.push(`unimplemented condition ${condition}`);
    if (dependencyAdapters[condition]) world.push(dependencyAdapters[condition]);
  }
  for (const stat of buff.stats ?? []) if (!supportedAttributes.has(stat.attribute)) world.push(`attribute consumer ${stat.attribute}`);
  if (buff.type === 'Unknown') reasons.push('unknown buff type');
  if (raw.EnableAddCd) reasons.push('buff reapplication cooldown');
  if (raw.IsTriggerByLayer) reasons.push('per-layer independent trigger timing');
  if (raw.SwitchPlayerState && raw.SwitchPlayerState !== 'EBSP_None') reasons.push(`player switch state ${raw.SwitchPlayerState}`);
  if (raw.PropertyContext_AddMaxLayer) reasons.push(`max layer property ${raw.PropertyContext_AddMaxLayer}`);
  if (raw.PropertyContext_AddDuration) reasons.push(`duration property ${raw.PropertyContext_AddDuration}`);
  if (buff.unsupported && !['EBT_ConditionBuff', 'EBT_ModifyCombatResult', 'EBT_SpecialSetState'].includes(buff.type)) reasons.push(buff.unsupported);
  if (buff.type === 'EBT_SpecialTriggerRangeDamage' && !buff.selfOnlyDamage && !buff.area) reasons.push(buff.areaUnsupported || 'area interpretation missing');
  if (buff.type === 'EBT_ModifyAttackDef' || buff.type === 'EBT_SpecialAddRogueAttribute') reasons.push('runtime currently emits explicit adapter diagnostic');
  for (const settings of raw.BuffSettingDataList ?? []) {
    if (settings.EnableDamageDefReplace) reasons.push('damage definition replacement');
    if (settings.EnableCheckAttackeeDistance) world.push('per-target hit distance');
    if (settings.EnableBuffAddRandomMultiCBuffCurLayer) reasons.push('random probability multiplied by current layers');
    if (settings.MaxLayerAdd) reasons.push('setting max-layer addition');
    if (settings.InitLifeTimeAdd) reasons.push('setting lifetime addition');
    if (buff.type === 'EBT_SBuffChangeSpecAttributeToOther' && !(settings.SourceType === 'Hp' && settings.TargetType === 'Shield')) reasons.push('resource conversion mode');
    for (const [field, value] of Object.entries(settings)) if (/PropertyContext|ModifyPropertyContext|ContextProperty/.test(field) && typeof value === 'string' && value) world.push(`property tuning ${value}`);
  }
  const refs = edges.get(key) ?? [];
  for (const edge of refs) if (!nodes.has(edge.to) && !edge.to.startsWith('damage:')) reasons.push(`missing ${edge.to}`);
  for (const edge of refs) if (edge.to.startsWith('damage:') && !damageIds.has(edge.to.slice(7))) reasons.push(`missing ${edge.to}`);
  const checks = testReport.effect_checks?.[buff.id] ?? [];
  const implementation = buff.type === 'Unknown' ? 'unsupported' : reasons.length ? 'partial' : world.length ? 'interpreted_requires_adapter_validation' : 'interpreted_requires_behavior_validation';
  return {
    id: buff.id, name: buff.name, type: buff.type, source: nodes.get(key).source,
    evidence: 'Recovered serialized configuration; no native algorithm body recovered',
    rule_basis: 'original_configuration_interpretation', reachable_from_catalog_roots: reached.has(key),
    reachability_parent: reached.get(key) ?? null, references: refs, referenced_by: incoming.get(key) ?? [],
    conditions, level_source: raw.LevelSourceType ?? null, implementation,
    remaining_rules: [...new Set(reasons)], adapter_dependencies: [...new Set(world)],
    behavior_checks: checks, behavior_acceptance: checks.length && checks.every(check => check.passed) ? 'named_checks_passed_full_acceptance_pending' : 'pending',
    native_parity: 'unverified',
  };
});
const counts = (items, field) => Object.fromEntries([...Map.groupBy(items, item => item[field])].map(([key, values]) => [key, values.length]));
write('reports/combat_effect_coverage.json', {
  schema: 1,
  methodology: 'Structured reference graph from playable character/enemy actions, non-admin system table roots, enabled campaign nodes and all recursively added buff/ability/summon references. Conditional and clear-only references do not activate graph edges. Reachability is potential availability, not proof of unlockability or complete behavior.',
  validation: 'Named assertions are imported from combat_test.json. A passing named assertion is not full per-effect, per-level, visual, mobile or native parity acceptance.',
  limitations: ['Some published unlock and event chains need runtime evidence.', 'Native formulas, AI selection, summon spatial behavior and action interruption windows are reconstructed.', 'Unknown property consumers and adapter dependencies remain open acceptance items.'],
  summary: {total_buffs: entries.length, potentially_reachable_buffs: entries.filter(row => row.reachable_from_catalog_roots).length, implementation: counts(entries, 'implementation'), behavior_acceptance: counts(entries, 'behavior_acceptance'), missing_references: invalid.length},
  test_report: {path: 'goDot/reports/combat_test.json', assertions: testReport.assertions ?? 0, failures: testReport.failures ?? []},
  missing_references: invalid, entries,
  summons: combat.summons.map(row => ({id: row.id, type: row.type, potentially_reachable: reached.has(`summon:${row.id}`), references: edges.get(`summon:${row.id}`), implementation: 'timed_damage_and_buff_emission_interpreted_spatial_adapter_validation_pending', native_parity: 'unverified'})),
  actions: combat.actions.map(row => ({id: row.key, source: row.source, potentially_reachable: reached.has(`action:${row.key}`), command_types: [...new Set(row.events.filter(event => event.enabled).map(event => event.type))], references: edges.get(`action:${row.key}`), behavior_acceptance: 'world_animation_movement_and_timeline_validation_pending'})),
});
