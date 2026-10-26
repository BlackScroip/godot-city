extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var source: String = OS.get_cmdline_user_args()[0]
	var ai_script = load(source.path_join("goDot/scripts/domain/enemy_ai.gd"))
	check(not ai_script._native_platform_supported("iOS", true), "iOS keeps the script backend")
	check(not ai_script._native_platform_supported("Web", true), "Web keeps the script backend")
	check(not ai_script._native_platform_supported("macOS", false), "Unsupported architecture keeps the script backend")
	check(ai_script._native_platform_supported("Android", true), "Android arm64 can load native")
	check(ai_script._native_platform_supported("macOS", true), "macOS arm64 can load native")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("goDot/assets/data/combat.json")))
	for name in catalog.ai_graphs:
		var ai = ai_script.new()
		check(ai.configure({"ai": name}, catalog.ai_graphs[name], 731), "Graph loads: " + name)
		check(ai.backend_name() == "gdscript", "Missing library falls back: " + name)
		for frame in 120:
			var result: Dictionary = ai.tick(1.0 / 60.0, {"target_available": true, "distance": 2.0, "move_speed": 5.0})
			check(result.has("status"), "Fallback tick: " + name)
	check(not ClassDB.class_exists("CombatAIProbe"), "Missing library was not loaded")
	print("NATIVE_AI_MISSING_LIBRARY ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
