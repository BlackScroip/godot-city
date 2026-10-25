extends SceneTree

const Rewards = preload("res://scripts/domain/breakable_rewards.gd")
const Interactions = preload("res://scripts/world_interactions.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Source catalog loads")
	var profile := DungeonProfile.new()
	var systems := DungeonSystems.new(catalog, profile)
	systems.begin_run(73912, 1, 100)
	var minimum = Rewards.new(systems, func(_limit): return 0)
	var maximum = Rewards.new(systems, func(limit): return limit - 1)
	check(minimum.destroyable("10003") == [{"id": 101, "amount": 1, "material": true, "direct": false}], "Pot guarantees one source minimum gold without inventing material rewards")
	check(maximum.destroyable("10003") == [{"id": 101, "amount": 3, "material": true, "direct": false}], "RandomTools maximum is inclusive: pot can drop three gold")
	check(minimum.destroyable("70001")[0].amount == 40 and maximum.destroyable("70001")[0].amount == 60, "Gold lode applies configured base20, source +0..500 permille, and native gold attribute baseline")
	check(minimum.destroyable("70002")[0].amount == 30 and maximum.destroyable("70002")[0].amount == 45, "Magic lode applies configured base30 and +0..500 permille")
	check(minimum.destroyable("70001", {"GoldLodeDropBaseAmount": 10, "GoldLodeDropFactor": 500, "DropGoldFactor": 1000})[0].amount == 135, "Gold lode modifiers preserve source order of truncation")
	check(minimum.destroyable("70002", {"MagicPointLodeDropBaseAmount": 10, "MagicPointLodeDropFactor": 500})[0].amount == 60, "Magic lode modifiers are independent of gold factors")
	check(maximum.destroyable("10003", {"DestroyableDropMagicPointChance": 1000}).size() == 1, "Source strict magic chance excludes roll1000 at threshold1000")
	var magic = minimum.destroyable("10003", {"DestroyableDropMagicPointChance": 1})
	check(magic.size() == 2 and magic[1].id == 102 and magic[1].amount == 20, "Pot magic is a separate attribute branch with native base20")
	var recover = minimum.destroyable("10003", {"DestroyableDropRecoverRate": 1000})
	check(recover.size() == 2 and not recover[1].material, "Pot optional recovery uses source recovery pool")
	for config_id in Rewards.MATERIALS:
		var drops: Array = minimum.destroyable(config_id)
		check(drops.size() == 1 and drops[0].id == Rewards.MATERIALS[config_id] and drops[0].amount == 1 and drops[0].direct, "Each exact source gathering ID maps to its own immediate material")
		check(not catalog.find("MaterialData", drops[0].id).is_empty(), "Each gathering reward has its source item and image catalog identity")
		check(minimum.destroyable(config_id, {"CollectingMaterialsDoubleProbability": 1})[0].amount == 2, "Collecting double roll uses source inclusive1..1000 comparison")
		check(maximum.destroyable(config_id, {"CollectingMaterialsDoubleProbability": 999})[0].amount == 1, "Collecting maximum roll1000 respects threshold999")
	check(minimum.destroyable("10001")[0].id == 101 and maximum.destroyable("10001").is_empty(), "Generic destructible has source <=100 of0..1000 gold branch")
	check(minimum.destroyable("missing").is_empty(), "Unbound names do not invent drops")
	var first: Array = Rewards.new(systems).destroyable("70001")
	var restored := DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "Breakable RNG state is persistable")
	var clone := DungeonSystems.new(catalog, restored)
	check(Rewards.new(systems).destroyable("10003") == Rewards.new(clone).destroyable("10003"), "Restoring the run preserves next source pot roll")
	check(not first.is_empty(), "Actual profile RNG emits lode resources")
	_test_damage_and_consumption()
	print("BREAKABLE_SOURCE_RULES_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _test_damage_and_consumption() -> void:
	var environment := Node3D.new()
	root.add_child(environment)
	var visual := Node3D.new()
	visual.name = "pot"
	environment.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "Collider_pot"
	body.collision_layer = 5
	body.collision_mask = 7
	environment.add_child(body)
	var altar := Node3D.new()
	altar.name = "altar"
	environment.add_child(altar)
	var egg := Node3D.new()
	egg.name = "sprite_abilityitemicon_14104__u7182"
	altar.add_child(egg)
	var markers := [{"SceneName": "Test", "SourceGameObjectId": "pot", "Type": "EEUT_DestoryableItem", "Path": ["pot"], "DataJson": "{}", "exported_node_name": "pot", "world_position": [0, 0, 0]},
		{"SceneName": "Test", "SourceGameObjectId": "altar", "Type": "EEUT_UIInteractable", "Path": ["altar"], "DataJson": JSON.stringify({"UIBtnName": Interactions.SPRITES_ALTAR}), "exported_node_name": "altar", "world_position": [1, 0, 0]}]
	var rules := {"Bindings": [{"SceneName": "Test", "SourceGameObjectId": "pot", "ConfigId": "10003", "SupportsRules": true}],
		"Definitions": [{"ID": "10003", "Type": "EEUT_DestoryableItem", "CanBeAttack": true, "CanBeAttackCamp": "100", "Durablity": 50, "BreakEffect": "source_pot_break", "DropItemIdList": []}]}
	var collider := {"fileID": "pot", "path": "Test/pot", "kind": 65, "active": true, "world_matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], "properties": {"m_Size": {"x": 1, "y": 1.2, "z": 1}, "m_Center": {"x": 0, "y": 0.6, "z": 0}, "m_IsTrigger": 0, "m_Enabled": 1}}
	var interactions := Interactions.new()
	var rewards: Array = []
	var effects: Array = []
	interactions.reward_requested.connect(func(context): rewards.append(context))
	interactions.effect_requested.connect(func(context): effects.append(context))
	interactions.setup(environment, markers, {"rules": rules, "colliders": [collider]})
	check(not interactions.damage_marker("pot", 50, 1, "enemy"), "Source camp mask rejects enemy attack")
	check(interactions.damage_near(Vector3(0, 0.6, 0), 0.3, 20.9, 2, "swing").size() == 1 and interactions.state_for("pot").hp == 30, "Pot durability uses integer tenacity, not fractional HP damage")
	check(interactions.damage_near(Vector3.ZERO, 1, 20, 2, "swing").is_empty(), "One emitted swing cannot double hit the same pot")
	var partial: Dictionary = JSON.parse_string(JSON.stringify(interactions.snapshot()))
	check(interactions.restore(partial) and not interactions.damage_marker("pot", 20, 2, "swing"), "Hit deduplication survives room state restore")
	check(rewards.is_empty(), "Partial durability damage does not drop rewards")
	check(interactions.damage_segment(Vector3(-3, 0.6, 0), Vector3(3, 0.6, 0), 0.1, 30, 2, "bullet").size() == 1, "Fast swept bullet breaks a narrow pot between frame endpoints")
	check(interactions.state_for("pot").broken and not visual.visible and not visual.get_meta("unityActive"), "Broken pot hides its model and source particle ancestry")
	check(body.collision_layer == 0 and body.collision_mask == 0, "Broken pot no longer blocks movement or projectiles")
	check(rewards.size() == 1 and rewards[0].destroyable_reward and rewards[0].config_id == "10003", "Source reward dispatch emits once even with empty serialized drop list")
	check(effects.size() == 1 and effects[0].address == "source_pot_break", "Broken pot plays its exact source destruction effect")
	check(not interactions.damage_collider(body, 50) and not interactions.damage_marker("pot", 50), "Broken pot cannot produce repeated rewards from another hit route")
	var broken: Dictionary = JSON.parse_string(JSON.stringify(interactions.snapshot()))
	check(interactions.restore(broken) and rewards.size() == 1, "Restore preserves destruction without replaying drops")
	check(interactions.prompt_for(interactions.nearest_interaction(Vector3(1, 0, 0)))[0] == "精灵祭坛", "Source altar key produces an interaction prompt")
	check(interactions.interact("altar").success and rewards.size() == 2 and rewards[1].sprites_altar, "Clicking source altar requests its spirit selection")
	check(not interactions.state_for("altar").used and egg.visible, "Reward request alone does not consume altar before successful selection")
	check(interactions.set_altar_consumed("altar") and altar.visible and not egg.visible, "Successful acquisition consumes source egg while preserving altar plinth")
	check(not interactions.set_altar_consumed("altar") and not interactions.interact("altar").success, "Consumed altar cannot grant a second spirit")
	check(interactions.restore(JSON.parse_string(JSON.stringify(interactions.snapshot()))) and not egg.visible, "Consumed egg remains absent after snapshot restore")
	environment.free()
