extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("LOCALIZATION EDGE FAILURE: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var original := DungeonLocale.current_locale()
	var original_path := DungeonLocale.settings_path
	DungeonLocale.set_locale("en", false)
	var current_effect := DungeonCatalog.clean("<#specinfo=gongjili>+10%，最多持有20件。")
	print("CURRENT_EFFECT=", current_effect)
	check("10" in current_effect and "20" in current_effect and not "Dodge" in current_effect,
		"Current relic attack/stack description must not become an obsolete dodge-speed effect")
	check(DungeonCatalog.clean('<#LocalizationId="keyword_EquipmentList">战斗</LocalizationId>') == DungeonLocale.text("战斗"),
		"Current source translation takes priority over an obsolete semantic-key translation")
	DungeonLocale._add_template("检查字符串：%s。", "String check: %s.")
	check(DungeonLocale.text("检查字符串：。") == "String check: .",
		"Formatted string template accepts an empty string argument")
	DungeonLocale._add_template("检查字符：%c。", "Character check: %c.")
	check(DungeonLocale.text("检查字符：A。") == "Character check: A.",
		"Formatted character template preserves the actual character")
	DungeonLocale._add_template("检查十六进制：%x。", "Hex check: %x.")
	check(DungeonLocale.text("检查十六进制：ff。") == "Hex check: ff.",
		"Formatted hex template accepts hex digits")
	DungeonLocale._add_template("检查字符串：%s；10% drop", "String check: %s; 10% drop")
	check(DungeonLocale.text("检查字符串：A；10% drop") == "String check: A; 10% drop",
		"Percentage followed by a word is not treated as a formatting placeholder")
	DungeonLocale.settings_path = "user://missing-language-directory-%d/language.cfg" % Time.get_ticks_usec()
	check(not DungeonLocale.set_locale("ja", true), "Failed language persistence is reported")
	check(DungeonLocale.current_locale() == "en", "Failed persistence leaves the active language unchanged")
	DungeonLocale.settings_path = original_path
	DungeonLocale.set_locale(original, false)
	print("LOCALIZATION_EDGE_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
