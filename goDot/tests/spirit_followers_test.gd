extends SceneTree

var failures: Array[String] = []
var checks := 0

class PresentationRecorder extends Node3D:
	var effects: Array = []
	func summon_trigger(_actor: DungeonActor, raw: Dictionary, point: Vector3, phase: String, source_only: bool) -> void:
		effects.append({"effect": str(raw.get("TriggerEffectName_" + phase, "")), "point": point, "dimensions": Vector3.ONE, "source_only": source_only})

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var profile := DungeonProfile.new()
	var systems := DungeonSystems.new(catalog, profile)
	profile.data.run.active = true
	profile.data.run.inventory = {"20250": 1, "20260": 1, "20103": 1}
	var player := DungeonActor.new()
	player.set_physics_process(false)
	var followers = load("res://scripts/presentation/spirit_followers.gd").new()
	root.add_child(followers)
	followers.sync_from_run(systems, player)
	check(followers.entries.size() == 2, "Only owned spirits become followers")
	check(followers.media.apk_sha256 == "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "Follower media belongs to the supplied APK")
	check(followers.media.followers.size() == 33, "Every source follower prefab is retained")
	check(followers.media.ability_bindings.size() == 33 and followers.media.unmapped_abilities.is_empty(), "Every source spirit ability has an obtainable loot binding")
	check(followers.media.ability_bindings["20340"].summons == ["50205079"] and followers.media.ability_bindings["20350"].summons == ["50205078"], "Combined spirit bindings follow source IDs rather than misleading prefab filenames")
	for entry in followers.entries.values():
		check(not entry.visual.emitters.is_empty(), "Follower uses source particle emitters")
		check(entry.visual.unsupported == followers.media.effects[entry.prefab].unsupported, "Particle conversion limitations stay attached to each follower")
		check(followers.handles_prefab(entry.prefab + ".prefab"), "Active follower owns its exact summon presentation")
	var old = followers.entries[20250].visual
	followers.sync_from_run(systems, player)
	check(followers.entries[20250].visual == old, "Repeated sync does not duplicate followers")
	var templates: int = followers._templates.size()
	var particles = followers.entries[20250].visual.emitters[0].node
	followers.advance(0.1, player)
	var age: float = followers.entries[20250].visual.age
	followers.advance(0.1, player, true)
	check(followers.entries[20250].visual.age == age and particles.speed_scale == 0.0, "Modal pause freezes source particle simulation")
	var start: Vector3 = followers.entries[20250].position
	player.position += Vector3(4, 0, 0)
	followers.advance(1.0 / 60.0, player)
	var intermediate: Vector3 = followers.entries[20250].position
	check(intermediate.x > start.x and intermediate.x < player.position.x, "Follower smoothly catches up")
	for frame in 120: followers.advance(1.0 / 60.0, player)
	check((followers.entries[20250].position as Vector3).distance_to(player.position) < 2.5, "Follower catches moving owner")
	player.position += Vector3(100, 0, 0)
	followers.advance(1.0 / 60.0, player)
	check((followers.entries[20250].position as Vector3).distance_to(player.position) < 2.5, "Teleport rebases follower")
	profile.data.run.inventory.erase("20250")
	profile.data.run.inventory["20251"] = 1
	followers.sync_from_run(systems, player)
	check(not followers.entries.has(20250) and followers.entries.has(20251), "Upgraded spirit replaces old presentation")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(profile.data))
	followers.clear()
	check(profile.restore(snapshot), "Profile restores")
	followers.sync_from_run(systems, player)
	check(followers.entries.size() == 2 and followers.entries.has(20251), "Saved inventory restores exact companions")
	profile.data.run.inventory = {"20210": 1, "20211": 1, "20212": 1, "20232": 1, "20270": 1}
	followers.sync_from_run(systems, player)
	check(followers.entries.keys() == [20270], "Source combined spirit replaces both component families and their lower tiers")
	var recorder := PresentationRecorder.new()
	profile.data.run.inventory = {"20210": 1}
	followers.sync_from_run(systems, player)
	check(followers.trigger_message("unrelated", player, recorder) == 0, "Unrelated gameplay messages emit no follower effect")
	check(followers.trigger_message("trigger_firesprite", player, recorder) == 1, "Fire spirit responds to its source custom trigger")
	check(recorder.effects.back().effect == "23120601_fx_skill_firesword_hit_full.prefab" and recorder.effects.back().point == followers.entries[20210].visual.global_position, "Tier one fire effect starts at its actual follower")
	check(recorder.effects.back().source_only, "Follower custom trigger retains the source prefab lifetime and visual gain")
	profile.data.run.inventory = {"20211": 1}
	followers.sync_from_run(systems, player)
	followers.trigger_message("trigger_firesprite", player, recorder)
	check(recorder.effects.back().effect == "23120601_fx_skill_firesword_hit.prefab", "Upgraded fire uses the source upgraded effect")
	recorder.free()
	profile.data.run.inventory = {"20250": 1, "20260": 1}
	followers.sync_from_run(systems, player)
	check(followers._templates.size() >= templates and followers.entries[20250].visual.emitters[0].node.mesh == particles.mesh, "Reacquisition reuses prepared particle meshes")
	profile.data.run.active = false
	followers.sync_from_run(systems, player)
	check(followers.entries.is_empty(), "End of run removes companions")
	profile.data.run = DungeonProfile.new_run()
	profile.data.run.active = true
	followers.sync_from_run(systems, player)
	check(followers.entries.is_empty(), "New run cannot retain old companions")
	var all_loot: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/LootData.json"))
	var spirit_count := 0
	for row in all_loot:
		if row.get("loot_type", "") not in ["随从", "高级随从"]: continue
		spirit_count += 1
		profile.data.run.inventory = {str(row.id): 1}
		followers.sync_from_run(systems, player)
		var entry: Dictionary = followers.entries[int(row.id)]
		followers.advance(0.05, player)
		check(not entry.visual.emitters.is_empty() and entry.visual.age > 0, "Every owned spirit animates its source prefab: %s" % row.id)
		check(entry.visual.scale == Vector3.ONE and entry.visual.rotation == Vector3.ZERO, "No invented icon squash or lean: %s" % row.id)
		var paused: Vector3 = entry.visual.position
		var paused_age: float = entry.visual.age
		followers.advance(0.0, player)
		check(entry.visual.position == paused and entry.visual.age == paused_age, "Zero step freezes spirit: %s" % row.id)
		player.facing = -entry.direction
		followers.advance(0.05, player)
		check((entry.direction as Vector3).is_normalized(), "Opposite facing keeps continuous unit direction: %s" % row.id)
		followers.advance(20.0, player)
		check(entry.visual.position.is_finite(), "Resume remains finite: %s" % row.id)
	check(spirit_count == followers.media.loot_bindings.size(), "Every currently available normal and upgraded spirit entry is covered")
	for prefab in followers.media.effects:
		var definition: Dictionary = followers.media.effects[prefab]
		check(definition.particle_systems > 0 and not definition.textures.is_empty(), "Every APK follower has source particle layers and textures: " + prefab)
		for low in [false, true]:
			var recovered: Node3D = followers._visual(prefab, low)
			followers.add_child(recovered)
			check(not recovered.emitters.is_empty() and recovered.particle_count <= (144 if low else 384), "Every recovered prefab instantiates within its particle budget: " + prefab)
			_check_persistent_icon(recovered, definition, "%s low=%s" % [prefab, low])
			recovered.free()
		for texture in definition.textures:
			check(ResourceLoader.exists(texture), "Follower source texture resolves: " + texture)
	player.free()
	followers.queue_free()
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _check_persistent_icon(visual: Node3D, definition: Dictionary, label: String) -> void:
	var icon: Dictionary = {}
	for emitter in visual.emitters:
		if emitter.node.get_parent().get_meta("source_layer", "") == "sprite_icon":
			icon = emitter
			break
	check(not icon.is_empty(), "Spirit body survives quality reduction: " + label)
	if icon.is_empty(): return
	var period := 0.0
	for layer in definition.layers:
		if layer.name == "sprite_icon": period = float(layer.duration) / float(layer.simulation_speed)
	check(icon.loop, "Spirit body retains its authored loop: " + label)
	visual.restart()
	visual.advance(0.01, false)
	for cycle in 3:
		# Simulate the CPU particle burst finishing, then cross its next source cycle.
		icon.node.emitting = false
		visual.advance(period, true)
		check(not icon.node.emitting, "Paused spirit cannot restart a finished burst: " + label)
		visual.advance(period, false)
		check(icon.node.emitting, "Spirit body reappears each cycle %d: %s" % [cycle, label])
		visual.advance(0.01, false)
		check(icon.node.emitting, "Spirit body stays active after its first lifetime: " + label)
	visual.restart()
	visual.advance(0.01, false)
	check(icon.node.emitting, "Reused spirit starts a fresh loop: " + label)
	icon.node.emitting = false
	visual.advance(period, false)
	check(icon.node.emitting, "Reused spirit resets its burst schedule: " + label)
	visual.stop()
	visual.advance(period, false)
	check(not icon.node.emitting and not visual.visible, "Removed spirit never restarts its body: " + label)
