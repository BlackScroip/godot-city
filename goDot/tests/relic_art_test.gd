extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_generated/relics/manifest.json"))
	check(manifest.get("installed", false), "Audited atlas installed")
	check(manifest.items.size() == 243, "All 243 requested relics included")
	var counts: Dictionary = {}
	var paths: Dictionary = {}
	for item in manifest.items:
		var loot = catalog.find("LootData", int(item.id))
		var ability = catalog.find("AbilityItems", int(loot.ability_item_id))
		check(str(item.name) == str(ability.Name), "Name matches catalog: " + str(item.id))
		check(int(item.rarity) == int(ability.Rare), "Rarity matches catalog: " + str(item.id))
		check(not paths.has(str(item.path)), "Unique asset: " + str(item.id))
		paths[str(item.path)] = true
		var art = DungeonStyle.texture("loot:" + str(int(item.id)))
		check(art != null and art.resource_path == str(item.path), "Generated PNG resolves: " + str(item.id))
		if art == null: continue
		var image = art.get_image()
		check(image.get_size() == Vector2i(128,128), "Stable square dimensions: " + str(item.id))
		check(image.get_pixel(64, 2).is_equal_approx(Color(str(item.hex))), "Correct rarity frame: " + str(item.id))
		counts[int(item.rarity)] = int(counts.get(int(item.rarity), 0)) + 1
	check(counts == {1:6, 2:26, 3:48, 4:90, 5:73}, "Rarity distribution matches configuration")
	var atlas = load("res://assets/art_generated/relics/relic-atlas.png") as Texture2D
	check(atlas != null and atlas.get_size() == Vector2(3456,1152), "Regular atlas has 27 by 9 cells")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "items": manifest.items.size(), "rarity_counts": counts}
	var file = FileAccess.open("res://reports/relic-art-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("RELIC_ART ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
