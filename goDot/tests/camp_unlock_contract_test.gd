extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Packaged catalog loads")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	var before = JSON.stringify(profile.data)
	check(not systems.character_recruit_status(2).can_recruit, "Recruitment reflects missing facility")
	check(not systems.unlock_character(2).success and JSON.stringify(profile.data) == before, "Locked recruitment leaves the profile unchanged")
	check(not systems.select_character(2).success and JSON.stringify(profile.data) == before, "Unowned character cannot become active through an alternate command")
	check(not systems.equip_weapon(201).success and JSON.stringify(profile.data) == before, "Unowned weapon cannot be equipped")
	profile.data.buildings["1"] = 1
	systems.grant_material(502, 10)
	check(systems.character_recruit_status(2).can_recruit, "Recruitment quote follows facility and exact material balance")
	check(systems.unlock_character(2).success and systems.material(502) == 0, "Recruitment charges once and grants the default weapon")
	before = JSON.stringify(profile.data)
	check(not systems.unlock_character(2).success and JSON.stringify(profile.data) == before, "Repeated recruitment is atomic")
	check(systems.select_character(2).success and int(profile.data.selected_weapon) == 201, "Selecting a recruited character equips its owned default")
	before = JSON.stringify(profile.data)
	check(not systems.equip_weapon(101).success and JSON.stringify(profile.data) == before, "Owned but incompatible weapon is rejected")
	systems.set_record("weapon:202", 1)
	check(systems.equip_weapon(202).success, "A compatible crafted weapon can be equipped")
	check(systems.select_character(1).success and int(profile.data.selected_weapon) == 101, "Returning to the starter restores its weapon")
	check(systems.select_character(2).success and int(profile.data.selected_weapon) == 202, "Each character remembers its equipped weapon")
	var restored = DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "Character loadout survives JSON save and restore")
	var resumed = DungeonSystems.new(catalog, restored)
	check(resumed.select_character(1).success and resumed.select_character(2).success and int(restored.data.selected_weapon) == 202, "Restored loadouts retain the same selection behavior")
	check(systems.begin_run(1234, 2, 100).success, "Owned character can start an adventure")
	before = JSON.stringify(profile.data)
	check(not systems.select_character(1).success and not systems.equip_weapon(201).success and JSON.stringify(profile.data) == before, "An active adventure rejects camp loadout changes")
	systems.end_run(false)
	var row: Dictionary = catalog.find("CharData", 3)
	var original = row.duplicate(true)
	row.is_cash_only_unlock = true
	before = JSON.stringify(profile.data)
	check(not systems.unlock_character(3).success and JSON.stringify(profile.data) == before, "Cash-only recruitment cannot bypass payment verification")
	row.merge(original, true)
	systems.set_record("chaos:claimed:1", 2)
	systems.grant_material(101, 20000)
	systems.grant_material(503, 10)
	before = JSON.stringify(profile.data)
	check(not systems.awakening_status(103).can_unlock and not systems.unlock_awakening(103).success and JSON.stringify(profile.data) == before, "Awakening honors its camp facility")
	profile.data.buildings["2"] = 1
	var awake = systems.awakening_status(103)
	check(awake.can_unlock and not awake.can_toggle, "An unlocked tier can be purchased before activation")
	check(systems.unlock_awakening(103).success and systems.awakening_status(103).can_toggle, "Awakening quote refreshes after purchasing the node")
	check(systems.toggle_awakening(103).success and systems.awakening_status(103).active, "Activation updates point allocation and current state")
	check(systems.toggle_awakening(103).success and not systems.awakening_status(103).active, "Deactivation releases point allocation")
	before = JSON.stringify(profile.data)
	check(not systems.camp_treasure_quote(1).can_buy and not systems.open_camp_treasure_boxes(1).success and JSON.stringify(profile.data) == before, "The shop cannot bypass the chest keeper's introductory dialogue")
	check(systems.execute_npc_function(140101).success, "Completing the chest keeper's real introduction opens the next option")
	for count in [1, 5, 50, 300]:
		var quote = systems.camp_treasure_quote(count)
		check(quote.price["101"] == int(catalog.find("ShopTreasureBoxData", quote.id).price) * count, "Chest batch uses source price: " + str(count))
	before = JSON.stringify(profile.data)
	check(not systems.open_camp_treasure_boxes(0).success and not systems.open_camp_treasure_boxes(301).success and JSON.stringify(profile.data) == before, "Unsupported chest counts cannot change gold or RNG")
	var quote = systems.camp_treasure_quote(1)
	var gold = systems.material(101)
	check(quote.can_buy and systems.open_camp_treasure_boxes(1).success and systems.material(101) == gold - int(quote.price["101"]), "A valid chest purchase deducts the quoted amount once")
	for node in [systems, resumed]: node.decorations = null
	print("CAMP_UNLOCK_CONTRACT ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
