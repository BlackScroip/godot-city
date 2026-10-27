extends SceneTree

class FixtureHud extends DungeonHud:
	var shown_rows: Array = []
	var shown_layout := ""
	var shown_context: Dictionary = {}
	func show_page(_title: String, rows: Array, layout := "list", context: Dictionary = {}) -> void:
		shown_rows = rows
		shown_layout = layout
		shown_context = context
		modal_open = true

class FixtureAds extends RefCounted:
	var enabled := false
	func available() -> bool:
		return enabled

class FixtureWorld extends RefCounted:
	var player = DungeonActor.new()
	func asset_path(_kind: String, _id: int) -> String:
		return ""

class FixtureGame extends Node:
	var catalog = DungeonCatalog.new()
	var profile = DungeonProfile.new()
	var systems: DungeonSystems
	var hud = FixtureHud.new()
	var world = FixtureWorld.new()
	var selected_character := 1
	var save_store = DungeonSaveStore.new("/private/tmp/city-navigation-menu-fixture.json")
	var difficulty := 0
	var resource_audio = null
	var ads = FixtureAds.new()
	var ad_rewards: RefCounted
	func _save(_immediate := false) -> bool:
		return true

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var game = FixtureGame.new()
	check(game.catalog.load_all(), "Packaged catalog loads")
	game.systems = DungeonSystems.new(game.catalog, game.profile)
	game.ad_rewards = preload("res://scripts/domain/ad_rewards.gd").new(game.systems)
	game.world.player.combat = DungeonCombat.new()
	game.world.player.combat.configure()
	var menus = DungeonMenus.new(game)
	_settings(game, menus)
	_characters(game, menus)
	_weapons(game, menus)
	_inventory(game, menus)
	_meal_buffs(game, menus)
	_mall(game, menus)
	game.systems.decorations = null
	game.world.player.free()
	game.hud.free()
	game.free()
	print("NAVIGATION_MENU_RULES ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _settings(game: FixtureGame, menus: DungeonMenus) -> void:
	for available in [false, true]:
		game.ads.enabled = available
		menus.open("settings")
		check(game.hud.shown_layout == "settings", "Settings opens with ads available = " + str(available))
		var rows = game.hud.shown_rows
		check(rows.any(func(row): return row.title == "广告隐私") == available, "Privacy command follows platform availability")
		var visual_rows = rows.filter(func(row): return row.has("options") and row.get("section", "") == "画面")
		for key in ["quality", "shadows", "fps"]:
			check(visual_rows.any(func(row): return row.get("key", "") == key), "Visual option survives the optional privacy row: " + key)
		for row in visual_rows:
			check(row.options.filter(func(option): return option.selected).size() == 1, "Exactly one option is selected for " + str(row.title))
		for action in ["save", "retreat", "quit"]:
			check(rows.any(func(row): return row.get("buttons", []).any(func(button): return button.action == action)), "Save and return commands remain connected: " + action)

func _characters(game: FixtureGame, menus: DungeonMenus) -> void:
	game.profile.data.run.active = false
	game.profile.data.run.talents["101"] = 2
	menus.open("character_talents", 2)
	check(not game.hud.shown_rows.is_empty(), "Unselected camp character has talent rows")
	for row in game.hud.shown_rows:
		var source = game.catalog.find("CharTalentData", int(row.config_id))
		check(int(source.get("chara_id", 0)) == 2, "Talent preview follows the requested character")
		check(row.buttons[0].disabled and row.title.ends_with("Lv.0"), "Camp preview cannot learn or show an old run rank")
	game.profile.data.run.active = true
	game.profile.data.run.character_id = 1
	game.systems.set_record("talent:choices", 1)
	menus.open("character_talents", 2)
	for row in game.hud.shown_rows:
		var source = game.catalog.find("CharTalentData", int(row.config_id))
		check(int(source.get("chara_id", 0)) == 1, "Active run restricts talent learning to its character")
	game.world.player.combat.health = 37
	menus.open("characters")
	check(game.hud.shown_rows.size() == 1, "Run detail shows one active character")
	check(str(game.hud.shown_rows[0].stats[0][1]).begins_with("37 /"), "Run detail reads actual combat health")
	check(not game.hud.shown_rows[0].buttons.any(func(button): return str(button.action).begins_with("op:")), "Run character detail has no persistent growth commands")
	game.profile.data.run.active = false
	menus.open("characters")
	for row in game.hud.shown_rows:
		var source = game.catalog.find("CharData", int(row.config_id))
		if not source.get("is_cash_only_unlock", false): continue
		check(row.buttons.any(func(button): return button.action == "op:unlock_character" and button.disabled), "Cash-only characters do not expose a free recruitment command")
		check(row.buttons.any(func(button): return button.action == "page:mall"), "Cash-only character preview links to the store")

func _weapons(game: FixtureGame, menus: DungeonMenus) -> void:
	game.profile.data.run.active = true
	menus.open("weapons")
	check(not game.hud.shown_rows.is_empty(), "Active character weapon detail exists")
	for row in game.hud.shown_rows:
		check(row.in_run and row.buttons.is_empty(), "Run weapon view has no ignored equipment or camp upgrade commands")
		check(int(row.config_id) == int(row.weapon_id) and not game.catalog.find("WeaponData", int(row.config_id)).is_empty(), "Read-only weapon keeps its catalog identity")
	check(game.hud.shown_rows.filter(func(row): return row.active_character).size() == 1, "Equipped weapon remains the initial showcase selection")
	game.profile.data.run.active = false
	menus.open("weapons")
	for row in game.hud.shown_rows:
		check(not row.in_run and row.buttons.any(func(button): return button.action == "op:upgrade_weapon"), "Camp retains crafting and upgrade commands")
		var equip = row.buttons.filter(func(button): return button.action == "equip_weapon")[0]
		check(equip.disabled == (game.systems.stat("weapon:" + str(int(row.weapon_id))) == 0 or int(row.weapon_id) == int(game.profile.data.selected_weapon)), "Camp equip button follows ownership and active equipment")

func _mall(game: FixtureGame, menus: DungeonMenus) -> void:
	menus.open("mall")
	var catalog_rows = game.catalog.rows("MallTradeData")
	check(game.hud.shown_rows.size() == catalog_rows.filter(func(row): return bool(row.get("Enable", false))).size(), "Store only exposes enabled packaged offers")
	var payments: Dictionary = {}
	for row in game.hud.shown_rows:
		var offer = game.catalog.find("MallTradeData", int(row.config_id))
		check(not offer.is_empty() and offer.get("Enable", false), "Each store item maps to an enabled source offer")
		var payment = str(offer.get("GoodsPayType", ""))
		payments[payment] = int(payments.get(payment, 0)) + 1
		if payment == "Ad":
			check(row.buttons.any(func(button): return button.action == "ad:mall"), "Advertising offers use the rewarded-ad completion path")
			check(not row.buttons.any(func(button): return button.action == "op:buy_mall"), "Advertising offers have no direct purchase command")
		elif payment == "Money":
			check(row.payment_type == "Money" and row.buttons[0].disabled, "Money payment remains visible and unavailable without a payment service")
			check(row.description.contains("付费购买") and row.description.contains(str(row.offer_quote.message)), "Money item presents its payment type and actual blocked reason")
			check(int(row.offer_quote.price) == int(offer.Price) and int(row.offer_quote.currency) == 0, "Money item preserves original price without a fabricated gold conversion")
		elif payment in ["Gold", "PurchaseCion", "FreeCion"]:
			check(row.buttons[0].disabled == not row.offer_quote.success, "Currency purchase command follows actual balance and quota")
	check(payments.has("Ad") and payments.has("Money"), "Real catalog includes both advertising and money payment types")
	var purchase_coin = catalog_rows.filter(func(offer): return offer.get("Enable", false) and offer.get("GoodsPayType", "") == "FreeCion")[0].duplicate(true)
	purchase_coin.GoodsId = 994001
	purchase_coin.GoodsPayType = "PurchaseCion"
	purchase_coin.Price = 20
	game.catalog.tables.MallTradeData.append(purchase_coin)
	game.catalog._indices.MallTradeData["994001"] = purchase_coin
	game.profile.data.materials["90001"] = 20
	menus.open("mall")
	var purchase_coin_row: Dictionary = game.hud.shown_rows.filter(func(entry): return int(entry.config_id) == 994001)[0]
	check(purchase_coin_row.payment_type == "PurchaseCion" and purchase_coin_row.offer_quote.currency == 90001 and not purchase_coin_row.buttons[0].disabled, "Native purchase coin enum uses its own wallet and valid trade command")
	check(purchase_coin_row.description.contains("20 " + DungeonCatalog.clean(game.systems.material_name(90001))), "Purchase coin pricing uses the original price and source currency name")

func _inventory(game: FixtureGame, menus: DungeonMenus) -> void:
	game.profile.data.materials.merge({"102": 120, "50011": 1, "10101": 10, "801": 2}, true)
	game.profile.data.buildings["4"] = 2
	game.profile.data.run.active = false
	menus.open("storage")
	var context = game.hud.shown_context
	var rows = game.hud.shown_rows
	check(context.camp and not context.in_run, "Camp role shell uses the camp mode")
	check(context.role_navigation.map(func(entry): return entry.page) == ["characters", "weapons", "storage"], "APK camp navigation shows character, weapon and warehouse")
	check(context.resources.size() == 1 and context.resources[0][0] == "material:101", "Role shell keeps the source gold counter")
	check(rows.any(func(row): return int(row.get("material_id", 0)) == 10101 and row.count == 10), "Warehouse carries actual collected material counts")
	check(not rows.any(func(row): return int(row.get("material_id", 0)) in [102, 50011]), "APK warehouse excludes magic points and token items")
	var boxes = rows.filter(func(row): return int(row.get("material_id", 0)) == 801)
	check(boxes.size() == 1 and boxes[0].buttons[0].action == "op:open_material_box", "Owned material boxes keep their real opening command in the warehouse")
	check(rows.any(func(row): return row.description.contains("获取途径")), "Warehouse descriptions preserve source acquisition text")
	game.profile.data.run.inventory = {"10000": 2, "10100": 1}
	menus.open("inventory")
	check(not game.hud.shown_rows.any(func(row): return row.has("loot_id")), "Camp cannot display stale adventure relics")
	game.profile.data.run.active = true
	menus.open("inventory")
	context = game.hud.shown_context
	rows = game.hud.shown_rows
	check(not context.camp and context.in_run, "Adventure role shell uses the run mode")
	check(context.resources.map(func(entry): return entry[0]) == ["material:101", "material:102", "loot:12101", "material:108"], "APK adventure role resource list uses the actual always-display counters")
	check(context.role_navigation.map(func(entry): return entry.page) == ["characters", "weapons", "inventory", "storage"], "APK adventure navigation adds the backpack while retaining warehouse")
	check(rows.size() == 1 and int(rows[0].loot_id) == 10000 and rows[0].count == 2, "Backpack lists owned visible relics and filters hidden consumed drops")
	check(not rows.any(func(row): return row.has("material_id")), "Backpack and warehouse use their separate source inventories")
	game.profile.data.buildings["4"] = 3
	menus.open("weapons")
	check(game.hud.shown_context.role_navigation.map(func(entry): return entry.page) == ["characters", "weapons", "inventory", "storage", "partners"], "Institute level three adds the APK run partner entry")
	game.profile.data.run.active = false
	menus.open("characters")
	check(game.hud.shown_context.role_navigation.size() == 3 and not game.hud.shown_context.partner_navigation, "Camp navigation excludes run-only entries even with a completed institute")

func _meal_buffs(game: FixtureGame, menus: DungeonMenus) -> void:
	var first = game.catalog.rows("CatMealData")[0]
	var second = game.catalog.rows("CatMealData")[1]
	var first_id = DungeonCatalog.row_id(first)
	var second_id = DungeonCatalog.row_id(second)
	game.profile.data.run.active = true
	game.profile.data.recipes[str(first_id)] = 3
	game.profile.data.recipes[str(second_id)] = 1
	game.profile.data.meal_selection = {str(second_id): 1}
	game.profile.data.last_meals = {str(second_id): 1}
	game.profile.data.purchased_meals = {str(first_id): 2}
	var before = JSON.stringify(game.profile.data)
	menus.open("meal_buffs")
	check(JSON.stringify(game.profile.data) == before, "Opening meal effects never buys, researches or changes the order")
	check(game.hud.shown_rows.size() == 1, "Meal effects excludes recipes, temporary selection and last order")
	var row: Dictionary = game.hud.shown_rows[0]
	var ability = DungeonCatalog.ids(first.AbilityItemId)[1]
	check(row.meal_id == first_id and row.config_id == first_id and row.meal_level == 2, "Meal effects reads the actual purchased rank")
	check(row.ability_id == ability and game.systems.rank(game.systems.ability_sources(), ability) == 1, "Displayed meal is the same ability used by combat progression")
	check(row.description == DungeonCatalog.clean(game.systems._part(first.Description, 1)), "Meal effect description uses the exact purchased configuration level")
	check(row.icon == first.IconName and row.buttons.is_empty(), "Meal effects keeps the original icon and has no purchase commands")
	game.systems.clear_invalid_meals("CompleteRegion")
	menus.open("meal_buffs")
	check(game.hud.shown_rows.size() == 1 and not game.hud.shown_rows[0].has("meal_id"), "Expired regional effects disappear instead of showing the last order")
	game.profile.data.erase("purchased_meals")
	game.profile.data.selected_meal = first_id
	game.profile.data.meal_rank = 1
	menus.open("meal_buffs")
	check(game.hud.shown_rows[0].meal_level == 1 and game.hud.shown_rows[0].ability_id == DungeonCatalog.ids(first.AbilityItemId)[0], "Legacy purchased meal saves retain the actual effect")
	game.profile.data.run.active = false
	menus.open("meal_buffs")
	check(game.hud.shown_rows.size() == 1 and not game.hud.shown_rows[0].has("meal_id"), "Meal buff popup only exposes effects in an active adventure")
