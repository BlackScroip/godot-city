extends SceneTree

const RichSource = preload("res://scripts/presentation/source_rich_text.gd")
const APK_SHA256 := "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
const TABLE_COUNTS := {"CharTalentData": 271, "CharTalentLevelData": 587, "AbilityItems": 1023, "AdvantureEventData": 124}
const FOCUS_ICONS := {
	107: ["buff_zhongji", "buff_zhuorejianqi"],
	116: ["buff_jianxin", "buff_gongjili"],
	118: ["buff_jianxin", "buff_putonggongji", "buff_jianxin"],
}
const SOURCE_UNRESOLVED := ["buff_longhunnengliang", "buff_sikadizhinunengliang", "buff_sishenbiaoji"]
const DYNAMIC_WORDING_SENTINEL := "314159"

var checks := 0
var failures: Array[String] = []
var terms: Dictionary = {}
var sprites: Dictionary = {}
var raw_tables: Dictionary = {}
var term_uses: Dictionary = {}
var sprite_uses: Dictionary = {}
var table_reports: Dictionary = {}
var field_reports: Array = []
var dynamic_fields: Array = []
var focus_reports: Array = []
var resource_reports: Array = []
var wording_differences: Array = []
var semantic := RegEx.create_from_string("(?i)<#specinfo=[\"']?([^>\"']+)[\"']?>")
var source_sprite := RegEx.create_from_string("(?i)<sprite\\s+name=[\"']([^\"']+)[\"'][^>]*>")
var source_color := RegEx.create_from_string("(?i)<(?:color\\s*=\\s*)?(#[0-9a-f]{3,8})>")
var result_image := RegEx.create_from_string("\\[img=(\\d+)x(\\d+)\\](.*?)\\[/img\\]")
var result_color := RegEx.create_from_string("(?i)\\[color=(#[0-9a-f]{3,8})\\]")
var any_source_tag := RegEx.create_from_string("</?[#A-Za-z][^>]*>")
var missing_source := RegEx.create_from_string("【(?:图标|术语|文本)：")
var dynamic_token := RegEx.create_from_string("<#(backpack_[^>]+)>")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DungeonLocale.set_locale("zh_CN", false)
	var source_terms: Array = JSON.parse_string(FileAccess.get_file_as_string(RichSource.TERMS_PATH))
	sprites = JSON.parse_string(FileAccess.get_file_as_string(RichSource.INLINE_PATH))
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/talent_view/inline-provenance.json"))
	check(source_terms.size() == 132 and sprites.size() == 87, "Full APK keyword and sprite inventories are present")
	check(provenance.get("apk_sha256", "") == APK_SHA256, "Inline resource provenance identifies the supplied APK")
	for row in source_terms: terms[str(row.key)] = row
	var unresolved: Array = provenance.get("unresolved", []).duplicate()
	unresolved.sort()
	check(unresolved == SOURCE_UNRESOLVED, "Known absent source sprite names remain explicit without substitute artwork")
	_validate_resources(provenance)
	var label := RichSource.new()
	label.add_theme_font_size_override("normal_font_size", 31)
	root.add_child(label)
	for table in TABLE_COUNTS:
		var path := "res://assets/data/" + str(table) + ".json"
		var data: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
		raw_tables[table] = data
		var stats := {"path": path, "sha256": FileAccess.get_sha256(path), "rows": data.size(), "raw_strings": 0, "tagged_fields": 0, "semantic_occurrences": 0, "image_occurrences": 0, "color_occurrences": 0, "dynamic_placeholders": 0}
		for row_index in data.size():
			var row: Dictionary = data[row_index]
			var strings: Array = []
			_collect_strings(row, "$[%d]" % row_index, strings)
			stats.raw_strings += strings.size()
			for entry in strings:
				var raw := str(entry.value)
				if any_source_tag.search(raw) == null: continue
				var location := "%s:%d:%s" % [table, DungeonCatalog.row_id(row), entry.path]
				var inspected := _inspect_raw(label, raw, location)
				for key in ["semantic_occurrences", "image_occurrences", "color_occurrences", "dynamic_placeholders"]: stats[key] += int(inspected[key])
				stats.tagged_fields += 1
				inspected.merge({"table": table, "row_id": DungeonCatalog.row_id(row), "field": entry.path})
				field_reports.append(inspected)
				if int(inspected.dynamic_placeholders) > 0:
					dynamic_fields.append({"table": table, "row_id": DungeonCatalog.row_id(row), "name": DungeonCatalog.row_name(row), "field": entry.path, "source": raw, "displayed_without_runtime_context": label.get_parsed_text(), "tokens": dynamic_token.search_all(raw).map(func(match): return match.get_string(1))})
		check(int(stats.semantic_occurrences) == int(TABLE_COUNTS[table]), str(table) + " raw semantic occurrence count covers the complete supplied corpus")
		table_reports[table] = stats
	check(term_uses.size() == 62, "All 62 semantic terms actually used in Chinese source descriptions are covered")
	for name in SOURCE_UNRESOLVED: check(not sprite_uses.has(name), name + " is absent from actual Chinese description expansion")
	await _verify_focus_cards()
	label.queue_free()
	var report := {
		"schema": 1, "passed": failures.is_empty(), "checks": checks, "failures": failures,
		"apk_sha256": APK_SHA256, "locale": "zh_CN", "input_mode": "Direct recursive JSON string reads before DungeonCatalog.description or clean; expected image/color sequences come from the APK keyword table.",
		"source_keyword_count": terms.size(), "mapped_sprite_count": sprites.size(), "actual_semantic_term_count": term_uses.size(), "actual_unique_sprite_count": sprite_uses.size(),
		"tables": table_reports, "term_occurrences": term_uses, "sprite_occurrences": sprite_uses,
		"fields": field_reports, "focus_talents": focus_reports, "resources": resource_reports,
		"wording_validation": "Independent APK keyword expansion, source image positions preserved as spaces, CR normalized as RichTextLabel does. Dynamic slots use a fixed numeric sentinel only for static wording checks; their untouched isolated output is recorded separately.",
		"wording_differences": wording_differences,
		"unresolved_source_sprites_unused_by_actual_chinese_text": unresolved,
		"dynamic_fields_requiring_runtime_context": dynamic_fields,
		"limitations": ["This is headless text, markup, resource and real talent-card binding verification; it does not assert rasterized icon color, spacing or glyph layout.", "Raw backpack placeholders require per-run numeric context. Their occurrences and isolated-renderer output are recorded separately; successful static icon checks do not assert that runtime values were filled.", "Only the actual Chinese source corpus is exhaustive. Other locales retain the separate source_rich_text_test smoke coverage."]
	}
	FileAccess.open("res://reports/source-rich-text-raw-audit-20261028.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SOURCE_RICH_TEXT_RAW_TEST ", JSON.stringify({"passed": report.passed, "checks": checks, "failures": failures, "terms": term_uses.size(), "sprites": sprite_uses.size(), "raw_fields": field_reports.size(), "dynamic_fields": dynamic_fields.size()}))
	quit(0 if failures.is_empty() else 1)

func _collect_strings(value: Variant, path: String, target: Array) -> void:
	if value is String:
		if not value.is_empty(): target.append({"path": path, "value": value})
	elif value is Dictionary:
		for key in value: _collect_strings(value[key], path + "." + str(key), target)
	elif value is Array:
		for index in value.size(): _collect_strings(value[index], path + "[%d]" % index, target)

func _expanded_source(raw: String, location: String) -> String:
	var result := raw
	for depth in 8:
		var matches := semantic.search_all(result)
		if matches.is_empty(): return result
		for match in matches:
			var key := "<#specinfo=" + match.get_string(1) + ">"
			check(terms.has(key), location + " has source term " + key)
			var replacement := str(terms.get(key, {}).get("text_cn", ""))
			check(not replacement.is_empty(), location + " has authored Chinese expansion " + key)
			result = result.replace(match.get_string(), replacement)
	check(semantic.search(result) == null, location + " source expansion terminates")
	return result

func _inspect_raw(label: RichTextLabel, raw: String, location: String) -> Dictionary:
	var semantic_matches := semantic.search_all(raw)
	for match in semantic_matches:
		var key := match.get_string(1)
		term_uses[key] = int(term_uses.get(key, 0)) + 1
	var expanded := _expanded_source(raw, location)
	var expected_names: Array[String] = []
	var expected_paths: Array[String] = []
	for match in source_sprite.search_all(expanded):
		var name := match.get_string(1)
		expected_names.append(name)
		expected_paths.append(str(sprites.get(name, "")))
		sprite_uses[name] = int(sprite_uses.get(name, 0)) + 1
		check(sprites.has(name) and not RichSource.sprite_path(name).is_empty(), location + " resolves its authored sprite " + name)
	var expected_colors: Array[String] = []
	for match in source_color.search_all(expanded): expected_colors.append(match.get_string(1).to_lower())
	label.set_source(raw)
	var rendered_paths: Array[String] = []
	for match in result_image.search_all(label.text):
		rendered_paths.append(match.get_string(3))
		check(int(match.get_string(1)) == label.get_theme_font_size("normal_font_size") and int(match.get_string(2)) == label.get_theme_font_size("normal_font_size"), location + " sizes inline images to the description font")
	var rendered_colors: Array[String] = []
	for match in result_color.search_all(label.text): rendered_colors.append(match.get_string(1).to_lower())
	check(rendered_paths == expected_paths, location + " retains every source icon in order, including repeats")
	check(rendered_colors == expected_colors, location + " retains every authored color span in order")
	check(any_source_tag.search(label.text) == null and any_source_tag.search(label.get_parsed_text()) == null, location + " has no leaked TMP markup")
	check(missing_source.search(label.get_parsed_text()) == null, location + " has no missing semantic text or image fallback")
	var dynamic_matches := dynamic_token.search_all(raw)
	var wording_source := expanded
	if not dynamic_matches.is_empty():
		# Verify authored wording independently of the separate per-run value resolver.
		wording_source = dynamic_token.sub(wording_source, DYNAMIC_WORDING_SENTINEL, true)
		label.set_source(dynamic_token.sub(raw, DYNAMIC_WORDING_SENTINEL, true))
	var expected_text := _readable_source(wording_source)
	var actual_text := label.get_parsed_text().replace("\r", "")
	check(actual_text == expected_text, location + " preserves independent APK readable wording")
	if actual_text != expected_text:
		wording_differences.append({"location": location, "source": raw, "expected": expected_text, "actual": actual_text})
	if not dynamic_matches.is_empty(): label.set_source(raw)
	return {"semantic_occurrences": semantic_matches.size(), "image_occurrences": expected_names.size(), "color_occurrences": expected_colors.size(), "dynamic_placeholders": dynamic_matches.size(), "sprites": expected_names, "wording_mode": "raw" if dynamic_matches.is_empty() else "numeric_sentinel_in_dynamic_slots"}

func _readable_source(expanded: String) -> String:
	var text := source_sprite.sub(expanded, " ", true)
	text = text.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
	return any_source_tag.sub(text, "", true).replace("\r", "")

func _validate_resources(provenance: Dictionary) -> void:
	for name in sprites:
		var path := str(sprites[name])
		check(path.begins_with("res://") and FileAccess.file_exists(path), name + " has a real extracted image file")
		check(RichSource.sprite_path(str(name)) == path, name + " resolves only to its source map entry")
		var source_rows: Array = provenance.get("sprites", []).filter(func(row): return row.get("name", "") == name and row.get("output", "") == path)
		check(source_rows.size() == 1, name + " has one exact APK Sprite provenance record")
		var texture: Texture2D = load(path)
		check(texture != null, name + " imports as a real texture resource")
		if texture == null: continue
		var image := texture.get_image()
		check(not image.is_empty() and image.get_used_rect().has_area(), name + " contains visible source artwork")
		resource_reports.append({"name": name, "path": path, "sha256": FileAccess.get_sha256(path), "width": image.get_width(), "height": image.get_height(), "source": source_rows[0] if source_rows.size() == 1 else {}})

func _verify_focus_cards() -> void:
	var canvas := SubViewport.new()
	canvas.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(canvas)
	var page := DungeonMenuPage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	var rows: Array = []
	for id in FOCUS_ICONS:
		var talent: Dictionary = raw_tables.CharTalentData.filter(func(row): return int(row.id) == id)[0]
		var level_rows: Array = []
		for level_id in DungeonCatalog.ids(talent.level_data_id_list):
			var level: Dictionary = raw_tables.CharTalentLevelData.filter(func(row): return int(row.id) == int(level_id))[0]
			level_rows.append({"level": level_rows.size() + 1, "source_description": str(level.effect_description)})
		rows.append({"config_id": id, "title": talent.name, "icon": talent.icon_name, "target_level": 1, "source_description": talent.description, "talent_level_descriptions": level_rows, "buttons": [{"action": "choose_talent", "id": id}]})
	page.display("选择本局天赋", rows, "talent")
	var selection: Node = page.special.get_child(0)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 3: await process_frame
		for index in rows.size():
			var part: Dictionary = selection.parts[index]
			var id := int(rows[index].config_id)
			var expected: Array = FOCUS_ICONS[id].map(func(name): return str(sprites.get(name, "")))
			var paths: Array = result_image.search_all(part.description.text).map(func(match): return match.get_string(3))
			check(part.description is RichSource and part.description.source_text == rows[index].source_description, "Talent %d uses original description in the actual card at %s" % [id, dimensions])
			check(paths == expected, "Talent %d actual card retains its screenshot icon sequence at %s" % [id, dimensions])
			for level in rows[index].talent_level_descriptions:
				check(part.level_description.source_text.contains(level.source_description), "Talent %d actual card preserves raw level %d description" % [id, int(level.level)])
			check(any_source_tag.search(part.level_description.text) == null and missing_source.search(part.level_description.get_parsed_text()) == null, "Talent %d level descriptions resolve source icons and colors" % id)
			for match in result_image.search_all(part.description.text): check(int(match.get_string(1)) == part.description.get_theme_font_size("normal_font_size"), "Talent %d inline icons follow responsive font updates" % id)
			focus_reports.append({"talent_id": id, "viewport": [dimensions.x, dimensions.y], "source": part.description.source_text, "bbcode": part.description.text, "parsed": part.description.get_parsed_text(), "icons": FOCUS_ICONS[id], "level_source": part.level_description.source_text, "level_bbcode": part.level_description.text})
	canvas.queue_free()
	await process_frame

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
