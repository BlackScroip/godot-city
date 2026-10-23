class_name DungeonDialogue
extends RefCounted

var stories: Dictionary = {}
var simple: Dictionary = {}
var diagnostics: Array[String] = []

func load_all() -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/dialogue.json"))
	if not data is Dictionary: return false
	for row in data.get("Stories", []): stories[str(row.Id)] = row
	for row in data.get("SimpleTalk", []): simple[str(row.Id)] = row
	return not stories.is_empty()

func read_story(id: String, seed_value: int) -> Array:
	var story: Dictionary = stories.get(id.trim_suffix("_cn"), {})
	var variables: Dictionary = {}
	var random = RandomNumberGenerator.new()
	random.seed = seed_value
	for variable in story.get("RandomVariables", []):
		variables[str(variable.Name)] = random.randi_range(int(variable.Min), int(variable.Max))
	var result: Array = []
	for line in story.get("Lines", []):
		if _matches(str(line.get("Condition", "")), variables): result.append(line.duplicate(true))
	return result

func _matches(condition: String, variables: Dictionary) -> bool:
	for clause in condition.split("&&", false):
		clause = clause.strip_edges()
		if clause == "g_lauguage==\"CN\"": continue
		var values = clause.split("=")
		if values.size() == 2 and variables.has(values[0].strip_edges()) and values[1].strip_edges().is_valid_int():
			if int(variables[values[0].strip_edges()]) != int(values[1]): return false
		else:
			if not diagnostics.has(clause): diagnostics.append(clause)
			return false
	return true

func read_simple(id: String) -> Array:
	var result: Array = []
	var visited: Dictionary = {}
	while simple.has(id) and not visited.has(id):
		visited[id] = true
		var row: Dictionary = simple[id]
		result.append({"Text": str(row.get("Text", "")), "Speaker": "", "LineIndex": result.size(), "UnlockCondition": str(row.get("UnlockCondition", "")), "OnlyOnce": bool(row.get("OnlyOnce", false)), "Id": id})
		id = str(row.get("NextId", ""))
	return result
