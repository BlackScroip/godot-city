extends SceneTree

const APK_SHA256 := "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
const PROVENANCE := "res://assets/ui/camp/awakening/provenance.json"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP PROGRESSION ICONS: " + message)

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _run() -> void:
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROVENANCE))
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/camp/awakening/resource_map.json"))
	var central: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/camp/resource_map.json"))
	check(provenance.apk_sha256 == APK_SHA256, "recovery is pinned to audited APK")
	check(provenance.missing.is_empty() and provenance.requested_names.size() == 36 and provenance.sprites.size() == 36 and mapping.size() == 36, "all 36 requested source sprites were recovered")
	check(provenance.public_awakening_nodes == 110, "recovery uses the complete public source node set")
	check(provenance.config_sources.has("CharaTalentAwakeTreeData") and provenance.config_sources.has("RelationshipTokenData"), "original source table identities are retained")
	var recovered_awakenings := 0
	for sprite in provenance.sprites:
		var sprite_name := str(sprite.name)
		var path := str(sprite.path)
		check(mapping.get(sprite_name) == path and central.get(sprite_name) == path, "resource maps address source sprite " + sprite_name)
		check(not str(sprite.source_asset).is_empty() and not str(sprite.sprite_path_id).is_empty() and str(sprite.source.bundle_sha256).length() == 64, "source identity retained " + sprite_name)
		check(FileAccess.get_sha256(path) == sprite.png_sha256, "PNG bytes match recovered source " + sprite_name)
		var decoded := Image.new()
		var error := decoded.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		check(error == OK and not decoded.is_empty(), "source PNG decodes " + sprite_name)
		if error != OK or decoded.is_empty(): continue
		check(decoded.get_width() == int(sprite.width) and decoded.get_height() == int(sprite.height), "source dimensions preserved " + sprite_name)
		decoded.convert(Image.FORMAT_RGBA8)
		check(_hash(decoded.get_data()) == sprite.rgba_sha256, "decoded RGBA pixels match source " + sprite_name)
		var bounds := decoded.get_used_rect()
		var expected: Array = sprite.alpha_bounds
		check(bounds.has_area() and bounds == Rect2i(int(expected[0]), int(expected[1]), int(expected[2]) - int(expected[0]), int(expected[3]) - int(expected[1])), "visible source alpha bounds preserved " + sprite_name)
		var texture := DungeonStyle.texture(sprite_name)
		check(texture != null and texture.resource_path == path and texture.get_size() == Vector2(decoded.get_size()), "game loader resolves exact source PNG " + sprite_name)
		if sprite_name.begins_with("sprite_awake_"): recovered_awakenings += 1
	check(recovered_awakenings == 35, "all 35 previously absent public awakening icons restored")
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "source catalog loads")
	var public_count := 0
	for row in catalog.rows("CharaTalentAwakeTreeData"):
		if bool(row.get("is_admin_mode", false)) or not bool(row.get("is_enabled", true)): continue
		public_count += 1
		var texture := DungeonStyle.texture(str(row.icon_name))
		check(texture != null, "every public node has its authored sprite " + str(int(row.id)))
	check(public_count == 110, "all 110 public awakening nodes checked")
	var token_levels := 0
	for row in catalog.rows("RelationshipTokenData"):
		if int(row.material_id) != 50081: continue
		token_levels += 1
		check(str(row.icon_name) == "sprite_tokenicon_50081" and DungeonStyle.texture(str(row.icon_name)) != null, "Petra token source artwork resolves at level " + str(int(row.level)))
	check(token_levels == 6, "all six source levels of Petra token checked")
	check(DungeonStyle.missing.is_empty(), "no progression asset lookup falls back to missing artwork")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "recovered_sprites": provenance.sprites.size(), "public_awakening_nodes": public_count, "petra_token_levels": token_levels, "provenance": PROVENANCE, "scope": "Exact PNG and RGBA digests, dimensions, alpha bounds, central resource mapping and Godot texture loading. Original APK runtime not executed."}
	var output := FileAccess.open("res://reports/camp-progression-icons-test.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("CAMP_PROGRESSION_ICONS_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
