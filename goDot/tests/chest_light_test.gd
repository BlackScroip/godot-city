extends SceneTree

const PROPS = preload("res://scripts/presentation/room_props.gd")
const EFFECTS = preload("res://scripts/presentation/environment_effects.gd")
const APK_SHA := "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"

class TestWorld extends Node3D:
	var low_effects := false
	var paused := false
	var _background := false
	var hud: Node
	var player: Node3D
	var environment_root: Node3D
	var interactions := DungeonWorldInteractions.new()

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROPS.CHEST_CATALOG))
	check(source.apk_sha256 == APK_SHA, "Chest effects belong to the selected APK")
	var world := TestWorld.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	world.environment_root = Node3D.new()
	world.add_child(world.environment_root)
	var visual := MeshInstance3D.new()
	visual.name = "Chest"
	visual.mesh = BoxMesh.new()
	world.environment_root.add_child(visual)
	var original := Node3D.new()
	original.name = "23121501_fx_other_propblue_u123"
	visual.add_child(original)
	world.interactions.setup(world.environment_root, [{"SceneName": "Test", "SourceGameObjectId": "chest", "Type": "EEUT_AbilityItemTreasureBox", "DataJson": '{"TreasureId":1,"TreasureType":"Normal"}', "exported_node_name": "Chest"}])
	var props := PROPS.new()
	props.name = "RoomProps"
	world.environment_root.add_child(props)
	props.configure(world)
	props.set_process(false)
	var effects := EFFECTS.new()
	effects.name = "EnvironmentEffects"
	world.environment_root.add_child(effects)
	effects.configure(world)
	effects.set_process(false)
	props._process(0.01)
	effects._process(0.1)
	check(not original.visible and not bool(original.get_meta("unityActive")), "Imported ambient cannot overlap the managed source light")
	for quality in ["Normal", "Unusual", "Luxury", "Curse", "Curse_Final"]:
		world.interactions._items.chest.data.TreasureType = quality
		props.refresh_chests()
		props._process(0.01)
		effects._process(0.1)
		var entry: Dictionary = props.props[0]
		check(entry.effect_address == source.chests[quality].ambient_effect, quality + " binds the APK ambient prefab")
		check(effects.effects[entry.effect_address].source_sha256 == source.effects[entry.effect_address].source_sha256, quality + " overrides the old APK effect definition")
		check(entry.effect_anchor.scale.is_equal_approx(Vector3.ONE * (1.5 if quality in ["Normal", "Unusual"] else 1.0)), quality + " preserves the source ambient root scale")
		var ambient: Array = effects.bindings.filter(func(binding): return PROPS.CHEST_EFFECTS.values().has(binding.address))
		check(ambient.size() == 1 and ambient[0].active, quality + " has exactly one active ambient binding")
		check(entry.anchor.find_children("*", "MeshInstance3D", true, false).all(func(mesh): return not mesh.mesh is PlaneMesh), quality + " has no added rune plane")
		world.interactions.presentation_requested.emit("chest_open", {"marker_id": "chest", "position": Vector3.ZERO, "data": {"TreasureType": quality}})
		check(effects.bindings.any(func(binding): return binding.transient and binding.address == source.chests[quality].open_effect), quality + " opening uses its APK burst")
	var trial_origin := world.interactions.setup_trial_chests(2.5)
	check(trial_origin.is_finite(), "Trial has a source origin")
	props.refresh_chests()
	props._process(0.01)
	effects._process(0.1)
	check(props.props.size() == 3, "All three trial boxes receive managed presentation")
	for entry in props.props:
		var quality := str(entry.item.data.TreasureType)
		check(entry.effect_address == source.chests[quality].ambient_effect, "Trial " + quality + " replaces its cloned light")
		check(entry.item.visual.get_children().filter(func(child): return str(child.name).begins_with("InteractionPresentation")).size() == 1, "Trial " + quality + " removes cloned presentation nodes")
	var ambient: Array = effects.bindings.filter(func(binding): return PROPS.CHEST_EFFECTS.values().has(binding.address))
	check(ambient.size() == 3 and ambient.all(func(binding): return binding.active), "Trial exposes one ambient light per box")
	world.interactions.sync_trial_chests(1)
	props._process(0.01)
	effects._process(0.1)
	check(ambient.all(func(binding): return not binding.active and not binding.effect.visible), "Opening stops the chosen light and hides the other boxes' lights")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.interactions.snapshot()))
	check(world.interactions.restore(saved), "Opened trial state restores")
	props.refresh_chests()
	props._process(0.01)
	effects._process(0.1)
	ambient = effects.bindings.filter(func(binding): return PROPS.CHEST_EFFECTS.values().has(binding.address))
	check(ambient.size() == 3 and ambient.all(func(binding): return not binding.active), "Restoring an opened trial never restarts its ambient lights")
	world.free()
	await process_frame
	print("CHEST_LIGHT ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
