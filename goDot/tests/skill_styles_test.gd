extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _has_effect(presentation: Node, key: String) -> bool:
	return presentation.active.any(func(entry): return entry.key == key and entry.authored != null)

func _run() -> void:
	var presentation = Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.audio_enabled = false
	presentation.set_process(false)
	var actor := DungeonActor.new()
	actor.is_player = true
	actor.combat = DungeonCombat.new()
	actor.combat.configure(null, null, 1)
	root.add_child(actor)
	actor.combat.statuses.clear()
	presentation.sync_actor_buffs(actor)
	check(not presentation._buff_styles.has(actor.get_instance_id()) and presentation.active.is_empty(), "An empty status owner skips visual synchronization without allocating state")
	actor.combat.add_buff("100101")
	presentation.sync_actor_buffs(actor)
	check(_has_effect(presentation, "23120601_fx_skill_firesword_buff"), "Persistent burning uses its APK KeepEffect")
	var first_count: int = presentation.active.size()
	presentation.sync_actor_buffs(actor)
	check(presentation.active.size() == first_count, "Repeated status synchronization retains one persistent effect")
	presentation.cancel_actor(actor)
	check(presentation.active.size() == first_count, "Cancelling an action retains status-owned visual effects")
	actor.combat.remove_buff("100101")
	presentation.sync_actor_buffs(actor)
	check(presentation.active.is_empty(), "Removing a status returns its persistent visual to the pool")
	actor.combat.add_buff("119901")
	presentation.sync_actor_buffs(actor)
	check(_has_effect(presentation, "23120601_fx_skill_firesword_buff"), "CommonBuffEffectId resolves its exact source effect buff")
	actor.combat.add_buff("100101")
	presentation.sync_actor_buffs(actor)
	check(presentation.active.filter(func(entry): return entry.key == "23120601_fx_skill_firesword_buff").size() == 1, "Shared common effects are referenced once across overlapping buffs")
	actor.combat.statuses.clear()
	presentation.sync_actor_buffs(actor)
	check(presentation.active.is_empty(), "Common-effect lifetime follows its remaining source owners")
	var end_key := "24050801_fx_env_healingwater_heal"
	presentation._buff_style_bindings["100101"] = {"100101": {"KeepEffect": "23120601_fx_skill_firesword_buff.prefab", "EndEffect": end_key + ".prefab"}}
	actor.combat.add_buff("100101")
	presentation.sync_actor_buffs(actor)
	check(_has_effect(presentation, "23120601_fx_skill_firesword_buff"), "An empty owner begins styles when a status is added")
	actor.combat.statuses.clear()
	presentation.sync_actor_buffs(actor)
	check(not presentation.active.any(func(entry): return entry.has("buff_style")) and _has_effect(presentation, end_key), "An owner becoming empty releases KeepEffect and still emits EndEffect")
	var end_spawned: int = presentation.spawned
	presentation.sync_actor_buffs(actor)
	check(presentation.spawned == end_spawned, "An empty owner emits EndEffect once before returning to the empty fast path")
	presentation._buff_style_bindings.erase("100101")
	presentation.clear()
	presentation.buff_effect(actor, {"phase": "start", "definition": {"StartEffect": "24050801_fx_env_healingwater_heal.prefab", "DummyData": {"DummyType": "Unit_FootBottom"}}})
	check(_has_effect(presentation, "24050801_fx_env_healingwater_heal"), "Instant healing StartEffect has an authored visual")
	presentation.clear()
	presentation.buff_effect(actor, {"phase": "counter_max", "definition": {"PlayEffectWhenLayerMax": "26020602_fx_blade_counterexplode.prefab", "DummyData": {"DummyType": "Unit_Center"}}})
	check(_has_effect(presentation, "26020602_fx_blade_counterexplode"), "Counter threshold renders the exact source explosion")
	presentation.clear()
	actor.combat.add_buff("26081701")
	presentation.emit_effect(actor, "25122501_fx_lance_atk_slash1.prefab", Vector3.ZERO)
	check(_has_effect(presentation, "25122501_fx_lance_atk_slash1_fashionsummer"), "Source cosmetic replacement binds the exact authored effect")
	presentation.clear()
	actor.combat.statuses.clear()
	var healing: Dictionary = actor.combat._summon_index["600011"].raw_data
	presentation.summon_phase(actor, healing, Vector3(3, 0, 4), "Loop")
	check(_has_effect(presentation, "23111701_fx_skill_lightorb_xuanyanchenduan_healingtriggerwave"), "Healing field emits its exact source interval wave")
	check(presentation.active.back().authored.scale.is_equal_approx(Vector3(5, 1, 5)), "Field wave retains serialized nonuniform scale")
	check(presentation.active.back().root.position.is_equal_approx(Vector3(3, 0, 4)), "Field effect uses the summon position")
	presentation.clear()
	var shock: Dictionary = actor.combat._summon_index["309101"].raw_data
	presentation.summon_phase(actor, shock, Vector3.ZERO, "Start")
	check(_has_effect(presentation, "23100901_fx_skill_thunderaxe_dianheyongdong_explode"), "A summon without a prefab still emits its source Start effect")
	presentation.clear()
	var fire: Dictionary = actor.combat._summon_index["50205011"].raw_data
	presentation.summon_created(actor, fire, Vector3.ZERO)
	check(presentation.active.is_empty(), "Fire spirit creation does not invent a custom-message trigger")
	presentation.summon_trigger(actor, fire, Vector3.ZERO, "NoDelay")
	check(_has_effect(presentation, "23120601_fx_skill_firesword_hit_full"), "Fire spirit custom trigger uses its exact source effect")
	presentation.clear()
	var definition: Dictionary = presentation.media.effects["23120601_fx_skill_firesword_buff"]
	var original = definition.duplicate(true)
	var layers: Array = preload("res://scripts/presentation/authored_effect.gd").resolved_layers(definition)
	check(not str(definition.get("material_library", "")).is_empty(), "Refreshed style binds a shared source material library")
	check(layers.any(func(layer): return layer.materials.any(func(material): return material.has("source_floats") and material.has("source_colors"))), "Shared materials retain original shader properties")
	check(definition == original, "Resolving shared materials does not modify imported source data")
	presentation.emit_effect(actor, "23101901_fx_axe_atk_hit", Vector3.ZERO)
	check(presentation.active.back().authored.get_children().all(func(node): return node.get_meta("source_layer", "") != "23101901_hit_ring"), "An APK mesh-mode layer with no source mesh does not become an invented quad")
	presentation.clear()
	for id in ["240700", "40000", "50230720"]:
		var pickup: Dictionary = actor.combat._summon_index[id].raw_data
		var token: int = presentation.summon_started(actor, pickup, Vector3.ZERO)
		check(token > 0 and _has_effect(presentation, str(pickup.Prefab).trim_suffix(".prefab")), "Pickup " + id + " uses actual APK particle geometry")
		presentation.summon_ended(token)
		presentation.summon_pickup(actor, pickup, Vector3.ZERO)
		check(_has_effect(presentation, "23121501_fx_other_proppickup"), "Pickup " + id + " emits its source pickup style")
		presentation.clear()
	var models := 0
	for key in presentation.media.effects:
		if presentation.media.effects[key].get("models", []).is_empty(): continue
		presentation.emit_effect(actor, key, Vector3.ZERO)
		check(not presentation.active.is_empty() and presentation.active.back().authored != null, key + " constructs its source model")
		if not presentation.active.is_empty():
			var authored = presentation.active.back().authored
			check(authored.find_children("*", "MeshInstance3D", true, false).size() > 0, key + " has actual source geometry")
			presentation._process(1.0 / 60.0)
			var clone = authored.instantiate_effect()
			root.add_child(clone)
			clone.restart()
			clone.advance(1.0 / 60.0, false)
			clone.stop()
			clone.free()
		models += 1
		presentation.clear()
	check(models == 13, "All thirteen model-only skill resources are represented")
	check(presentation.missing.is_empty(), "Covered source styles need no missing-resource substitution")
	var report = {"passed": failures.is_empty(), "checks": checks, "models": models, "failures": failures, "scope": "Source style dispatch, status/common-buff lifetime, exact replacement mappings and recovered models. Headless checks do not establish APK visual equivalence or device FPS."}
	FileAccess.open("res://reports/skill-styles-runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SKILL_STYLES ", JSON.stringify(report))
	presentation.free()
	actor.free()
	quit(0 if failures.is_empty() else 1)
