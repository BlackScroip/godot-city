extends SceneTree

const Descriptors = preload("res://scripts/presentation/effect_descriptors.gd")
const Authored = preload("res://scripts/presentation/authored_effect.gd")
const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _source_equivalence() -> void:
	var media = Descriptors.load_catalog()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Descriptors.SOURCE_PATH))
	check(media.effects.size() == source.effects.size(), "Every source effect retains an indexed entry")
	for key in source.effects:
		var actual = Descriptors.effect(key)
		check(actual == source.effects[key], "Complete effect source survives archive: " + key)
		check(media.effects[key].textures == source.effects[key].textures, "Texture metadata remains compatible: " + key)
		check(media.effects[key].get("models", []) == source.effects[key].get("models", []), "Model metadata remains compatible: " + key)
	var materials: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat_presentation/materials.json"))
	for key in materials:
		check(Descriptors.material(key) == materials[key], "Complete material source survives archive: " + key)
	check(Descriptors._effects.size() <= Descriptors.EFFECT_CACHE_CAPACITY, "Effect records have a bounded decoded cache")
	check(Descriptors._materials.size() <= Descriptors.MATERIAL_CACHE_CAPACITY, "Material records have a bounded decoded cache")
	check(Descriptors.effect("missing-source-effect").is_empty(), "Unknown source effect remains unknown")
	check(Descriptors.material("missing-source-material").is_empty(), "Unknown source material remains unknown")

func _prepare(presentation: Node, combats: Array) -> Array:
	presentation.prepare_combat(combats)
	var names: Array = []
	for entry in presentation._preparation:
		if entry.has("effect"): names.append(entry.effect)
	while presentation.has_pending_preparation():
		presentation.prepare_step()
		await process_frame
	return names

func _run() -> void:
	_source_equivalence()
	var initial_reads = Descriptors.descriptor_io_reads
	check(initial_reads == 3, "Index and two raw archives are read once during setup")
	var presentation = Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	presentation.audio_enabled = false
	var actor = DungeonActor.new()
	actor.is_player = true
	actor.combat = DungeonCombat.new()
	check(actor.combat.configure().success, "Player fixture loads")
	root.add_child(actor)
	var enemies: Array = []
	for id in [11001, 13001]:
		var enemy = DungeonCombat.new()
		check(enemy.configure_enemy(id).success, "Enemy fixture loads %d" % id)
		enemies.append(enemy)
	var names: Array = await _prepare(presentation, [actor.combat] + enemies)
	check(not names.is_empty(), "Room dependency closure prepares actual source effects")
	check(Descriptors.descriptor_io_reads == initial_reads, "Room prewarm decodes memory without descriptor IO")
	var parsed = Descriptors.effect_parses
	for name in names:
		presentation.emit_effect(actor, name, Vector3.ZERO)
		check(not presentation.active.is_empty() and presentation.active.back().key == name, "Prepared source effect can emit: " + name)
		presentation.clear()
	check(Descriptors.descriptor_io_reads == initial_reads, "Every prepared effect emits without descriptor IO")
	check(Descriptors.effect_parses == parsed, "Prepared room templates also avoid descriptor parsing on cast")
	var cold = "25122501_fx_lance_atk_slash1"
	check(not names.has(cold), "Fallback fixture is outside the sword room closure")
	presentation.emit_effect(actor, cold, Vector3.ZERO)
	check(not presentation.active.is_empty() and presentation.active.back().authored != null, "Unpredicted source effect uses its exact archived particles")
	var direct = Authored.new()
	direct.configure(presentation.media.effects[cold], false, presentation.texture_cache)
	check(direct.particle_count == presentation.active.back().authored.particle_count and direct.emitters.size() == presentation.active.back().authored.emitters.size(), "Existing direct header configuration resolves the complete source effect")
	direct.free()
	check(Descriptors.descriptor_io_reads == initial_reads, "Unpredicted effect fallback never reads descriptors from disk")
	check(presentation.missing.is_empty(), "Known source effects never become missing after splitting")
	presentation.clear()
	var definition = presentation.effect_definition(cold)
	var layers: Array = Authored.resolved_layers(definition)
	check(not layers.is_empty() and layers.any(func(layer): return not layer.get("materials", []).is_empty()), "Original definitions resolve their source materials without a runtime header")
	check(Descriptors.descriptor_io_reads == initial_reads, "Original or companion source definitions reuse the in-memory material archive")
	var pending: Dictionary = {}
	presentation._collect_media({"AddBuffIDList": ["50202100"], "SummonUnitIdList": [actor.combat._summon_index.keys()[0]]}, actor.combat, {}, {}, pending)
	check(pending.has("buff:50202100"), "Buff-list dependencies join the media closure")
	check(pending.size() >= 2, "Summon-list dependencies join the media closure")
	for character in [2, 7, 1]:
		actor.combat.configure(null, null, character)
		var cross_room: Array = await _prepare(presentation, [actor.combat])
		check(not cross_room.is_empty(), "Changing character or returning to an earlier room can prepare %d" % character)
		for name in cross_room:
			presentation.emit_effect(actor, name, Vector3.ZERO)
			presentation.clear()
		check(Descriptors.descriptor_io_reads == initial_reads, "Cross-room decode and casting use memory archives %d" % character)
	check(Descriptors._effects.size() <= Descriptors.EFFECT_CACHE_CAPACITY and Descriptors._materials.size() <= Descriptors.MATERIAL_CACHE_CAPACITY, "Cross-room source caches stay bounded")
	print("EFFECT_DESCRIPTOR_TEST ", JSON.stringify({"checks": checks, "failures": failures, "stats": Descriptors.stats()}))
	actor.queue_free()
	presentation.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
