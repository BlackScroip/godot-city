extends SceneTree

const RichSource = preload("res://scripts/presentation/source_rich_text.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	DungeonLocale.set_locale("zh_CN", false)
	var label = RichSource.new()
	label.add_theme_font_size_override("normal_font_size", 31)
	root.add_child(label)
	label.set_source("<#specinfo=shanbigongji>命中后生成<color=#4bba3c>风压奇点</color>，造成25%<#specinfo=gongjili>伤害。")
	check(label.bbcode_enabled and label.fit_content and not label.scroll_active, "Source descriptions wrap and fit without a nested scroll area")
	check(label.get_parsed_text() == " 闪避攻击命中后生成风压奇点，造成25% 攻击力伤害。", "Spirit description keeps authored terms and wording")
	check(label.text.contains("[img=31x31]") and label.text.contains("[color=#4bba3c]风压奇点[/color]"), "Inline artwork follows the caller's font size and source colors")
	label.set_source("<color=#fff><b>金币</b></color><br/><i>战利品</i><br />[url=https://example.invalid]原文[/url]")
	check(label.get_parsed_text() == "金币\n战利品\n[url=https://example.invalid]原文[/url]", "TMP breaks and emphasis render while source BBCode remains literal")
	check(not label.text.contains("[url=https://"), "Source strings cannot introduce clickable BBCode")
	label.set_source("<#LocalizationId='keyword_chara'>角色</LocalizationId>：<#specinfo='gongjili'>")
	check(label.get_parsed_text() == "角色： 攻击力", "Inline localization resolves without duplicated fallback")
	label.set_source("<#LocalizationId=\"keyword_chara\"><br><#LocalizationId='unknown_text'><u>原始后备</u></LocalizationId>")
	check(label.get_parsed_text() == "角色\n原始后备", "Bare localization and formatted inline fallbacks are readable")
	label.set_source("<#specinfo=unknown_status>，<#LocalizationId=unknown_text>，<#futuretag=value>，<sprite name='missing_icon'>")
	check(label.get_parsed_text() == "【术语：unknown_status】，【文本：unknown_text】，【futuretag=value】，【图标：missing_icon】", "Unknown semantic values retain readable fallback labels")
	label.set_source("<sprite name=\"buff_gongjili\"><sprite=4>金币 > 0，1 < 2")
	check(label.text.contains(RichSource.sprite_path("buff_gongjili")) and label.get_parsed_text().contains("【图标：4】金币 > 0，1 < 2"), "Named TMP sprites resolve and numeric sprites retain a bounded fallback")
	check(RichSource.sprite_path("res://project.godot").is_empty(), "Sprite values only resolve through the extracted resource map")
	var terms: Array = JSON.parse_string(FileAccess.get_file_as_string(RichSource.TERMS_PATH))
	check(terms.size() == 132, "The complete APK keyword table is available to every altar family")
	for row in terms:
		label.set_source(str(row.key))
		check(not label.text.contains("<") and not label.get_parsed_text().is_empty(), "Keyword %s renders without raw TMP tags" % row.key)
		check(label.get_parsed_text().replace("【图标：buff_longhunnengliang】", "").replace("【图标：buff_sikadizhinunengliang】", "").strip_edges() == DungeonCatalog.clean(row.key), "Keyword %s preserves the canonical display name" % row.key)
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads for source descriptions")
	for table in ["LootData", "CharTalentData", "CharTalentLevelData", "RogueLevelDifficultyInfluencerData"]:
		for row in catalog.rows(table):
			var raw := DungeonCatalog.description(row)
			if raw.is_empty(): continue
			label.set_source(raw)
			check(not label.text.contains("<#") and not label.text.contains("<color") and not label.text.contains("<sprite"), "%s %d resolves every source token" % [table, DungeonCatalog.row_id(row)])
	for locale in ["zh_TW", "en", "ja", "ko"]:
		DungeonLocale.set_locale(locale, false)
		label.set_source("<#specinfo=gongjili>+10%<br><#specinfo=jinglingjitan>")
		check(not label.text.contains("<#") and label.text.contains("[img="), "%s retains localized source terms and inline artwork" % locale)
	DungeonLocale.set_locale("zh_CN", false)
	label.queue_free()
	print("SOURCE_RICH_TEXT_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
