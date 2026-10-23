import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (relative, fallback) => {
  const filename = path.join(project, relative);
  return fs.existsSync(filename) ? JSON.parse(fs.readFileSync(filename, 'utf8')) : fallback;
};
const text = relative => fs.readFileSync(path.join(project, relative), 'utf8');
const hash = value => crypto.createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');
const idOf = row => Number(row.id ?? row.Id ?? row.ID ?? row.GoodsId ?? row.DetailsId ?? 0);
const ids = value => (Array.isArray(value) ? value : String(value ?? '').split(/[,|]/)).map(Number).filter(x => Number.isInteger(x) && x > 0);
const unique = values => [...new Set(values)];
const nameOf = row => row.name ?? row.Name ?? row.title ?? row.GoodsName ?? row.DetailsName ?? row.BuffData?.Name_EDT ?? '';
const manifest = read('assets/data/manifest.json', { tables: {} });
const tables = Object.fromEntries(Object.keys(manifest.tables).map(name => [name, read(`assets/data/${name}.json`, [])]));
tables.Buildings = tables.RogueConfigData.MainCityDevelopDataList.map((row, id) => ({ ...row, id }));
const indices = Object.fromEntries(Object.entries(tables).filter(([, rows]) => Array.isArray(rows)).map(([name, rows]) => [name, new Map(rows.map(row => [idOf(row), row]))]));
const systemsTest = read('reports/systems-tests.json', {});
const combatTest = read('reports/combat_test.json', {});
const campaignTest = read('reports/campaign_test.json', {});
const combat = read('assets/data/combat.json', { buffs: [] });
const systemsSource = text('scripts/domain/systems.gd');
const effectsSource = text('scripts/domain/effects.gd');
const combatSource = text('scripts/domain/combat.gd');
const uiSource = text('scripts/menus.gd') + text('scripts/main.gd');
const worldSource = text('scripts/world.gd') + text('scripts/main.gd');
const allTestSource = text('tests/systems_test.gd') + text('tests/combat_test.gd');
const suitePassed = systemsTest.success === true && systemsTest.failures?.length === 0;
const taskIds = new Set((systemsTest.task_ids ?? []).map(Number));
const groupIds = new Set((systemsTest.group_ids ?? []).map(Number));
const curseIds = new Set((systemsTest.purification_ids ?? []).map(Number));
const combatBuffIndex = new Map(combat.buffs.map(row => [Number(row.id), row]));

function origin(table, row, index) {
  return {
    key: `${table}:${idOf(row)}:${index}`,
    table, id: idOf(row), row_index: index, name: nameOf(row),
    config_source: table === 'Buildings' ? `${manifest.tables.RogueConfigData.source}#MainCityDevelopDataList[${index}]` : manifest.tables[table]?.source,
    config_sha256: table === 'Buildings' ? manifest.tables.RogueConfigData.sha256 : manifest.tables[table]?.sha256,
    row_sha256: hash(row), provenance: 'recovered_configuration',
    original_apk_behavior_parity: 'unverified',
  };
}

function tally(rows, key) {
  return rows.reduce((result, row) => {
    const value = typeof key === 'function' ? key(row) : row[key];
    result[value] = (result[value] ?? 0) + 1;
    return result;
  }, {});
}

const methodMap = {
  CharData: ['unlock_character', 'upgrade_character', 'attributes'],
  WeaponData: ['upgrade_weapon', 'selected_weapon_buffs', 'progression_buff_bindings'],
  TalentTreeData: ['upgrade_global_talent', 'ability_sources'],
  TalentTreeLevelData: ['upgrade_global_talent', 'ability_sources'],
  CharTalentData: ['learn_character_talent', 'attributes'],
  CharTalentLevelData: ['learn_character_talent', 'progression_buff_bindings'],
  CharaTalentAwakeTreeData: ['unlock_awakening', 'toggle_awakening', 'upgrade_awakening_level'],
  MonsterPartnerData: ['unlock_partner', 'upgrade_partner', 'equip_partner', 'attributes'],
  MonsterWorkData: ['start_work', 'collect_work', 'upgrade_work'],
  CatMealData: ['cook_meal', 'ability_sources'],
  Buildings: ['upgrade_building'],
  NPCData: ['give_npc_gift', 'prepare_npc_support'],
  NPCFunctionData: ['npc_function_status', 'execute_npc_function', 'claim_npc_support'],
  RelationshipTokenData: ['refresh_tokens', 'upgrade_token', 'equip_token'],
  RelationshipAmplifyData: ['equip_amplifier', 'compose_amplifier', 'reroll_amplifier'],
  ItemPoolData: ['roll_pool', '_pool_candidates'],
  ItemPoolSubData: ['_pool_candidates'],
  AdvantureEventData: ['event_for_node', 'event_view', 'resolve_event'],
  MallTradeData: ['offer_quote', 'buy_offer'],
  MallTradeDetailsData: ['_mall_reward_options'],
  ShopTreasureBoxData: ['open_material_box', 'open_camp_treasure_boxes'],
  MaterialData: ['material', 'spend', 'grant_material'],
  EnemyData: ['record_kill', 'record_boss_rating'],
  DamageValues: ['effects.instant_buff', 'combat.receive'],
};

const reconstructedRules = [
  { id: 'R01', rule: 'Pure GDScript interpretation of recovered Unity configuration; Unity engine, FSM and MonoBehaviour code are reimplemented.', scope: 'all systems' },
  { id: 'R02', rule: 'Damage defense formula, interruption windows, enemy action selection, collision and summon movement are reconstructed.', scope: 'combat' },
  { id: 'R03', rule: 'Deterministic route topology/weight interpretation and PRNG algorithm are offline implementations.', scope: 'campaign and random rewards' },
  { id: 'R04', rule: 'Completed normal rooms grant one of each existing regional material; boss rooms grant three. Boss growth resources: 103:2,107:2,501:2,502:1,90002:20,503:1,504:10,108:20,106:1, plus one random original Tier1 amplifier.', scope: 'claim_node_materials' },
  { id: 'R05', rule: 'Money/Ad/Other offers use gold with price=max(1000,original Price*1000,total maximum reward gold valuation); original Enable, limit and reset mode remain. No real purchases or ad SDK.', scope: 'offer_quote and buy_offer' },
  { id: 'R06', rule: 'Inventory boxes consume one held box, give configured guaranteed_id every opening, and perform one weighted draw. Camp box uses original configured min/max draw count.', scope: 'open_material_box' },
  { id: 'R07', rule: 'One golden apple advances one relationship level. Awakening level acts as the activation point budget. Three identical amplifiers compose a random next-tier amplifier; three slots maximum.', scope: 'persistent growth' },
  { id: 'R08', rule: 'NPC support uses three persistent choices once per NPC per run; gem trader starts with one drop and configured region limits; room shop region price scaling is reconstructed.', scope: 'shops and NPC support' },
  { id: 'R09', rule: 'Blessing selection is an offline option with no subscription backend. Source cash-only normal recruitment fallback, if any, is offline.', scope: 'service replacements' },
  { id: 'R10', rule: 'Random regional mall materials use regions up to max cleared region+1; the original city-level multiplier has not been recovered.', scope: '_mall_reward_options' },
];

const systemRows = [];
for (const [table, methods] of Object.entries(methodMap)) {
  for (const [index, row] of (tables[table] ?? []).entries()) {
    const id = idOf(row);
    const issues = [];
    let state = 'domain_path_present_parity_unverified';
    let testScope = 'batch_operations_or_shared_interpreter_only_no_per_id_success_assertion';
    if (table === 'CharData') {
      if (row.available_state !== 'Normal') state = 'source_admin_record_intentionally_excluded';
      else testScope = suitePassed ? 'recruitment_resource_route_asserted_without_direct_resource_grants; combat_growth_focused_on_id_1' : 'unverified';
    }
    if (table === 'Buildings' && Number(row.max_level) === 0) state = 'source_service_placeholder_not_upgradable_building';
    if (table === 'MonsterWorkData') {
      testScope = suitePassed ? 'all_16_jobs_all_3_levels_exact_start_upgrade_costs_due_boundary_rewards_duplicate_claim_and_busy_partner_asserted' : 'unverified';
      issues.push('UTC timing is reconstructed; original per-room/per-level progress acceleration is not wired.');
    }
    if (table === 'WeaponData') testScope = [101, 102].includes(id) && suitePassed ? 'actual_combat_growth_rank_switch_assertions' : 'upgrade_batch_exercised_effect_behavior_not_individually_verified';
    if (table === 'AdvantureEventData') testScope = systemsTest.event_template_choices?.[id] !== undefined ? `one_available_choice_asserted:${systemsTest.event_template_choices[id]};other_branches_unverified` : 'unverified';
    if (table === 'NPCFunctionData') {
      if (row.func_msg_name === 'Rogue_OpenShop') {
        state = uiSource.includes('Rogue_OpenShop') ? 'host_destination_wired_world_flow_unverified' : 'host_navigation_required';
        issues.push('Domain operation requires host navigation; destination and actual interaction need UI acceptance.');
      }
      testScope = [140101, 101001].includes(id) && suitePassed ? 'focused_transaction_assertions' : 'navigation_or_dialogue_path_present_individual_world_flow_unverified';
    }
    if (table === 'MallTradeData') {
      if (!row.Enable) state = 'source_disabled_row';
      testScope = suitePassed ? 'all_effective_enabled_ids_purchase_quote_cost_and_limit_asserted;disabled_effective_ids_rejected' : 'unverified';
      if (['Ad', 'Money', 'Other'].includes(row.GoodsPayType)) issues.push('Offline gold replacement R05; original online behavior is not reproduced.');
      if ((tables.MallTradeData.filter(x => idOf(x) === id)).length > 1) issues.push('Duplicate source ID; catalog uses last row, ledger preserves every source row.');
    }
    if (table === 'ShopTreasureBoxData') testScope = suitePassed ? 'every_box_id_consumption_and_configured_guarantee_asserted;original_guarantee_cadence_unverified' : 'unverified';
    if (table === 'RelationshipAmplifyData') testScope = 'Tier1 boss-source variety checked; all next-tier pools present; each ID effect and natural collection duration unverified';
    systemRows.push({
      ...origin(table, row, index), implementation: state,
      implementation_file: 'scripts/domain/systems.gd', methods,
      method_presence: methods.map(method => ({ method, found: method.includes('.') || systemsSource.includes(`func ${method}(`) })),
      tests: { scope: testScope, domain_suite_passed: suitePassed, evidence: 'reports/systems-tests.json', world_ui: 'not_verified_per_id' },
      issues,
    });
  }
}
systemRows.push({ ...origin('RogueConfigData', tables.RogueConfigData, 0), id: 'singleton', implementation: 'shared_configuration_loaded_not_every_field_interpreted', methods: ['catalog.load_all'], tests: { scope: 'table_load_asserted;individual_config_options_unverified', world_ui: 'not_verified_per_field' } });

const unlockTypeMethods = {
  0: [], 10: ['begin_run'], 11: ['end_run'], 12: ['end_run'], 13: ['complete_node'], 20: ['record_kill'], 21: ['upgrade_global_talent'],
  30: ['grant_material'], 31: ['spend'], 40: ['add_loot'], 41: ['add_loot'], 51: ['collect_work'], 52: ['upgrade_work'],
  100: ['upgrade_building'], 101: ['upgrade_building'], 200: ['execute_npc_function'], 201: ['give_npc_gift'],
  300: ['upgrade_weapon'], 301: ['upgrade_weapon'], 302: ['upgrade_weapon'], 400: ['unlock_character'], 401: ['upgrade_character'],
  402: ['upgrade_partner'], 403: ['upgrade_character'], 404: ['complete_node'], 500: ['invest_shop'], 600: ['claim_achievement'],
  601: ['claim_achievement'], 1000: ['add_loot'], 1001: ['complete_node'], 1002: ['add_loot'], 1010: ['grant_material'],
  1021: ['record_boss_rating'], 1030: ['complete_node'], 1040: ['end_run'], 1051: ['upgrade_global_talent'], 1052: ['upgrade_global_talent'],
  1061: ['cook_meal'], 1062: ['cook_meal'], 9001: ['is_unlocked'], 9002: ['is_unlocked'], 9201: ['begin_run', 'end_run'],
  9999: ['grant_material', 'record_kill', 'complete_node', 'add_loot'],
};
const directAchievementConditions = unique(tables.SubAchieveData.map(x => Number(x.unlock_data_id)).concat(tables.AchieveData.flatMap(x => ids(x.unlock_group_id))));
const conditionClosure = new Set();
const missingConditions = new Set();
function expandCondition(id) {
  if (!id || conditionClosure.has(id)) return;
  const row = indices.UnlockData.get(id);
  if (!row) { missingConditions.add(id); return; }
  conditionClosure.add(id);
  if ([9001, 9002].includes(Number(row.unlock_condition_type))) {
    for (const key of ['unlock_param1', 'unlock_param2', 'unlock_param3']) expandCondition(Number(row[key]));
  }
}
directAchievementConditions.forEach(expandCondition);
const achievementGroups = tables.AchieveData.map((row, index) => ({
  ...origin('AchieveData', row, index), prerequisite_condition_ids: ids(row.unlock_group_id),
  task_ids: tables.SubAchieveData.filter(x => Number(x.group_id) === idOf(row)).map(idOf), rewards: row.reward_get_materials,
  implementation: 'claim_checks_all_original_tasks_and_prerequisites_and_one_time_reward',
  domain_test: groupIds.has(idOf(row)) && suitePassed ? 'claimed_duplicate_rejected_save_reload_duplicate_rejected' : 'unverified',
  natural_world_completion: 'unverified_accelerated_domain_test_is_not_natural_playthrough',
}));
const achievementTasks = tables.SubAchieveData.map((row, index) => ({
  ...origin('SubAchieveData', row, index), group_id: Number(row.group_id), condition_id: Number(row.unlock_data_id), rewards: row.reward_get_materials,
  implementation: 'progress_query_original_condition_group_prerequisites_and_one_time_reward',
  domain_test: taskIds.has(idOf(row)) && suitePassed ? 'progress_queried_claimed_duplicate_rejected_save_reload_duplicate_rejected' : 'unverified',
  natural_world_completion: 'unverified_accelerated_domain_test_is_not_natural_playthrough',
}));
const unlockRows = tables.UnlockData.map((row, index) => ({
  ...origin('UnlockData', row, index), type: Number(row.unlock_condition_type), parameters: [row.unlock_param1, row.unlock_param2, row.unlock_param3],
  implementation: Object.hasOwn(unlockTypeMethods, row.unlock_condition_type) ? 'predicate_path_present' : 'unsupported',
  producer_methods: unlockTypeMethods[row.unlock_condition_type] ?? [],
  producer_callsites: (unlockTypeMethods[row.unlock_condition_type] ?? []).map(method => ({ method, world_call_present: worldSource.includes(`.${method}(`), menu_call_present: uiSource.includes(method) })),
  required_by_achievement_dependency_closure: conditionClosure.has(idOf(row)),
  test_scope: conditionClosure.has(idOf(row)) && suitePassed ? 'participates_in_all_achievement_domain_claims;each_boolean_branch_not_individually_tested' : 'predicate_interpreter_present_no_per_id_assertion',
  original_apk_and_natural_world_parity: 'unverified',
}));

const supportedRawConditionTypes = new Set([...combatSource.matchAll(/"(ECT_[A-Za-z0-9_]+)"\s*(?:,|:)/g)].map(match => match[1]));
const supportedCombatAttributes = new Set((combatSource.match(/const SUPPORTED_ATTRIBUTES = \[(.*?)\]/s)?.[1].match(/"([^"]+)"/g) ?? []).map(x => x.slice(1, -1)));
function walk(value, visit) {
  if (Array.isArray(value)) { value.forEach(item => walk(item, visit)); return; }
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) { visit(key, child, value); walk(child, visit); }
}
function references(row, pattern) {
  const result = [];
  walk(row, (key, value) => { if (pattern.test(key) && (typeof value === 'string' || Array.isArray(value))) result.push(...ids(value)); });
  return unique(result);
}
const abilityRows = tables.AbilityItems.map((row, index) => {
  const issues = [];
  const conditions = [];
  const kinds = [];
  if (!['', 'None', 'Init', 'Get', 'RogueEventType'].includes(row.TriggerEventType ?? '')) issues.push(`Top-level trigger not dispatched by domain interpreter: ${row.TriggerEventType}`);
  if (row.TriggerEventType === 'RogueEventType' && !systemsSource.includes(`dispatch("${row.RogueEventTriggerData?.EventType}"`)) issues.push(`Top-level event has no known systems producer: ${row.RogueEventTriggerData?.EventType}`);
  if (row.EnableCaculateAttributeSource) issues.push('Computed attribute-source scaling is not fully interpreted.');
  walk(row, (key, value) => {
    if (key === 'CombineDataType') {
      kinds.push(value);
      const curseTransformation = value === 'StateChange' && tables.LootData.some(loot => Number(loot.ability_item_id) === idOf(row) && loot.loot_type === '诅咒遗物');
      if (!curseTransformation && !['NormalModifyRogue', 'NormalModifyBuff', 'NormalTrigger', 'RecordTrigger'].includes(value)) issues.push(`Component requires specialized handling: ${value}`);
    }
    if (key === 'ConditionType') { conditions.push(value); if (value !== 'RecordValue') issues.push(`Domain ability condition not interpreted: ${value}`); }
    if (key === 'MsgName' && value && !['Rogue_ClearMagicPoint', 'Rogue_AddNewLootToInventory'].includes(value)) issues.push(`Ability message not handled: ${value}`);
  });
  for (const component of row.CombineDataList ?? []) {
    if ((component.ConditionList ?? []).length && ['NormalModifyRogue', 'NormalModifyBuff'].includes(component.CombineDataType)) issues.push('Conditional persistent modifier does not pass unconditional attribute collection.');
  }
  const buffIds = references(row, /^(ModifyBuff|AddBuff)$/);
  const abilityIds = references(row, /^(ExtraAbilityItemIDList|AddAbilityItemId)$/);
  for (const id of buffIds) if (!combatBuffIndex.has(id)) issues.push(`Missing referenced buff: ${id}`);
  for (const id of abilityIds) if (!indices.AbilityItems.has(id)) issues.push(`Missing referenced ability: ${id}`);
  return { ...origin('AbilityItems', row, index), implementation: issues.length ? 'partial_interpreter_with_known_gaps' : 'interpreter_path_present_behavior_unverified',
    entry_trigger: row.TriggerEventType, components: unique(kinds), conditions: unique(conditions), buff_ids: buffIds, ability_ids: abilityIds,
    implementation_files: ['scripts/domain/effects.gd', 'scripts/domain/systems.gd', 'scripts/domain/combat.gd'],
    tests: { focused_system_case: [10000, 10100, 12101].includes(idOf(row)) && suitePassed, every_effect_branch: 'unverified', world_ui: 'unverified' }, issues: unique(issues) };
});
const buffRows = combat.buffs.map((row, index) => {
  const id = Number(row.id);
  const raw = indices.Buffs.get(id);
  const issues = [];
  const conditions = (row.raw_data?.Conditions ?? []).map(x => x.ConditionType);
  const unknownConditions = conditions.filter(type => !supportedRawConditionTypes.has(type));
  if (row.type === 'Unknown') issues.push('Importer could not resolve source buff type.');
  if (row.unsupported) issues.push(`Importer diagnostic: ${row.unsupported}`);
  if (row.unsupportedState) issues.push('Dodge/block/antiheal flags need world adapter verification.');
  if (row.areaUnsupported && !row.area) issues.push(`Area adapter unresolved: ${row.areaUnsupported}`);
  for (const type of unknownConditions) issues.push(`Raw combat condition handler missing: ${type}`);
  for (const stat of row.stats ?? []) if (!supportedCombatAttributes.has(stat.attribute)) issues.push(`Numeric attribute requires systems adapter: ${stat.attribute}`);
  const children = unique((row.initial ?? []).map(Number).concat(ids(row.modify), references(row.raw_data ?? {}, /^(BuffTriggerId|BuffId|BuffID|TargetBuffId|AddBuffId)$/)));
  for (const child of children) if (!combatBuffIndex.has(child)) issues.push(`Missing referenced buff: ${child}`);
  return { ...(raw ? origin('Buffs', raw, tables.Buffs.indexOf(raw)) : { table: 'Buffs', id, provenance: 'combat_importer_additional_record', config_source: 'assets/data/combat.json', row_index: index }),
    type: row.type, implementation: issues.length ? 'partial_or_adapter_review_required' : 'combat_interpreter_path_present_behavior_unverified',
    raw_condition_types: conditions, compiled_trigger_count: row.triggers?.length ?? 0, initial_and_referenced_buffs: children,
    tests: { id_literal_present_in_test_source: allTestSource.includes(`"${id}"`), combat_suite_passed: combatTest.failures?.length === 0, source_parity: 'not_individually_verified', world_ui: 'not_individually_verified' }, issues: unique(issues) };
});
const abilityIndex = new Map(abilityRows.map(row => [row.id, row]));
const poolMembership = new Map();
for (const pool of tables.ItemPoolData) for (const subId of ids(pool.sub_data_id_list)) for (const id of ids(indices.ItemPoolSubData.get(subId)?.item_id_list_str)) {
  if (!poolMembership.has(id)) poolMembership.set(id, []);
  poolMembership.get(id).push(idOf(pool));
}
const lootRows = tables.LootData.map((row, index) => ({
  ...origin('LootData', row, index), ability_id: Number(row.ability_item_id), type: row.loot_type, prerequisite_condition_id: Number(row.unlock_data_id),
  implementation: row.is_admin_only ? 'source_admin_record_intentionally_excluded' : 'acquisition_inventory_and_effect_interpreter_wired_parity_unverified',
  pool_membership: unique(poolMembership.get(idOf(row)) ?? []),
  reachability: poolMembership.has(idOf(row)) ? 'present_in_source_pool_gates_and_natural_roll_frequency_unverified' : row.loot_type === '净化遗物' ? 'purification_transformation_target' : 'no_direct_pool_membership_needs_event_evolution_or_source_review',
  ability_known_gap_count: abilityIndex.get(Number(row.ability_item_id))?.issues.length ?? null,
  tests: { purification_condition_asserted: curseIds.has(idOf(row)) && suitePassed, every_combat_effect: 'unverified', natural_acquisition: 'unverified_per_id' },
}));

const materialSources = new Map();
const addMaterialSource = (id, source) => {
  if (!materialSources.has(Number(id))) materialSources.set(Number(id), []);
  materialSources.get(Number(id)).push(source);
};
for (const id of [103, 106, 107, 108, 501, 502, 503, 504, 90002]) addMaterialSource(id, 'R04 reconstructed boss growth drop');
addMaterialSource(101, 'world kill reward and original work/achievement/NPC rewards');
addMaterialSource(102, 'original MagicPoint instant loot and adventure events; original per-monster chance not recovered');
for (const row of tables.MaterialData) if (idOf(row) >= 10101 && idOf(row) <= 10501) addMaterialSource(idOf(row), 'R04 reconstructed regional room harvest');
for (const row of tables.MonsterWorkData) addMaterialSource(row.materia_id, `original dispatch:${idOf(row)}`);
for (const table of ['SubAchieveData', 'AchieveData', 'NPCFunctionData']) for (const row of tables[table]) {
  for (const token of String(row.reward_get_materials ?? row.finish_talk_reward ?? '').split(/[,|]/)) {
    const [id, amount] = token.split(':').map(Number);
    if (id > 0 && amount > 0) addMaterialSource(id, `original configured reward:${table}:${idOf(row)}`);
  }
}
for (const row of tables.MallTradeData.filter(x => x.Enable)) for (const detail of row.Details ?? []) {
  const target = indices.MallTradeDetailsData.get(Number(detail.DetailsId));
  for (const id of ids(target?.MaterialId ?? detail.DetailsId)) addMaterialSource(id, `mall:${idOf(row)}:${['Money', 'Ad', 'Other'].includes(row.GoodsPayType) ? 'R05 gold conversion' : 'original currency'}`);
}
for (const row of tables.ShopTreasureBoxData) {
  for (const token of String(row.sub_data_id_list).split('|')) {
    const [id, amount, weight] = token.split(':').map(Number);
    if (id > 0 && amount > 0 && weight > 0) addMaterialSource(id, `box:${idOf(row)}:weighted`);
  }
  for (const token of String(row.guaranteed_id).split('|')) {
    const [id, amount] = token.split(':').map(Number);
    if (id > 0 && amount > 0) addMaterialSource(id, `box:${idOf(row)}:R06 guarantee cadence`);
  }
}
const materialAudit = tables.MaterialData.map(row => ({ id: idOf(row), name: nameOf(row), type: row.item_type,
  sources: unique(materialSources.get(idOf(row)) ?? []),
  status: row.item_type === 'TokenItem' ? 'unlock_via_relationship_conditions_not_inventory_quantity' : materialSources.has(idOf(row)) ? 'source_path_present_natural_duration_unverified' : 'no_implemented_natural_source_identified',
}));
for (const row of materialAudit) if (row.id === 901) { row.status = 'camp_service_box_opened_for_gold_inventory_item_not_produced'; row.sources = ['open_camp_treasure_boxes / original NPC gacha service']; }
const missingWeaponRefs = tables.CharData.flatMap(row => ids(row.can_equip_weapon_id_list).filter(id => !indices.WeaponData.has(id)).map(id => ({ character_id: idOf(row), weapon_id: id })));
const knownGaps = [
  { priority: 'P1', area: 'effects', detail: 'NormalValue/Random ability conditions, StateChange components and source-calculated attribute expressions remain partial. Consult every per-ID issue.' },
  { priority: 'P1', area: 'world_acceptance', detail: 'All 241 tasks/62 groups are asserted in accelerated domain simulation. A fresh-save world/UI playthrough of all achievements and a natural economy time-budget audit have not been completed.' },
  { priority: 'P1', area: 'special_modes', detail: 'Bounty, chaos/challenge modes and production enemy AI need independent source-driven parity and UI acceptance; having 40001/504 resource replacements does not prove these modes are migrated.' },
  { priority: 'P1', area: 'apk_parity', detail: 'No assertion in these ledgers establishes frame/timing, animation, collision, numerical formula or original APK behavior parity.' },
  { priority: 'P2', area: 'source_records', detail: '8 weapon IDs referenced by character equip lists have no WeaponData records; admin character 8 remains excluded.', records: missingWeaponRefs },
  { priority: 'P2', area: 'map_content', detail: '19 island environments have no recovered NodeData route/fight definition; not promoted into an invented sixth region.' },
  { priority: 'P2', area: 'economy_balance', detail: 'Reconstructed boss rewards, offline mall prices, box guarantee cadence and amplifier composition provide acquisition paths but need balance/playtime evaluation.' },
];

const shared = {
  schema: 1, generated_utc: new Date().toISOString(),
  implementation_hashes: Object.fromEntries(['scripts/domain/systems.gd', 'scripts/domain/effects.gd', 'scripts/domain/combat.gd', 'tests/systems_test.gd'].map(file => [file, hash(text(file))])),
  evidence: { systems: { assertions: systemsTest.assertions, failures: systemsTest.failures, success: suitePassed }, combat: { assertions: combatTest.assertions, failures: combatTest.failures }, campaign: { assertions: campaignTest.assertions, failures: campaignTest.failures } },
  acceptance_rule: 'A copied row or a present handler is not a completed migration. Per-ID world/UI and original APK parity require separate acceptance evidence.',
};
const output = (filename, report) => fs.writeFileSync(path.join(project, 'reports', filename), JSON.stringify(report, null, 2) + '\n');
output('systems-ledger.json', { ...shared, summary: { rows: systemRows.length, by_table: tally(systemRows, 'table'), by_status: tally(systemRows, 'implementation') }, reconstructed_rules: reconstructedRules, rows: systemRows,
  reachability_audit: { method: 'Static source/producer audit plus focused domain transaction tests. Test grant_material calls are explicitly excluded as natural sources.', materials: materialAudit, amplifiers: { tiers: tally(tables.RelationshipAmplifyData, 'rare'), tier1_source: 'R04 random original Tier1 boss reward', higher_tier_source: 'R07 three identical lower-tier composition, next-tier random pool', every_id_collection_and_effect: 'unverified' }, missing_weapon_references: missingWeaponRefs, no_source_material_ids: materialAudit.filter(row => row.status === 'no_implemented_natural_source_identified').map(row => row.id) }, known_gaps: knownGaps });
output('achievements-ledger.json', { ...shared, summary: { groups: achievementGroups.length, tasks: achievementTasks.length, conditions: unlockRows.length, types: tally(unlockRows, 'type'), task_domain_claims: taskIds.size, group_domain_claims: groupIds.size, achievement_condition_dependency_closure: conditionClosure.size, missing_condition_ids: [...missingConditions] }, group_rows: achievementGroups, task_rows: achievementTasks, condition_rows: unlockRows, known_gaps: knownGaps.filter(row => ['world_acceptance', 'source_records', 'economy_balance'].includes(row.area)) });
output('effects-ledger.json', { ...shared, summary: { abilities: abilityRows.length, buffs: buffRows.length, system_buff_rows: tables.Buffs.length, combat_importer_additional_buff_rows: buffRows.filter(row => row.provenance === 'combat_importer_additional_record').length, loot: lootRows.length, abilities_by_status: tally(abilityRows, 'implementation'), buffs_by_status: tally(buffRows, 'implementation'), loot_without_direct_pool_membership: lootRows.filter(row => !row.pool_membership.length).length }, ability_rows: abilityRows, buff_rows: buffRows, loot_rows: lootRows, known_gaps: knownGaps.filter(row => ['effects', 'apk_parity', 'world_acceptance'].includes(row.area)) });
console.log(JSON.stringify({ systems_rows: systemRows.length, achievement_tasks: achievementTasks.length, achievement_groups: achievementGroups.length, conditions: unlockRows.length, abilities: abilityRows.length, buffs: buffRows.length, loot: lootRows.length, ability_known_gap_rows: abilityRows.filter(row => row.issues.length).length, buff_review_rows: buffRows.filter(row => row.issues.length).length, natural_material_source_gaps: materialAudit.filter(row => row.status === 'no_implemented_natural_source_identified').map(row => row.id) }));
