import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const absolute = name => path.join(root, name);
const read = name => JSON.parse(fs.readFileSync(absolute(name), 'utf8'));
const optional = name => fs.existsSync(absolute(name)) ? read(name) : null;
const files = directory => fs.readdirSync(absolute(directory), { withFileTypes: true }).flatMap(entry => {
  const name = `${directory}/${entry.name}`;
  return entry.isDirectory() ? files(name) : [name];
});
const normalize = value => value.replaceAll('\\', '/').split('/').at(-1).replace(/\.(prefab|asset|ogg|wav|png)$/i, '').toLowerCase();
const catalog = read('assets/catalog.json');
const media = read('assets/combat_presentation/catalog.json');
const environment = read('assets/environment_effects/catalog.json');
const campaign = read('assets/data/campaign.json');
const combat = read('assets/data/combat.json');
const rules = read('assets/environment_rules.json');
const weaponData = read('assets/data/WeaponData.json');
const code = new Map(files('scripts').filter(name => name.endsWith('.gd')).map(name => [name, fs.readFileSync(absolute(name), 'utf8')]));
const resources = new Map();
function resource(kind, key) {
  const id = `${kind}:${normalize(key)}`;
  if (!resources.has(id)) resources.set(id, { kind, key: normalize(key), catalog_keys: [], catalogs: [], references: [], runtime_entries: [], clips: [], payloads: [] });
  return resources.get(id);
}
function index(kind, entries, origin) {
  for (const [key, value] of Object.entries(entries)) {
    const row = resource(kind, key);
    row.catalog_keys.push(key);
    row.catalogs.push(`${origin}#/${kind}/${key}`);
    if (kind === 'audio') {
      const layers = typeof value === 'string' ? [{ clips: [value] }] : value;
      row.clips.push(...layers.flatMap(layer => layer.clips ?? []));
      row.payloads.push(...row.clips);
    } else if (kind === 'ui') row.payloads.push(typeof value === 'string' ? value : value.path);
    else {
      row.converted_layers_by_catalog ??= [];
      row.converted_layers_by_catalog.push({ origin, layers: value.layers?.length ?? 0 });
    }
  }
}
index('effects', media.effects, 'assets/combat_presentation/catalog.json');
index('effects', environment.effects, 'assets/environment_effects/catalog.json');
index('audio', media.audio, 'assets/combat_presentation/catalog.json');
index('audio', catalog.audio, 'assets/catalog.json');
index('ui', catalog.ui, 'assets/catalog.json');
const byKey = new Map();
for (const row of resources.values()) {
  if (!byKey.has(row.key)) byKey.set(row.key, []);
  byKey.get(row.key).push(row);
}
function record(value, evidence) {
  for (const row of byKey.get(normalize(value)) ?? []) {
    // SoundData aliases overlap ordinary NPC and item IDs; require audio context.
    if (row.kind === 'audio' && /^\d+$/.test(row.key) && !/sound|voice|music|audio/i.test(evidence.field ?? '')) continue;
    row.references.push(evidence);
  }
}
const metadataFields = new Set(['source', 'path', 'animations', 'source_name', 'source_sha256', 'requested_effects', 'name', 'Name', 'Name_EDT', 'Description_EDT', 'description', 'Description']);
function walk(value, origin, pointer = '', state = {}, visitor = record) {
  if (typeof value === 'string') {
    visitor(value, { origin, pointer, field: state.field ?? '', evidence: state.disabled ? 'disabled_configuration' : 'configuration_reference', ...state });
    if (value.startsWith('{') || value.startsWith('[')) {
      try { walk(JSON.parse(value), origin, `${pointer}#serialized`, state, visitor); } catch { /* Some authored descriptions start with punctuation. */ }
    }
  } else if (Array.isArray(value)) value.forEach((child, i) => walk(child, origin, `${pointer}/${i}`, state, visitor));
  else if (value && typeof value === 'object') {
    const next = { ...state, disabled: state.disabled || value.enabled === false };
    if (typeof value.type === 'string' && value.type.startsWith('EET_')) next.command = value.type;
    for (const [field, child] of Object.entries(value)) {
      if (!metadataFields.has(field)) walk(child, origin, `${pointer}/${field}`, { ...next, field }, visitor);
    }
  }
}
for (const name of files('assets/data').filter(name => name.endsWith('.json'))) walk(read(name), name);
walk(rules, 'assets/environment_rules.json');
// Stop at unquoted comments so a commented literal cannot become binding proof.
for (const [origin, source] of code) {
  let method = '<class>';
  source.split('\n').forEach((line, lineIndex) => {
    const declaration = line.match(/^(?:static )?func ([\w]+)\(/);
    if (declaration) method = declaration[1];
    for (const match of line.matchAll(/#|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g)) {
      if (match[0] === '#') break;
      record(match[0].slice(1, -1), { origin, line: lineIndex + 1, method, evidence: 'code_literal_reference', field: line.trim() });
    }
  });
}
function entry(origin, method) {
  const line = (code.get(origin)?.split('\n') ?? []).findIndex(value => new RegExp(`^(?:static )?func ${method}\\(`).test(value));
  return { origin, method, line: line + 1, present: line >= 0 };
}
function glbJson(filename) {
  const fd = fs.openSync(absolute(filename), 'r');
  try {
    const header = Buffer.alloc(20);
    fs.readSync(fd, header, 0, 20, 0);
    if (header.toString('ascii', 0, 4) !== 'glTF' || header.readUInt32LE(16) !== 0x4e4f534a) throw new Error(`Invalid GLB JSON: ${filename}`);
    const json = Buffer.alloc(header.readUInt32LE(12));
    fs.readSync(fd, json, 0, json.length, 20);
    return JSON.parse(json.toString('utf8'));
  } finally { fs.closeSync(fd); }
}
const anchors = [];
const environmentKeys = Object.keys(environment.effects).sort((a, b) => b.length - a.length);
for (const [id, definition] of Object.entries(catalog.environments)) {
  const filename = definition.path.replace(/^res:\/\//, '');
  const counts = new Map();
  for (const [nodeIndex, node] of (glbJson(filename).nodes ?? []).entries()) {
    const name = (node.name ?? '').toLowerCase();
    const address = environmentKeys.find(key => name === key || name.startsWith(`${key}_`));
    if (!address) continue;
    const previous = counts.get(address) ?? { count: 0, first_node: nodeIndex, sample_names: [] };
    previous.count += 1;
    if (previous.sample_names.length < 3) previous.sample_names.push(node.name);
    counts.set(address, previous);
  }
  for (const [key, value] of counts) {
    const evidence = { origin: filename, pointer: `/nodes/${value.first_node}`, evidence: 'serialized_scene_anchor', environment_id: id, count: value.count, sample_names: value.sample_names };
    resource('effects', key).references.push(evidence);
    anchors.push({ key, ...evidence });
  }
}
for (const row of resources.values()) {
  for (const field of ['catalog_keys', 'catalogs', 'clips', 'payloads']) row[field] = [...new Set(row[field].filter(Boolean))];
  row.missing_payloads = row.payloads.filter(value => value.startsWith('res://') && !fs.existsSync(absolute(value.slice(6))));
  row.references = [...new Map(row.references.map(value => [JSON.stringify(value), value])).values()];
  const literals = row.references.filter(ref => ref.evidence === 'code_literal_reference');
  const config = row.references.filter(ref => ref.evidence === 'configuration_reference');
  const scene = row.references.filter(ref => ref.evidence === 'serialized_scene_anchor');
  row.status = literals.length ? 'code_reference_candidate' : scene.length ? 'scene_anchor_candidate' : config.length ? 'configuration_reference_only' : row.references.length ? 'disabled_configuration_only' : 'indexed_only';
  row.gameplay_reachability = 'not_established_by_static_reference';
  row.runtime_verified = false;
  if (row.kind === 'effects') {
    if (config.some(ref => ref.origin === 'assets/data/combat.json')) row.runtime_entries.push(entry('scripts/presentation/combat_presentation.gd', 'emit_effect'));
    if (scene.length || config.some(ref => ref.origin === 'assets/environment_rules.json')) row.runtime_entries.push(entry('scripts/presentation/environment_effects.gd', 'configure'), entry('scripts/presentation/environment_effects.gd', 'trigger_at'));
    if (config.some(ref => ref.origin === 'assets/data/environment_feedback.json')) row.runtime_entries.push(entry('scripts/presentation/environment_effects.gd', '_on_presentation_requested'), entry('scripts/presentation/environment_effects.gd', 'trigger_at'));
    if (config.some(ref => ref.origin === 'assets/data/player_lifecycle.json')) row.runtime_entries.push(entry('scripts/presentation/player_lifecycle.gd', 'begin_action'), entry('scripts/presentation/player_lifecycle.gd', '_start_effect'));
    if (config.some(ref => ref.origin === 'assets/data/pickup_feedback.json')) row.runtime_entries.push(entry('scripts/ground_loot.gd', '_bind_pickup_effect'), entry('scripts/presentation/environment_effects.gd', 'register_anchor'));
  } else if (row.kind === 'audio' && config.length) {
    if (config.some(ref => ref.origin === 'assets/data/resource_bindings.json')) row.runtime_entries.push(entry('scripts/presentation/resource_audio.gd', 'play_event'), entry('scripts/presentation/resource_audio.gd', 'enter_environment'), entry('scripts/presentation/resource_audio.gd', '_physics_process'));
    if (config.some(ref => ref.origin === 'assets/data/player_lifecycle.json')) row.runtime_entries.push(entry('scripts/presentation/player_lifecycle.gd', '_dispatch_due'), entry('scripts/presentation/resource_audio.gd', 'play_named'));
    if (config.some(ref => ref.origin === 'assets/environment_rules.json')) row.runtime_entries.push(entry('scripts/world_interactions.gd', '_sound'), entry('scripts/presentation/resource_audio.gd', 'play_named'));
    if (config.some(ref => !['assets/data/resource_bindings.json', 'assets/data/player_lifecycle.json', 'assets/environment_rules.json'].includes(ref.origin))) row.runtime_entries.push(entry('scripts/presentation/combat_presentation.gd', 'play_sound'));
  }
  row.runtime_entries.push(...literals.filter(ref => ref.method !== '<class>').map(ref => entry(ref.origin, ref.method)));
  row.runtime_entries = [...new Map(row.runtime_entries.map(value => [`${value.origin}:${value.method}`, value])).values()];
}
// Flattened combined prefabs carry child particle layers without their address.
// Matching layer-name sets is a reuse candidate, not proof of equal transforms.
for (const [key, definition] of Object.entries(environment.effects)) {
  const row = resource('effects', key);
  if (row.status !== 'indexed_only') continue;
  const names = definition.layers.filter(layer => layer.active !== false && layer.renderer?.enabled !== false).map(layer => layer.name);
  if (names.length < 2) continue;
  row.embedded_layer_candidates = Object.entries(environment.effects).filter(([parentKey, parent]) => {
    const parentRow = resource('effects', parentKey);
    return parentKey !== key && parent.layers.length > definition.layers.length && !['indexed_only', 'disabled_configuration_only', 'embedded_layer_candidate'].includes(parentRow.status) && names.every(name => parent.layers.some(layer => layer.name === name));
  }).map(([parentKey]) => ({ parent_key: parentKey, matching_render_layer_names: names, evidence: 'observed_layer_name_subset', equality: 'transforms_timing_and_modules_not_asserted_equivalent' }));
  if (row.embedded_layer_candidates.length) row.status = 'embedded_layer_candidate';
}
const clipUsers = new Map();
for (const row of resources.values()) {
  if (row.kind !== 'audio' || ['indexed_only', 'disabled_configuration_only'].includes(row.status)) continue;
  for (const clip of row.clips) {
    if (!clipUsers.has(clip)) clipUsers.set(clip, []);
    clipUsers.get(clip).push(row.key);
  }
}
for (const row of resources.values()) {
  if (row.kind !== 'audio') continue;
  row.shared_with_referenced_keys = [...new Set(row.clips.flatMap(clip => clipUsers.get(clip) ?? []).filter(key => key !== row.key))];
  if (row.status === 'indexed_only' && row.clips.length && row.clips.every(clip => clipUsers.has(clip))) row.status = 'shared_audio_alias';
  row.review_category = row.status !== 'indexed_only' ? 'binding_evidence_present_parity_unverified' : /voice|(?:^|_)n(?:n)?(?:attack|satk|subskill|mainskill)/i.test(row.key) ? 'unused_voice_or_take_review_original_usage_before_binding' : 'no_trigger_evidence_found';
}
const uiByDigest = new Map();
for (const row of resources.values()) {
  if (row.kind !== 'ui') continue;
  row.payload_sha256 = row.payloads.filter(value => fs.existsSync(absolute(value.slice(6)))).map(value => ({ path: value, sha256: crypto.createHash('sha256').update(fs.readFileSync(absolute(value.slice(6)))).digest('hex') }));
  for (const payload of row.payload_sha256) {
    if (!uiByDigest.has(payload.sha256)) uiByDigest.set(payload.sha256, []);
    uiByDigest.get(payload.sha256).push(row);
  }
}
for (const row of resources.values()) {
  if (row.kind !== 'ui') continue;
  const same = row.payload_sha256.flatMap(value => uiByDigest.get(value.sha256) ?? []).filter(value => value !== row);
  row.shared_content_keys = [...new Set(same.map(value => value.key))];
  if (row.status === 'indexed_only' && same.some(value => value.references.length)) row.status = 'shared_ui_alias';
}
for (const kind of ['characters', 'enemies', 'weapons', 'environments']) {
  for (const [key, definition] of Object.entries(catalog[kind])) {
    const row = resource(kind, key);
    row.catalog_keys = [key];
    row.catalogs = [`assets/catalog.json#/${kind}/${key}`];
    row.payloads = [definition.path];
    row.missing_payloads = fs.existsSync(absolute(definition.path.slice(6))) ? [] : [definition.path];
    row.source = { path: definition.source, sha256: definition.source_sha256, original_source_exists: fs.existsSync(path.resolve(root, '..', definition.source ?? '')) };
    row.animation_count = definition.animations?.length ?? 0;
    row.gameplay_reachability = 'not_established_by_static_reference';
    row.runtime_verified = false;
    row.status = 'dynamic_model_binding_candidate';
    row.runtime_entries = [entry('scripts/world.gd', 'asset_path')];
    const loader = { characters: 'create_player', enemies: 'spawn_wave', environments: 'load_environment' }[kind];
    if (loader) row.runtime_entries.push(entry('scripts/world.gd', loader));
    if (kind === 'characters' || kind === 'enemies') row.runtime_entries.push(entry('scripts/actor.gd', 'set_visual'));
    if (kind === 'characters' || kind === 'enemies') {
      const i = combat[kind].findIndex(value => String(value.id) === key);
      if (i >= 0) row.references.push({ origin: 'assets/data/combat.json', pointer: `/${kind}/${i}`, evidence: 'fighter_configuration' });
    } else if (kind === 'weapons') {
      const i = weaponData.findIndex(value => String(value.id ?? value.Id) === key);
      if (i >= 0) row.references.push({ origin: 'assets/data/WeaponData.json', pointer: `/${i}`, evidence: 'equipment_configuration' });
      row.runtime_entries.push(entry('scripts/actor.gd', 'equip_weapon'));
    } else {
      const nodes = campaign.Nodes.filter(value => String(value.EnvironmentId || value.Id) === key);
      const special = campaign.SpecialStages.filter(value => String(value.EnvironmentId || value.Id) === key);
      const supplemental = campaign.SupplementalEnvironments.find(value => String(value.Id) === key);
      row.campaign_node_ids = nodes.map(value => value.Id);
      row.special_stage_ids = special.map(value => value.Id);
      row.supplemental_kind = supplemental?.Kind ?? null;
      row.status = nodes.length ? 'campaign_environment_candidate' : supplemental?.Kind === 'MainCity' ? 'camp_environment_candidate' : supplemental?.Kind === 'IslandWithoutNodeData' ? 'environment_without_route_data' : 'special_or_preserved_environment';
      row.references = [...nodes.map(value => ({ origin: 'assets/data/campaign.json', node_id: value.Id, evidence: 'enabled_campaign_node' })), ...special.map(value => ({ origin: 'assets/data/campaign.json', stage_id: value.Id, evidence: 'special_stage_configuration', kind: value.PracticeKind }))];
    }
  }
}
const rows = [...resources.values()].sort((a, b) => a.kind.localeCompare(b.kind) || a.key.localeCompare(b.key));
const summary = {};
for (const row of rows) {
  summary[row.kind] ??= {};
  summary[row.kind][row.status] = (summary[row.kind][row.status] ?? 0) + 1;
}
const apkBundle = optional('reports/RESOURCE_APK_REA_EVIDENCE.json');
const apkInventory = apkBundle?.records.find(record => record.operation === 'inventory_artifact');
const ledgers = ['effects', 'systems', 'achievements'].map(name => {
  const filename = `reports/${name}-ledger.json`;
  const ledger = optional(filename);
  if (!ledger) return { filename, missing: true };
  return { filename, generated_utc: ledger.generated_utc, summary: ledger.summary, known_gaps: ledger.known_gaps, stale_implementation_hashes: Object.entries(ledger.implementation_hashes ?? {}).filter(([file, digest]) => !fs.existsSync(absolute(file)) || crypto.createHash('sha256').update(fs.readFileSync(absolute(file))).digest('hex') !== digest).map(([file]) => file) };
});
const assetFiles = files('assets').filter(name => !name.endsWith('.import'));
const extensions = {};
for (const name of assetFiles) extensions[path.extname(name) || '(none)'] = (extensions[path.extname(name) || '(none)'] ?? 0) + 1;
const missingEffects = new Map((media.missing_effects ?? []).map(key => [normalize(key), { key, references: [] }]));
walk(combat, 'assets/data/combat.json', '', {}, (value, evidence) => {
  if (missingEffects.has(normalize(value))) missingEffects.get(normalize(value)).references.push(evidence);
});
const apkScanPath = 'reports/unresolved-effects-apk.json';
const apkScan = optional(apkScanPath);
const apkComparison = apkScan ? {
  report: apkScanPath,
  report_sha256: crypto.createHash('sha256').update(fs.readFileSync(absolute(apkScanPath))).digest('hex'),
  evidence_type: apkScan.evidence_type,
  source: apkScan.source,
  apk_identity_matches_inventory: apkInventory ? apkScan.source.apk_sha256 === apkInventory.normalized_result.manifest.root_sha256 : null,
  coverage: apkScan.coverage,
  queries: Object.entries(apkScan.queries).map(([key, query]) => ({
    key,
    status: query.status,
    exact_manifest_match_count: query.exact_manifest_matches.length,
    exact_fx_gameobject_match_count: query.exact_fx_gameobject_matches.length,
    source_references: query.source_references,
    near_names: query.near_names.map(value => ({ address: value.address, already_imported: value.already_imported, relationship: value.relationship })),
    action: query.action,
  })),
  observations: apkScan.observations,
  inferences: apkScan.inferences,
  unknowns: apkScan.unknowns,
} : { report: apkScanPath, status: 'report_unavailable' };
for (const row of missingEffects.values()) {
  const query = apkComparison.queries?.find(value => normalize(value.key) === normalize(row.key));
  row.apk_scan_status = query?.status ?? 'not_checked';
}
function reviewGroup(kind, keys) {
  const name = keys.join(' ');
  if (kind === 'effects') {
    if (/portal/.test(name)) return '传送门颜色变体';
    if (/energyrift/.test(name)) return '能量裂隙阶段';
    if (/treasure|prop.*appear/.test(name)) return '宝箱、掉落和道具';
    if (/wallthorn|dart|spine|airwall/.test(name)) return '陷阱和屏障';
    return '场景装饰与能量';
  }
  if (/voice|unitychan/.test(name)) return '角色语音和备用录音';
  if (/npc_|blacksmith/.test(name)) return 'NPC声音';
  if (/audio_music|anim_videoplayer/.test(name)) return '登录、过场和区域提示音乐';
  if (/ambient|ambiance/.test(name)) return '环境氛围';
  if (/audio_ui_|audio_fx_btn/.test(name)) return '界面反馈';
  if (/trap_/.test(name)) return '陷阱声音';
  if (/envunit_|chest|treasure|boilingwater|cutvegetable|changestage|magic_startgame/.test(name)) return '环境交互和宝箱';
  if (/sound_monster|duyanjuren|frog_move|shuixiyi_move|haixiang|jiaolu|jingshi|jushimoxiang|moguguai|tubolong|xiaoxueguai|rabbitatk|monster_chimera/.test(name)) return '怪物动作声音';
  if (/skill|swordatk|wandatk|wandbullet|zhendanghudun|lightmagicepic/.test(name)) return '武器和技能声音';
  return '其他战斗声音';
}
const unboundAudio = new Map();
for (const row of rows.filter(value => value.kind === 'audio' && ['indexed_only', 'disabled_configuration_only'].includes(value.status))) {
  for (const clip of row.clips.filter(value => !clipUsers.has(value))) {
    if (!unboundAudio.has(clip)) unboundAudio.set(clip, []);
    unboundAudio.get(clip).push(row.key);
  }
}
const result = {
  schema: 3,
  scope: 'Converted catalogs, raw AudioClip fallback names, environment GLB anchors, model configuration, retained APK inventory and bounded missing-effect manifest/FX scan. Static references never establish execution or full original parity.',
  apk: apkInventory ? { evidence_id: apkInventory.evidence_id, manifest: apkInventory.normalized_result.manifest, limitations: apkInventory.limitations } : { status: 'evidence_bundle_unavailable' },
  source_trees: ['OfflineUnity', 'RecoveredUnity', 'Recovery'].map(name => ({ path: `../${name}`, present: fs.existsSync(path.resolve(root, '..', name)) })),
  asset_inventory: { files: assetFiles.length, extensions, unique_audio_payloads: new Set(rows.filter(row => row.kind === 'audio').flatMap(row => row.clips)).size, unique_ui_payloads: uiByDigest.size },
  summary,
  scene_anchor_summary: { environments: Object.keys(catalog.environments).length, matched_effect_types: new Set(anchors.map(row => row.key)).size, matched_nodes: anchors.reduce((sum, row) => sum + row.count, 0) },
  missing_effect_definitions: [...missingEffects.values()],
  missing_effect_apk_comparison: apkComparison,
  unbound_audio_payloads: [...unboundAudio].map(([clip, keys]) => ({ clip, keys, review_group: reviewGroup('audio', keys), grouping_evidence: 'inferred_from_names_not_a_recovered_trigger' })),
  unbound_effects: rows.filter(row => row.kind === 'effects' && row.status === 'indexed_only').map(row => ({ key: row.key, review_group: reviewGroup('effects', [row.key]), grouping_evidence: 'inferred_from_names_not_a_recovered_trigger' })),
  prior_migration_ledgers: ledgers,
  limitations: [
    'Code literals include constants, exclusion lists and helper definitions; a literal alone does not prove execution.',
    'Configuration includes unused actions, Buffs and summons. Enabled flags are respected; natural root/condition reachability is not fully solved.',
    'Model configuration and loader paths establish an adapter, not per-character/per-room natural playthrough or visual parity.',
    'Scene anchors are serialized names; source activation, distance culling, particle budgets and play-on-awake gates still apply. Embedded-layer candidates are observed name subsets, not asserted transform/timing equivalence.',
    'Audio aliases share physical clips. Unused voice takes are preserved for original-usage review, never arbitrarily assigned to gameplay.',
    'REA APK inventory proves archive identity and membership, not Unity bundle object semantics or original execution.',
    'Fonts, textures, shaders and materials are supporting payloads counted by extension; they need no independent gameplay trigger.',
    'Prior migration ledgers keep original timestamps; changed implementation hashes invalidate using their totals as current behavioral verdicts.',
  ],
  resources: rows,
};
fs.mkdirSync(absolute('reports'), { recursive: true });
fs.writeFileSync(absolute('reports/resource-usage.json'), JSON.stringify(result, null, 2) + '\n');
const indexedOnly = rows.filter(row => ['indexed_only', 'disabled_configuration_only'].includes(row.status));
const disabledOnly = indexedOnly.filter(row => row.status === 'disabled_configuration_only');
const islands = rows.filter(row => row.status === 'environment_without_route_data');
const labels = { effects: '特效', audio: '音频名称/别名', ui: 'UI图', characters: '角色模型', enemies: '敌人模型', weapons: '武器模型', environments: '环境模型' };
function groupedLines(values, kind) {
  const groups = new Map();
  for (const value of values) {
    if (!groups.has(value.review_group)) groups.set(value.review_group, []);
    groups.get(value.review_group).push(value);
  }
  return [...groups].flatMap(([group, entries]) => [
    `### ${group}（${entries.length}${kind === 'audio' ? '个物理clip' : '个特效'}）`, '',
    ...entries.map(value => kind === 'audio' ? `- ${value.keys.map(key => `\`${key}\``).join('、')}；文件 \`${path.basename(value.clip)}\`` : `- \`${value.key}\``), '',
  ]);
}
const lines = [
  '# 资源接入盘点', '',
  '当前工程静态审计。索引、配置、代码字面量、动态加载入口、场景锚点与运行验收分别记录；任何静态引用均不标记为“已完整实装”。', '',
  '| 类别 | 总数 | 状态分布 |', '| --- | ---: | --- |',
  ...Object.entries(summary).map(([kind, values]) => `| ${labels[kind]} | ${Object.values(values).reduce((a, b) => a + b, 0)} | ${Object.entries(values).map(([status, count]) => `${status}: ${count}`).join('; ')} |`), '',
  `音频名称不区分大小写归并，物理音频文件去重为 ${result.asset_inventory.unique_audio_payloads} 个，其中 ${unboundAudio.size} 个物理clip暂未找到有效引用；共用别名不重复算待补音效。39个UI名称按文件SHA-256去重为 ${uiByDigest.size} 个内容，逐项记录相同内容别名。特效覆盖战斗目录与环境目录的并集。`, '',
  '## 原APK与恢复边界', '',
  ...(apkInventory ? [`- APK SHA-256：\`${apkInventory.normalized_result.manifest.root_sha256}\`。`, `- REA Evidence：\`${apkInventory.evidence_id}\`；节点 ${apkInventory.normalized_result.manifest.node_count}，occurrence ${apkInventory.normalized_result.manifest.occurrence_count}。完整证据：\`RESOURCE_APK_REA_EVIDENCE.json\`。`] : ['- 本轮REA导出不可用。']),
  ...result.source_trees.map(row => `- \`${row.path}\`：${row.present ? '当前存在' : '当前不存在，历史来源路径无法直接复核'}。`), '',
  'REA这里证明APK身份及ZIP成员，不能证明原游戏实际触发或全部Unity对象已转换。需要结合缓存、原资源哈希、Bundle对象和原运行证据逐项比对。', '',
  '## 接入证据', '',
  '- 角色、敌人、武器已有原ID配置和动态加载器；逐项记录方法及配置路径，仍需自然流程验收。',
  `- ${result.scene_anchor_summary.matched_effect_types} 种环境特效匹配 ${result.scene_anchor_summary.matched_nodes} 个GLB节点；运行时还受激活、距离与粒子预算限制。`,
  '- 战斗动作、Buff、召唤物和环境交互逐项记录JSON引用路径；禁用命令不能单独算有效引用。',
  '- 本轮新增代码引用会自动纳入；代码存在仍需对应测试或运行记录证明触发。', '',
  '- 玩家进场、离场和复活事件现由 `player_lifecycle.json` 与 `player_lifecycle.gd` 对接；上升/降落位移由 `player_transfer.gd` 补充。原事件与本地位移分开保留。',
  '- 宝箱品质开箱特效依照原配置 `EnvUnitCfg_[19001]/TypePrefabOpenFxList` 对接。保护目标完成时选用destruction是本地流程适配；已有精确源锚点优先，读档不重播瞬时反馈。',
  '- `pickup_feedback.json` 对接矿石素材103的持续星光、原配置50004中能力道具10002的生成特效。拾取和清场释放绑定，读档恢复持续效果且不重播生成特效。未将默认道具配置泛化到所有同品质物品。',
  '- 菜单、拾取、升级、区域氛围及脚步由 `resource_bindings.json` 对接；BGM在 `resource_audio.gd::play_music` 显式选取营地和区域曲目。交互物原配置音效经 `world_interactions.gd::_sound` 转发。', '',
  '组合特效已经展平粒子层；部分独立子特效名称无直接引用，但相同渲染层已由有引用的组合特效承载，不能再次生成造成重复。以下仅断言层名集合匹配，变换、延时和模块仍需源比对。', '',
  '| 独立特效 | 承载组合特效候选 |', '| --- | --- |',
  ...rows.filter(row => row.status === 'embedded_layer_candidate').map(row => `| \`${row.key}\` | ${row.embedded_layer_candidates.map(value => `\`${value.parent_key}\``).join(', ')} |`), '',
  '## 尚未完成', '',
  `- ${islands.length} 个海岛环境缺NodeData路线/战斗定义。不能编造第六区域后宣称还原。`,
  '- 原禁用关卡、官方教学、开发测试与主城单独分类，不混算缺失海岛。',
  `- ${missingEffects.size} 个特效历史引用在战斗转换目录缺定义；最新APK精确名称扫描结果见下表，未将近名资源当作别名导入。`,
  '- 旧effects-ledger记录38项ability语义缺口和622项Buff审阅项；实现哈希已变化，这是历史待复核清单，并非本轮重新跑出的行为失败数。',
  '- 未找到自然触发不是删除资源的依据；备用语音与录音take需先确认原用途，不随机消费。', '',
  '| 海岛环境ID | 场景 |', '| --- | --- |', ...islands.map(row => `| ${row.key} | ${catalog.environments[row.key].scene_name} |`), '',
  '## 缺失定义的APK复查', '',
  ...(apkComparison.coverage ? [
    `扫描 ${apkComparison.coverage.manifest_assets} 条manifest资源、${apkComparison.coverage.manifest_bundles} 个bundle索引；解析全部 ${apkComparison.coverage.action_configuration_assets_parsed}/${apkComparison.coverage.action_configuration_assets_declared} 份动作配置（${apkComparison.coverage.action_configuration_bundles} 个包），检查 ${apkComparison.coverage.fx_bundles} 个FX包中的 ${apkComparison.coverage.fx_gameobjects} 个GameObject。`, '',
    `来源APK与REA inventory哈希${apkComparison.apk_identity_matches_inventory ? '一致' : '未确认一致'}；manifest为 \`${apkComparison.source.manifest_member}\`，SHA-256 \`${apkComparison.source.manifest_sha256}\`。完整源JSON指针、event启用状态和近名候选见 \`${apkScanPath}\`。`, '',
    '以下7个名称在声明的manifest及FX对象扫描中均未找到精确匹配。没有搜索范围外bundle中的隐藏GameObject，也没有证明native代码不存在fallback。近名只代表词法近似，未建立alias。', '',
  ] : ['APK精确名称复查报告当前不可用。', '']),
  '| 缺失特效定义 | 本地配置引用数 | APK扫描状态 | 首个原配置证据 |', '| --- | ---: | --- | --- |',
  ...[...missingEffects.values()].map(row => {
    const source = apkComparison.queries?.find(value => normalize(value.key) === normalize(row.key))?.source_references[0];
    return `| \`${row.key}\` | ${row.references.length} | ${row.apk_scan_status} | \`${source ? `${source.address}#${source.json_pointer}` : `assets/data/combat.json#${row.references[0]?.pointer ?? ''}`}\` |`;
  }), '',
  '这7个“缺定义”名称与下文7个“已有资源但原命令禁用”的特效是两组不同项目。', '',
  `## 未绑定特效完整清单（${result.unbound_effects.length}个）`, '',
  '以下用途分类仅按名称推断，不代表恢复了原触发。详细物理文件、配置、锚点和判定路径见JSON；缺少触发证据不等于必须制造新玩法。', '',
  ...groupedLines(result.unbound_effects, 'effects'),
  `## 未绑定音频完整清单（${result.unbound_audio_payloads.length}个物理clip）`, '',
  '按物理文件去重；每行列出全部尚未有效引用的名称/别名及文件。用途分类仅按名称推断。备用语音、录音take和未明事件保留，未随机分配触发。', '',
  ...groupedLines(result.unbound_audio_payloads, 'audio'),
  '## 原禁用配置资源完整清单', '',
  '原命令的enabled=false保持不变；仅禁用引用不能算有效触发，已有资源也不应因盘点而强行启用。音频物理clip可能被其他名称共用。', '',
  '| 类别 | 名称 | 首个禁用配置证据 |', '| --- | --- | --- |',
  ...disabledOnly.map(row => { const reference = row.references.find(value => value.evidence === 'disabled_configuration'); return `| ${labels[row.kind]} | \`${row.key}\` | \`${reference.origin}#${reference.pointer}\` |`; }), '',
  '## UI资源', '',
  `39个UI名称已有38个代码引用候选和1个同内容别名，没有仅索引UI。\`gold_button\` 与 \`interaction_frame\` 文件内容相同，SHA-256为 \`fcff3a0a6c4fd0f99739224cb672bae108813dd7883e2e9c909ea43397c5ce3e\`。`, '',
  '## 生成与判定边界', '',
  '- 重新生成：\`node tools/audit_resource_usage.mjs\`。逐项报告：\`reports/resource-usage.json\`。',
  '- code_reference_candidate：代码字面量候选；scene_anchor_candidate：序列化锚点；embedded_layer_candidate：组合特效含同名渲染层；configuration_reference_only：仅配置；shared_audio_alias：所有物理clip均被其他已引用名称共用；shared_ui_alias：SHA-256相同UI已有其他名称被引用；indexed_only：无触发证据；disabled_configuration_only：只有禁用命令。',
  ...result.limitations.map(value => `- ${value}`), '',
];
fs.writeFileSync(absolute('reports/RESOURCE_USAGE.md'), lines.join('\n'));
console.log(JSON.stringify({ summary, physical_audio_files: result.asset_inventory.unique_audio_payloads, scene_anchors: result.scene_anchor_summary, missing_effects: [...missingEffects.keys()], missing_payloads: rows.filter(row => row.missing_payloads.length).map(row => ({ kind: row.kind, key: row.key, paths: row.missing_payloads })) }, null, 2));
