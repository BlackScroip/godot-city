extends SceneTree

const Descriptions = preload("res://scripts/domain/ability_descriptions.gd")
const ENGLISH_STATUS_STARTS := {
	20119: " (current).", 20120: " (Current)", 20133: " (Current)",
	20138: " (When Move Forward degrees:", 20151: " (Current ",
	20162: " (When Move Forward degrees:", 20166: " (Current)",
	20193: " (Current)", 20400: " (Current)", 20401: " (Current)",
	20405: " (Current)", 20406: " (Current progress:", 20407: " (Current)",
	20409: " (Current)", 20410: " (Current)", 20415: " (Current progress:",
	20417: " (When Move Forward:", 20420: " (Current.)", 20422: " (Current progress:",
	20423: " (Current)", 20425: " (Current)", 20426: " (Current stacks:",
	20432: " (Current)", 20562: " (Currently)", 20574: " (Current)",
	20582: " (Current ", 20583: " (Current stacks:", 20584: "<#backpack_record_trigger>",
	21171: " (Current)", 22011: " (When Move Forward:", 22012: " (current).",
	22021: " (Current progress:", 22031: " (Current progress:", 22041: " (When Move Forward:",
	22051: " (When Move Forward:", 22061: " (When Move Forward:", 22071: " (When Move Forward:",
	22072: " (current).", 22081: " (When Move Forward:", 22091: " (When Move Forward degrees:",
	22101: " (When Move Forward:", 22111: " (Current progress:", 22121: " (When Move Forward:",
	22131: " (Current progress:", 22141: " (When Move Forward:", 22151: " (Current progress:",
	22161: " (when Move Forward:", 22171: " (When Move Forward:", 22181: " (When Move Forward:",
	22191: "<#backpack_progress>", 22201: " (When Move Forward:", 23024: " ( Triggered.)",
	23050: " (Current)", 23051: " (Current stacks:"
}

var checks := 0
var failures: Array[String] = []
var catalog := DungeonCatalog.new()
var profile := DungeonProfile.new()
var systems: DungeonSystems
var descriptions: RefCounted

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	check(catalog.load_all(), "Actual catalog loads")
	systems = DungeonSystems.new(catalog, profile)
	descriptions = Descriptions.new(systems)
	for language in ["zh_CN", "en"]:
		DungeonLocale.set_locale(language, false)
		var rows := 0
		for row in catalog.rows("AbilityItems"):
			if not str(row.get("Description", "")).contains("<#backpack_"): continue
			rows += 1
			var id := DungeonCatalog.row_id(row)
			var localized := DungeonLocale.text(str(row.Description))
			var marker: String = ENGLISH_STATUS_STARTS[id] if language == "en" else "<color=#fdd033>（"
			var boundary := localized.find(marker)
			check(boundary >= 0, "%s %d actual status boundary is present" % [language, id])
			if boundary < 0: continue
			var expected := localized.left(boundary)
			profile.data.run.active = true
			profile.data.run.inventory.clear()
			var preview: String = descriptions.source(id, id)
			check(preview == expected, "%s %d unowned preview preserves the complete body and removes the complete status" % [language, id])
			profile.data.run.inventory[str(id)] = 1
			var owned: String = descriptions.source(id, id)
			check(owned.begins_with(expected) and owned != preview and not owned.contains("<#backpack_"), "%s %d owned status still resolves its value" % [language, id])
			profile.data.run.active = false
			check(descriptions.source(id, id) == expected, "%s %d camp preview removes stale owned status" % [language, id])
		check(rows == 54, "%s covers all 54 authored dynamic descriptions" % language)
	_body_parentheses()
	systems.decorations = null
	print("ABILITY_DESCRIPTION_PREVIEW_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _body_parentheses() -> void:
	DungeonLocale.set_locale("en", false)
	var cases := [
		["Gain damage (up to 10). (Current)<#backpack_layer> stacks)", "Gain damage (up to 10)."],
		["(cumulative holding period) Gain damage. (Current stacks: <#backpack_layer>)", "(cumulative holding period) Gain damage."],
		["Keep (current strategy) and (triggered damage) text. (Current progress: <#backpack_progress>)", "Keep (current strategy) and (triggered damage) text."],
		["Gain a reward (up to 10).<#backpack_record_trigger>(a) Number of reports", "Gain a reward (up to 10)."],
		["Keep body (up to 10) and <#backpack_record_trigger> applications while held.", "Keep body (up to 10) and  applications while held."],
		["Damage (Current stacks: <#backpack_layer>) has additional body text.", "Damage (Current stacks: ) has additional body text."]
	]
	profile.data.run.active = false
	for index in cases.size():
		catalog._indices.AbilityItems["993031"] = {"ID": "993031", "Description": cases[index][0]}
		check(descriptions.source(993031, 993031) == cases[index][1], "Only the supported final status is removed, preserving body parentheses fixture %d" % index)
