#include "combat_ai_probe.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <string>
#include <unordered_map>

using namespace godot;

namespace {
constexpr int FAILURE = 0, SUCCESS = 1, RUNNING = 2, RESTING = 3, OPTIONAL = 5;
constexpr double EPSILON = 0.000000001;
constexpr const char *OPCODE = "__city_native_ai_kind";
Variant lookup(const Dictionary &d, const char *key, const Variant &fallback = Variant()) {
  return d.get(StringName(key), fallback);
}
Dictionary dict(const Variant &v) { return v.get_type() == Variant::DICTIONARY ? Dictionary(v) : Dictionary(); }
Array array(const Variant &v) { return v.get_type() == Variant::ARRAY ? Array(v) : Array(); }
String text(const Variant &v) { return v.get_type() == Variant::STRING ? String(v) : v.stringify(); }
double number(const Dictionary &d, const char *key, double fallback = 0) { return double(lookup(d, key, fallback)); }
int64_t integer(const Dictionary &d, const char *key, int64_t fallback = 0) { return int64_t(lookup(d, key, fallback)); }
bool flag(const Dictionary &d, const char *key, bool fallback = false) { return lookup(d, key, fallback).booleanize(); }
}

void CombatAIProbe::_bind_methods() {
  ClassDB::bind_method(D_METHOD("configure", "runtime"), &CombatAIProbe::configure);
  ClassDB::bind_method(D_METHOD("tick", "delta", "context", "trace_enabled"), &CombatAIProbe::tick);
  ClassDB::bind_method(D_METHOD("sync_timing", "clock", "random_state"), &CombatAIProbe::sync_timing);
}

CombatAIProbe::Kind CombatAIProbe::kind(const String &name) {
  static const std::unordered_map<std::string, Kind> kinds = {
    {"Parallel", PARALLEL}, {"BinarySelector", BINARY}, {"ActionNode", ACTION_NODE},
    {"ProbabilitySelector", PROBABILITY}, {"ConditionalEvaluator", EVALUATOR},
    {"Filter", FILTER}, {"Switch", SWITCH}, {"Selector", SELECTOR}, {"Merge", MERGE},
    {"FlipSelector", FLIP}, {"StepIterator", STEP}, {"WaitUntil", WAIT},
    {"Sequencer", SEQUENCER}, {"Repeater", REPEATER}, {"ConditionList", CONDITION_LIST},
    {"CheckString", CHECK_STRING}, {"CheckNull", CHECK_NULL}, {"CheckFloat", CHECK_FLOAT},
    {"CheckVectorDistance", CHECK_DISTANCE}, {"NCCondition_CheckTargetLineCollisionWall", CHECK_WALL},
    {"CheckInt", CHECK_INT}, {"CheckBoolean", CHECK_BOOL},
    {"NCCondition_RoleUnit_CheckAttribute", CHECK_ATTRIBUTE},
    {"NCCondition_RoleUnit_CheckBuffExist", CHECK_BUFF}, {"ActionList", ACTION_LIST},
    {"SetFloat", SET_FLOAT}, {"SetInt", SET_INT}, {"SetVariable", SET_VARIABLE},
    {"SetBoolean", SET_BOOL}, {"NCTask_RefreshMonsterIndex", REFRESH_INDEX},
    {"NCTask_AddBuffToUnit", ADD_BUFF}, {"NCTask_RoleUnit_SetCustomPropertyFloat", SET_PROPERTY},
    {"NCTask_MessageCenter_Send", SEND_MESSAGE}
  };
  const auto found = kinds.find(name.utf8().get_data());
  return found == kinds.end() ? UNKNOWN : found->second;
}

String CombatAIProbe::type(const Dictionary &data) {
  if (data.has("__dungeon_ai_type")) return text(data["__dungeon_ai_type"]);
  String qualified = text(lookup(data, "$type", "")).get_slice("`", 0);
  return qualified.get_slice(".", qualified.count("."));
}

Variant CombatAIProbe::compile_value(const Variant &value) {
  if (value.get_type() == Variant::ARRAY) {
    Array result;
    Array values = value;
    for (int64_t i = 0; i < values.size(); ++i) result.append(compile_value(values[i]));
    return result;
  }
  if (value.get_type() != Variant::DICTIONARY) return value;
  Dictionary data = value, result;
  Array keys = data.keys();
  for (int64_t i = 0; i < keys.size(); ++i) {
    Variant key = keys[i];
    result[key] = key == Variant("_value") ? data[key] : compile_value(data[key]);
  }
  result[OPCODE] = int(kind(type(data)));
  return result;
}

CombatAIProbe::Kind CombatAIProbe::compiled_kind(const Dictionary &data) {
  return Kind(integer(data, OPCODE, UNKNOWN));
}

bool CombatAIProbe::configure(const Dictionary &runtime) {
  nodes.clear();
  indices.clear();
  blackboard = dict(lookup(runtime, "blackboard"));
  variables = dict(lookup(runtime, "variables"));
  states = dict(lookup(runtime, "states"));
  diagnostics = array(lookup(runtime, "diagnostics"));
  timing = dict(lookup(runtime, "timing"));
  repeat = flag(runtime, "repeat", true);
  sync_timing(number(timing, "clock"), integer(timing, "random_state", 1));
  Dictionary source_nodes = dict(lookup(runtime, "nodes"));
  Dictionary children = dict(lookup(runtime, "children"));
  Array ids = source_nodes.keys();
  nodes.reserve(ids.size());
  for (int64_t i = 0; i < ids.size(); ++i) {
    Node node;
    node.id = text(ids[i]);
    node.data = dict(compile_value(source_nodes[ids[i]]));
    node.kind = compiled_kind(node.data);
    indices[node.id] = i;
    nodes.push_back(std::move(node));
  }
  for (Node &node : nodes) {
    Array child_ids = array(children.get(node.id, Array()));
    for (int64_t i = 0; i < child_ids.size(); ++i) {
      node.children.push_back(int(indices.get(text(child_ids[i]), -1)));
    }
  }
  root = int(indices.get(lookup(runtime, "root", ""), -1));
  reset_serial = 0;
  depth = 0;
  return root >= 0;
}

void CombatAIProbe::sync_timing(double clock_value, int64_t random_value) {
  clock = clock_value;
  random_state = uint32_t(random_value);
  timing["clock"] = clock;
  timing["random_state"] = int64_t(random_state);
}

Dictionary CombatAIProbe::tick(double step, const Dictionary &context_value, bool trace_enabled) {
  properties = Dictionary();
  buffs = Array();
  messages = Array();
  tracing = trace_enabled;
  if (tracing || !trace.is_empty()) trace = Array();
  if (tracing || !visited.is_empty()) visited = Dictionary();
  depth = 0;
  if (root < 0 || !std::isfinite(step) || step < 0) return result(FAILURE);
  delta = step;
  clock += step;
  context = context_value;
  blackboard["IP_SelfObj"] = true;
  blackboard["IP_Target"] = flag(context, "target_available") ? Variant(true) : Variant();
  blackboard["IP_MoveSpeed"] = number(context, "move_speed");
  blackboard["IP_BattleClipTimer"] = number(context, "battle_time", clock);
  if (context.has("attack_cooldown") && blackboard.has("BB_AttackCD")) blackboard["BB_AttackCD"] = number(context, "attack_cooldown");
  if (context.has("current_action")) blackboard["IP_CurAction"] = text(context["current_action"]);
  if (context.has("blackboard")) {
    Dictionary overrides = dict(context["blackboard"]);
    Array names = overrides.keys();
    for (int64_t i = 0; i < names.size(); ++i) if (blackboard.has(names[i])) blackboard[names[i]] = overrides[names[i]];
  }
  int root_status = integer(dict(states.get(nodes[root].id, Dictionary())), "status", RESTING);
  if (repeat && root_status != RESTING && root_status != RUNNING) reset_branch(root);
  int status = tick_node(root);
  timing["clock"] = clock;
  timing["random_state"] = int64_t(random_state);
  return result(status);
}

Dictionary CombatAIProbe::result(int status) const {
  Dictionary output;
  output["action"] = text(lookup(blackboard, "OP_AIAction", ""));
  output["properties"] = properties;
  output["buffs"] = buffs;
  output["messages"] = messages;
  output["status"] = status;
  output["trace"] = trace;
  output["visited"] = visited.keys();
  return output;
}

int CombatAIProbe::tick_node(int index) {
  if (index < 0 || index >= int(nodes.size())) return FAILURE;
  Node &node = nodes[index];
  if (node.visiting || depth > 128) {
    report(String("Behavior tree cycle at ") + node.id);
    return FAILURE;
  }
  Dictionary state = dict(states.get(node.id, Dictionary()));
  int status = integer(state, "status", RESTING);
  if (status != RESTING && status != RUNNING) return status;
  node.visiting = true;
  ++depth;
  if (tracing) visited[node.id] = true;
  status = execute_node(index, state);
  Dictionary current = dict(states.get(node.id, Dictionary()));
  current["status"] = status;
  --depth;
  node.visiting = false;
  return status;
}

int CombatAIProbe::execute_node(int index, Dictionary state) {
  const Node &node = nodes[index];
  const Dictionary &data = node.data;
  const auto &children = node.children;
  auto reset = [&](int child) { reset_branch(child); };
  switch (node.kind) {
    case ACTION_NODE: return task(dict(lookup(data, "_action")), node.id);
    case BINARY: {
      if (children.size() < 2) return OPTIONAL;
      if (!state.has("selection") || flag(data, "dynamic")) {
        int selection = condition(dict(lookup(data, "_condition"))) ? 0 : 1;
        if (state.has("selection") && integer(state, "selection") != selection) reset(children[integer(state, "selection")]);
        state["selection"] = selection;
      }
      return tick_node(children[integer(state, "selection")]);
    }
    case EVALUATOR: {
      if (children.empty()) return OPTIONAL;
      if (!state.has("condition") || flag(data, "dynamic")) state["condition"] = condition(dict(lookup(data, "_condition")));
      if (!flag(state, "condition")) {
        if (flag(data, "dynamic")) reset(children[0]);
        return integer(data, "falseReturnStatus", FAILURE);
      }
      return tick_node(children[0]);
    }
    case MERGE: return children.empty() ? OPTIONAL : tick_node(children[0]);
    case WAIT:
      if (!flag(state, "condition")) state["condition"] = condition(dict(lookup(data, "_condition")));
      if (!flag(state, "condition")) return RUNNING;
      return children.empty() ? SUCCESS : tick_node(children[0]);
    case FILTER: {
      if (children.empty()) return OPTIONAL;
      int mode = integer(data, "filterMode", 1);
      bool limited = mode == 0
        ? integer(state, "count") >= int64_t(value(dict(lookup(data, "maxCount")), 1))
        : clock + EPSILON < number(state, "ready_at");
      if (limited) return flag(data, "inactiveWhenLimited", true) ? OPTIONAL : FAILURE;
      int status = tick_node(children[0]);
      if (status == SUCCESS || status == FAILURE) {
        if (mode == 1) state["ready_at"] = clock + std::max(0.0, double(value(dict(lookup(data, "coolDownTime")), 5.0)));
        else {
          int policy = integer(data, "policy");
          if (policy == 0 || (policy == 1 && status == SUCCESS) || (policy == 2 && status == FAILURE)) state["count"] = integer(state, "count") + 1;
        }
      }
      return status;
    }
    case SWITCH: {
      if (children.empty()) return FAILURE;
      if (!state.has("selection") || flag(data, "dynamic")) {
        int64_t selection = int64_t(value(dict(lookup(data, "intCase"))));
        if (integer(data, "outOfRangeMode", 1) == 1) selection = ((selection % int64_t(children.size())) + children.size()) % children.size();
        if (selection < 0 || selection >= int64_t(children.size())) return FAILURE;
        if (state.has("selection") && integer(state, "selection") != selection) reset(children[integer(state, "selection")]);
        state["selection"] = selection;
      }
      return tick_node(children[integer(state, "selection")]);
    }
    case STEP: {
      if (children.empty()) return OPTIONAL;
      int64_t step = integer(state, "step");
      int64_t size = children.size();
      return tick_node(children[((step % size) + size) % size]);
    }
    case PROBABILITY: return probability(index, state);
    case SELECTOR: case FLIP: case SEQUENCER: {
      Array order;
      if (state.has("order")) order = array(state["order"]);
      else {
        for (int child : children) order.append(nodes[child].id);
        state["order"] = order;
      }
      int64_t start = flag(data, "dynamic") ? 0 : integer(state, "cursor");
      for (int64_t i = start; i < order.size(); ++i) {
        int child = int(indices.get(text(order[i]), -1));
        int status = tick_node(child);
        if (status == RUNNING) {
          if (state.has("cursor") && integer(state, "cursor") != i) reset(int(indices.get(text(order[integer(state, "cursor")]), -1)));
          state["cursor"] = i;
          return RUNNING;
        }
        if (node.kind == SEQUENCER && status == FAILURE) return FAILURE;
        if (node.kind != SEQUENCER && status == SUCCESS) {
          if (node.kind == FLIP) { Variant successful = order.pop_at(i); order.append(successful); }
          return SUCCESS;
        }
      }
      return node.kind == SEQUENCER ? SUCCESS : FAILURE;
    }
    case PARALLEL: {
      int status = RESTING, completed = 0, policy = integer(data, "policy");
      for (int child : children) {
        int prior = integer(dict(states.get(nodes[child].id, Dictionary())), "status", RESTING);
        if (flag(data, "dynamic") && prior != RESTING && prior != RUNNING) reset(child);
        int current = tick_node(child);
        if (current != RUNNING) ++completed;
        if (status == RESTING && ((current == FAILURE && (policy == 0 || policy == 2)) || (current == SUCCESS && (policy == 1 || policy == 2)))) status = current;
      }
      if (status != RESTING) {
        for (int child : children) if (integer(dict(states.get(nodes[child].id, Dictionary())), "status", RESTING) == RUNNING) reset(child);
        return status;
      }
      if (completed == int(children.size())) return policy == 1 ? FAILURE : policy == 0 ? SUCCESS : RUNNING;
      return RUNNING;
    }
    case REPEATER: {
      if (children.empty()) return OPTIONAL;
      int child = children[0];
      int prior = integer(dict(states.get(nodes[child].id, Dictionary())), "status", RESTING);
      if (prior != RESTING && prior != RUNNING) reset(child);
      int status = tick_node(child);
      if (status == RUNNING) return RUNNING;
      state["iterations"] = integer(state, "iterations") + 1;
      int mode = integer(data, "repeaterMode");
      if (mode == 0 && integer(state, "iterations") >= int64_t(value(dict(lookup(data, "repeatTimes")), 1))) return status;
      if (mode == 1 && status == integer(data, "repeatUntilStatus")) return status;
      return RUNNING;
    }
    default: report(String("Unsupported node ") + type(data)); return FAILURE;
  }
}

int CombatAIProbe::probability(int index, Dictionary state) {
  const Node &node = nodes[index];
  if (!state.has("weights")) {
    Array weights, failed;
    state["weights"] = weights;
    state["failed"] = failed;
    state["dice"] = random();
    double fail_weight = std::max(0.0, double(value(dict(lookup(node.data, "failChance")))));
    state["fail_weight"] = fail_weight;
    state["total"] = fail_weight;
    Array sources = array(lookup(node.data, "childWeights", Array()));
    for (size_t i = 0; i < node.children.size(); ++i) {
      double weight = std::max(0.0, double(value(dict(sources[i]))));
      weights.append(weight);
      state["total"] = number(state, "total") + weight;
    }
  }
  double total = number(state, "total");
  if (total <= 0) return FAILURE;
  double cumulative = number(state, "fail_weight") / total;
  double dice = number(state, "dice");
  if (dice < cumulative) return FAILURE;
  Array failed = array(state["failed"]), weights = array(state["weights"]);
  for (size_t i = 0; i < node.children.size(); ++i) {
    if (failed.has(int64_t(i))) continue;
    cumulative += double(weights[i]) / total;
    if (dice > cumulative) continue;
    int status = tick_node(node.children[i]);
    if (status == SUCCESS || status == RUNNING) return status;
    if (status == FAILURE) {
      failed.append(int64_t(i));
      state["total"] = total - double(weights[i]);
      return RUNNING;
    }
  }
  return FAILURE;
}

bool CombatAIProbe::condition(const Dictionary &data) {
  bool passed = false;
  Kind code = compiled_kind(data);
  switch (code) {
    case CONDITION_LIST: {
      bool any = integer(data, "checkMode") == 1;
      passed = !any;
      Array items = array(lookup(data, "conditions", Array()));
      for (int64_t i = 0; i < items.size(); ++i) {
        bool current = condition(dict(items[i]));
        if (any && current) { passed = true; break; }
        if (!any && !current) { passed = false; break; }
      }
      break;
    }
    case CHECK_STRING: passed = text(value(dict(lookup(data, "valueA")), "")) == text(value(dict(lookup(data, "valueB")), "")); break;
    case CHECK_BOOL: passed = value(dict(lookup(data, "valueA")), false).booleanize() == value(dict(lookup(data, "valueB")), false).booleanize(); break;
    case CHECK_NULL: passed = value(dict(lookup(data, "variable")), Variant()).get_type() == Variant::NIL; break;
    case CHECK_FLOAT: case CHECK_INT:
      passed = compare(double(value(dict(lookup(data, "valueA")))), double(value(dict(lookup(data, "valueB")))), integer(data, "checkType"), code == CHECK_FLOAT ? number(data, "differenceThreshold", 0.05) : 0.0);
      break;
    case CHECK_DISTANCE:
      passed = flag(context, "target_available") && compare(number(context, "distance", std::numeric_limits<double>::infinity()), double(value(dict(lookup(data, "distance")))), integer(data, "comparison"));
      break;
    case CHECK_WALL: passed = flag(context, "line_blocked"); break;
    case CHECK_ATTRIBUTE:
      if (integer(data, "CheckAttribute") == 3) passed = compare(number(context, "hp_ratio", 1.0) * 1000.0, double(value(dict(lookup(data, "CheckVale")))), integer(data, "CheckType"));
      break;
    case CHECK_BUFF: {
      bool target = parameter_name(dict(lookup(data, "SelfGo"))) == "IP_Target";
      Array values = array(lookup(context, target ? "target_buffs" : "self_buffs", Array()));
      passed = values.has(text(value(dict(lookup(data, "CheckBuffId")), "")));
      break;
    }
    default: report(String("Unsupported condition ") + type(data)); break;
  }
  return flag(data, "_invert") ? !passed : passed;
}

int CombatAIProbe::task(const Dictionary &data, const String &node_id) {
  if (flag(data, "_isDisabled")) return SUCCESS;
  Kind code = compiled_kind(data);
  switch (code) {
    case ACTION_LIST: {
      Array actions = array(lookup(data, "actions", Array()));
      for (int64_t i = 0; i < actions.size(); ++i) if (task(dict(actions[i]), node_id) == FAILURE) return FAILURE;
      break;
    }
    case SET_VARIABLE:
      assign(dict(lookup(data, "valueA")), value(dict(lookup(data, "valueB")), typed_default(text(lookup(data, "$type", "")))), node_id);
      break;
    case SET_FLOAT: case SET_INT: {
      Dictionary target = dict(lookup(data, "valueA"));
      double a = double(value(target)), b = double(value(dict(lookup(data, "valueB"))));
      if (flag(data, "perSecond")) b *= delta;
      switch (integer(data, "Operation")) {
        case 0: a = b; break;
        case 1: a += b; break;
        case 2: a -= b; break;
        case 3: a *= b; break;
        case 4: a = Math::is_zero_approx(b) ? a : a / b; break;
      }
      assign(target, code == SET_INT ? Variant(int64_t(a)) : Variant(a), node_id);
      break;
    }
    case SET_BOOL: {
      Dictionary target = dict(lookup(data, "boolVariable"));
      int mode = integer(data, "setTo", 1);
      assign(target, mode == 2 ? !value(target, false).booleanize() : mode == 1, node_id);
      break;
    }
    case REFRESH_INDEX: {
      int64_t index = integer(context, integer(data, "mode") == 1 ? "alive_monster_count" : "monster_index");
      assign(dict(lookup(data, "MonsterIndex")), index, node_id);
      break;
    }
    case ADD_BUFF: {
      String id = text(value(dict(lookup(data, "BuffId")), ""));
      if (!id.is_empty() && !buffs.has(id)) buffs.append(id);
      break;
    }
    case SET_PROPERTY:
      properties[text(value(dict(lookup(data, "PropertyName")), ""))] = double(value(dict(lookup(data, "PropertyValue"))));
      break;
    case SEND_MESSAGE: {
      Dictionary message, parameters;
      message["name"] = text(value(dict(lookup(data, "MessageName")), ""));
      for (int i = 1; i < 4; ++i) {
        String stem = String("MessageParams") + String::num_int64(i);
        String name = text(value(dict(data.get(stem + "Name", Dictionary())), ""));
        if (!name.is_empty()) parameters[name] = value(dict(data.get(stem + "Value", Dictionary())), "");
      }
      message["parameters"] = parameters;
      messages.append(message);
      break;
    }
    default: report(String("Unsupported task ") + type(data)); return FAILURE;
  }
  return SUCCESS;
}

String CombatAIProbe::parameter_name(const Dictionary &parameter) const {
  if (parameter.has("__dungeon_ai_parameter_name")) return text(parameter["__dungeon_ai_parameter_name"]);
  return text(variables.get(text(lookup(parameter, "_targetVariableID", "")), lookup(parameter, "_name", "")));
}

Variant CombatAIProbe::value(const Dictionary &parameter, const Variant &fallback) const {
  String name = parameter_name(parameter);
  return name.is_empty() ? lookup(parameter, "_value", fallback) : blackboard.get(name, fallback);
}

void CombatAIProbe::assign(const Dictionary &parameter, const Variant &assigned, const String &node_id) {
  String name = parameter_name(parameter);
  if (name.is_empty()) return;
  blackboard[name] = assigned;
  if (tracing) {
    Dictionary entry;
    entry["node"] = node_id;
    entry["variable"] = name;
    entry["value"] = assigned;
    trace.append(entry);
  }
}

Variant CombatAIProbe::typed_default(const String &name) {
  if (name.contains("System.Boolean")) return false;
  if (name.contains("System.String")) return "";
  if (name.contains("System.Int32")) return int64_t(0);
  return 0.0;
}

bool CombatAIProbe::compare(double a, double b, int method, double threshold) {
  switch (method) {
    case 0: return std::abs(a - b) <= threshold;
    case 1: return a - b > EPSILON;
    case 2: return b - a > EPSILON;
    case 3: return a - b >= -EPSILON;
    case 4: return b - a >= -EPSILON;
    default: return false;
  }
}

void CombatAIProbe::reset_branch(int index) { reset_node(index, ++reset_serial); }

void CombatAIProbe::reset_node(int index, uint64_t serial) {
  if (index < 0 || index >= int(nodes.size())) return;
  Node &node = nodes[index];
  if (node.reset_mark == serial) return;
  node.reset_mark = serial;
  Dictionary state = dict(states.get(node.id, Dictionary()));
  if (integer(state, "status", RESTING) == RESTING) return;
  Dictionary retained;
  retained["status"] = RESTING;
  if (node.kind == FILTER) {
    retained["count"] = lookup(state, "count", 0);
    retained["ready_at"] = lookup(state, "ready_at", 0.0);
  } else if (node.kind == STEP) retained["step"] = integer(state, "step") + 1;
  else if (node.kind == FLIP && state.has("order")) retained["order"] = state["order"];
  states[node.id] = retained;
  for (int child : node.children) reset_node(child, serial);
}

double CombatAIProbe::random() {
  random_state = uint32_t(1664525U * random_state + 1013904223U);
  return double(random_state) / 4294967296.0;
}

void CombatAIProbe::report(const String &message) {
  if (!diagnostics.has(message)) diagnostics.append(message);
}
