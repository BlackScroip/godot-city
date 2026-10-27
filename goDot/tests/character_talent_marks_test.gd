extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	var first: Dictionary = catalog.rows("CharTalentData")[0]
	var other: Dictionary = {}
	for row in catalog.rows("CharTalentData"):
		if int(row.chara_id) != int(first.chara_id):
			other = row
			break
	var id = int(first.id)
	var other_id = int(other.id)
	check(not systems.is_character_talent_marked(id), "Default talents are unmarked")
	check(not systems.toggle_character_talent_mark(-1).success, "Unknown talent cannot be marked")
	check(not systems.toggle_character_talent_mark(id, int(other.chara_id)).success, "Character mismatch cannot be marked")
	check(systems.toggle_character_talent_mark(id, int(first.chara_id)).marked, "Long press marks the talent")
	check(systems.toggle_character_talent_mark(other_id).success, "Other character can hold separate marks")
	profile.data.run = DungeonProfile.new_run(271, int(first.chara_id), 100)
	check(systems.is_character_talent_marked(id), "Starting a run preserves marks")
	var restored = DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "Marked profile survives JSON save round trip")
	check(restored.data.marked_character_talents[0] is int, "Saved mark IDs normalize to integers")
	var restored_systems = DungeonSystems.new(catalog, restored)
	check(restored_systems.is_character_talent_marked(id), "Reloaded mark is queryable")
	check(restored_systems.clear_character_talent_marks(int(first.chara_id)).success, "Clear current character succeeds")
	check(not restored_systems.is_character_talent_marked(id) and restored_systems.is_character_talent_marked(other_id), "Clear preserves other characters' marks")
	check(not restored_systems.toggle_character_talent_mark(other_id).marked, "Second long press cancels mark")
	var legacy = profile.data.duplicate(true)
	legacy.erase("marked_character_talents")
	check(restored.restore(legacy) and restored.data.marked_character_talents.is_empty(), "Legacy saves receive an empty marks list")
	for bad in ["bad", [null], [-1], [0], [1.5]]:
		var snapshot = profile.data.duplicate(true)
		snapshot.marked_character_talents = bad
		check(not restored.restore(snapshot), "Malformed mark data is rejected: " + str(bad))
	var host = DungeonMenuPage.new()
	root.add_child(host)
	host.page_context = {"systems": systems}
	var view = preload("res://scripts/presentation/talent_selection.gd").new()
	host.add_child(view)
	var card = {"config_id": id, "title": "Talent", "description": "", "icon": "", "buttons": []}
	view.configure(host, [card, {"config_id": id, "marked": false, "buttons": []}])
	await process_frame
	check(view.parts[0].panel.get_meta("talent_marked"), "Candidate resolves persistent marks from page context")
	check(not view.parts[1].panel.get_meta("talent_marked"), "Explicit row mark state takes precedence")
	var badge = view.parts[0].icon.get_node_or_null("TalentMark")
	check(is_instance_valid(badge) and badge.visible and badge.texture != null, "Marked candidate shows the recovered ring badge")
	check(badge.get_child_count() > 0 and badge.get_child(0) is TextureRect and badge.get_child(0).texture != null, "Candidate marker includes its recovered star")
	check(not view.parts[1].icon.get_node("TalentMark").visible, "Unmarked candidate hides the badge")
	view._select(1)
	check(view.parts[0].panel.get_meta("talent_marked"), "Choosing a different candidate preserves marked highlight")
	check(badge.visible, "Candidate selection does not hide persistent mark badge")
	host.queue_free()
	await process_frame
	print("CHARACTER TALENT MARKS TEST: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)
