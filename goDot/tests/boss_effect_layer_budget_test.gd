extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const Effect = preload("res://scripts/presentation/authored_effect.gd")
const EFFECTS := [
	"24120601_fx_enemy_feimolong_bullet_lighting_thunderwarning",
	"24120901_fx_enemy_feimolong_bullet_lighting_darkwarning",
	"26070401_fx_enemy_mojiehua_attack1_spray",
	"26070901_fx_enemy_mojiehua_attack2_slash",
	"26071801_fx_enemy_mojiehua_attack3_duyejidang",
	"26071801_fx_enemy_mojiehua_stage1permanent",
	"26091901_fx_enemy_dilong_roartostone_fall",
]
const PROTECTED_BURSTS := {
	"26071801_fx_enemy_mojiehua_attack3_duyejidang": {"26071801_duyejidang_splashes": 5},
	"26091901_fx_enemy_dilong_roartostone_fall": {"26091901_fall_particle": 4},
	"24120601_fx_enemy_feimolong_bullet_lighting_thunderwarning": {"24120601_thunderwarning_particle": 4, "24120601_thunder_lightning": 2, "24120601_thunder_lightningring": 2},
	"24120901_fx_enemy_feimolong_bullet_lighting_darkwarning": {"24120601_thunderwarning_particle": 4, "24120601_thunder_lightning": 2, "24120601_thunder_lightningring": 2},
}
const RetainedParticle = preload("res://scripts/presentation/retained_particle.gd")
const WARNING := "fx_other_enemyatkrangerectangle_fowardz"
const FILLER := "24042901_fx_enemy_senlinlangwang_roar_fireball"

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _eligible(layer: Dictionary) -> bool:
	if not bool(layer.get("active", true)) or not bool(layer.get("emission", {}).get("enabled", true)): return false
	var renderer: Dictionary = layer.get("renderer", {})
	if not bool(renderer.get("enabled", true)) or layer.get("materials", []).is_empty(): return false
	var mode := int(renderer.get("render_mode", 0))
	return mode != 5 and (mode != 4 or not str(layer.get("mesh", "")).is_empty())

func _run() -> void:
	var presentation := Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	var rows: Array[Dictionary] = []
	for name in EFFECTS:
		var definition: Dictionary = presentation.effect_definition(name)
		presentation._prepare_effect_textures(definition)
		var expected: Dictionary = {}
		for layer in Effect.resolved_layers(definition):
			if _eligible(layer): expected[str(layer.get("source_file_id", layer.name))] = str(layer.name)
		var effect := Effect.new()
		root.add_child(effect)
		effect.configure(definition, false, presentation.texture_cache)
		var actual: Dictionary = {}
		for entry in effect.emitters + effect.retained_particles:
			actual[str(entry.node.get_parent().get_meta("source_layer_id", ""))] = true
		var missing: Array[String] = []
		for layer_id in expected:
			if not actual.has(layer_id): missing.append(str(expected[layer_id]) + ":" + str(layer_id))
		_check(not expected.is_empty(), name + " has source layers")
		_check(missing.is_empty(), name + " drops enabled source layers: " + str(missing))
		_check(effect.emitters.size() <= (28 if PROTECTED_BURSTS.has(name) else 18) and effect.particle_count <= 384, name + " respects full-quality budgets")
		rows.append({"effect": name, "expected_layers": expected.size(), "rendered_layers": actual.size(), "missing_layers": missing, "emitters": effect.emitters.size(), "particles": effect.particle_count})
		if PROTECTED_BURSTS.has(name):
			_check_effect_schedules(effect, definition, name, false)
			_check_clone(effect, name, false)
		effect.free()
		if PROTECTED_BURSTS.has(name):
			var reduced := Effect.new()
			root.add_child(reduced)
			reduced.configure(definition, true, presentation.texture_cache)
			_check(reduced.emitters.size() <= (15 if name == "26071801_fx_enemy_mojiehua_attack3_duyejidang" else 12) and reduced.particle_count <= 144, name + " respects reduced-quality budgets")
			_check_effect_schedules(reduced, definition, name, true)
			_check_clone(reduced, name, true)
			reduced.free()
	var pressure := await _check_global_pressure(presentation)
	_check_flower_lifetime(presentation)
	_check_flower_hit_pressure(presentation)
	_check_boss_density_feedback(presentation)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "effects": rows,
		"pressure": pressure, "scope": "Seven Boss effects: enabled source layers in full quality, APK burst timing and independent clones for four protected prefabs, and concurrent Boss effects with critical warnings under shared budgets. This does not prove Unity shader parity or device frame rate."}
	var file := FileAccess.open("/private/tmp/boss-effect-layer-budget.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("BOSS_EFFECT_LAYER_BUDGET ", JSON.stringify(report))
	presentation.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _source_times(layer: Dictionary) -> Array[float]:
	var result: Array[float] = []
	var speed: float = maxf(0.01, float(layer.get("simulation_speed", 1)))
	var delay: float = maxf(0, Effect.scalar(layer.get("start_delay", {})))
	for burst in layer.get("emission", {}).get("m_Bursts", []):
		if float(burst.get("probability", 1)) <= 0: continue
		for cycle in maxi(1, int(burst.get("cycleCount", 1))):
			result.append((delay + float(burst.get("time", 0)) + cycle * float(burst.get("repeatInterval", 0))) / speed)
	result.sort()
	return result

func _check_effect_schedules(effect: Node3D, definition: Dictionary, name: String, low: bool) -> void:
	var protected: Dictionary = PROTECTED_BURSTS[name]
	var seen: Dictionary = {}
	for layer in Effect.resolved_layers(definition):
		if not _eligible(layer) or RetainedParticle.handles(layer): continue
		var emission: Dictionary = layer.get("emission", {})
		if emission.get("m_Bursts", []).is_empty() or Effect.scalar(emission.get("rateOverTime", {})) > 0: continue
		var layer_name := str(layer.name)
		var expected := _source_times(layer)
		if low:
			if not protected.has(layer_name) or expected.size() <= 1: continue
			var target := int(protected[layer_name])
			var sampled: Array[float] = []
			for index in mini(target, expected.size()):
				var sample_index := roundi(float(index) * float(expected.size() - 1) / float(target - 1)) if target > 1 else 0
				sampled.append(expected[sample_index])
			expected = sampled
			seen[layer_name] = true
		var id := str(layer.get("source_file_id", layer_name))
		var entries: Array = effect.emitters.filter(func(entry: Dictionary) -> bool: return str(entry.node.get_parent().get_meta("source_layer_id", "")) == id)
		var actual: Array[float] = []
		var nodes := {}
		for entry in entries:
			actual.append(float(entry.delay))
			nodes[entry.node.get_instance_id()] = true
			_check(effect.lifetime + 0.00001 >= float(entry.delay) + float(entry.node.lifetime) / float(entry.speed), name + " lifetime covers " + layer_name)
		actual.sort()
		_check(actual.size() == expected.size(), "%s %s burst count low=%s expected=%s actual=%s" % [name, layer_name, low, expected, actual])
		_check(nodes.size() == entries.size(), "%s %s overlapping bursts have independent nodes low=%s" % [name, layer_name, low])
		for index in mini(actual.size(), expected.size()):
			_check(is_equal_approx(actual[index], expected[index]), "%s %s burst timing low=%s expected=%s actual=%s" % [name, layer_name, low, expected, actual])
	if low:
		for layer_name in protected: _check(seen.has(layer_name), name + " reduced-quality protected burst exists: " + str(layer_name))
		if name == "26071801_fx_enemy_mojiehua_attack3_duyejidang":
			var selected := {}
			var expanding_layers := {}
			for entry in effect.emitters + effect.retained_particles:
				var parent: Node = entry.node.get_parent()
				var layer_name := str(parent.get_meta("source_layer", ""))
				selected[layer_name] = true
				if layer_name == "26071801_duyejidang_kuoshan": expanding_layers[str(parent.get_meta("source_layer_id", ""))] = true
			for layer_name in ["26070901_shoubuxuli_mofa", "26070901_shoubuxuli_boom", "26071801_duyejidang_trails", "26071801_duyejidang_ring_big", "26071801_duyejidang_ring_left", "26071801_duyejidang_ring_right", "26071801_duyejidang_smoke"]:
				_check(selected.has(layer_name), name + " reduced-quality attack silhouette retains " + layer_name)
			_check(expanding_layers.size() == 2, name + " reduced-quality attack retains both distinct expanding layers")

func _check_clone(effect: Node3D, name: String, low: bool) -> void:
	var clone: Node3D = effect.instantiate_effect()
	root.add_child(clone)
	_check(clone.emitters.size() == effect.emitters.size(), name + " clone retains emitter schedule low=" + str(low))
	effect.restart()
	clone.restart()
	for index in effect.emitters.size():
		var original: Dictionary = effect.emitters[index]
		var copy: Dictionary = clone.emitters[index]
		_check(original.node != copy.node and original.node.material_override != copy.node.material_override and is_equal_approx(float(original.delay), float(copy.delay)), name + " clone owns its emitter and material low=" + str(low))
	effect.advance(effect.lifetime, false)
	_check(effect.emitters.all(func(entry: Dictionary) -> bool: return entry.started), name + " starts all scheduled bursts low=" + str(low))
	_check(clone.emitters.all(func(entry: Dictionary) -> bool: return not entry.started), name + " clone is unaffected by original advancement low=" + str(low))
	clone.advance(clone.lifetime, false)
	effect.restart()
	_check(clone.emitters.all(func(entry: Dictionary) -> bool: return entry.started), name + " restart does not reset clone low=" + str(low))
	clone.free()

func _check_global_pressure(presentation: Node3D) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var wolf := DungeonActor.new()
	wolf.actor_id = 13001
	wolf.combat = DungeonCombat.new()
	wolf.combat.configure_enemy(13001)
	root.add_child(wolf)
	wolf.set_physics_process(false)
	var action: Dictionary = wolf.combat._action("ActGroup_senlinlangwang", "attack3")
	var hit: Dictionary = action.hits.filter(func(row): return row.get("enabled", false) and WARNING in str(row.get("raw", "")).to_lower())[0]
	for low in [false, true]:
		presentation.low_quality = low
		var limit: int = presentation.FEEL.low_emitter_budget if low else presentation.FEEL.emitter_budget
		var particle_limit: int = presentation.FEEL.low_particle_budget if low else presentation.FEEL.particle_budget
		for name in PROTECTED_BURSTS:
			presentation.clear()
			for index in 3: presentation.emit_effect(wolf, name, Vector3.ZERO, Vector3.ONE, 1.0)
			var baseline: int = presentation.active.filter(func(entry): return entry.key == name).size()
			_check(baseline >= 2, name + " admits multiple concurrent effects low=" + str(low))
			_emit_warnings(presentation, wolf, hit)
			var warnings: Array = presentation.active.filter(func(entry): return entry.key == WARNING and entry.important and entry.source_warning)
			var boss_count: int = presentation.active.filter(func(entry): return entry.key == name).size()
			_check(warnings.size() == 5 and boss_count >= 2, name + " retains concurrent Boss effects and all five warnings low=" + str(low))
			_check(presentation._active_emitters <= limit and presentation._active_particles <= particle_limit, name + " concurrent effects respect shared budgets low=" + str(low))
			var previous_spawned: int = presentation.spawned
			for index in 128: presentation.emit_effect(wolf, name, Vector3.ZERO, Vector3.ONE, 1.0)
			warnings = presentation.active.filter(func(entry): return entry.key == WARNING and entry.important and entry.source_warning)
			_check(warnings.size() == 5, name + " repeated normal effects cannot evict warnings low=" + str(low))
			_check(presentation._active_emitters <= limit and presentation._active_particles <= particle_limit, name + " repeated effects respect shared budgets low=" + str(low))
			_check(presentation.spawned - previous_spawned == 128 and presentation.active.size() < 128, name + " recycles normal effects instead of warnings low=" + str(low))
			var reversed := _check_saturated_warning(presentation, wolf, hit, name, low, limit, particle_limit)
			results.append({"effect": name, "low": low, "concurrent_bosses": boss_count, "warnings": warnings.size(), "active_emitters": reversed.active_emitters, "emitter_budget": limit, "active_particles": reversed.active_particles, "particle_budget": particle_limit, "bosses_before_warning": reversed.bosses_before, "bosses_after_warning": reversed.bosses_after})
	presentation.clear()
	wolf.queue_free()
	await process_frame
	return results

func _emit_warnings(presentation: Node3D, wolf: DungeonActor, hit: Dictionary) -> void:
	for index in 5:
		var event := {"definition": hit, "emit_index": index, "sequence": wolf.combat._cast_sequence}
		var transform_data := DungeonProjectile.multipoint_transform(event, Vector3.ZERO, wolf.facing)
		presentation.attack_emitted(wolf, event, transform_data.position, transform_data.facing)

func _check_saturated_warning(presentation: Node3D, wolf: DungeonActor, hit: Dictionary, name: String, low: bool, limit: int, particle_limit: int) -> Dictionary:
	presentation.clear()
	for index in 128: presentation.emit_effect(wolf, name, Vector3.ZERO, Vector3.ONE, 1.0)
	var template: Node3D = presentation._authored_template(FILLER, presentation._authored_cache_key(FILLER, true), low, true)
	var filler_emitters: int = template.emitters.size()
	var filler_particles: int = template.particle_count
	while filler_emitters > 0 and presentation._active_emitters + filler_emitters <= limit and presentation._active_particles + filler_particles <= particle_limit and not presentation.pool.is_empty():
		presentation.emit_effect(wolf, FILLER, Vector3.ZERO, Vector3.ONE, 1.0)
	var before: int = presentation.active.filter(func(entry): return entry.key == name).size()
	var saturated_emitters: int = presentation._active_emitters
	_emit_warnings(presentation, wolf, hit)
	var after: int = presentation.active.filter(func(entry): return entry.key == name).size()
	var warnings: Array = presentation.active.filter(func(entry): return entry.key == WARNING and entry.important and entry.source_warning)
	_check(before >= 2 and after >= 1 and after < before, name + " critical warnings evict only some ordinary Boss effects low=" + str(low))
	_check(warnings.size() == 5 and presentation._active_emitters <= limit and presentation._active_particles <= particle_limit, name + " admits every warning under saturation low=" + str(low))
	return {"active_emitters": presentation._active_emitters, "active_particles": presentation._active_particles, "saturated_emitters": saturated_emitters, "bosses_before": before, "bosses_after": after}

func _check_flower_lifetime(presentation: Node3D) -> void:
	var flower := DungeonActor.new()
	flower.actor_id = 13002
	flower.combat = DungeonCombat.new()
	flower.combat.configure_enemy(13002)
	root.add_child(flower)
	flower.set_physics_process(false)
	var name := "26071801_fx_enemy_mojiehua_attack3_duyejidang"
	var action: Dictionary = flower.combat._action("ActGroup_mojiehua", "attack3")
	var events: Array = action.events.filter(func(event): return event.get("enabled", false) and name in str(event.get("raw", "")).to_lower())
	_check(events.size() == 1, "Flower attack3 contains its authored poison effect")
	if events.is_empty():
		flower.free()
		return
	var trigger: Dictionary = DungeonWorld._raw_definition(events[0]).get("EffectTriggerDef", {})
	_check(trigger.get("DummyType", "") == "EEDT_DummyChild" and trigger.get("DestoryWhenActionSwitch", false), "Poison source effect follows the boss and ends with its action")
	for low in [false, true]:
		presentation.clear()
		presentation.low_quality = low
		flower.combat._cast_sequence = 11
		presentation.trigger(flower, trigger, 11)
		_check(presentation.active.size() == 1, "Poison trigger creates one effect low=" + str(low))
		if presentation.active.is_empty(): continue
		var entry: Dictionary = presentation.active.back()
		_check(float(entry.duration) >= float(entry.authored.lifetime) - 0.00001, "Poison trigger retains authored lifetime low=" + str(low))
		presentation._process(4.1)
		_check(presentation.active.size() == 1, "Poison trigger remains visible beyond four seconds low=" + str(low))
		flower.combat._cast_sequence = 12
		presentation._process(0.01)
		_check(presentation.active.is_empty(), "Poison trigger is removed when its source action changes low=" + str(low))
		presentation.emit_effect(flower, name, Vector3.ZERO, Vector3.ONE, 1.0)
		_check(presentation.active.size() == 1, "Direct poison effect is created low=" + str(low))
		if presentation.active.is_empty(): continue
		entry = presentation.active.back()
		_check(float(entry.duration) >= float(entry.authored.lifetime) - 0.00001, "Direct poison effect retains authored lifetime low=" + str(low))
		presentation._process(4.1)
		_check(presentation.active.size() == 1, "Direct poison effect remains visible beyond four seconds low=" + str(low))
	presentation.clear()
	flower.free()

func _check_boss_density_feedback(presentation: Node3D) -> void:
	var flower := DungeonActor.new()
	flower.actor_id = 13002
	flower.combat = DungeonCombat.new()
	flower.combat.configure_enemy(13002)
	root.add_child(flower)
	flower.set_physics_process(false)
	var poison_name := "26071801_fx_enemy_mojiehua_attack3_duyejidang"
	var hit_name := "26072201_fx_enemy_mojiehua_attack_hit"
	var filler_name := "26072001_fx_enemy_mojiehua_baozidanmu"
	var action: Dictionary = flower.combat._action("ActGroup_mojiehua", "attack3")
	var events: Array = action.events.filter(func(event): return event.get("enabled", false) and poison_name in str(event.get("raw", "")).to_lower())
	if events.is_empty():
		_check(false, "Flower poison event exists for low-density feedback test")
		flower.free()
		return
	var trigger: Dictionary = DungeonWorld._raw_definition(events[0]).get("EffectTriggerDef", {})
	for low in [false, true]:
		for density in [0, 1]:
			presentation.clear()
			presentation.low_quality = low
			presentation.effects_density = density
			flower.combat._cast_sequence = 11
			presentation.trigger(flower, trigger, 11)
			var poison: Array = presentation.active.filter(func(entry): return entry.key == poison_name)
			_check(poison.size() == 1 and poison[0].priority and not poison[0].detached, "Boss poison retains action ownership at density=%s low=%s" % [density, low])
			for index in 5: presentation.emit_effect(flower, hit_name, Vector3.ZERO, Vector3.ONE, 1.0, null, false, -1, false, true)
			var hits: Array = presentation.active.filter(func(entry): return entry.key == hit_name)
			_check(hits.size() >= 2, "Boss hits remain visible alongside poison at density=%s low=%s" % [density, low])
			var limit: int = presentation.FEEL.low_emitter_budget if low else presentation.FEEL.emitter_budget
			var particle_limit: int = presentation.FEEL.low_particle_budget if low else presentation.FEEL.particle_budget
			_check(presentation._active_emitters <= limit and presentation._active_particles <= particle_limit, "Boss feedback respects the quality cap at density=%s low=%s" % [density, low])
			if low and density == 0:
				_check(presentation._active_emitters > int(limit * 0.35), "Boss feedback can use reserved headroom above the reduced density cap")
			flower.combat._cast_sequence = 12
			presentation._process(0.01)
			_check(presentation.active.filter(func(entry): return entry.key == poison_name).is_empty(), "Boss poison still ends on action switch at density=%s low=%s" % [density, low])
	presentation.clear()
	presentation.low_quality = true
	presentation.effects_density = 0
	for index in 20: presentation.emit_effect(flower, filler_name, Vector3.ZERO, Vector3.ONE, 1.0)
	_check(presentation._active_emitters <= int(presentation.FEEL.low_emitter_budget * 0.35), "Ordinary boss effects still follow the reduced density cap")
	var normal := DungeonActor.new()
	normal.actor_id = 13002
	normal.combat = DungeonCombat.new()
	normal.combat.configure_enemy(13002)
	normal.combat.enemy = normal.combat.enemy.duplicate()
	normal.combat.enemy["rank"] = "Normal"
	root.add_child(normal)
	presentation.clear()
	for index in 20: presentation.emit_effect(normal, hit_name, Vector3.ZERO, Vector3.ONE, 1.0, null, false, -1, false, true)
	_check(presentation._active_emitters <= int(presentation.FEEL.low_emitter_budget * 0.35), "Non-boss priority effects still follow the reduced density cap")
	presentation.clear()
	presentation.effects_density = 2
	flower.free()
	normal.free()

func _check_flower_hit_pressure(presentation: Node3D) -> void:
	var flower := DungeonActor.new()
	flower.actor_id = 13002
	flower.combat = DungeonCombat.new()
	flower.combat.configure_enemy(13002)
	root.add_child(flower)
	flower.set_physics_process(false)
	presentation.clear()
	presentation.low_quality = true
	presentation.effects_density = 2
	flower.combat._cast_sequence = 11
	var poison_name := "26071801_fx_enemy_mojiehua_attack3_duyejidang"
	var filler_name := "26072001_fx_enemy_mojiehua_baozidanmu"
	var hit_name := "26072201_fx_enemy_mojiehua_attack_hit"
	var action: Dictionary = flower.combat._action("ActGroup_mojiehua", "attack3")
	var events: Array = action.events.filter(func(event): return event.get("enabled", false) and poison_name in str(event.get("raw", "")).to_lower())
	if events.is_empty():
		_check(false, "Flower attack3 poison event exists for budget-pressure test")
		flower.free()
		return
	presentation.trigger(flower, DungeonWorld._raw_definition(events[0]).get("EffectTriggerDef", {}), 11)
	if presentation.active.is_empty():
		_check(false, "Flower attack3 poison starts before budget pressure")
		flower.free()
		return
	var poison: Dictionary = presentation.active.back()
	_check(poison.priority and not poison.detached and poison.sequence == 11, "Poison tail is protected without detaching it from its action")
	presentation.emit_effect(flower, "26071801_fx_enemy_mojiehua_attack3_xuanwo", Vector3.ZERO, Vector3.ONE, 5.0, null, false, -1, false, true)
	for index in 2: presentation.emit_effect(flower, filler_name, Vector3.ZERO, Vector3.ONE, 5.0)
	for index in 5: presentation.emit_effect(flower, hit_name, Vector3.ZERO, Vector3.ONE, 5.0, null, false, -1, false, true)
	var fillers_before: int = presentation.active.filter(func(entry): return entry.key == filler_name).size()
	var hits_before: int = presentation.active.filter(func(entry): return entry.key == hit_name).size()
	var hit_template: Node3D = presentation._authored_template(hit_name, presentation._authored_cache_key(hit_name, false), true, false)
	_check(fillers_before == 2 and hits_before == 5 and presentation._active_emitters + hit_template.emitters.size() > presentation.FEEL.low_emitter_budget, "Fixture reaches the flower attack's low-quality emitter pressure")
	presentation.emit_effect(flower, hit_name, Vector3.ZERO, Vector3.ONE, 5.0, null, false, -1, false, true)
	_check(presentation.active.has(poison), "Poison remains during hit-effect pressure")
	_check(presentation.active.filter(func(entry): return entry.key == hit_name).size() == hits_before + 1, "The new hit feedback is admitted")
	_check(presentation.active.filter(func(entry): return entry.key == filler_name).size() < fillers_before, "A lower-priority burst yields budget first")
	_check(presentation._active_emitters <= presentation.FEEL.low_emitter_budget and presentation._active_particles <= presentation.FEEL.low_particle_budget, "Protected poison and hits respect reduced-quality budgets")
	flower.combat._cast_sequence = 12
	presentation._process(0.01)
	_check(not presentation.active.has(poison), "Protected poison still ends on action switch")
	presentation.clear()
	flower.free()
