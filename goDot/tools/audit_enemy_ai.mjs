import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {isDeepStrictEqual} from 'node:util';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const project = path.join(root, 'goDot');
const reportDirectory = path.join(project, 'reports');
const catalog = JSON.parse(fs.readFileSync(path.join(project, 'assets/data/combat.json'), 'utf8'));
const startup = JSON.parse(fs.readFileSync(path.join(project, 'assets/data/monster_behavior.json'), 'utf8'));
const nodeTypes = new Set(['Parallel', 'BinarySelector', 'ActionNode', 'ProbabilitySelector', 'ConditionalEvaluator', 'Filter', 'Switch', 'Selector', 'Merge', 'FlipSelector', 'StepIterator', 'WaitUntil', 'Sequencer', 'Repeater']);
const conditionTypes = new Set(['ConditionList', 'CheckString', 'CheckNull', 'CheckFloat', 'CheckVectorDistance', 'NCCondition_CheckTargetLineCollisionWall', 'CheckInt', 'CheckBoolean', 'NCCondition_RoleUnit_CheckAttribute', 'NCCondition_RoleUnit_CheckBuffExist']);
const taskTypes = new Set(['ActionList', 'SetFloat', 'SetInt', 'SetVariable', 'SetBoolean', 'NCTask_RefreshMonsterIndex', 'NCTask_AddBuffToUnit', 'NCTask_RoleUnit_SetCustomPropertyFloat', 'NCTask_MessageCenter_Send']);
const knownUnmappedOutputs = new Set(['ActGroup_juchifeiyao/meaninglessrunaway']);
const issues = [];
const hashBuffer = value => crypto.createHash('sha256').update(value).digest('hex');
const hashFile = async filename => {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(filename)) hash.update(chunk);
  return hash.digest('hex');
};
const typeOf = value => String(value?.$type ?? '').split('`')[0].split('.').at(-1);
const addCount = (counts, key) => { counts[key] = (counts[key] ?? 0) + 1; };
const apk = path.join(root, 'com.teamelo.dungeonchasers.apk');
const sourceEvidence = JSON.parse(execFileSync(process.env.PYTHON ?? 'python3', [path.join(project, 'tools/extract_enemy_ai_evidence.py'), '--apk', apk], {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}));
const sourceGraphs = sourceEvidence.graphs;
const counts = {nodes: {}, conditions: {}, tasks: {}};
const graphReports = {};

for (const graphName of [...new Set(catalog.enemies.map(enemy => enemy.ai))].sort()) {
  const graph = catalog.ai_graphs[graphName];
  const definition = catalog.enemies.find(enemy => enemy.ai === graphName);
  if (!graph) { issues.push(`Missing graph ${graphName}`); continue; }
  const intact = isDeepStrictEqual(graph, sourceGraphs[graphName]?.graph);
  if (!intact) issues.push(`Normalized graph differs from packaged serialization: ${graphName}`);
  const variables = graph.localBlackboard?._variables ?? {};
  const variableNames = new Map(Object.entries(variables).map(([name, value]) => [value._id, name]));
  const parameterName = parameter => variableNames.get(parameter?._targetVariableID) ?? parameter?._name ?? '';
  const parameter = (value, fallback = 0) => parameterName(value) ? {variable: parameterName(value)} : (value?._value ?? fallback);
  const nodes = new Map();
  const children = new Map();
  const incoming = new Set();
  const ignoredEditorNodes = [];
  for (const [index, node] of graph.nodes.entries()) {
    if (!Object.hasOwn(node, '$id')) { ignoredEditorNodes.push({array_index: index, type: typeOf(node)}); continue; }
    const id = String(node.$id);
    if (nodes.has(id)) issues.push(`${graphName} duplicate node ${id}`);
    nodes.set(id, node);
    children.set(id, []);
  }
  for (const edge of graph.connections) {
    const parent = String(edge._sourceNode.$ref);
    const child = String(edge._targetNode.$ref);
    if (!nodes.has(parent) || !nodes.has(child)) { issues.push(`${graphName} dangling edge ${parent}->${child}`); continue; }
    children.get(parent).push(child);
    incoming.add(child);
  }
  const roots = [...nodes.keys()].filter(id => !incoming.has(id));
  if (!roots.length || roots[0] !== '0') issues.push(`${graphName} does not have serialized node zero as its first root`);
  const reachable = new Set();
  const visit = id => {
    if (reachable.has(id)) return;
    reachable.add(id);
    for (const child of children.get(id)) visit(child);
  };
  if (roots.length) visit(roots[0]);
  const graphCounts = {nodes: {}, conditions: {}, tasks: {}};
  const actions = [];
  const predicates = [];
  const specialTasks = [];
  const selectors = [];
  const filters = [];
  const anomalies = [];
  const scanTasks = (task, nodeId, category) => {
    if (!task || !Object.keys(task).length) return;
    const type = typeOf(task);
    addCount(counts[category], type);
    addCount(graphCounts[category], type);
    if (!(category === 'conditions' ? conditionTypes : taskTypes).has(type)) issues.push(`${graphName}/${nodeId} unsupported ${category} ${type}`);
    if (category === 'conditions' && type !== 'ConditionList') predicates.push({node: nodeId, type, source: task});
    if (category === 'tasks') {
      if (parameterName(task.valueA) === 'OP_AIAction' && Object.hasOwn(task.valueB ?? {}, '_value')) actions.push({node: nodeId, action: task.valueB._value});
      if (type.startsWith('NCTask_')) specialTasks.push({node: nodeId, type, source: task});
    }
    for (const nested of task[category === 'conditions' ? 'conditions' : 'actions'] ?? []) scanTasks(nested, nodeId, category);
  };
  for (const id of reachable) {
    const node = nodes.get(id);
    const type = typeOf(node);
    addCount(counts.nodes, type);
    addCount(graphCounts.nodes, type);
    if (!nodeTypes.has(type)) issues.push(`${graphName}/${id} unsupported node ${type}`);
    scanTasks(node._condition, id, 'conditions');
    scanTasks(node._action, id, 'tasks');
    if (type === 'ProbabilitySelector') selectors.push({node: id, children: children.get(id), weights: node.childWeights.map(value => parameter(value)), fail_chance: parameter(node.failChance)});
    if (type === 'Filter') filters.push({node: id, children: children.get(id), mode: node.filterMode ?? 1, cooldown_seconds: parameter(node.coolDownTime, 5), max_count: parameter(node.maxCount, 1), policy: node.policy ?? 0, inactive_when_limited: node.inactiveWhenLimited ?? true});
    if (type === 'BinarySelector' && children.get(id).length < 2) anomalies.push({node: id, issue: 'BinarySelector has fewer than two connections and returns Optional before checking its condition.', children: children.get(id)});
  }
  graphReports[graphName] = {
    source: definition.ai_source,
    packaged_path_id: sourceGraphs[graphName]?.path_id,
    serialized_sha256: sourceGraphs[graphName]?.serialized_sha256,
    graph_json_sha256: hashBuffer(JSON.stringify(graph)), source_graph_matches: intact,
    root: roots[0], detached_root_candidates: roots.slice(1), reachable_node_count: reachable.size, serialized_node_count: graph.nodes.length,
    connected_node_count: nodes.size, ignored_editor_nodes: ignoredEditorNodes,
    unreachable_nodes: [...nodes.keys()].filter(id => !reachable.has(id)),
    blackboard: variables, counts: graphCounts, action_assignments: actions,
    predicates, special_tasks: specialTasks, probability_selectors: selectors,
    filters, anomalies,
  };
}

const actionKeys = new Set(catalog.actions.map(action => action.key));
const interruptMappings = new Map();
for (const action of catalog.actions) {
  for (const [index, event] of action.events.entries()) {
    if (!event.enabled || event.type !== 'EET_Interrupt' || !actionKeys.has(`${action.group}/${event.target}`)) continue;
    const raw = JSON.parse(event.raw);
    for (const condition of raw.Conditions ?? []) {
      if (condition.InterruptType !== 'EIT_CheckAI') continue;
      const key = `${action.group}/${condition.CompareVal}`;
      if (!interruptMappings.has(key)) interruptMappings.set(key, []);
      interruptMappings.get(key).push({source_action: action.key, event_index: index, start_time: event.time, target_action: event.target, source: raw});
    }
  }
}
const testsFile = path.join(reportDirectory, 'enemy-ai-test.json');
const tests = fs.existsSync(testsFile) ? JSON.parse(fs.readFileSync(testsFile, 'utf8')) : null;
const enemies = catalog.enemies.map(enemy => {
  const graph = graphReports[enemy.ai];
  const actions = [...new Set(graph.action_assignments.map(assignment => assignment.action))];
  const nonActionOutputs = actions.map(action => `${enemy.group}/${action}`).filter(key => !actionKeys.has(key));
  const unmapped = nonActionOutputs.filter(key => !interruptMappings.has(key));
  for (const key of unmapped) if (!knownUnmappedOutputs.has(key)) issues.push(`Unexpected unmapped AI output ${key}`);
  return {
    id: enemy.id, name: enemy.name, action_group: enemy.group,
    first_action: startup.enemies[String(enemy.id)].first_action,
    boss_action: startup.enemies[String(enemy.id)].boss_action,
    graph: enemy.ai, source: enemy.ai_source, actions,
    non_action_name_outputs: nonActionOutputs,
    source_interrupt_mappings: Object.fromEntries(nonActionOutputs.filter(key => interruptMappings.has(key)).map(key => [key, interruptMappings.get(key)])),
    unmapped_outputs: unmapped,
    interpreter_test: tests?.cases.find(test => test.enemy === enemy.id) ?? null,
    apk_runtime_parity: 'not observed',
  };
});
const report = {
  schema: 1, generated: '2026-10-24',
  artifact: {path: path.relative(root, apk), sha256: await hashFile(apk), il2cpp_sha256: '3fe1d04b7bef2b6c315161d14141b6fe9c148dd326ae6efafaccf7a29854d628'},
  methodology: 'Original NodeCanvas MonoBehaviour._serializedGraph JSON read directly from the APK UnityFS AI bundle with UnityPy, cross-checked against combat.ai_graphs. Native constructor, execution, blackboard bridge and enum semantics verified by static ARM64 disassembly. Godot interpreter reconstruction tested independently; APK execution and visual equivalence remain unobserved.',
  packaged_evidence: Object.fromEntries(Object.entries(sourceEvidence).filter(([key]) => key !== 'graphs')),
  startup_evidence: {file: 'assets/data/monster_behavior.json', ...startup.provenance},
  evidence: ['APK_MONSTER_AI_BRIDGE_NATIVE.txt', 'APK_MONSTER_NODECANVAS_NATIVE.txt', 'APK_MONSTER_INDEX_NATIVE.txt', 'APK_ATTACK_MOVEMENT_NATIVE.txt', 'APK_MOVEMENT_TIMING_NATIVE.txt'],
  coverage: {enemy_definitions: enemies.length, startup_definitions: Object.keys(startup.enemies).length, unique_graphs: Object.keys(graphReports).length, all_source_graphs_match: Object.values(graphReports).every(graph => graph.source_graph_matches), node_kinds: Object.keys(counts.nodes).length, condition_kinds: Object.keys(counts.conditions).length, task_kinds: Object.keys(counts.tasks).length, non_action_name_output_count: [...new Set(enemies.flatMap(enemy => enemy.non_action_name_outputs))].length, unmapped_output_count: [...new Set(enemies.flatMap(enemy => enemy.unmapped_outputs))].length},
  counts, enemies, graphs: graphReports,
  tests: tests ? {assertions: tests.assertions, failures: tests.failures, report: 'enemy-ai-test.json'} : {status: 'not run'},
  unknowns: ['Unity random stream is not reproduced; seeded LCG makes reconstruction deterministic.', 'Original Unity NodeCanvas/Godot frame and navigation execution have no live APK parity capture.', 'The ray graph outputs meaninglessrunaway, which has no matching direct action or enabled EIT_CheckAI mapping in its imported action group; this remains diagnosed instead of inventing an attack.', 'Reward slime twenty percent HP branch is malformed in packaged serialization; behavior and reward balance were not silently repaired.'],
  issues,
};
fs.mkdirSync(reportDirectory, {recursive: true});
fs.writeFileSync(path.join(reportDirectory, 'monster-ai-audit.json'), JSON.stringify(report, null, 2) + '\n');
const lines = [
  '# APK Monster AI Implementation', '',
  'Generated 2026-10-24 by `node goDot/tools/audit_enemy_ai.mjs`.', '',
  '## Result', '',
  `All ${enemies.length} monster definitions use the ${Object.keys(graphReports).length} packaged NodeCanvas graphs through \`DungeonEnemyAI\`. Source order, blackboard variables, distances, cooldowns, HP/buff predicates, weighted selection and phase acknowledgements are interpreted from serialized data instead of round-robin action names.`, '',
  `Source graph verification: ${report.coverage.all_source_graphs_match ? 'all graphs match MonoBehaviour._serializedGraph directly from the APK AI bundle' : 'FAILED'}. Supported rooted graph kinds: ${report.coverage.node_kinds} nodes, ${report.coverage.condition_kinds} conditions, ${report.coverage.task_kinds} tasks.`, '',
  `Interpreter validation: ${tests?.assertions ?? 0} assertions, ${tests?.failures.length ?? 'unknown'} failures. These tests exercise the Godot reconstruction, not the APK runtime.`, '',
  '## Evidence', '',
  `- APK SHA-256: \`${report.artifact.sha256}\`.`,
  `- ARM64 libil2cpp.so SHA-256: \`${report.artifact.il2cpp_sha256}\`.`,
  `- AI bundle: \`${sourceEvidence.bundle_member}\`, SHA-256 \`${sourceEvidence.bundle_sha256}\`.`,
  '- `APK_MONSTER_AI_BRIDGE_NATIVE.txt`: AIStatus_BT Init/Update and action start/end/change blackboard bridge. OP_AIAction is consumed by action-engine EIT_CheckAI interrupts; the tree does not directly interrupt attacks.',
  '- `APK_MONSTER_NODECANVAS_NATIVE.txt`: NodeCanvas native constructors and execution. JSON omission uses constructor defaults: Filter cooldown mode=1, cooldown=5s, count=1, inactive=true; SetBoolean setTo=1; Switch LoopIndex=1.',
  '- `APK_MONSTER_INDEX_NATIVE.txt`: RefreshMonsterIndex at file 0x2EC07D8 uses zero-based matching-species order before self in MonsterList for mode=0; mode=1 writes total list count. CheckFloat constructor at 0x51F9994 stores 0.05.',
  '- `APK_ATTACK_MOVEMENT_NATIVE.txt` and `APK_MOVEMENT_TIMING_NATIVE.txt`: authored movement/timing semantics used by the combat and actor integration.',
  '- `monster-ai-audit.json`: original source hashes, parsed graph identity, all rooted conditions/actions/weights/filters, source EIT_CheckAI output mappings, disconnected editor nodes and per-monster bounded sweep coverage.', '',
  `- \`assets/data/monster_behavior.json\`: all 39 exact MonsterActionCfg FirstAct/BossAct/BossActTime fields with TextAsset path IDs and hashes. Source bundle \`${startup.provenance.bundle_member}\`, SHA-256 \`${startup.provenance.bundle_sha256}\`.`,
  '- Startup actions: 38 monsters start born; flying dragon 53001 starts bosspose. Shark 52002 starts born, which adds source buff 45100206 at time zero and unconditionally enters born_bosspose at action time 0.017, then dive at action time 3.5. Its AI waits for that opening acknowledgement plus battle time >=6s before becoming attack ready.',
  '- Chimera 52001 source ActionGroup is ActGroup_chimera while the imported group is ActGroup_Chimera. The case-only difference is preserved and validated; first/boss action values are unchanged.', '',
  '## Integration', '',
  '- `configure(definition, graph, seed)` retains local variable IDs, rooted connections and source order. Serialized node zero is the first root. Detached nodes with/without serialized IDs are listed separately and do not execute.',
  '- `tick(delta, context)` returns requested action plus custom properties, self buffs, messages, trace and visited node IDs. Context supplies target availability/distance/line collision, HP ratio, speed, battle time, current action, live buffs, attack cooldown and monster cohort index.',
  '- `notify_action_started/ended` acknowledge actual action-engine transitions. The last started/ended names persist as source blackboard values; action time and AI wall-clock time remain separate.',
  '- `snapshot/restore` saves blackboard, node states, clock and reconstruction RNG; graph name/schema must match. JSON numeric round-trips are covered.', '',
  '## Per-Monster Coverage', '',
  '| ID | Name | Graph | FirstAct | BossAct | Unmapped outputs |',
  '| --- | --- | --- | --- | --- | --- |',
  ...enemies.map(enemy => `| ${enemy.id} | ${enemy.name} | ${enemy.graph} | ${enemy.first_action} | ${enemy.boss_action || 'none'} | ${enemy.unmapped_outputs.map(key => key.split('/').at(-1)).join(', ') || 'none'} |`), '',
  '## Source Gaps And Limits', '',
  '- AI outputs are decision labels, not necessarily action names. Thirteen of fourteen non-action-name outputs are mapped by enabled source EIT_CheckAI interrupts: seven runaway-to-runway mappings and six golem attack suffix mappings. Mapping events and their other conditions are retained in the audit; actual transition timing remains the action engine responsibility.',
  ...report.unknowns.map(value => '- ' + value),
  '- The reward slime graph root has 80/60/40/20 percent HP messages, but its final BinarySelector has only one child. Native BinarySelector at file 0x52307EC returns Optional when child count is below two, so the last reward branch is not activated by this source graph.',
  '- No APK runtime, desktop/mobile visual parity or device performance claim is made by this report. Those require separate integration and device acceptance.', '',
  '## Reproduce', '',
  '```sh',
  '/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --log-file /private/tmp/city-enemy-ai-test.log --script res://tests/enemy_ai_test.gd',
  'PYTHONPATH=/private/tmp/city-charge-pydeps python3 goDot/tools/build_monster_behavior.py --apk com.teamelo.dungeonchasers.apk --manifest /private/tmp/city-charge-assets/manifest.json',
  'PYTHONPATH=/private/tmp/city-charge-pydeps node goDot/tools/audit_enemy_ai.mjs',
  '```', '',
  'The audit uses Python 3 and UnityPy to read the original APK bundle; PYTHONPATH points to the UnityPy installation used in this workspace.', '',
];
fs.writeFileSync(path.join(reportDirectory, 'MONSTER_AI_IMPLEMENTATION.md'), lines.join('\n'));
console.log(JSON.stringify({coverage: report.coverage, tests: report.tests, issues}, null, 2));
if (issues.length) process.exitCode = 1;
