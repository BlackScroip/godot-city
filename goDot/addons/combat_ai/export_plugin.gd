@tool
extends EditorPlugin

var exporter: EditorExportPlugin

func _enter_tree() -> void:
	exporter = CombatAIExport.new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	remove_export_plugin(exporter)
	exporter = null

class CombatAIExport extends EditorExportPlugin:
	const RUNTIME := "res://addons/combat_ai/runtime/"

	func _get_name() -> String:
		return "DungeonCombatAI"

	func _supports_platform(_platform) -> bool:
		return true

	func _export_begin(features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
		var platform := "android" if features.has("android") else "macos" if features.has("macos") else ""
		if platform.is_empty() or not features.has("arm64"): return
		var configuration := "debug" if is_debug else "release"
		var suffix := "so" if platform == "android" else "dylib"
		var library := RUNTIME + "libcombat_ai.%s.%s.arm64.%s" % [platform, configuration, suffix]
		if not FileAccess.file_exists(library): return
		add_shared_object(library, PackedStringArray(["arm64"]), "")
		add_file(RUNTIME + "combat_ai.cfg", FileAccess.get_file_as_bytes(RUNTIME + "combat_ai.cfg"), false)
		add_file("res://addons/combat_ai/LICENSE.godot-cpp.txt", FileAccess.get_file_as_bytes("res://addons/combat_ai/LICENSE.godot-cpp.txt"), false)

	func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
		if path.begins_with(RUNTIME): skip()
