extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const Telegraph = preload("res://scripts/presentation/attack_telegraph.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _arg(name: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--%s=" % name): return value.get_slice("=", 1)
	return fallback

func _effects(value: Variant, media: Dictionary, found: Dictionary) -> void:
	if value is Dictionary:
		for child in value.values(): _effects(child, media, found)
	elif value is Array:
		for child in value: _effects(child, media, found)
	elif value is String:
		var key = value.get_file().trim_suffix(".prefab").to_lower()
		if media.effects.has(key) and not media.effects[key].get("layers", []).is_empty() and "enemyatkrange" not in key: found[key] = true

func _counts(presentation: Node) -> Vector2i:
	var result := Vector2i.ZERO
	for entry in presentation.active:
		if entry.authored:
			result.x += entry.authored.particle_count
			result.y += entry.authored.emitters.size()
	return result

func _run() -> void:
	var baseline = "--baseline" in OS.get_cmdline_user_args()
	root.size = Vector2i(960, 540)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 8, -10)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var presentation = Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	presentation.audio_enabled = false
	var actor := DungeonActor.new()
	actor.combat = DungeonCombat.new()
	actor.combat.configure_enemy(13001)
	root.add_child(actor)
	var rows: Array[Dictionary] = []
	for low in [false, true]:
		presentation.low_quality = low
		for boss in actor.combat.catalog.enemies:
			if boss.get("rank", "") != "Boss": continue
			actor.combat.configure_enemy(int(boss.id))
			var names: Dictionary = {}
			for action in actor.combat.catalog.actions:
				if not str(action.key).begins_with(str(boss.group) + "/"): continue
				for command in action.get("events", []) + action.get("hits", []):
					if command.get("enabled", false): _effects(DungeonWorld._raw_definition(command), presentation.media, names)
			var before_warm = Time.get_ticks_usec()
			if presentation.has_method("prepare_combat"):
				presentation.prepare_combat([actor.combat])
				while presentation.has_pending_preparation():
					presentation.prepare_step()
					await process_frame
			var warm_ms = (Time.get_ticks_usec() - before_warm) / 1000.0
			var prepared_builds: int = presentation.get("authored_builds") if not baseline else 0
			var timings: Array[float] = []
			var peak := Vector2i.ZERO
			for key in names:
				for index in 12:
					var before = Time.get_ticks_usec()
					presentation.emit_effect(actor, key, Vector3.ZERO, Vector3.ONE, 0.6)
					timings.append((Time.get_ticks_usec() - before) / 1000.0)
					peak = peak.max(_counts(presentation))
				presentation._process(0.016)
				await process_frame
			presentation.clear()
			timings.sort()
			rows.append({"boss": int(boss.id), "low_quality": low, "effects": names.size(), "prepare_ms": warm_ms, "spawn_p95_ms": timings[int(timings.size() * 0.95)] if not timings.is_empty() else 0, "spawn_max_ms": timings.back() if not timings.is_empty() else 0, "peak_particles": peak.x, "peak_emitters": peak.y})
			if not baseline:
				check(names.is_empty() or peak.x > 0 and peak.y > 0, "Boss %s actually emits particles (%s)" % [boss.id, low])
				check(presentation.authored_builds == prepared_builds, "Boss %s prepares every action effect before casting (%s)" % [boss.id, low])
				check(peak.x <= (presentation.FEEL.low_particle_budget if low else presentation.FEEL.particle_budget), "Boss %s respects global particle budget (%s)" % [boss.id, low])
				check(peak.y <= (presentation.FEEL.low_emitter_budget if low else presentation.FEEL.emitter_budget), "Boss %s respects global emitter budget (%s)" % [boss.id, low])
				check(presentation.active.is_empty() and presentation.pool.size() == presentation.FEEL.effect_budget, "Clear returns every active effect")
	if not baseline:
		var key = "24080201_fx_sword_satk_dimensionalslash"
		presentation.low_quality = false
		presentation.emit_effect(actor, key, Vector3.ZERO)
		var original: Node3D = presentation.active.back().authored
		presentation.emit_effect(actor, key, Vector3.ZERO)
		var other: Node3D = presentation.active.back().authored
		check(original.emitters.size() > 0 and original.emitters.size() == other.emitters.size(), "Clones retain their emitter definitions")
		check(original.emitters[0].node.mesh == other.emitters[0].node.mesh, "Clones share loaded geometry")
		check(original.emitters[0].node.material_override != other.emitters[0].node.material_override, "Clones retain independent animated uniforms")
		presentation.clear()
		check(presentation._active_particles == 0 and presentation._active_emitters == 0, "Clear releases particle and emitter accounting")
		var before_reuse: int = presentation.authored_reuses
		presentation.emit_effect(actor, key, Vector3.ZERO)
		check(presentation.authored_reuses == before_reuse + 1, "Scene changes retain reusable effects")
		presentation.clear()
		check(presentation._authored_pool_size <= presentation.FEEL.effect_budget and presentation._authored_templates.size() <= presentation.FEEL.effect_template_budget, "Persistent caches remain bounded")
	var first := Telegraph.new()
	var second := Telegraph.new()
	first.configure(Vector2(2, 3))
	second.configure(Vector2(4, 5), 1)
	if not baseline:
		check(first.material.shader == second.material.shader, "Warnings share their compiled shader")
		check(first.material != second.material, "Warnings retain independent progress and dimensions")
	first.free()
	second.free()
	var report = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "rows": rows, "scope": "Seven bosses' authored action effects, twelve overlapping instances per effect, full and reduced quality. CPU spawn cost and active particle/emitter totals; headless runs do not measure GPU or device frame rate."}
	FileAccess.open(_arg("output", "res://reports/combat-performance.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("COMBAT_PERFORMANCE ", JSON.stringify(report))
	presentation.queue_free()
	actor.queue_free()
	camera.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
