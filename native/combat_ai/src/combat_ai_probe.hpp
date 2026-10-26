#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <cstdint>
#include <vector>

namespace godot {

class CombatAIProbe : public RefCounted {
  GDCLASS(CombatAIProbe, RefCounted)

  enum Kind {
    UNKNOWN, PARALLEL, BINARY, ACTION_NODE, PROBABILITY, EVALUATOR, FILTER, SWITCH,
    SELECTOR, MERGE, FLIP, STEP, WAIT, SEQUENCER, REPEATER, CONDITION_LIST,
    CHECK_STRING, CHECK_NULL, CHECK_FLOAT, CHECK_DISTANCE, CHECK_WALL, CHECK_INT,
    CHECK_BOOL, CHECK_ATTRIBUTE, CHECK_BUFF, ACTION_LIST, SET_FLOAT, SET_INT,
    SET_VARIABLE, SET_BOOL, REFRESH_INDEX, ADD_BUFF, SET_PROPERTY, SEND_MESSAGE
  };
  struct Node {
    String id;
    Dictionary data;
    Kind kind = UNKNOWN;
    std::vector<int> children;
    bool visiting = false;
    uint64_t reset_mark = 0;
  };
  std::vector<Node> nodes;
  Dictionary indices, states, blackboard, variables, context, timing;
  Dictionary properties, visited;
  Array buffs, messages, trace, diagnostics;
  int root = -1;
  int depth = 0;
  bool repeat = true;
  bool tracing = true;
  uint32_t random_state = 1;
  uint64_t reset_serial = 0;
  double clock = 0.0;
  double delta = 0.0;

  static Kind kind(const String &name);
  static String type(const Dictionary &data);
  static Variant compile_value(const Variant &value);
  static Kind compiled_kind(const Dictionary &data);
  String parameter_name(const Dictionary &parameter) const;
  Variant value(const Dictionary &parameter, const Variant &fallback = 0.0) const;
  void assign(const Dictionary &parameter, const Variant &value, const String &node_id);
  static Variant typed_default(const String &type);
  static bool compare(double a, double b, int method, double threshold = 0.0);
  bool condition(const Dictionary &data);
  int task(const Dictionary &data, const String &node_id);
  int tick_node(int index);
  int execute_node(int index, Dictionary state);
  int probability(int index, Dictionary state);
  void reset_branch(int index);
  void reset_node(int index, uint64_t serial);
  double random();
  void report(const String &message);
  Dictionary result(int status) const;

protected:
  static void _bind_methods();

public:
  bool configure(const Dictionary &runtime);
  Dictionary tick(double step, const Dictionary &context_value, bool trace_enabled);
  void sync_timing(double clock_value, int64_t random_value);
};
}
