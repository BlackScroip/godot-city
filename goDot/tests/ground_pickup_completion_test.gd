extends SceneTree

const Drops = preload("res://scripts/ground_loot.gd")
const PickupCard = preload("res://scripts/presentation/pickup_card.gd")

class DropWorld extends Node3D:
	var systems: RefCounted
	var environment_root: Node3D

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var systems := DungeonSystems.new(catalog, DungeonProfile.new())
	systems.begin_run(20105, 1, 100)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := DropWorld.new()
	world.systems = systems
	viewport.add_child(world)
	var drops := Drops.new()
	world.add_child(drops)
	var card := PickupCard.new()
	card.theme = DungeonStyle.theme()
	viewport.add_child(card)
	drops.spawn(20105, Vector3.ZERO, 3)
	var entry: Dictionary = drops.entries[0]
	check(entry.visual.texture.resource_path == "res://assets/ui/pickup/sprite_abilityitemicon_20105.png", "Ground boots use original transparent APK sprite")
	check(DungeonStyle.texture("loot:20105").resource_path == "res://assets/art_generated/relics/relic_20105.png", "Inventory relic artwork retains its existing generated tile")
	for id in [10100, 10101, 10102, 15101, 15102, 15103, 16101, 16102, 16103]:
		check(DungeonStyle.texture("loot:" + str(id)).resource_path == "res://assets/ui/pickup/sprite_abilityitemicon_%d.png" % id, "Shop utility resolves actual source art: %d" % id)
	for id in [101, 102, 103]:
		check(DungeonStyle.texture("material:" + str(id)).resource_path == "res://assets/ui/pickup/sprite_materialicon_%d.png" % id, "Currency and material resolve actual source art: %d" % id)
	check(entry.has("rarity_glow") and is_instance_valid(entry.rarity_glow), "Loose relic has ground quality glow")
	check(entry.rarity_color == Drops.RARITY_COLORS[1], "Boots use actual AbilityItems Rare1 color")
	check(entry.rarity_glow.texture.resource_path == Drops.PICKUP_GLOW_TEXTURE, "Ground glow reuses extracted APK texture")
	card.bind(entry, systems)
	check(card.visible and card.name_label.text == "迅捷之靴", "Nearby boots show source name")
	check(card.description_label.text.contains("移动速度") and card.description_label.text.contains("20"), "Description preserves source effect and stack limit")
	check(not card.current_key.is_empty() and card.icon.texture != null, "Pickup card has instance identity and icon")
	card.close_button.pressed.emit()
	check(not card.visible, "Close dismisses the card")
	card.bind(entry, systems)
	check(not card.visible, "Per-frame nearby refresh does not reopen dismissed card")
	check(drops.entries.size() == 1 and int(entry.amount) == 3, "Closing detail does not consume the ground stack")
	card.bind({}, systems)
	card.bind(entry, systems)
	check(card.visible, "Leaving and approaching the item reopens detail")
	card.bind(entry, systems, true)
	check(not card.visible, "Modal state hides pickup details")
	card.bind(entry, systems)
	check(card.visible, "Closing a modal restores eligible pickup detail")
	drops.spawn(20105, Vector3(1, 0, 0))
	card.dismiss()
	var first_key := card.current_key
	card.bind(drops.entries[1], systems)
	check(card.visible and card.current_key != first_key, "Another instance of the same item is independently inspectable")
	var before := int(systems.profile.data.run.inventory.get("20105", 0))
	check(drops.pickup(Vector3.ZERO, systems).success, "First stacked pickup succeeds")
	check(int(entry.amount) == 2 and drops.entries.has(entry), "Picking one copy retains the rest of a configured stack")
	var saved: Array = JSON.parse_string(JSON.stringify(drops.snapshot()))
	var old_glow: Sprite3D = entry.rarity_glow
	drops.restore(saved)
	check(old_glow.is_queued_for_deletion(), "Restoring ground state releases the previous quality glow")
	check(int(drops.entries[0].amount) == 2 and drops.entries[0].has("rarity_glow"), "Restored stack retains quantity and rebuilds its glow")
	check(drops.pickup(Vector3.ZERO, systems).success and drops.pickup(Vector3.ZERO, systems).success, "Remaining stack copies can be collected")
	check(int(systems.profile.data.run.inventory.get("20105", 0)) == before + 3, "Stack collection grants exact total")
	systems.profile.data.run.inventory["20105"] = 20
	check(not drops.pickup(Vector3(1, 0, 0), systems).success and drops.entries.size() == 1, "A capped relic remains visible and unconsumed")
	var gold := systems.material(101)
	drops.spawn(101, Vector3(10, 0, 0), 11, true)
	check(not drops.entries.back().has("rarity_glow"), "Automatic currency does not gain a manual item quality glow")
	for frame in 120: drops.advance_collection(1.0 / 60.0, Vector3.ZERO, systems)
	check(systems.material(101) == gold + 11 and drops.entries.size() == 1, "Currency attraction and manual relic retention stay independent")
	card.bind(drops.entries[0], systems)
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390)]:
		viewport.size = dimensions
		card.layout(Vector2(dimensions))
		for frame in 3: await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		check(bounds.encloses(card.get_global_rect()), "Pickup panel stays inside %s" % dimensions)
		check(bounds.encloses(card.close_button.get_global_rect()), "Pickup close control stays inside %s" % dimensions)
		check(card.description_label.size.x > 120 and card._scroll.size.y > 50, "Readable scrolling description fits %s" % dimensions)
		check(card.get_global_rect().encloses(card._scroll.get_global_rect()), "Description viewport stays within panel at %s" % dimensions)
		check(card.description_label.size.x <= card._scroll.size.x, "Description wraps inside scroll viewport at %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://reports/pickup-completion-%dx%d.png" % [dimensions.x, dimensions.y])
	var click := card.close_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = click
	viewport.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = click
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	viewport.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = click
	release.button_index = MOUSE_BUTTON_LEFT
	viewport.push_input(release, true)
	await process_frame
	check(not card.visible, "Physical mouse click activates pickup close control")
	card.bind(drops.entries[0], systems)
	check(not card.visible and drops.entries.size() == 1, "Physical close remains dismissed without collecting the item")
	drops.clear()
	check(drops.entries.is_empty(), "Clearing a room releases remaining manual drops")
	systems.decorations = null
	world.queue_free()
	viewport.queue_free()
	await process_frame
	print("GROUND_PICKUP_COMPLETION_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
