extends "res://tests/spirit_world_abilities_test.gd"

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Choices = preload("res://scripts/domain/room_choices.gd")
const Partners = preload("res://scripts/domain/partner_skills.gd")
var data_catalog
var data_profile
var data_systems
var observed: SupportWorld

class SupportWorld extends ObservedWorld:
	var support_events: Array = []
	func _consume(actor: DungeonActor, event: Dictionary) -> void:
		if actor.is_player and event.type in ["summon", "hit"]:
			support_events.append(event.duplicate(true))
		super._consume(actor, event)

func _run() -> void:
	observed = SupportWorld.new()
	world = observed
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.low_effects = true
	data_catalog = Catalog.new()
	_check(data_catalog.load_all(), "Source catalog loads")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Partners.DATA))
	for skill in source.skills:
		for level in range(1, 4):
			_fixture(int(skill.id), level)
			var controller = world._partner_controller()
			controller.tick(world.player.combat, 150, true)
			_check(controller.request(world.player.combat, 0).success, "Partner source action starts: %s level %d" % [skill.id, level])
			for frame in 400: _step()
			var created: Array = world.summons.map(func(unit): return str(unit.id))
			var diagnostics: Array = world.diagnostics.duplicate()
			for actor in world.actors:
				diagnostics.append_array(actor.combat.diagnostics)
			diagnostics = diagnostics.filter(func(message):
				if not str(message).begins_with("Summon behavior requires world adapter: "): return true
				return not created.has(str(message).trim_prefix("Summon behavior requires world adapter: ").get_slice(" ", 0)))
			_check(diagnostics.is_empty(), "Real partner world dispatch resolves dependencies: %s level %d %s" % [skill.id, level, diagnostics])
			_check(not created.is_empty() or world.player.combat.shield > 0, "Partner creates world carriers or its source shield: %s level %d" % [skill.id, level])
			if int(skill.id) == 22002: _check(created.has("6231011"), "Sand domain delayed carrier creates real field at level %d" % level)
			if int(skill.id) == 53001 and level == 2: _check(is_equal_approx(float(controller.state().sp), 25.0), "Dragon level two refund travels through real world adapter")
			rows.append({"id": int(skill.id), "level": level, "summons": created, "contacts": world.impacts.size(), "shield": world.player.combat.shield, "sp": controller.state().sp, "diagnostics": diagnostics})
			await process_frame
	_delayed_damage_source()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "skills": rows, "scope": "All twelve APK partner actions at levels one through three run for eight seconds in real Godot domain/world adapters with controlled nearby targets. Checks carrier dispatch, delayed sand field, source shield and dragon support energy refund. It does not establish original APK runtime, exact rendered asset parity or every conditional hit effect."}
	FileAccess.open("res://reports/partner-skill-world-20261027.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PARTNER_SKILL_WORLD ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "skills": rows.size(), "failures": failures}))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _fixture(id: int, level: int) -> void:
	_reset()
	observed.support_events.clear()
	data_profile = Profile.new()
	data_systems = Systems.new(data_catalog, data_profile)
	data_systems.begin_run(73281, 1, 500)
	data_profile.data.run.counters[Choices.SLOTS] = [{"id": id, "level": level}]
	world.systems = data_systems
	world._partner_skill_rules = null
	world.player.combat.configure(null, data_systems, 1, 0, 193)
	world.player.combat.custom_properties["EnemyDistances"] = [2.0, 3.0, 4.0]
	var bindings: Dictionary = data_systems.progression_buff_bindings()
	world.player.combat.set_progression_buffs(bindings.roots, bindings.externally_counted_numeric_ids)
	world.player.combat.actor_key = "player"
	world.player.combat.drain_events()
	world.player.face_direction(Vector3.BACK)
	for index in 5:
		var enemy := _actor("partner-target:%d" % index, false, Vector3((index - 2) * 1.5, 0, 3))
		enemy.combat.max_health = 1000000000
		enemy.combat.health = enemy.combat.max_health
		enemy.combat.custom_properties["EnemyDistances"] = [enemy.position.length()]

func _delayed_damage_source() -> void:
	_fixture(13001, 1)
	world.player.combat.set_external_attributes({"MonsterPartnerDamageRate": 1000, "NormalAtkDamageRate": 9000})
	var controller = world._partner_controller()
	controller.tick(world.player.combat, 150, true)
	_check(controller.request(world.player.combat, 0).success, "Support provenance fixture casts original wolf action")
	for frame in 100:
		_step()
		if not world.summons.is_empty(): break
	_check(not world.summons.is_empty(), "Support parent exists before later player action")
	world.player.combat._current_slot = 0
	world.player.combat.current_action = "sys_idle"
	world.player.combat._cast_sequence += 100
	_step(400)
	var child_summons: Array = observed.support_events.filter(func(event): return event.type == "summon" and str(event.id) != "6130011")
	var child_hits: Array = observed.support_events.filter(func(event): return event.type == "hit" and not str(event.get("summon_id", "")).is_empty())
	_check(not child_summons.is_empty() and child_summons.all(func(event): return int(event.get("slot", -1)) == 5), "Delayed support child carriers preserve partner slot after player changes actions")
	_check(not child_hits.is_empty() and child_hits.all(func(event): return int(event.get("slot", -1)) == 5), "Delayed support hits preserve partner slot after player changes actions")
	var wrong_damage: Array = child_hits.filter(func(event):
		var damage := float(event.get("uncritical_damage", 0))
		var expected: float = world.player.combat.effective_attack_power() * float(event.definition.get("multiplier", 0)) * 2.0
		return not is_equal_approx(damage, expected))
	_check(wrong_damage.is_empty(), "Delayed support damage uses partner bonus rather than following normal attack bonus")
	rows.append({"case": "delayed_support_damage_source", "children": child_summons.size(), "hits": child_hits.size(), "wrong_damage": wrong_damage.size()})

func _step(count: int = 1) -> void:
	for frame in count:
		for actor in world.actors:
			var distances: Array = []
			for other in world.actors:
				if other.is_player != actor.is_player and not other.dead: distances.append(actor.position.distance_to(other.position))
			actor.combat.custom_properties["EnemyDistances"] = distances
		super._step()
