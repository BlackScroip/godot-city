extends SceneTree

const Descriptions = preload("res://scripts/domain/ability_descriptions.gd")
const RichSource = preload("res://scripts/presentation/source_rich_text.gd")

class FixtureWorld extends Node:
	var player := DungeonActor.new()
	var _camp_camera := false

class FixtureGame extends Node:
	var catalog := DungeonCatalog.new()
	var profile := DungeonProfile.new()
	var systems: DungeonSystems
	var hud: DungeonHud
	var world := FixtureWorld.new()
	var selected_character := 1
	var resource_audio = null

var checks := 0
var failures: Array[String] = []
var observations: Array = []
var captures: Array[String] = []
var game: FixtureGame
var descriptions: RefCounted
var label: SourceRichText
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func reset(inventory: Dictionary = {}) -> void:
	game.profile.data.run = DungeonProfile.new_run(20261028, 1, 100)
	game.profile.data.run.active = true
	game.profile.data.run.inventory = inventory.duplicate(true)
	game.profile.data.materials["102"] = 0

func plain(id: int, combat: RefCounted = null) -> String:
	label.set_source(descriptions.source(id, id, combat))
	return label.get_parsed_text()

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	DungeonLocale.set_locale("zh_CN", false)
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = FixtureGame.new()
	canvas.add_child(game)
	game.add_child(game.world)
	check(game.catalog.load_all(), "Actual APK catalog loads")
	game.systems = DungeonSystems.new(game.catalog, game.profile)
	game.hud = DungeonHud.new()
	canvas.add_child(game.hud)
	game.world.player.combat = DungeonCombat.new()
	game.world.player.combat.configure(null, game.systems, 1)
	descriptions = Descriptions.new(game.systems)
	label = RichSource.new()
	canvas.add_child(label)
	_all_dynamic_fields()
	_source_factors()
	_runtime_values()
	await _presentation_bindings()
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "dynamic_fields": observations.size(), "observations": observations, "captures": captures, "native_evidence": "ability-descriptions-native-20261028.json"}
	FileAccess.open("res://reports/ability-descriptions-tests-20261028.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ABILITY_DESCRIPTIONS_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "dynamic_fields": observations.size()}))
	game.systems.decorations = null
	game.world.player.free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _all_dynamic_fields() -> void:
	for row in game.catalog.rows("AbilityItems"):
		var raw := DungeonCatalog.description(row)
		if not raw.contains("<#backpack_"): continue
		var id := DungeonCatalog.row_id(row)
		var loot_id := 0
		for loot in game.catalog.rows("LootData"):
			if int(loot.ability_item_id) == id:
				loot_id = int(loot.id)
				break
		check(loot_id > 0, "%d has an actual backpack item" % id)
		reset({str(loot_id): 1})
		var source: String = descriptions.source(id, loot_id)
		label.set_source(source)
		check(not source.contains("<#backpack_") and not label.text.contains("backpack_"), "%d resolves every runtime placeholder" % id)
		check(RegEx.create_from_string("（(?:当前|已触发)[^）]*[0-9]").search(label.get_parsed_text()) != null, "%d owned status contains an actual number" % id)
		check(not label.text.contains("<#") and not label.text.contains("<color") and not label.text.contains("<sprite"), "%d renders without TMP markup" % id)
		if RichSource.source_to_bbcode(raw).contains("[img="): check(label.text.contains("[img="), "%d preserves its source term icons" % id)
		observations.append({"ability_id": id, "loot_id": loot_id, "owned_source": source, "owned_text": label.get_parsed_text()})
		game.profile.data.run.inventory.clear()
		var preview: String = descriptions.source(id, loot_id)
		check(not preview.contains("<#backpack_") and not preview.contains("（当前") and not preview.contains("（已触发"), "%d unowned preview removes the complete runtime annotation" % id)
		game.profile.data.run.inventory[str(loot_id)] = 1
		game.profile.data.run.active = false
		check(descriptions.source(id, loot_id) == preview, "%d camp preview does not reuse stale adventure counters" % id)
	check(observations.size() == 54, "All 54 actual dynamic description fields are covered")

func _source_factors() -> void:
	reset({"20133": 1, "10000": 3, "20210": 2, "11001": 99})
	check(descriptions.source_attribute("BackPackLootCount") == 6, "Visible backpack count includes gems and spirits but excludes hidden currency")
	check(descriptions.source_attribute("GemHaveCount") == 3, "Gem count uses owned amounts")
	check(plain(20133).contains("当前6层"), "Medal description follows all visible backpack quantities")
	var attributes := {}
	game.systems.effects.ability_attributes(20133, 1, attributes)
	check(attributes.get("SubSkillDamageRate", 0) == 300, "Medal applies six authored five-percent layers")
	reset({"20401": 1, "20210": 4, "20211": 2, "20212": 3, "20270": 2})
	check(descriptions.source_attribute("SpritesRarityTotal") == 13, "Spirit weighting is unique kinds at one, two, three, and seven")
	check(plain(20401).contains("当前13层"), "Spirit collection description follows native weighted kinds")
	attributes.clear()
	game.systems.effects.ability_attributes(20401, 1, attributes)
	check(attributes.get("DefAddRate", 0) == 1300, "Spirit weighting also drives its actual defense effect")
	reset({"23050": 1, "20210": 5, "10000": 9, "11001": 99})
	check(descriptions.source_attribute("LootAllStarNum") == 10, "Star total counts each retained kind once and excludes consumed resource categories")
	check(plain(23050).contains("当前3层"), "Dream key divides unique total stars by three")
	reset({"20552": 1, "24001": 3, "24002": 2})
	check(descriptions.source_attribute("MonsterPartnerGeneralCount") == 5, "Partner general count sums actual matching loot quantities")
	attributes.clear()
	game.systems.effects.ability_attributes(20552, 1, attributes)
	check(attributes.get("MonsterPartnerSpChargeSpeed", 0) == 875, "Partner support necklace uses its source count multiplier")
	reset({"20193": 1, "20195": 1})
	game.profile.data.run.counters["SearchPointMax"] = 1
	game.profile.data.run.counters["SearchPoint"] = 4
	check(descriptions.source_attribute("SearchPoint") == 4, "Search points come from the run search state")
	attributes.clear()
	game.systems.effects.ability_attributes(20195, 1, attributes)
	check(attributes.get("TimeLimitRoomAddTime", 0) == 2 and attributes.get("DodgeRoomAddDodgeCount", 0) == 1 and attributes.get("RemainTargetAddHp", 0) == 8, "Combine fixed components remain one while variable components use the source factor")
	attributes.clear()
	game.systems.effects.ability_attributes(20162, 3, attributes)
	check(attributes.get("DropMagicPointFactor", 0) == 200, "A non-calculated fixed component remains one application when ability sources aggregate")
	var fixed_roots := {}
	game.systems._gather_ability_buffs(20120, 3, fixed_roots, [])
	check(int(fixed_roots.get("50201200", 0)) == 1, "Non-calculated fixed buff binding uses the native component factor")
	reset({"20407": 1})
	game.profile.data.materials["102"] = 1499
	check(plain(20407).contains("当前2层"), "Resource division truncates at an incomplete five-hundred threshold")
	game.profile.data.materials["102"] = 26001
	check(plain(20407).contains("当前52层"), "Normal source display reports its uncapped native calculation factor")
	attributes.clear()
	game.systems.effects.ability_attributes(20407, 1, attributes)
	check(attributes.get("SkillActive2ChargeSpeed", 0) == 500 and attributes.get("MainSkillDamageRate", 0) == 500, "Actual staff buff respects its separate fifty-layer limit")
	for pair in [[20420, 50204201, 50], [20426, 50204261, 100]]:
		reset({str(pair[0]): 1, "10000": 199})
		var roots := {}
		var counted := []
		game.systems._gather_ability_buffs(pair[0], 1, roots, counted)
		check(int(roots.get(str(pair[1]), 0)) == pair[2], "%d progression binding caps the variable source buff" % pair[0])
		check(plain(pair[0]).contains("当前%d层" % pair[2]), "%d explicit buff status uses the same cap" % pair[0])
		var combat := DungeonCombat.new()
		combat.configure(null, game.systems, 1)
		combat.set_progression_buffs([{"id": str(pair[1]), "layers": 7}], [])
		check(plain(pair[0], combat).contains("当前7层"), "%d live combat layer takes precedence over a reconstructed preview" % pair[0])
		combat.set_progression_buffs([], [])
		combat.statuses.clear()
	reset({"20425": 1})
	game.profile.data.run.counters["CampNpcSupportCount"] = 4
	check(plain(20425).contains("当前4层"), "Support count renders from this adventure's actual claims")
	var calculated := 0
	for row in game.catalog.rows("AbilityItems"):
		if not row.get("EnableCaculateAttributeSource", false): continue
		calculated += 1
		check(str(row.CaculateAttributeSource) in ["MagicPoint", "SearchPoint", "CampNpcSupportCount", "BackPackLootCount", "BackPackLootCount_1Star", "GemHaveCount", "SpritesRarityTotal", "LootAllStarNum", "MonsterPartnerGeneralCount"], "%s has an implemented native calculation source" % row.ID)
	check(calculated == 19, "All nineteen source-calculated abilities use supported attributes")

func _runtime_values() -> void:
	reset({"20406": 1})
	game.systems.grant_material(102, 2501)
	check(plain(20406).contains("当前进度：2501/10000"), "Ordinary relic description follows its real upgrade progress")
	reset({"22012": 1})
	game.systems.grant_material(102, 125)
	check(plain(22012).contains("当前2层"), "Event layer description follows completed thresholds with remainder")
	reset({"20584": 1})
	game.systems.effects.dispatch_message("MonsterTrigger_20581", {"Arg1": "125"})
	check(plain(20584).contains("1/10"), "Record trigger status shows executions instead of reward quantity or remaining progress")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.profile.data))
	var restored := DungeonProfile.new()
	check(restored.restore(snapshot), "Dynamic description counters survive valid JSON save restoration")
	var restored_systems := DungeonSystems.new(game.catalog, restored)
	var restored_descriptions := Descriptions.new(restored_systems)
	check(restored_descriptions.source(20584, 20584) == descriptions.source(20584, 20584), "Restored display preserves the execution count")
	restored_systems.effects.dispatch_message("MonsterTrigger_20581", {"Arg1": "25"})
	label.set_source(restored_descriptions.source(20584, 20584))
	check(label.get_parsed_text().contains("2/10"), "Restored remainder produces the next displayed execution")
	restored_systems.decorations = null

func _presentation_bindings() -> void:
	reset({"20133": 1, "10000": 3})
	var menus := DungeonMenus.new(game)
	check(menus.description(game.catalog.find("AbilityItems", 20133)).contains("当前4层"), "Plain compatibility descriptions resolve runtime state before cleanup")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		menus.open("inventory")
		for frame in 4: await process_frame
		var inventory := game.hud.page.inventory_view
		inventory.select_item("loot:20133")
		inventory._adapt()
		check(inventory.description_label is SourceRichText and inventory.description_label.text.contains("[img=") and inventory.description_label.text.contains("[color=#fdd033]"), "Inventory preserves source icons and colors at %s" % dimensions)
		check(inventory.description_label.get_parsed_text().contains("当前4层"), "Inventory binds live description values at %s" % dimensions)
		check(inventory.description_label.text.contains("[img=%dx%d]" % [13, 13] if dimensions.y < 600 else "[img=23x23]"), "Inventory icon dimensions follow the adapted font size at %s" % dimensions)
		await _capture("inventory")
		menus.open("archive")
		for frame in 4: await process_frame
		var archive := game.hud.page.camp_service_view
		for index in archive.rows.size():
			if int(archive.rows[index].get("loot_id", 0)) == 20133: archive.select_row(index); break
		var archived := archive.details.get_node_or_null("SourceDescription") as SourceRichText
		check(archived != null and archived.text.contains("[img=") and archived.get_parsed_text().contains("当前4层"), "Archive detail binds source icons and actual state at %s" % dimensions)
		await _capture("archive")
		var row := {"title": "侍从勋章", "loot_id": 20133, "price": 50, "source_description": menus.ability_source(20133, 20133), "description": "", "affordable": true}
		game.hud.show_page("迷宫商店", [row], "room_shop", {"magic": 100, "shop": {}})
		var shop: Control = game.hud.page.room_shop_view
		for frame in 4: await process_frame
		shop._show_item(row)
		for frame in 4: await process_frame
		var shop_text := shop.modal.find_child("SourceDescription", true, false) as SourceRichText
		check(shop_text != null and shop_text.text.contains("[img=") and shop_text.get_parsed_text().contains("当前4层"), "Shop inspect modal preserves the same source description at %s" % dimensions)
		check(game.hud.modal_open and not game.hud.skill_cluster.is_visible_in_tree() and not game.hud.vitals.is_visible_in_tree() and not game.hud.navigation.is_visible_in_tree(), "Shop detail uses the real modal path without overlapping gameplay controls at %s" % dimensions)
		await _capture("shop")
		game.hud.close_page()
		await process_frame

func _capture(view: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var opening: Tween = game.hud.page._open_tween
	if opening and opening.is_valid() and opening.is_running(): await opening.finished
	await RenderingServer.frame_post_draw
	var picture := canvas.get_texture().get_image()
	var path := "res://reports/ability-description-%s-%dx%d.png" % [view, canvas.size.x, canvas.size.y]
	check(not picture.is_empty() and picture.save_png(path) == OK, "Source description view renders: " + view + str(canvas.size))
	captures.append(path)
