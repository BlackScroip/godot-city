extends SceneTree

const Effect = preload("res://scripts/presentation/authored_effect.gd")
const FEEL = preload("res://assets/feel_settings.tres")
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat_presentation/catalog.json"))
	var textures: Dictionary = {}
	for path in catalog.get("texture_sources", {}):
		var full_path = "res://assets/combat_presentation/" + str(path)
		if ResourceLoader.exists(full_path): textures[full_path] = load(full_path)
	var retained = {
		"24080201_fx_sword_satk_drawknife": ["24080201_drawknife_star", "24080201_drawknife_particle"],
		"24080201_fx_sword_satk_drawknifestrengthen": ["24080201_drawknifestrengthen_fire"],
		"23102601_fx_wand_atk_move": ["23102601_move_bubble", "23102601_move_spray"],
		"23082101_fx_skill_firesword_cuilianzhijian_slash1": ["23082101_slash1_slash1", "23082101_slash1_slash2", "23082101_slash1_slash3", "23082101_slash1_particle"],
		"23082101_fx_skill_firesword_cuilianzhijian_slash2": ["23082101_slash2_slash1", "23082101_slash2_slash2", "23082101_slash2_slash3", "23082101_slash2_particle"],
		"23081901_fx_skill_firesword_niyanzhiren_accumulation": ["23081901_accumulation_flash", "23081901_accumulation_ring", "23081901_accumulation_line", "23081901_accumulation_fire"],
		"23081901_fx_skill_firesword_niyanzhiren_fireslash": ["23081901_fireslash_slash1_1", "23081901_fireslash_slash2_1", "23081901_fireslash_slash3_1", "23081901_fireslash_slash1_2", "23081901_fireslash_slash2_2", "23081901_fireslash_slash3_2", "23081901_fireslash_fire1", "23081901_fireslash_fire2"],
		"23102601_fx_wand_atk_launch": ["23102601_launch_flash", "23102601_launch_spray", "23102601_launch_ring"],
		"23102601_fx_wand_atk_waterbomb": ["23102601_waterbomb_bomb", "23102601_waterbomb_bomblight"],
		"23102601_fx_wand_atk_explode": ["23102601_explode_prick", "23102601_explode_stretchedspray"],
		"23082501_fx_skill_firesword_niyanzhiren_explosion": ["23082501_explosion_firedark", "23082501_explosion_airwave"]
	}
	for key in retained:
		var definition: Dictionary = catalog.effects[key]
		var source_copy = definition.duplicate(true)
		var suppressed: Array = FEEL.effect_emitter_suppressions.get(key, [])
		for name in suppressed:
			check(definition.layers.any(func(layer): return layer.name == name), "%s suppression names an existing source layer" % name)
		for low in [false, true]:
			var effect = Effect.new()
			root.add_child(effect)
			effect.configure(definition, low, textures, suppressed)
			var names: Array = []
			for node in effect.get_children(): names.append(str(node.get_meta("source_layer", "")))
			for name in suppressed: check(name not in names, "%s is absent in %s quality" % [name, "low" if low else "full"])
			# Reduced mode has a fixed emitter cap, so retain source priority ordering.
			if not low:
				for name in retained[key]: check(name in names, "%s remains rendered" % name)
			check(effect.emitters.size() > 0, "%s keeps its authored effect" % key)
			check(effect.emitters.size() <= (8 if low else 18), "%s respects emitter budget" % key)
			effect.free()
		check(definition == source_copy, "%s leaves imported source unchanged" % key)
	check(not FEEL.effect_emitter_suppressions.has("enemyatkrange"), "Danger telegraphs have no generic ring suppression")
	var report = {"checks": checks, "failures": failures, "effects": retained.size(), "quality_levels": 2}
	FileAccess.open("res://reports/effect-layer-filter-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("EFFECT_LAYER_FILTER ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
