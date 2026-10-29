extends SceneTree

const Tally = preload("res://scripts/domain/battle_tally.gd")
const Readout = preload("res://scripts/presentation/battle_readout.gd")
const HIT := {"source_key": "player", "receiver_key": "enemy:11001:1", "resolved_accepted": true, "resolved_damage": 25.0}

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var tally = Tally.new()
	var readout = Readout.new()
	root.add_child(readout)
	readout.update_values(tally, null, "")
	check(not readout.stats.visible, "Idle entry never shows zero hits or empty damage statistics")
	for invalid in [HIT.merged({"resolved_damage": 0}, true), HIT.merged({"resolved_accepted": false}, true), HIT.merged({"source_key": "enemy:1"}, true), HIT.merged({"receiver_key": "player"}, true)]:
		tally.record(invalid, "player")
	readout.update_values(tally, null, "")
	check(not readout.stats.visible and tally.combo_hits == 0, "Misses and incoming damage cannot reveal the statistics")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	var zero_definition: Dictionary = {}
	for summon in catalog.summons:
		if str(summon.id) == "16311003": zero_definition = summon.hit
	check(not zero_definition.is_empty(), "APK zero-combo summon is present in the catalog")
	var zero_hit: Dictionary = HIT.merged({"definition": zero_definition}, true)
	tally.record(zero_hit, "player")
	check(tally.combo_hits == 0 and tally.damage == 25, "APK zero-combo attack deals damage without starting a combo")
	tally.record(HIT, "player")
	tally.advance(1.5, true)
	tally.record(zero_hit, "player")
	tally.record(HIT.merged({"attack_collision": false}, true), "player")
	tally.record(HIT.merged({"continuous": true}, true), "player")
	readout.update_values(tally, null, "")
	check(tally.combo_hits == 1 and is_equal_approx(tally.combo_remaining, 0.5), "Zero-combo attacks and status damage cannot extend a combo")
	check(tally.combo_damage == 100 and readout.total.text == "100", "Damage remains visible while the counter stays unchanged")
	var multi_hit: Dictionary = HIT.merged({"definition": {"raw": "{\"HitComboCaculate\":10}"}}, true)
	tally.record(multi_hit, "player")
	var multi_saved: Dictionary = tally.snapshot()
	var multi_restored = Tally.new()
	multi_restored.restore(multi_saved)
	check(tally.combo_hits == 11 and tally.combo_remaining == 2.0 and multi_restored.snapshot() == multi_saved, "Authored increments and checkpoint restoration preserve hit count")
	tally.reset()
	readout.update_values(tally, null, "")
	tally.record(HIT, "player")
	readout.update_values(tally, null, "")
	check(readout.stats.visible and readout.hits.text == "1" and readout.total.text == "25", "First settled hit reveals the complete combo readout")
	check(readout.combo_bar.value == 1.0 and readout.stage == 0, "First hit starts a full Nice countdown")
	tally.advance(1.5, true)
	readout.update_values(tally, null, "", 1.5)
	check(is_equal_approx(readout.combo_bar.value, 0.25) and readout.rate.text == "17", "Countdown and DPS use the current combo time")
	var saved: Dictionary = tally.snapshot()
	var restored = Tally.new()
	restored.restore(saved)
	check(restored.snapshot() == saved, "Checkpoint restores the live combo with its remaining countdown")
	tally.record(HIT, "player")
	readout.update_values(tally, null, "", 0.1)
	check(tally.combo_hits == 2 and tally.combo_damage == 50 and tally.combo_remaining == 2.0, "Continued hit renews the two-second combo window")
	check(readout.combo_bar.value > 0.25, "Refilled countdown moves toward the new value")
	var paused: Dictionary = tally.snapshot()
	tally.advance(20.0, true, false)
	readout.update_values(tally, null, "", 0.0)
	check(tally.snapshot() == paused, "Paused and background time cannot advance a saved combo")
	tally.advance(1.999, false)
	readout.update_values(tally, null, "", 0.1)
	check(readout.stats.visible and tally.combo_hits == 2, "Combo remains alive immediately before the timeout even after combat ends")
	tally.advance(0.002, false)
	readout.update_values(tally, null, "", 0.1)
	check(tally.combo_hits == 0 and tally.combo_damage == 0 and tally.hits == 2 and tally.damage == 50, "Timeout clears the combo while preserving cumulative settlement counters")
	check(readout.stats.visible and readout.stats.modulate.a > 0 and readout.stats.modulate.a < 1 and readout.hits.text == "2", "Timeout fades the final figures without flashing zero")
	tally.record(HIT, "player")
	readout.update_values(tally, null, "")
	check(readout.stats.visible and readout.stats.modulate.a == 1 and readout.hits.text == "1" and readout.total.text == "25", "A new hit interrupts fading and starts a fresh combo")
	check(readout.rate.text == "25", "A new combo resets DPS even when it deals the same damage as the last combo")
	tally.advance(2.0, false)
	readout.update_values(tally, null, "", 0.15)
	var fade_alpha: float = readout.stats.modulate.a
	readout.update_values(tally, null, "", 0.0)
	check(readout.stats.modulate.a == fade_alpha, "Paused presentation does not finish a pending fade")
	readout.update_values(tally, null, "", 0.15)
	check(not readout.stats.visible, "All combo statistics disappear after the 0.3-second fade")
	tally.restore({"hits": 10, "damage": 250, "elapsed": 12})
	readout.update_values(tally, null, "")
	check(not readout.stats.visible and tally.hits == 10, "Legacy cumulative saves never invent a live combo")
	tally.reset()
	for count in 40:
		tally.record(HIT, "player")
		readout.update_values(tally, null, "", 0.1)
		check(readout.stage == mini(3, int((count + 1) / 10)), "Stage boundaries follow 10/20/30 hits: %d" % (count + 1))
		check(readout.hit_tail.texture != null and readout.description.texture != null and readout.combo_bar.texture_progress != null, "Each stage uses recovered APK sprites: %d" % (count + 1))
	tally.record(HIT.merged({"resolved_damage": 999999999999.0}, true), "player")
	readout.update_values(tally, null, "", 0.1)
	for value in [readout.total, readout.rate]:
		check(value.get_theme_font("font").get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, value.get_theme_font_size("font_size")).x <= value.size.x, "Large damage values fit the fixed readout width")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		readout._layout()
		check(Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size)).encloses(readout.stats.get_global_rect()), "Stats remain within viewport %s" % dimensions)
		check(Rect2(Vector2.ZERO, readout.stats.size).encloses(readout.combo_bar.get_rect()), "Recovered progress texture cannot enlarge the fixed readout at %s" % dimensions)
	readout.hide()
	check(not readout.stats.is_visible_in_tree(), "Modal parent suppression hides the stats without clearing domain state")
	readout.show()
	check(readout.stats.is_visible_in_tree() and tally.combo_hits == 41, "Closing a modal restores the same frozen combo")
	tally.reset()
	readout.update_values(tally, null, "")
	check(not readout.stats.visible, "New room removes previous-room figures immediately")
	var boss := DungeonActor.new()
	boss.combat = DungeonCombat.new()
	boss.combat.configure_enemy(13001)
	root.add_child(boss)
	readout.update_values(tally, boss, "Boss")
	check(readout.boss.visible and not readout.stats.visible, "Boss HP remains visible independently of hidden combo statistics")
	boss.dead = true
	readout.update_values(tally, boss, "Boss")
	check(not readout.boss.visible, "Boss death continues to hide its independent HP bar")
	boss.queue_free()
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures}
	FileAccess.open("res://reports/battle-readout-visibility.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BATTLE_READOUT_VISIBILITY ", JSON.stringify(report))
	readout.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
