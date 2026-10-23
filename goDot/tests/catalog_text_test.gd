extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var catalog = DungeonCatalog.new()
	catalog.load_all()
	check(DungeonCatalog.clean("命中附加<#specinfo=zhuoshao>。") == "命中附加灼烧。", "Burn term survives cleanup")
	check(DungeonCatalog.clean("<#specinfo=zhuorejianqi>与<#specinfo=anshi>") == "灼热剑气与暗蚀", "APK proper names resolve")
	check(DungeonCatalog.clean("<color=#fff><#specinfo=gongjili></color>+10%<br><#specinfo=putonggongji>") == "攻击力+10%\n普通攻击", "Legacy combat terms and line breaks remain")
	check(DungeonCatalog.clean("<#specinfo=unknown_status>") == "【术语：unknown_status】", "Unknown semantic term remains visible")
	check(DungeonCatalog.clean("<#LocalizationId=\"keyword_Relics\">遗物</LocalizationId>") == "遗物", "Inline localization fallback is not duplicated")
	check(DungeonCatalog.clean("<#LocalizationId=\"keyword_chara\">") == "角色", "Bare localization resolves APK text")
	check(DungeonCatalog.clean("<#LocalizationId=\"unknown_id\">") == "【文本：unknown_id】", "Unknown localization retains identifier")
	check(DungeonCatalog.clean("<#futuretag=target>") == "【futuretag=target】", "Unknown semantic markup is not silently discarded")
	var regex = RegEx.new()
	regex.compile("<#specinfo=([^>]+)>")
	var terms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/DisplayTerms.json"))
	for table in ["CharTalentData", "CharTalentLevelData", "AbilityItems"]:
		for row in catalog.rows(table):
			var raw = DungeonCatalog.description(row)
			var cleaned = DungeonCatalog.clean(raw)
			for matched in regex.search_all(raw):
				var key = matched.get_string(1)
				check(terms.specinfo.has(key) and cleaned.contains(terms.specinfo.get(key, "__missing__")), "%s %d retains %s" % [table, DungeonCatalog.row_id(row), key])
	print("CATALOG_TEXT_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
