extends SceneTree

const Appearance = preload("res://scripts/domain/room_appearance.gd")
const Interactions = preload("res://scripts/world_interactions.gd")
var failures: Array[String] = []
var checks := 0

class FixedRoll extends RefCounted:
	var value := 0
	var limits: Array = []
	func _init(selected: int) -> void: value = selected
	func next(limit: int) -> int:
		limits.append(limit)
		return mini(value, limit - 1)

class TestSystems extends DungeonSystems:
	var test_attributes: Dictionary = {}
	func attributes(_character: int = 0) -> Dictionary: return test_attributes

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var systems := TestSystems.new(catalog, DungeonProfile.new())
	systems.begin_run(491, 1, 100)
	var zero := FixedRoll.new(0)
	var helper := Appearance.new(systems, zero.next)
	for id in Appearance.MATERIAL_IDS:
		check(helper.environment_chance(id, {"Type": 2}, {}, {}) == 180, "Configured material baseline " + id)
	check(helper.environment_chance("10058", {}, {}, {}) == -1, "Unobserved material ID is not inferred")
	var attrs := {"CollectingMaterialsAppearChance": 18.9, "RestRoomCollectingMaterialsAppearChance": 21.9, "CollectingMaterialsIncrementAddAppearChance": 42.9}
	check(helper.environment_chance("10017", {"Type": 3}, attrs, {"10000": 0}) == 261, "Rest and actual material increment add separately truncated attributes")
	check(helper.environment_chance("10017", {"Type": 3, "FirstOrFinal": 1}, attrs, {"10000": 0}) == 240, "First sentinel excludes rest bonus")
	check(helper.environment_chance("10017", {"Type": 3, "IsFirstOrFinal": 1}, attrs, {"10000": 0}) == 240, "Native first sentinel alias supported")
	check(helper.environment_chance("10017", {"Type": 3, "IncrementOptions": "CollectingMaterials"}, attrs, {}) == 219, "Candidate flag alone does not add material increment bonus")
	check(helper.environment_chance("10017", {"Type": 2}, {"CollectingMaterialsAppearChance": -180.9}, {}) == 0, "Negative chance clamps to zero after truncation")
	check(helper.environment_chance("10017", {"Type": 3}, {"CollectingMaterialsAppearChance": 0.9, "RestRoomCollectingMaterialsAppearChance": 0.9}, {}) == 180, "Fractional components do not combine before truncation")
	check(helper.environment_chance("70001", {"Type": 11}, {}, {}) == 200, "Gold does not receive event magic guarantee")
	check(helper.environment_chance("70002", {"Type": 11}, {}, {}) == 1000, "Event magic lode uses source plus1000")
	check(helper.environment_chance("70001", {"Type": 2}, {"GoldLodeAppearChance": 16.9}, {}) == 216, "Gold occurrence attribute4016")
	check(helper.environment_chance("70002", {"Type": 2}, {"MagicPointLodeAppearChance": 15.9}, {}) == 215, "Magic occurrence attribute4015")
	check(helper.environment_chance("70001", {}, {"GoldLodeAppearChance": -500}, {"70001": 0}) == 700, "Selected lode adds1000 before clamp rather than overriding modifiers")
	check(helper.environment_chance("70001", {}, {}, {"70002": 0}) == 200, "Different lode increment does not match gold")
	check(helper.environment_chance("70003", {}, {}, {}) == -1, "Gold apple remains outside lode rules")
	check(helper.environment_chance("13008", {}, {}, {}) == 0 and helper.environment_chance("13008", {}, {}, {"13008": 0}) == 1000, "Source spirit altar follows selected increment")
	check(helper.environment_chance("13006", {}, {"MonsterPartnerSkillSelectorAppearChance": 1000}, {"13006": 0}) == 0, "Partner scene also requires building4 level3 despite a saved increment")
	systems.profile.data.buildings["4"] = 3
	check(helper.environment_chance("13006", {}, {"MonsterPartnerSkillSelectorAppearChance": 17.9}, {}) == 17, "Partner selector independent scene modifier after unlock")
	catalog.config.EnvUnitRandomAppearChanceDic["NodeIncrementMonsterPartnerAppearChance"] = 7
	check(helper.environment_chance("13006", {}, {"MonsterPartnerSkillSelectorAppearChance": 17.9}, {}) == 24, "Partner baseline uses exact source dictionary key")
	catalog.config.EnvUnitRandomAppearChanceDic.erase("NodeIncrementMonsterPartnerAppearChance")
	systems.profile.data.buildings.erase("4")
	check(helper.environment_chance("13004", {"Type": 12}, {"CurseAltarAppearChance": 1000}, {}) == 0, "Entrance curse override ignores ordinary probability")
	check(helper.environment_chance("13004", {"Type": 12}, {"CurseAltarAppearRegionEnter": 0.9}, {}) == 0, "Curse entrance switch truncates before comparing to one")
	check(helper.environment_chance("13004", {"Type": 12}, {"CurseAltarAppearRegionEnter": 1}, {}) == 1000, "Difficulty curse entrance switch enables altar")
	check(helper.environment_chance("13004", {"Type": 3, "FirstOrFinal": 1}, {"CurseAltarAppearRegionEnter": 1}, {}) == 1000, "First sentinel also uses entrance altar switch")
	check(helper.environment_chance("13004", {"Type": 2}, {"CurseAltarAppearChance": 123.9, "CurseAltarAppearRegionEnter": 1}, {}) == 123, "Regular room uses ordinary curse occurrence")
	check(helper.environment_chance("130041", {"Type": 13}, {}, {}) == 1000, "Old-day room forces its own altar")
	check(helper.environment_chance("130041", {"Type": 12}, {"OldDayAltarAppearRegionEnter": 1}, {}) == 1000, "Old-day entrance switch is separate")
	check(helper.environment_chance("130041", {"Type": 12}, {"CurseAltarAppearRegionEnter": 1}, {}) == 0, "Curse switch does not enable old-day altar")
	var only_gold := {"IncrementOptions": "GoldLode"}
	for boundary in [[249, true], [250, false], [1000, false]]:
		var fixed := FixedRoll.new(int(boundary[0]))
		var selected: Dictionary = Appearance.new(systems, fixed.next).roll_increments(only_gold, {})
		check(selected.has("70001") == bool(boundary[1]), "Node chance250 strict boundary " + str(boundary[0]))
		check(fixed.limits.has(1001), "Node probability roll includes1000")
	var maximum := FixedRoll.new(1000)
	check(not Appearance.new(systems, maximum.next).roll_increments(only_gold, {"GoldIncrementAppearChance": 750.9}).has("70001"), "Chance1000 can fail at inclusive endpoint")
	check(Appearance.new(systems, maximum.next).roll_increments(only_gold, {"GoldIncrementAppearChance": 751.9}).has("70001"), "Node chance remains above1000 rather than clamping")
	check(helper.roll_increments(only_gold, {"GoldIncrementAppearChance": -250}).is_empty(), "Zero increment chance fails even at roll0")
	check(helper.roll_increments({"IncrementOptions": 8}, {}).is_empty(), "Partner increment gated before building4 level3")
	systems.profile.data.buildings["4"] = 3
	check(helper.roll_increments({"IncrementOptions": 8}, {}).has("13006"), "Partner increment unlock uses exact building threshold")
	var all_increments := helper.roll_increments({"IncrementOptions": 31}, {})
	check(all_increments.size() == 4, "Native maximum selects four after shuffle")
	check(all_increments.values().all(func(value): return int(value) == 0), "Node increment values start at zero")
	check(helper.roll_increments({"IncrementOptions": "0"}, {}).is_empty(), "No candidate increments means no selected bonus")
	var picked := helper.node_increments("saved-node", only_gold)
	var calls := zero.limits.size()
	check(helper.node_increments("saved-node", only_gold) == picked and zero.limits.size() == calls, "Reopening node preserves increment draw")
	picked.clear()
	check(helper.node_increments("saved-node", only_gold).has("70001"), "Returned increment data cannot mutate stored result")
	var items := [{"id": "material", "binding": {"ConfigId": "10017"}}, {"id": "jar", "binding": {"ConfigId": "10001"}}]
	var at179 := FixedRoll.new(179)
	var at180 := FixedRoll.new(180)
	check(Appearance.new(systems, at179.next).environment_decisions("material179", {}, items).get("material", false), "Material roll179 succeeds chance180")
	check(not Appearance.new(systems, at180.next).environment_decisions("material180", {}, items).get("material", true), "Material roll180 fails chance180")
	check(not Appearance.new(systems, at180.next).environment_decisions("material180", {}, items).has("jar"), "Uncontrolled jars retain source activation")
	check(at179.limits.has(1000) and not at179.limits.has(1001), "Scene roll excludes1000")
	var decisions := helper.environment_decisions("environment-save", {"IncrementOptions": 0}, items)
	systems.test_attributes["CollectingMaterialsAppearChance"] = -1000
	check(helper.environment_decisions("environment-save", {}, items) == decisions, "Room scene decisions do not reroll after attributes change")
	var clone_profile := DungeonProfile.new()
	check(clone_profile.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "Nested occurrence state survives profile JSON restore")
	var clone := TestSystems.new(catalog, clone_profile)
	check(Appearance.new(clone, maximum.next).node_increments("saved-node", only_gold).has("70001"), "Saved increment does not reroll at maximum endpoint")
	check(Appearance.new(clone, maximum.next).environment_decisions("environment-save", {}, items) == decisions, "Saved per-instance decisions survive restart")
	var altar_items := [{"id": "altar", "data": {"UIBtnName": "EnvUnit_MonoData_BtnDisplayName_CurseAltar"}}]
	systems.test_attributes = {"CurseAltarAppearRegionEnter": 1}
	check(helper.environment_decisions("curse-source", {"Type": 12}, altar_items).get("altar", false), "Exact source UI identity receives curse occurrence rule")
	var campaign := DungeonCampaign.new()
	check(campaign.configure() and campaign.generate(491, 0).success, "Campaign for node occurrence integration")
	var step := int(systems.profile.data.run.random_step)
	systems.ensure_map_node_increments(campaign)
	check(int(systems.profile.data.run.random_step) == step, "World-map selection does not roll an unchosen region")
	check(campaign.select_region(int(campaign.region_choices()[0].node_id)).success, "Select actual world region before its node increments")
	systems.ensure_map_node_increments(campaign)
	step = int(systems.profile.data.run.random_step)
	systems.ensure_map_node_increments(campaign)
	check(int(systems.profile.data.run.random_step) == step, "Map reopen reuses all per-occurrence increments")
	for room in campaign.route_map():
		var key := "%d:%d:%d" % [491, int(room.layer_index), int(room.node_id)]
		check(systems.profile.data.run.counters.get("node_increments:" + key) is Dictionary, "Every visible route occurrence has persisted actual increments")
	_test_physical_activation()
	systems.decorations = null
	clone.decorations = null
	print("ROOM_APPEARANCE_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _test_physical_activation() -> void:
	var root := Node3D.new()
	var visual := Node3D.new()
	visual.name = "gold"
	root.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "Collider_gold-body"
	body.collision_layer = 5
	body.collision_mask = 3
	root.add_child(body)
	var marker := {"SceneName": "Test", "SourceGameObjectId": "gold", "Type": "EEUT_DestoryableItem", "Path": ["gold"], "DataJson": "{}", "exported_node_name": "gold", "world_position": [0, 0, 0]}
	var binding := {"SceneName": "Test", "SourceGameObjectId": "gold", "ConfigId": "70001", "SupportsRules": true}
	var definition := {"ID": "70001", "Type": "EEUT_DestoryableItem", "Durablity": 10, "CanBeAttack": true, "CanBeAttackCamp": "100"}
	var collider := {"path": "Test/gold", "fileID": "gold-body"}
	var interactions := Interactions.new()
	interactions.setup(root, [marker], {"rules": {"Bindings": [binding], "Definitions": [definition]}, "colliders": [collider]})
	check(visual.visible and body.collision_layer == 5, "Source mine starts visible and solid")
	interactions.apply_room_appearance({"gold": false})
	check(not interactions.state_for("gold").enabled and not visual.visible and body.collision_layer == 0 and body.collision_mask == 0, "Failed appearance disables attack target visual and collision together")
	check(interactions.damage_near(Vector3.ZERO, 5, 10).is_empty(), "Invisible unspawned mine cannot be harvested")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(interactions.snapshot()))
	check(interactions.restore(snapshot) and not visual.visible and body.collision_layer == 0, "Failed appearance stays disabled through snapshot restore")
	root.free()
