extends Node

signal initialization_progress(value: float)
signal initialization_failed(message: String)

var startup_loading := false
var initialized := false
var _initializing := false
var catalog: RefCounted
var profile: RefCounted
var systems: RefCounted
var campaign: RefCounted
var save_store := DungeonSaveStore.new()
var world: DungeonWorld
var hud: DungeonHud
var menus: DungeonMenus
var dialogue: RefCounted = preload("res://scripts/domain/dialogue.gd").new()
var selected_character := 1
var selected_weapon := 101
var difficulty := 0
var active_page := ""
var autosave_time := 0.0
var audio: AudioStreamPlayer
var resource_audio = preload("res://scripts/presentation/resource_audio.gd").new()
var _save_queued := false
var _save_delay := 0.0
var last_snapshot_ms := 0.0
var _save_warning := ""
var _loading := false
var _transitioning := false
var _exit_after_reward := false
var _death_pending := false
var _death_remaining := 0.0
var _death_camera_elapsed := 0.0
var _death_will_revive := false
var _revival_stage := 0
var room_loading: CanvasLayer
var boss_intro: CanvasLayer
var battle_tally = preload("res://scripts/domain/battle_tally.gd").new()
var _introduced_bosses: Dictionary = {}
var _smoke := false
var _smoke_clock := 0.0
var _capture_path := ""
var _room_key := ""
var _binding_action := ""
var _smoke_output := "res://reports"
var _wall_start := 0
var _peak_process := 0.0
var _peak_physics := 0.0
var ads = preload("res://scripts/ads_service.gd").new()
var ad_rewards: RefCounted
const DEFAULT_KEYS = {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "skill": [KEY_SPACE], "dodge": [KEY_SHIFT], "burst": [KEY_Q], "heavy": [KEY_R], "pause_game": [KEY_ESCAPE], "interact": [KEY_E], "map": [KEY_M]}

func _ready() -> void:
	var arguments = OS.get_cmdline_user_args()
	if "--combat-stress" in arguments or OS.has_feature("combat_stress"):
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		add_child(preload("res://scenes/combat_stress.tscn").instantiate())
		return
	_initializing = startup_loading
	if startup_loading: await _initialization_step(0.0)
	_smoke = "--smoke" in arguments
	var output_index = arguments.find("--smoke-output")
	if output_index >= 0 and output_index + 1 < arguments.size(): _smoke_output = arguments[output_index + 1]
	if _smoke:
		save_store = DungeonSaveStore.new(_smoke_output.path_join("runtime-profile.json"))
		_wall_start = Time.get_ticks_usec()
	var capture_index = arguments.find("--capture")
	if capture_index >= 0 and capture_index + 1 < arguments.size(): _capture_path = arguments[capture_index + 1]
	catalog = load("res://scripts/domain/catalog.gd").new()
	if not catalog.load_all():
		push_error("Cannot load packaged game data")
		if startup_loading: initialization_failed.emit("游戏数据加载失败，请重试")
		else: get_tree().quit(2)
		return
	profile = load("res://scripts/domain/profile.gd").new()
	dialogue.load_all()
	var saved = {} if _smoke else save_store.load_profile()
	if not saved.is_empty(): profile.data = saved
	_configure_input()
	if startup_loading: await _initialization_step(0.25)
	systems = load("res://scripts/domain/systems.gd").new(catalog, profile)
	systems.changed.connect(_on_changed)
	campaign = load("res://scripts/domain/campaign.gd").new()
	campaign.configure()
	selected_character = int(profile.data.get("selected_character", 1))
	selected_weapon = int(profile.data.get("selected_weapon", 101))
	difficulty = int(profile.data.get("selected_difficulty", 0))
	world = DungeonWorld.new()
	world.test_driver = _smoke
	world.systems = systems
	add_child(world)
	if startup_loading: await _initialization_step(0.5)
	hud = DungeonHud.new()
	add_child(hud)
	room_loading = preload("res://scripts/presentation/room_loading.gd").new()
	add_child(room_loading)
	boss_intro = preload("res://scripts/presentation/boss_intro.gd").new()
	add_child(boss_intro)
	boss_intro.finished.connect(func(): world.paused = hud.modal_open or _transitioning or _flow_locked())
	world.impact_confirmed.connect(_record_run_impact)
	world.hud = hud
	world.ground_loot.configure_altar_pointer(hud)
	world.ground_loot.altar_requested.connect(func(key: String, marker_id: String):
		if _transitioning or _flow_locked() or world._background or hud.modal_open: return
		if marker_id.is_empty(): _request_spirit_altar({"key": key})
		else: world.interactions.interact(marker_id))
	menus = DungeonMenus.new(self)
	ad_rewards = preload("res://scripts/domain/ad_rewards.gd").new(systems)
	add_child(ads)
	ads.message.connect(func(text): hud.toast(text))
	ads.finished.connect(func():
		if menus.current_page in ["mall", "meals", "work"]: menus.open(menus.current_page, menus.current_id))
	hud.action.connect(_action)
	hud.skill.connect(_skill)
	world.enemy_defeated.connect(_enemy_defeated)
	world.player_defeated.connect(_player_defeated)
	world.wave_cleared.connect(_wave_cleared)
	world.room_rewards_ready.connect(_finish_room)
	world.room_exit_ready.connect(func(): _save())
	world.environment_action.connect(_environment_action)
	world.environment_sound.connect(func(name): resource_audio.play_named(name))
	world.world_message.connect(func(message, context):
		if message == "camp_page":
			if context.page == "primary":
				if profile.data.run.active: _primary()
				else: menus.open("difficulty")
			else: menus.open(str(context.page))
		elif message == "room_action":
			if str(context.get("data", {}).get("UIBtnName", "")) == DungeonWorldInteractions.CURSE_ALTAR: _request_curse_altar(context)
			else: _room_action()
		else: hud.toast(message))
	add_child(resource_audio)
	resource_audio.configure(world.presentation.media, world)
	audio = resource_audio.music
	world.player_transfer.sound_requested.connect(func(name): resource_audio.play_named(name, false))
	world.player_revival.sound_requested.connect(func(name): resource_audio.play_named(name, false))
	_apply_settings()
	if startup_loading: await _initialization_step(0.75)
	_restore_flow()
	if not _flow_locked() and not profile.data.get("dialogue_state", {}).is_empty(): _show_dialogue()
	if not save_store.warning.is_empty(): hud.toast(save_store.warning)
	if startup_loading: await _initialization_step(1.0)
	_initializing = false
	initialized = true
	if _smoke: _smoke_begin.call_deferred()

func _initialization_step(value: float) -> void:
	initialization_progress.emit(value)
	await get_tree().process_frame

func _configure_input() -> void:
	var overrides: Dictionary = profile.data.get("key_bindings", {}) if profile else {}
	for key in DEFAULT_KEYS:
		if not InputMap.has_action(key): InputMap.add_action(key)
		InputMap.action_erase_events(key)
		for code in overrides.get(key, DEFAULT_KEYS[key]):
			var event = InputEventKey.new()
			event.physical_keycode = int(code)
			InputMap.action_add_event(key, event)

func _apply_settings() -> void:
	var mode = DungeonProfile.attack_mode(profile.data)
	world.set_attack_mode(mode)
	hud.set_attack_mode(mode)
	world.camera_shake_enabled = bool(profile.data.get("camera_shake", true))
	world.low_effects = bool(profile.data.get("low_effects", false))
	world.presentation.audio_enabled = bool(profile.data.get("audio_enabled", true))
	resource_audio.enabled = world.presentation.audio_enabled
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(profile.data.get("volume", 1.0)))))
	audio.stream_paused = not profile.data.get("audio_enabled", true)

func _input(event: InputEvent) -> void:
	if startup_loading or _initializing or _transitioning: return
	if _binding_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo: return
	var bindings: Dictionary = profile.data.get("key_bindings", {})
	bindings[_binding_action] = [int(event.physical_keycode)]
	profile.data["key_bindings"] = bindings
	_binding_action = ""
	_configure_input()
	_save()
	menus.open("settings")
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if startup_loading or _initializing or _transitioning or _flow_locked() or (boss_intro and boss_intro.active): return
	if event.is_action_pressed("map"):
		_toggle_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game"):
		if ads.busy():
			ads.cancel()
			get_viewport().set_input_as_handled()
			return
		if hud.modal_open:
			_exit_after_reward = false
			_close_page()
		else: menus.open("settings")
		get_viewport().set_input_as_handled()
		return
	if hud.modal_open: return
	for entry in [["skill", 2], ["dodge", 1], ["burst", 3], ["heavy", 4]]:
		if event.is_action_pressed(entry[0]): _skill(entry[1], true)
		if event.is_action_released(entry[0]) and entry[1] == 4: _skill(4, false)
	if event.is_action_pressed("interact"):
		_interact()

func _interact() -> void:
	if _transitioning or hud.modal_open or not world.interactions or not is_instance_valid(world.player): return
	if not world.ground_loot.nearest(world.player.position).is_empty():
		var entry = world.ground_loot.nearest(world.player.position)
		if entry.has("altar"):
			_request_spirit_altar({"key": str(entry.altar)})
			return
		var magic_before = systems.material(102)
		var rewards_before = profile.data.run.rewards.size()
		var result = world.ground_loot.pickup(world.player.position, systems)
		hud.toast(menus.clean(result.message))
		if result.success:
			resource_audio.play_event("pickup_coin" if int(entry.id) == 101 else "pickup_material" if entry.material else "pickup_ability")
			_apply_growth()
			_save()
			if not systems.pending_character_talent_reward().is_empty(): _talent_rewards()
			elif int(entry.id) in [13101, 13102, 13103] and systems.material(102) > magic_before:
				hud.toast("天赋已满级，转化为魔力 +%d" % (systems.material(102) - magic_before))
			elif profile.data.run.rewards.size() > rewards_before:
				_rewards(str(profile.data.run.rewards.back().key))
		return
	world.interactions.interact_nearest(world.player.position)

func _process(delta: float) -> void:
	if _initializing or not world or not world.player: return
	menus.tick(delta)
	save_store.poll()
	if save_store.last_failed and save_store.warning != _save_warning:
		_save_warning = save_store.warning
		hud.toast(_save_warning)
	elif not save_store.last_failed: _save_warning = ""
	if _save_queued:
		_save_delay += delta
		if _save_delay >= 0.25 and not save_store.is_saving(): _capture_save()
	_tick_death(delta)
	world.paused = startup_loading or hud.modal_open or _transitioning or _flow_locked() or boss_intro.active
	_update_battle_presentation(delta)
	world.ground_loot.update_altar_pointer(world.camera, world.player.global_position, profile.data.run.active and not world.paused and not world._background)
	hud.set_adventure_mode(profile.data.run.active)
	var combat = world.player.combat
	if profile.data.run.active:
		if not world.paused and not world._background and not world._camp_camera:
			profile.data.run.counters["run:elapsed"] = float(profile.data.run.counters.get("run:elapsed", 0)) + maxf(0, delta)
		profile.data.run.health = maxf(0, combat.health)
		profile.data.run.max_health = combat.max_health
		profile.data.run.armor = combat.armor
		if systems.effects and not world.paused:
			systems.effects.advance(delta * world.simulation_scale)
		_drain_buffs()
	autosave_time += delta
	if autosave_time >= 10:
		autosave_time = 0
		_save()
	var room: Dictionary = campaign.current_room() if profile.data.run.active else {}
	var title = "难度 %d" % difficulty
	var status = "%s  Lv.%d   生命 %d / %d" % [menus.name_of(catalog.find("CharData", selected_character)), int(profile.data.character_levels.get(str(selected_character), 1)), combat.health, combat.max_health]
	if not room.is_empty(): status += "   波次 %d / %d" % [mini(int(room.get("wave_count", 0)), int(room.get("waves_cleared", 0)) + 1), int(room.get("wave_count", 0))]
	var resources = "金币 %d   魔力 %d   矿石 %d" % [systems.material(101), systems.material(102), systems.material(103)]
	var primary = "出发冒险"
	if profile.data.run.active:
		primary = "路线" if campaign.state.phase == "route" else "领取奖励" if campaign.state.phase == "reward" else "继续前进" if campaign.room_ready() else "交互"
	hud.update_state(title, combat.health, combat.max_health, status, resources, primary)
	hud.update_counters(systems, difficulty)
	var nearby: Dictionary = world.interactions.nearest_interaction(world.player.position) if world.interactions else {}
	var loot = world.ground_loot.nearest(world.player.position)
	hud.primary.visible = not hud.modal_open and (not nearby.is_empty() or not loot.is_empty())
	if not nearby.is_empty():
		var prompt: Array = world.interactions.prompt_for(nearby)
		hud.primary.text = str(prompt[0])
		if nearby.marker.get("Type", "") == "EEUT_NPC":
			var npc = catalog.find("NPCData", str(nearby.data.get("NpcId", "")))
			hud.primary.text = str(npc.get("name", "交谈"))
		hud.primary.icon = DungeonStyle.texture("sprite_conversation_talk" if not profile.data.run.active or prompt[1] == "npc" else str(prompt[2]))
		hud.primary.add_theme_color_override("font_color", Color("74d8ff") if nearby.marker.get("Type", "") == "EEUT_AbilityItemTreasureBox" else Color.WHITE)
	hud.show_pickup(loot, systems, hud.modal_open)
	hud.objective_guide.update_target(world, hud.modal_open or not profile.data.run.active or world.fighting)
	world.update_event_markers(not profile.data.run.active)
	hud.readiness_suspended = world.paused or world._background or hud.modal_open
	hud.low_effects = world.low_effects
	hud.update_combat(combat, not profile.data.run.active)
	hud.update_intent(world.intent)
	if _smoke:
		_peak_process = maxf(_peak_process, Performance.get_monitor(Performance.TIME_PROCESS))
		_peak_physics = maxf(_peak_physics, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		_smoke_clock += delta
		if _smoke_clock > 18: _smoke_end()

func _new_combat() -> RefCounted:
	var combat = load("res://scripts/domain/combat.gd").new()
	combat.configure(null, systems, selected_character, difficulty, int(profile.data.run.get("seed", 1)))
	if systems.has_method("attributes"):
		combat.set_external_attributes(systems.attributes(selected_character))
	_bind_progression(combat)
	return combat

func _camp() -> void:
	if boss_intro: boss_intro.finish()
	battle_tally.reset()
	_introduced_bosses.clear()
	_loading = true
	world.load_environment(10000, true)
	world.create_player(_new_combat(), selected_character)
	if profile.data.run.active:
		world.player.combat.health = minf(world.player.combat.max_health, float(profile.data.run.health))
		world.player.combat.armor = float(profile.data.run.armor)
	_equip_visual()
	hud.close_page()
	hud.set_adventure_mode(profile.data.run.active)
	active_page = ""
	_loading = false
	_play_music(0, true)
	resource_audio.enter_environment(0, true)

func _action(kind: String, id: Variant, extra: Variant) -> void:
	if _transitioning or boss_intro.active: return
	if kind == "start_chest_trial" and not _flow_locked():
		_start_chest_trial(int(id))
		return
	if _flow_locked():
		if kind == "result_next":
			resource_audio.play_event("ui_confirm")
			_result_next()
		elif kind == "result_camp":
			resource_audio.play_event("ui_back")
			_result_camp()
		return
	if kind not in ["volume", "auto_route"] and not kind.begins_with("page:"):
		resource_audio.play_event("ui_back" if kind == "close_page" else "ui_dialogue" if kind == "talk_next" else "ui_click")
	if kind == "close_page":
		_exit_after_reward = false
		if not profile.data.get("dialogue_state", {}).is_empty():
			profile.data.dialogue_state = {}
			_save(true)
		if ads.busy(): ads.cancel()
		else: _close_page()
		return
	if kind == "cancel_ad":
		ads.cancel()
		return
	if ads.busy():
		hud.toast("请等待广告结束")
		return
	if kind == "privacy_ads":
		if ads.bridge != null: ads.bridge.call("privacy_options")
		return
	if kind.begins_with("ad:") or kind.begins_with("ad_skip:"):
		var context = {"kind": kind.get_slice(":", 1), "id": int(id), "level": int(extra)}
		var quote = ad_rewards.quote(context)
		if not quote.success:
			hud.toast(str(quote.message))
			return
		if kind.begins_with("ad_skip:"):
			hud.toast(str(ad_rewards.claim(context, "skip-" + str(Time.get_ticks_usec()), true).message))
			_apply_growth()
			menus.open(menus.current_page, menus.current_id)
		else:
			var started = ads.request(str(quote.point), func():
				var result = ad_rewards.claim(context, str(ads.pending.id))
				hud.toast(str(result.message))
				_apply_growth())
			if started: hud.show_page("广告准备中", [menus.item("", "", [menus.command("取消", "cancel_ad")])])
		return
	if kind.begins_with("visual:"):
		DungeonStyle.set_option(kind.trim_prefix("visual:"), id)
		DungeonStyle.apply_options(world)
		menus.open("settings")
		return
	if kind.begins_with("page:"):
		if not profile.data.get("dialogue_state", {}).is_empty():
			profile.data.dialogue_state = {}
			_save(true)
		if kind == "page:character_talents" and not systems.pending_character_talent_reward().is_empty():
			_talent_rewards()
			return
		menus.open(kind.trim_prefix("page:"), int(id))
		return
	if kind.begins_with("op:"):
		var method = kind.trim_prefix("op:")
		if method == "execute_npc_function":
			_start_dialogue(int(id))
			return
		var args: Array = [] if method in ["unlock_token_slot", "unlock_amplifier_slot", "reroll_amplifier", "refresh_tokens"] else [id]
		if method == "start_work" and extra is Dictionary:
			args.append(int(extra.get("partner", 0)))
			args.append(int(extra.get("quantity", 1)))
		elif method in ["start_work", "cook_meal", "select_meal", "buy_room_offer", "choose_loot_reward", "resolve_event", "claim_npc_support", "equip_camp_decoration"]: args.append(extra)
		if not systems.has_method(method):
			push_error("Missing UI operation: " + method)
			hud.toast("操作暂不可用")
			return
		var building_stage = systems.rank(profile.data.buildings, id) if method == "upgrade_building" else 0
		var result = systems.callv(method, args)
		if result is Dictionary: hud.toast(str(result.get("message", "")))
		_apply_growth()
		if result is Dictionary and result.get("success", false):
			if method == "upgrade_building": resource_audio.play_event("build_success")
			elif method == "cook_meal": resource_audio.play_event("cook_success")
			elif method.begins_with("upgrade_") or method.begins_with("unlock_") or method.begins_with("learn_"): resource_audio.play_event("upgrade_success")
			elif method.begins_with("claim_") or method == "collect_work": resource_audio.play_event("reward_get")
			_save(true)
			if method == "upgrade_building":
				_close_page()
				world.refresh_camp_progression()
				world.focus_camp_building(int(id), building_stage + 1)
				return
			if method == "start_work":
				menus.open("work")
				return
			if method == "equip_camp_decoration": world.refresh_camp_progression()
		menus.open(menus.current_page, 0 if menus.current_page in ["tasks", "achievements", "talents"] else menus.current_id)
		return
	match kind:
		"confirm_stop_work":
			var state = systems.work_status(int(id))
			if state.order.is_empty(): return
			var warning = "停止后当前工作的进度将清空。"
			if int(state.completed_quantity) > 0: warning += "\n尚未领取的 %d 份产出也会丢弃。" % int(state.completed_quantity)
			hud.show_page("停止派遣？", [menus.item(state.name, warning, [menus.command("继续派遣", "page:work"), menus.command("停止派遣", "op:stop_work", id)])], "list", {"camp": true})
		"camp_navigate":
			if profile.data.run.active: return
			_close_page()
			if not world.navigate_to_camp_facility(str(id)): hud.toast("当前设施没有可用的到达位置")
		"map": _toggle_map()
		"talk_next": _next_dialogue()
		"talk_skip": _skip_dialogue()
		"camp", "achievements", "inventory", "settings": menus.open(kind)
		"primary": _primary()
		"interact": _interact()
		"select_character":
			if profile.data.run.active: hud.toast("冒险结束后可以切换角色")
			else:
				selected_character = int(id)
				selected_weapon = int(catalog.find("CharData", selected_character).get("default_weapon", 101))
				profile.data.selected_character = selected_character
				profile.data.selected_weapon = selected_weapon
				_camp()
				_save()
		"equip_weapon":
			if not profile.data.run.active:
				selected_weapon = int(id)
				profile.data.selected_weapon = selected_weapon
				_apply_growth()
				_equip_visual()
				_save()
				hud.toast("武器已装备")
		"difficulty":
			if not profile.data.run.active:
				var status = systems.difficulty_status(int(id), selected_character)
				if not status.can_start:
					hud.toast(str(status.reason))
				else:
					difficulty = int(id)
					_save()
					menus.open("difficulty")
		"chaos_level":
			var result = systems.select_chaos_level(int(id), selected_character)
			hud.toast(str(result.message))
			if result.success: _save()
			menus.open("difficulty")
		"claim_chaos_rewards":
			var result = systems.claim_chaos_rewards(selected_character)
			hud.toast(str(result.message))
			if result.success: _save()
			menus.open("difficulty")
		"enter_node": _select_node(int(id))
		"select_region": _select_region(int(id))
		"confirm_region": _select_region(int(id), true)
		"region_info": _region_info(int(id))
		"route_world": _route(not bool(campaign.state.get("region_selection", false)), "world")
		"route_rooms": _route(campaign.state.get("phase", "") != "route" or bool(campaign.state.get("region_selection", false)), "rooms")
		"auto_route":
			profile.data["auto_route"] = bool(id)
			_save()
			if bool(id) and campaign.state.get("phase", "") == "route": _route()
		"next": _leave_room()
		"leave_unclaimed": _leave_room(true)
		"room_action": _room_action()
		"finish_noncombat": _finish_noncombat()
		"event_choice":
			var result = systems.resolve_event(_room_key, int(id))
			hud.toast(str(result.get("message", "")))
			if result.get("success", false):
				_apply_growth()
				var view = systems.event_for_node(int(campaign.current_room().node_id), int(profile.data.run.seed), _room_key)
				if view.get("finished", true): _finish_noncombat()
				else: _room_action()
		"buy_room":
			var result = systems.buy_room_offer(_room_key, int(id))
			hud.toast(str(result.get("message", "")))
			_room_action()
		"choose_loot":
			var result = systems.choose_loot_reward(str(extra), int(id))
			hud.toast(str(result.get("message", "")))
			if result.success: resource_audio.play_event("reward_get")
			_apply_growth()
			if result.success and str(extra) == "old_day:" + _room_key:
				profile.data.run.counters["old_day:chosen:" + _room_key] = true
				_finish_noncombat()
			elif result.success and str(extra).begins_with("curse_altar:"):
				profile.data.run.counters["SelectLootRemainCount_Curse"] = maxi(0, int(profile.data.run.counters.get("SelectLootRemainCount_Curse", 0)) - 1)
				hud.close_page()
				_save()
				if _exit_after_reward: _leave_room()
			elif result.success and str(extra).begins_with("altar:"):
				profile.data.run.counters["SelectLootRemainCount_Sprites"] = maxi(0, int(profile.data.run.counters.get("SelectLootRemainCount_Sprites", 0)) - 1)
				world.ground_loot.remove_altar(str(extra))
				hud.close_page()
				_save()
				if _exit_after_reward: _leave_room()
			else: _rewards()
		"refresh_loot":
			hud.toast(str(systems.refresh_loot_reward(str(id)).message))
			_rewards()
		"choose_talent":
			var result = systems.choose_character_talent_reward(str(extra), int(id))
			hud.toast(str(result.get("message", "")))
			if result.success: resource_audio.play_event("talent_selected")
			_apply_growth()
			_save()
			if not systems.pending_character_talent_reward().is_empty(): _talent_rewards()
			elif _exit_after_reward: _leave_room()
			else: hud.close_page()
		"refresh_talent":
			hud.toast(str(systems.refresh_character_talent_reward(str(id)).message))
			_talent_rewards()
		"retreat":
			if profile.data.run.active:
				hud.show_page("结束本次冒险？", [menus.item("返回营地后，本次冒险将结束", "", [menus.command("继续冒险", "close_page"), menus.command("结束冒险", "confirm_retreat")])])
			else: _close_page()
		"confirm_retreat":
			if profile.data.run.active: _finish_run(false, "retreat")
		"save":
			hud.toast("进度已保存" if _save(true) else save_store.warning)
		"toggle_audio":
			profile.data["audio_enabled"] = not profile.data.get("audio_enabled", true)
			audio.stream_paused = not profile.data.audio_enabled
			world.presentation.audio_enabled = bool(profile.data.audio_enabled)
			resource_audio.enabled = bool(profile.data.audio_enabled)
			_save()
		"volume":
			profile.data["volume"] = clampf(float(id), 0, 1)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, profile.data.volume)))
			_save()
		"auto_attack":
			_action("auto_attack_mode", "normal" if bool(id) else "off", 0)
		"auto_attack_mode":
			profile.data["auto_attack_mode"] = str(id) if str(id) in ["normal", "heavy", "off"] else "normal"
			world.set_attack_mode(profile.data.auto_attack_mode)
			hud.set_attack_mode(profile.data.auto_attack_mode)
			_save()
			if menus.current_page == "settings" and hud.modal_open: menus.open("settings")
		"camera_shake", "low_effects":
			profile.data[kind] = bool(id)
			_apply_settings()
			_save()
		"bind_key":
			_binding_action = str(id)
			hud.toast("按下新的按键")
		"reset_keys":
			profile.data["key_bindings"] = {}
			_configure_input()
			_save()
			menus.open("settings")
		"quit":
			_save(true)
			get_tree().quit()

func _primary() -> void:
	if _flow_locked(): return
	if not profile.data.run.active:
		_exit_after_reward = false
		var seed_value = 12345 if _smoke else int(Time.get_unix_time_from_system()) & 0x7fffffff
		var combat = _new_combat()
		var generated = campaign.generate(seed_value, difficulty)
		if not generated.success:
			hud.toast("无法生成冒险路线")
			return
		var result = systems.begin_run(seed_value, selected_character, combat.max_health, difficulty)
		if not result.get("success", false):
			hud.toast(str(result.get("message", "")))
			return
		_route()
		_save()
	elif world.player.dead: _player_defeated()
	elif campaign.state.phase == "route": _route()
	elif campaign.state.phase == "reward": _leave_room()
	elif campaign.room_ready(): _finish_room()
	elif not campaign.current_room().get("combat", false): _room_action()

func _route(preview := false, map_scope := "") -> void:
	if not profile.data.run.active or _flow_locked() or campaign.state.is_empty(): return
	systems.ensure_map_node_increments(campaign)
	campaign.set_road_map_attributes(systems.attributes(selected_character))
	var region_selection = bool(campaign.state.get("region_selection", false))
	if map_scope.is_empty(): map_scope = "world" if region_selection else "rooms"
	if map_scope == "world":
		_world_route(preview or not region_selection)
		return
	var choices = campaign.choices()
	if choices.is_empty() and not preview: return
	var shift: Dictionary = systems.route_shift_quote()
	if not preview and bool(profile.data.get("auto_route", false)) and choices.size() == 1 and (campaign.vertical_choices().is_empty() or not shift.success):
		_select_node(int(choices[0].node_id))
		return
	var map: Array = campaign.route_map(false)
	var rows: Array = []
	for column in campaign.state.get("layers", []).size():
		var layer: Dictionary = campaign.state.layers[column]
		for room in map:
			if int(room.layer_index) != column: continue
			var node_id = int(room.node_id)
			var identity = column * 100000000 + int(node_id)
			var active = not preview and (bool(room.available) or (bool(room.vertical) and bool(shift.success)))
			var row = menus.item(str(room.display_name), "区域 %d" % int(room.Region), [menus.command("进入" if active else "已通过" if layer.complete else "未到达", "enter_node", int(node_id), 0, not active)])
			row.merge(room)
			row["name"] = str(room.display_name)
			row["Name"] = str(room.display_name)
			row["IconName"] = str(room.display_icon)
			row["NodeIncrementData"] = systems.room_node_increments("%d:%d:%d" % [int(profile.data.run.seed), column, node_id], room)
			row["available"] = active
			row["shift_cost"] = int(shift.cost)
			row["config_id"] = identity
			row["column"] = column
			row["icon"] = str(room.display_icon)
			rows.append(row)
	var character = catalog.find("CharData", selected_character)
	hud.show_page("区域路线" if preview else "选择路线", rows, "route", {"map_scope": "rooms", "preview": preview, "first_layer": int(map[0].layer_index) if not map.is_empty() else 0, "current_layer": int(campaign.state.layer_index), "portrait": character.get("square_icon_name", ""), "character": menus.name_of(character), "magic": systems.material(102), "search": shift.remaining, "search_max": shift.maximum, "shift_available": not preview and shift.success, "automatic": profile.data.get("auto_route", false)})
	world.paused = true
	_save()

func _world_route(preview: bool) -> void:
	var choices = campaign.region_choices()
	if not preview and bool(profile.data.get("auto_route", false)) and choices.size() == 1:
		_select_region(int(choices[0].node_id))
		return
	var rows = campaign.region_map()
	var character = catalog.find("CharData", selected_character)
	var shift = systems.route_shift_quote()
	var current_region = campaign.current_module_index() + 1
	hud.show_page("区域总览" if preview else "选择路线", rows, "route", {"map_scope": "world", "preview": preview, "first_layer": 1, "current_layer": current_region, "portrait": character.get("square_icon_name", ""), "character": "迷宫入口", "magic": systems.material(102), "search": shift.remaining, "search_max": shift.maximum, "automatic": profile.data.get("auto_route", false), "can_view_rooms": not bool(campaign.state.get("region_selection", false))})
	world.paused = true

func _region_info(id: int) -> void:
	for row in campaign.region_map():
		if int(row.node_id) != id: continue
		var details = menus.clean(str(row.get("lock_reason", row.get("description", ""))))
		hud.show_page(str(row.name), [menus.item(str(row.name), details, [menus.command("返回路线", "route_world")])])
		return

func _select_region(id: int, confirmed := false) -> void:
	if _transitioning or _flow_locked(): return
	var options = campaign.region_choices().filter(func(row): return int(row.node_id) == id)
	if options.is_empty(): return
	var clear_bosses: Array = options[0].get("clear_boss_ids", [])
	var known_boss = clear_bosses.any(func(enemy): return profile.data.stats.has("boss-rating:" + str(int(enemy))))
	if bool(options[0].get("high_risk", false)) and not clear_bosses.is_empty() and not known_boss and not confirmed:
		hud.show_page("高危区域", [menus.item(str(options[0].name), "此区域的魔物更加强大，金币掉落加成 100%。", [menus.command("返回路线", "route_world"), menus.command("确认进入", "confirm_region", id)])])
		return
	var result = campaign.select_region(id)
	if not result.get("success", false): return
	_save()
	var entrances = campaign.choices()
	if not entrances.is_empty(): _select_node(int(entrances[0].node_id))

func _select_node(id: int) -> void:
	if _transitioning or _flow_locked() or campaign.state.get("phase", "") != "route": return
	var destination: Dictionary = {}
	for choice in campaign.choices() + campaign.vertical_choices():
		if int(choice.node_id) == id: destination = choice
	if destination.is_empty(): return
	if destination.get("vertical", false) and not systems.route_shift_quote().success:
		hud.toast("刻印圣典不足，无法上下换路")
		return
	_transitioning = true
	world.paused = true
	if world._camp_camera:
		hud.close_page()
		await _play_player_transfer(false)
	room_loading.begin(str(destination.get("Name", destination.get("name", "下一关"))))
	await get_tree().process_frame
	var path = world.asset_path("environments", destination.get("environment_id", destination.get("stage_id", "")))
	if path.is_empty() or not ResourceLoader.exists(path):
		room_loading.finish()
		_transitioning = false
		_route()
		hud.toast("关卡资源缺失，无法进入")
		return
	var prepared: Resource
	if not path.is_empty() and ResourceLoader.exists(path):
		var error = ResourceLoader.load_threaded_request(path)
		if error != OK:
			room_loading.finish()
			_transitioning = false
			_route()
			hud.toast("关卡加载失败，请重试")
			return
		var progress: Array = []
		while ResourceLoader.load_threaded_get_status(path, progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			room_loading.set_progress(float(progress[0]) * 0.8 if not progress.is_empty() else 0.1)
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			prepared = ResourceLoader.load_threaded_get(path)
		else:
			room_loading.finish()
			_transitioning = false
			_route()
			hud.toast("关卡加载失败，请重试")
			return
	room_loading.set_progress(0.85)
	world.release_environment()
	await get_tree().process_frame
	_enter_node(id)
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		room_loading.set_progress(0.95)
		await get_tree().process_frame
	room_loading.set_progress(1.0)
	await get_tree().process_frame
	room_loading.finish()
	await _play_player_transfer(true)
	_transitioning = false
	world.paused = hud.modal_open
	# Hold the threaded resource until the scene has been instantiated.
	prepared = null

func _enter_node(id: int) -> void:
	var vertical = campaign.vertical_choices().any(func(room): return int(room.node_id) == id)
	if vertical and not systems.route_shift_quote().success:
		hud.toast("刻印圣典不足，无法上下换路")
		return
	var result = campaign.enter(id, vertical)
	if not result.get("success", false):
		hud.toast(str(result.get("message", "")))
		return
	if vertical: systems.consume_route_shift()
	resource_audio.play_event("route_change")
	_load_room()
	_save()

func _load_room(resume := false) -> void:
	boss_intro.finish()
	battle_tally.reset()
	_introduced_bosses.clear()
	_loading = true
	var room: Dictionary = campaign.current_room()
	_room_key = "%d:%d:%d" % [int(profile.data.run.seed), int(campaign.state.layer_index), int(room.node_id)]
	systems.ensure_map_node_increments(campaign)
	world.load_environment(int(room.get("environment_id", room.stage_id)))
	world.room_fight_type = str(room.get("FightType", "Regular"))
	world.room_spawn_points = room.get("SpawnPoints", []).duplicate(true)
	world.enemy_stage_layer = clampi(int(room.get("progress_region", room.get("region", 1))), 1, 5)
	var combat = _new_combat()
	var previous_hp = float(profile.data.run.health)
	if resume and not profile.data.run.battle.is_empty(): combat.restore(profile.data.run.battle.get("player", {}))
	else: combat.health = minf(combat.max_health, previous_hp)
	var actor = world.create_player(combat, selected_character, room.get("player_start", {}))
	if str(room.flow) == "TreasureTrial": world.trial_room.configure(world, campaign)
	world.interactions.apply_room_appearance(systems.room_environment_appearance(_room_key, room, world.interactions._items.values()))
	_equip_visual()
	if resume and profile.data.run.battle.has("position"): actor.position = DungeonWorld.vector(profile.data.run.battle.position)
	profile.data.run.current_node = int(room.node_id)
	profile.data.run.region = int(room.get("progress_region", room.region))
	profile.data.run["area_level"] = int(room.region)
	profile.data.run["region_rewards"] = []
	for row in campaign.region_map():
		if int(row.node_id) == int(campaign.state.get("selected_slot", 0)):
			profile.data.run.region_rewards = row.get("extra_rewards", []).duplicate(true)
	resource_audio.enter_environment(int(room.region), false)
	if not resume:
		profile.data.run.counters["run:total_depth"] = int(profile.data.run.counters.get("run:total_depth", campaign.state.get("visited", []).size())) + 1
	hud.close_page()
	hud.set_adventure_mode(true)
	if resume: actor.invulnerability = maxf(0, float(profile.data.run.battle.get("invulnerability", 0)))
	if room.get("combat", false) and campaign.state.phase == "room":
		if resume and profile.data.run.battle.has("enemies"):
			for saved_enemy in profile.data.run.battle.enemies:
				world.spawn_wave([{"enemy_id": int(saved_enemy.id), "position": saved_enemy.position, "combat_snapshot": saved_enemy.combat}], difficulty, int(profile.data.run.seed))
				var enemy = world.actors.back()
				if enemy.combat.health <= 0: enemy.dead = true
			world.fighting = true
			world.room_stage = "fighting"
			world._wave_reported = false
			world.elapsed = float(profile.data.run.battle.get("elapsed", 0))
			world.received_hits = int(profile.data.run.battle.get("received_hits", 0))
			for unit in world.actors:
				if not unit.is_player: _introduced_bosses[str(unit.combat.actor_key)] = true
			var bindings: Dictionary = {}
			for unit in world.actors: bindings[str(unit.combat.actor_key)] = unit.combat
			for unit in world.actors:
				for key in unit.combat.rebind_buff_casters(bindings): world._diagnostic("Unresolved saved caster: " + str(key))
		else: world.arm_room_encounter(room.enemies, difficulty, int(profile.data.run.seed), int(campaign.state.wave_count) == 1)
	else:
		world.prepare_noncombat_gate(str(room.flow), campaign.state.phase == "reward")
		hud.toast("%s" % str(room.name))
	if resume:
		battle_tally.restore(profile.data.run.battle.get("tally", {}))
		world.restore_transients(profile.data.run.battle.get("transients", {}))
		if profile.data.run.battle.has("environment"): world.interactions.restore(profile.data.run.battle.environment)
		world.elapsed = float(profile.data.run.battle.get("elapsed", 0))
		world.received_hits = int(profile.data.run.battle.get("received_hits", 0))
	_restore_curse_altars()
	world.ground_loot.sync_source_altars(world.interactions, _room_key)
	world.interactions.set_exit_enabled(campaign.state.phase == "reward" or not room.get("combat", false))
	world.interactions.set_completion_chests_enabled(campaign.state.phase == "reward" or not room.get("combat", false))
	world.sync_room_gates()
	if str(room.flow) == "TreasureTrial": world.trial_room.sync()
	if not resume and systems.has_method("record_node_entry_effects"):
		systems.record_node_entry_resources(_room_key, str(room.node_type))
		systems.record_node_entry_effects(_room_key, str(room.node_type))
		combat.notify_gameplay("message", {"event_type": "EnterNode", "room_key": _room_key})
	_apply_growth()
	if room.get("combat", false):
		var enemy_ids: Array = []
		for wave in range(int(campaign.state.waves_cleared) + 1, int(campaign.state.wave_count) + 1):
			for spawn in campaign.wave_spawns(wave):
				var enemy_id = int(spawn.get("enemy_id", spawn.get("EnemyId", 0)))
				if not enemy_ids.has(enemy_id): enemy_ids.append(enemy_id)
		world.prepare_enemy_media(enemy_ids)
	_loading = false
	_play_music(int(room.region), false)
	if combat.health <= 0:
		actor.dead = true
		actor.collision_layer = 0
		actor.play_animation("death")
		_player_defeated()
	if not actor.dead and not _transitioning and (not resume or (room.get("combat", false) and campaign.state.phase == "room")):
		_prepare_loaded_combat(str(room.name), not resume)

func _prepare_loaded_combat(title: String, arrival := false) -> void:
	_transitioning = true
	world.paused = true
	room_loading.begin(title)
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await get_tree().process_frame
	await world.prepare_feedback_rendering()
	room_loading.finish()
	if arrival: await _play_player_transfer(true)
	_transitioning = false
	world.paused = hud.modal_open

func _play_player_transfer(arrival: bool) -> void:
	world.clear_input()
	if world.player_transfer.begin(world.player, arrival, world.presentation.media, world.presentation.texture_cache, world.low_effects):
		await world.player_transfer.finished

func _skill(slot: int, pressed: bool) -> void:
	if hud.modal_open or _transitioning or boss_intro.active: return
	var result = world.use_skill(slot, pressed)
	if slot > 1 and pressed and not result.get("success", false):
		resource_audio.play_event("skill_unavailable")
		hud.toast(str(result.get("message", "能量不足或冷却中")))

func _record_run_impact(impact: Dictionary) -> void:
	if not is_instance_valid(world.player): return
	var before = battle_tally.damage
	battle_tally.record(impact, str(world.player.combat.actor_key))
	var dealt = battle_tally.damage - before
	if not profile.data.run.active or dealt <= 0: return
	var counters: Dictionary = profile.data.run.counters
	counters["run:damage"] = float(counters.get("run:damage", 0)) + dealt
	counters["run:max_damage"] = maxf(float(counters.get("run:max_damage", 0)), dealt)

func _update_battle_presentation(delta: float) -> void:
	var target: DungeonActor
	for actor in world.actors:
		if is_instance_valid(actor) and not actor.dead and actor.combat.enemy.get("rank", "") == "Boss":
			target = actor
			break
	var name_text := ""
	if target:
		name_text = menus.name_of(catalog.find("EnemyData", target.actor_id))
		var key := str(target.combat.actor_key)
		if profile.data.run.active and not world.paused and not _introduced_bosses.has(key):
			_introduced_bosses[key] = true
			boss_intro.begin(world, target, name_text)
	battle_tally.advance(delta, world.fighting and not world.paused and not world._background)
	hud.battle_readout.visible = profile.data.run.active and not hud.modal_open and not _transitioning and not boss_intro.active and not _flow_locked()
	hud.battle_readout.update_values(battle_tally, target, name_text)
	hud.battle_readout.update_enemies(world.actors, world.camera, delta if not world.paused else 0.0)

func _enemy_defeated(enemy_id: int) -> void:
	systems.record_kill(enemy_id, 0)
	if str(catalog.find("EnemyData", enemy_id).get("enemy_rate", "")) == "Boss":
		systems.record_boss_rating(enemy_id, 3 if world.received_hits == 0 else 1)
	_save()

func _wave_cleared() -> void:
	if _flow_locked() or not profile.data.run.active: return
	campaign.clear_wave()
	if campaign.room_ready(): world.begin_room_clear()
	else:
		world.start_wave(campaign.wave_spawns(int(campaign.state.waves_cleared) + 1), difficulty, int(profile.data.run.seed), float(catalog.config.get("DefaultEnemySpawnDelay", 1.0)), int(campaign.state.waves_cleared) + 1 == int(campaign.state.wave_count))
		hud.toast("下一波敌人出现")
	_save()

func _finish_room() -> void:
	if campaign.state.phase != "room": return
	var room = campaign.current_room()
	if room.get("combat", false) and world.room_stage in ["entry", "protection", "fighting", "clearing"]: return
	var result = campaign.complete_room(world.elapsed, world.received_hits, 100)
	if not result.get("success", false): return
	world.fighting = false
	resource_audio.play_event("room_victory")
	if not room.get("combat", false):
		world.room_stage = "open"
		world.sync_room_gates()
	world.interactions.set_exit_enabled(world.room_stage != "rewards")
	world.interactions.set_completion_chests_enabled(true)
	if str(room.flow) == "Treasure" and not profile.data.run.counters.get("world_treasure:" + _room_key, false): _drop_treasure(world.player.position + Vector3(1.5, 0, 0))
	systems.complete_node(_room_key, int(room.node_id), int(room.get("progress_region", room.region)), str(room.flow) == "Boss", str(room.node_type))
	systems.claim_node_materials(_room_key, int(room.get("progress_region", room.region)), str(room.flow) == "Boss")
	if world.ground_loot.source_altars.is_empty() and systems.room_node_increments(_room_key, room).has("13008"):
		var key = "altar:" + _room_key
		world.ground_loot.spawn_altar(world.player.position + Vector3(-2.0, 0, 0), key)
	_save()
	hud.close_page()
	hud.toast("房间已完成，可拾取战利品后继续前进")

func _finish_noncombat() -> void:
	if str(campaign.current_room().get("flow", "")) == "TreasureTrial":
		if not campaign.decline_trial().success: return
		_finish_room()
		return
	if str(campaign.current_room().get("flow", "")) == "Curse" and not profile.data.run.counters.get("old_day:chosen:" + _room_key, false): return
	campaign.resolve_action()
	_finish_room()

func _leave_room(confirmed := false) -> void:
	if _transitioning or not profile.data.run.active or world.player.dead: return
	if world.room_stage in ["entry", "protection", "fighting", "clearing", "rewards", "opening", "event_locked"]: return
	if campaign.state.get("phase", "") != "reward": return
	_exit_after_reward = true
	if not systems.pending_character_talent_reward().is_empty():
		_talent_rewards()
		return
	if not profile.data.run.rewards.is_empty():
		_rewards()
		return
	if not confirmed:
		var unclaimed = world.ground_loot.entries.filter(func(entry): return not entry.material).size()
		var unopened := 0
		for item in world.interactions._items.values():
			if str(item.marker.get("Type", "")) == "EEUT_AbilityItemTreasureBox" and int(item.data.get("TreasureId", 0)) == 1 and not item.state.opened: unopened += 1
		if unclaimed > 0 or unopened > 0:
			var details: PackedStringArray = []
			if unclaimed > 0: details.append("还有 %d 件物品未拾取" % unclaimed)
			if unopened > 0: details.append("还有 %d 个宝箱未开启" % unopened)
			hud.show_page("确认离开", [menus.item("、".join(details), "离开后将无法返回拾取。", [menus.command("留在房间", "close_page"), menus.command("继续前进", "leave_unclaimed")])])
			return
	_transitioning = true
	world.paused = true
	hud.close_page()
	await _play_player_transfer(false)
	_transitioning = false
	world.ground_loot.settle_materials(systems)
	var result = campaign.advance()
	if not result.get("success", false): return
	_exit_after_reward = false
	for unit in world.summon_units:
		if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
	world.summon_units.clear()
	if campaign.state.phase == "won":
		_finish_run(true)
	else:
		_route()
	_save()

func _talent_rewards() -> void:
	var reward = systems.pending_character_talent_reward()
	if reward.is_empty():
		hud.close_page()
		return
	var rows: Array = []
	var quality = str(reward.quality)
	var grade = {"Low": "劣质", "Normal": "精致", "High": "传奇"}.get(quality, "劣质")
	var color = {"Low": Color("7cba81"), "Normal": Color("ab90db"), "High": Color("edbf58")}.get(quality, Color.WHITE)
	for value in reward.choices:
		var id = int(value)
		var talent = catalog.find("CharTalentData", id)
		var old_level = int(profile.data.run.talents.get(str(id), 0))
		var next_level = int(reward.levels[str(id)])
		var levels = DungeonCatalog.ids(talent.level_data_id_list)
		var detail = catalog.find("CharTalentLevelData", int(levels[next_level - 1]))
		var row = menus.item(menus.name_of(talent), menus.description(talent) + "\n\n" + menus.description(detail), [menus.command("选择", "choose_talent", id, str(reward.key))])
		row.merge({"icon": str(talent.get("icon_name", "")), "grade": grade, "grade_color": color, "level_text": "Lv.%d → Lv.%d" % [old_level, next_level]})
		rows.append(row)
	rows.append(menus.item("重选", "", [menus.command("重选", "refresh_talent", str(reward.key), 0, int(profile.data.run.counters.get("SelectRefreshTime", 0)) <= 0)]))
	rows.back()["presentation_role"] = "refresh"
	hud.show_page("选择本局天赋 · " + str(grade), rows, "talent")
	_save()

func _rewards(preferred_key := "") -> void:
	if not systems.pending_character_talent_reward().is_empty():
		_talent_rewards()
		return
	var rows: Array = []
	var selected_reward: Dictionary = {}
	for reward in profile.data.run.rewards:
		if not preferred_key.is_empty() and str(reward.key) != preferred_key: continue
		selected_reward = reward
		for id in reward.get("choices", []):
			var row = catalog.find("LootData", int(id))
			var ability = catalog.find("AbilityItems", int(row.get("ability_item_id", id)))
			rows.append(menus.item(menus.loot_name(int(id)), menus.description(ability), [menus.command("选择", "choose_loot", int(id), str(reward.key))]))
			rows.back()["icon"] = "loot:" + str(id)
		rows.append(menus.item("刷新", "", [menus.command("刷新", "refresh_loot", str(reward.key), 0, int(profile.data.run.counters.get("SelectRefreshTime", 0)) <= 0)]))
		rows.back()["presentation_role"] = "refresh"
		break
	if rows.is_empty():
		if _exit_after_reward: _leave_room()
		else: hud.close_page()
		return
	var altar = str(selected_reward.get("key", "")).begins_with("altar:")
	hud.show_page("请选择一个精灵" if altar else "冒险奖励", rows, "altar" if altar else "grid")

func _room_action() -> void:
	var room: Dictionary = campaign.current_room()
	var flow = str(room.get("flow", "Entrance"))
	var rows: Array = []
	if flow == "TreasureTrial":
		var trial: Dictionary = campaign.trial_status()
		if trial.phase != "choice": return
		var pipelines: Array = room.get("TrialData", {}).get("ChestWaveActionList", [])
		for index in mini(3, pipelines.size()):
			rows.append(menus.item(["普通宝箱", "精良宝箱", "豪华宝箱"][index], "%d 波陷阱" % str(pipelines[index]).split("|", false).size(), [menus.command("开启", "start_chest_trial", index)]))
		hud.show_page(str(room.name), rows)
		return
	if flow == "Curse" and campaign.state.phase == "room":
		var key = "old_day:" + _room_key
		systems.create_loot_reward(int(catalog.config.get("AbilityItemLootPoolId_OldDay", 0)), key, 3)
		_rewards(key)
		_save()
		return
	if flow == "Event" and systems.has_method("event_for_node"):
		var view = systems.event_for_node(int(room.node_id), int(profile.data.run.seed), _room_key)
		if view is Dictionary:
			rows.append(menus.item(str(view.get("name", room.name)), menus.clean(view.get("story", ""))))
			for choice in view.get("choices", []):
				rows.append(menus.item(str(choice.get("text", choice.get("name", "选择"))), "", [menus.command("选择", "event_choice", int(choice.get("id", 0)), 0, not choice.get("enabled", true))]))
	elif flow == "Shop" and systems.has_method("get_room_shop"):
		var shop = systems.get_room_shop(_room_key, int(room.get("progress_region", room.region)))
		for offer in shop.get("offers", []):
			rows.append(menus.item(menus.loot_name(int(offer.get("loot_id", 0))), "价格 %d 魔力" % int(offer.get("price", 0)), [menus.command("已售罄" if offer.get("sold", false) else "购买", "buy_room", int(offer.get("loot_id", 0)), 0, offer.get("sold", false))]))
			rows.back()["icon"] = "loot:" + str(int(offer.get("loot_id", 0)))
	else:
		if flow == "Rest" and not profile.data.run.counters.get("rest:" + _room_key, false):
			world.player.combat.health = minf(world.player.combat.max_health, world.player.combat.health + world.player.combat.max_health * 0.3)
			profile.data.run.health = world.player.combat.health
			profile.data.run.counters["rest:" + _room_key] = true
			_save()
		rows.append(menus.item(str(room.name), "", [menus.command("继续", "finish_noncombat")]))
	rows.append(menus.item("前往下一房间", "", [menus.command("继续前进", "finish_noncombat")]))
	rows.back()["presentation_role"] = "navigation"
	hud.show_page(str(room.name), rows, "shop" if flow == "Shop" else "list")

func _player_defeated() -> void:
	if not profile.data.run.active or _flow_locked(): return
	_exit_after_reward = false
	_death_pending = true
	_death_will_revive = systems.revival_count() > 0
	_revival_stage = 0
	_death_remaining = 1.5 if _death_will_revive else 2.0
	_death_camera_elapsed = 0.0
	world.begin_outcome_camera("sys_dead")
	world.paused = true
	world.player.suspended = true
	profile.data.run.health = 0.0
	_save()
	hud.show_page("正在复苏" if _death_will_revive else "冒险者倒下了", [], "outcome", {"title": "正在复苏" if _death_will_revive else "冒险者倒下了", "subtitle": "复苏宝石 × %d" % systems.revival_count() if _death_will_revive else "本次冒险结束", "portrait": catalog.find("CharData", selected_character).get("square_icon_name", ""), "pending": true})

func _flow_locked() -> bool:
	return _death_pending or not profile.data.run.get("outcome", {}).is_empty()

func _tick_death(delta: float) -> void:
	if not _death_pending or _transitioning or world._background: return
	# Keep the death pose moving while combat and player input remain suspended.
	if world.player.animation and _revival_stage != 2: world.player.animation.advance(delta)
	_death_camera_elapsed += delta
	world.tick_outcome_camera(_death_camera_elapsed, delta)
	_death_remaining -= delta
	if _death_remaining > 0: return
	if _death_will_revive:
		if _revival_stage == 0:
			_revival_stage = 1
			_death_remaining = 1.01
			hud.toast("复苏宝石 -1")
			return
		if _revival_stage == 2:
			if world.player_revival.active: return
			_death_pending = false
			world.end_outcome_camera()
			hud.close_page()
			world.paused = false
			_save()
			return
		var result = systems.revive()
		if result.success:
			world.player.dead = false
			world.player.collision_layer = 2
			world.player.velocity = Vector3.ZERO
			world.player.clear_impact_state()
			world.player.end_action_motion()
			world.player.action_time = 0.0
			_apply_growth()
			world.player.invulnerability = systems.revival_protection_seconds()
			world.player.combat.health = 0.0
			world.player.combat.revive(float(profile.data.run.health), world.player.invulnerability)
			world.player_revival.begin_action(world.player, "revival", world.presentation.media, world.presentation.texture_cache, world.low_effects)
			_revival_stage = 2
			_death_remaining = world.player_revival.duration
			_death_camera_elapsed = 0.0
			world.begin_outcome_camera("revival")
			_save()
			return
	_death_pending = false
	world.end_outcome_camera()
	_finish_run(false)

func _finish_run(victory: bool, reason := "battle") -> void:
	if not profile.data.run.active or not profile.data.run.get("outcome", {}).is_empty(): return
	resource_audio.play_event("run_victory" if victory else "run_defeat")
	_death_pending = false
	_exit_after_reward = false
	world.paused = true
	_loading = true
	world.ground_loot.settle_automatic(systems)
	var run: Dictionary = profile.data.run
	var total_depth = int(run.counters.get("run:total_depth", campaign.state.get("visited", []).size() + (1 if campaign.state.get("phase", "") == "room" else 0)))
	var work_progress = systems.advance_work_from_adventure(total_depth, int(run.region), victory, "settlement:" + str(int(run.seed)))
	run["outcome"] = {"victory": victory, "reason": reason, "stage": "share" if victory else "summary", "character_id": selected_character, "region": int(run.region), "rooms": run.completed_occurrences.size(), "revivals": int(run.counters.get("revivals:used", 0)), "materials": run.materials.duplicate(true), "experience_claimed": false}
	run.outcome["work_minutes"] = int(work_progress.get("minutes", 0))
	run.outcome["elapsed"] = float(run.counters.get("run:elapsed", 0))
	run.outcome["kills"] = int(run.counters.get("run:kills", 0))
	run.outcome["damage"] = float(run.counters.get("run:damage", 0))
	run.outcome["max_damage"] = float(run.counters.get("run:max_damage", 0))
	run.outcome["talents"] = run.talents.duplicate(true)
	run.outcome["inventory"] = run.inventory.duplicate(true)
	run.outcome.merge(systems.settlement_experience(total_depth, int(run.region), int(run.counters.get("run:kills", 0))))
	if not victory: campaign.fail()
	run.route = campaign.snapshot()
	systems.end_run(victory)
	profile.data["dialogue_state"] = {}
	_loading = false
	_save(true)
	_show_result()

func _show_result() -> void:
	var result: Dictionary = profile.data.run.get("outcome", {})
	if result.is_empty(): return
	var rewards = result.get("stage", "summary") == "rewards"
	var share = result.get("stage", "summary") == "share"
	var character: Dictionary = catalog.find("CharData", int(result.character_id))
	var materials: Dictionary = result.materials
	var context = {
		"title": "战斗胜利" if result.victory else "冒险结束" if result.get("reason", "battle") == "retreat" else "战斗失败",
		"stage": result.get("stage", "summary"), "portrait": character.get("full_icon_name", ""), "victory": result.victory,
		"button": "返回营地" if rewards else "继续" if share else "下一步", "action": "result_camp" if rewards else "result_next",
		"elapsed": result.get("elapsed", 0), "work_minutes": result.get("work_minutes", 0),
		"effective_experience": result.get("effective_experience", 0), "vouchers": result.get("vouchers", 0),
		"conversion_capacity": maxi(1, int(result.get("vouchers", 0))) * maxi(1, int(catalog.config.get("CharaUpgradeItemProvideExp", 100))),
		"talents": _result_items(result.get("talents", profile.data.run.talents), "talent"),
		"relics": _result_items(result.get("inventory", profile.data.run.inventory), "relic"),
		"rewards": _result_items(materials, "material"),
		"statistics": [["击败数量", str(int(result.get("kills", 0)))], ["总伤害", _result_number(float(result.get("damage", 0)))],
			["最大伤害", _result_number(float(result.get("max_damage", 0)))], ["获得魔力精华", str(int(materials.get("102", 0)))],
			["获得矿石素材", str(int(materials.get("103", 0)))], ["获得金币", str(int(materials.get("101", 0)))]]}
	hud.show_page("冒险结算", [], "outcome", context)
	world.paused = true

func _result_number(value: float) -> String:
	return "%.1f万" % (value / 10000.0) if value >= 10000 else str(int(value))

func _result_items(owned: Dictionary, kind: String) -> Array:
	var items: Array = []
	var keys = owned.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var id = int(key)
		var count = int(owned[key])
		if count <= 0 or (kind == "material" and id == 102): continue
		var row: Dictionary = catalog.find("CharTalentData" if kind == "talent" else "MaterialData" if kind == "material" else "AbilityItems", id)
		if row.is_empty(): continue
		var icon = str(row.get("icon_name", "")) if kind == "talent" else "sprite_materialicon_" + str(id) if kind == "material" else "sprite_abilityitemicon_" + str(id)
		if not DungeonStyle.texture(icon): icon = ("material:" if kind == "material" else "loot:") + str(id)
		items.append({"id": id, "name": DungeonCatalog.clean(DungeonCatalog.row_name(row)), "count": count,
			"icon": icon, "grade": 3 if kind == "talent" else 1 if kind == "material" else int(row.get("Rare", 1)),
			"talent": kind == "talent", "count_text": "★".repeat(mini(count, 3)) if kind == "talent" else str(count)})
	return items

func _result_next() -> void:
	var result: Dictionary = profile.data.run.get("outcome", {})
	if result.is_empty(): return
	if result.get("stage", "summary") == "share": result.stage = "summary"
	elif result.get("stage", "summary") == "summary":
		_loading = true
		systems.claim_settlement_experience()
		_loading = false
		result.stage = "rewards"
	else: return
	_save(true)
	_show_result()

func _result_camp() -> void:
	var result: Dictionary = profile.data.run.get("outcome", {})
	if result.is_empty() or result.get("stage", "summary") != "rewards": return
	profile.data.run.erase("outcome")
	_camp()
	world.paused = false
	_save(true)

func _toggle_map() -> void:
	if not profile.data.run.active or _transitioning or _flow_locked(): return
	if hud.modal_open:
		if hud.page._layout == "route": _close_page()
		return
	_route(campaign.state.get("phase", "") != "route")

func _close_page() -> void:
	if _flow_locked(): return
	if not profile.data.get("dialogue_state", {}).is_empty():
		profile.data.dialogue_state = {}
		_save(true)
	hud.close_page()
	world.paused = false

func _restore_flow() -> void:
	if not profile.data.run.get("outcome", {}).is_empty():
		_camp()
		_show_result()
		return
	if not profile.data.run.active:
		_camp()
		return
	if profile.data.run.route.is_empty() or not campaign.restore(profile.data.run.route) or campaign.state.get("phase", "") not in ["room", "reward", "route"]:
		profile.data.run.active = false
		_camp()
		hud.toast("冒险路线无法恢复，已返回营地")
		_save()
		return
	if campaign.state.phase in ["room", "reward"]:
		_load_room(true)
	else:
		_camp()
		_route()

func _npc_entry(npc_id: int) -> int:
	for row in catalog.rows("NPCFunctionData"):
		if int(row.get("npc_index", 0)) == npc_id and int(row.get("entertalk_order", -1)) == 0 and row.get("func_msg_name", "") != "NpcSupportTalk":
			return int(row.id)
	return 0

func _open_npc(npc_id: int) -> void:
	if catalog.find("NPCData", npc_id).is_empty(): return
	var entry = _npc_entry(npc_id)
	var priority := 0
	for candidate in catalog.rows("NPCFunctionData"):
		if int(candidate.get("npc_index", 0)) != npc_id: continue
		if profile.data.run.active and candidate.get("func_msg_name", "") == "NpcSupportTalk":
			if systems.npc_function_status(int(candidate.id)).success:
				entry = int(candidate.id)
				break
		if not profile.data.run.active and int(candidate.get("entertalk_order", 0)) > priority and systems.npc_function_status(int(candidate.id)).success:
			priority = int(candidate.entertalk_order)
			entry = int(candidate.id)
	menus.current_page = "npc"
	menus.current_id = npc_id
	_start_dialogue(entry)

func _start_dialogue(function_id: int) -> void:
	var status = systems.npc_function_status(function_id)
	if not status.success:
		hud.toast(status.message)
		if not profile.data.get("dialogue_state", {}).is_empty(): _show_dialogue()
		return
	var row: Dictionary = catalog.find("NPCFunctionData", function_id)
	menus.current_page = "npc"
	menus.current_id = int(row.get("npc_index", 0))
	if str(row.get("func_msg_name", "")) == "Rogue_OpenShop":
		if profile.data.run.active: _room_action()
		else: menus.open("mall")
		return
	var seed_value = int(profile.data.run.get("seed", 0)) + systems.stat("npc:executions:" + str(function_id)) + function_id
	var lines = dialogue.read_story(str(row.get("talk_file_entry", "")), seed_value)
	profile.data["dialogue_state"] = {"function_id": function_id, "index": -1, "lines": lines, "stage": "story"}
	_next_dialogue()

func _skip_dialogue() -> void:
	var state: Dictionary = profile.data.get("dialogue_state", {})
	if state.is_empty() or state.get("stage", "story") != "story": return
	state.index = state.get("lines", []).size()
	_next_dialogue()

func _next_dialogue() -> void:
	var state: Dictionary = profile.data.get("dialogue_state", {})
	if state.is_empty() or state.get("stage", "story") != "story": return
	state.index = int(state.index) + 1
	var function_id = int(state.function_id)
	if int(state.index) < state.lines.size():
		_show_dialogue()
		_save()
		return
	profile.data.dialogue_state = {}
	var result = systems.execute_npc_function(function_id)
	hud.toast(str(result.get("message", "")))
	_apply_growth()
	var row: Dictionary = catalog.find("NPCFunctionData", function_id)
	if str(row.get("func_msg_name", "")) == "NpcSupportTalk" and result.success:
		var rows: Array = []
		for offer in systems.npc_support_offer(function_id).get("offers", []):
			rows.append(menus.item(menus.loot_name(int(offer.loot_id)), "", [menus.command("选择", "op:claim_npc_support", function_id, int(offer.loot_id), offer.get("sold", false))]))
			rows.back()["icon"] = "loot:" + str(int(offer.loot_id))
		hud.show_page("冒险支援", rows)
	else:
		var label = menus.clean(row.get("btn_name", ""))
		if "再见" in label or "下次一定" in label:
			_close_page()
		else:
			_show_npc_choices(int(row.get("npc_index", 0)), function_id, state.get("lines", []))
	_save(true)

func _npc_choices(npc_id: int, function_id: int) -> Array:
	var choices: Array = []
	var services = {1000: ["公会支援表", "talents"], 1100: ["打造武器", "weapons"], 1200: ["战利品图鉴", "archive"], 1300: ["委托板", "tasks"], 2200: ["据点建设", "buildings"]}
	if not profile.data.run.active and services.has(npc_id):
		var service: Array = services[npc_id]
		choices.append(menus.command(service[0], "page:" + service[1]))
	var row: Dictionary = catalog.find("NPCFunctionData", function_id)
	var next_ids = DungeonCatalog.ids(row.get("next_func_id_array", ""))
	if next_ids.is_empty(): next_ids = DungeonCatalog.ids(catalog.find("NPCFunctionData", _npc_entry(npc_id)).get("next_func_id_array", ""))
	for next_id in next_ids:
		if not systems.npc_function_status(next_id).success: continue
		var next = catalog.find("NPCFunctionData", next_id)
		var label = menus.clean(next.get("btn_name", "交谈"))
		if "再见" in label or "下次一定" in label: continue
		var count = {"MainCityTreasureBoxGacha": 1, "MainCityTreasureBoxGacha5": 5, "MainCityTreasureBoxGacha50": 50, "MainCityTreasureBoxGacha300": 300}.get(next.get("func_msg_name", ""), 0)
		if count > 0:
			var box = catalog.find("ShopTreasureBoxData", int(catalog.config.get("StoreTreasureBoxId", 0)))
			label = "开启%d次 · 金币%d" % [count, int(box.get("price", 0)) * count]
		if "初次对话" in label: label = "初次见面"
		choices.append(menus.command(label, "op:execute_npc_function", next_id))
	choices.append(menus.command("再见", "close_page"))
	return choices

func _show_npc_choices(npc_id: int, function_id: int, lines: Array = []) -> void:
	profile.data.dialogue_state = {"function_id": function_id, "npc_id": npc_id, "stage": "choices", "lines": lines, "index": maxi(0, lines.size() - 1)}
	_show_dialogue()

func _show_dialogue() -> void:
	var state: Dictionary = profile.data.get("dialogue_state", {})
	if state.is_empty(): return
	var index = int(state.get("index", -1))
	var choosing = state.get("stage", "story") == "choices"
	if not choosing and (index < 0 or index >= state.get("lines", []).size()): return
	var line: Dictionary = state.lines[index] if index >= 0 and index < state.get("lines", []).size() else {}
	var function_id = int(state.get("function_id", 0))
	var npc_id = int(catalog.find("NPCFunctionData", function_id).get("npc_index", state.get("npc_id", 0)))
	var npc = catalog.find("NPCData", npc_id)
	var author = str(line.get("AuthorId", ""))
	if author.is_empty() or DungeonStyle.texture("characterillustration_" + author + "_normal") == null:
		var greeting = dialogue.read_story(str(catalog.find("NPCFunctionData", _npc_entry(npc_id)).get("talk_file_entry", "")), npc_id)
		if not greeting.is_empty(): author = str(greeting[0].get("AuthorId", ""))
	var choices = _npc_choices(npc_id, function_id) if choosing else []
	var context = {"speaker": str(line.get("Speaker", npc.get("name", ""))), "text": menus.clean(line.get("Text", npc.get("title", ""))), "portrait": "characterillustration_" + author + "_normal", "npc_id": npc_id, "choices": choices, "can_skip": not choosing}
	hud.show_page(context.speaker, [], "dialogue", context)
	world.paused = true

func _apply_growth() -> void:
	if not world or not world.player: return
	if systems.has_method("attributes"): world.player.combat.set_external_attributes(systems.attributes(selected_character))
	_bind_progression(world.player.combat)
	_drain_buffs()
	if profile.data.run.active:
		world.player.combat.health = clampf(float(profile.data.run.health), 0, world.player.combat.max_health)
		world.player.combat.armor = maxf(0, float(profile.data.run.armor))

func _bind_progression(combat: RefCounted) -> void:
	if systems.has_method("progression_buff_bindings"):
		var binding: Dictionary = systems.progression_buff_bindings(selected_character)
		combat.set_progression_buffs(binding.get("roots", []), binding.get("externally_counted_numeric_ids", []))

func _equip_visual() -> void:
	if not world or not world.player: return
	var entry: Dictionary = world.catalog.get("characters", {}).get(str(selected_character), {})
	world.player.equip_weapon(world.asset_path("weapons", selected_weapon), str(entry.get("weapon_socket", "dummy_hand_r")))

func _drain_buffs() -> void:
	var queue: Array = profile.data.run.counters.get("combat_buff_queue", [])
	for buff in queue: world.player.combat.add_buff(str(buff.id), int(buff.get("layers", 1)))
	queue.clear()

func _on_changed() -> void:
	if not _loading: _apply_growth()
	if _save_queued or _loading: return
	_save_queued = true

func _deferred_save() -> void:
	_save()

func _save(immediate := false) -> bool:
	if not profile: return false
	_save_queued = true
	if immediate:
		_capture_save()
		return save_store.flush()
	return true

func _capture_save() -> void:
	var before := Time.get_ticks_usec()
	_save_queued = false
	_save_delay = 0.0
	_build_save_snapshot()
	save_store.request_save(profile.data)
	last_snapshot_ms = (Time.get_ticks_usec() - before) / 1000.0

func _build_save_snapshot() -> bool:
	if not profile: return false
	profile.data.selected_character = selected_character
	profile.data.selected_weapon = selected_weapon
	profile.data.selected_difficulty = difficulty
	if profile.data.run.active and campaign and not campaign.state.is_empty():
		profile.data.run.route = campaign.snapshot()
		if world and world.player:
			var actor = world.player
			profile.data.run.health = maxf(0, actor.combat.health)
			profile.data.run.max_health = actor.combat.max_health
			profile.data.run.armor = actor.combat.armor
			if campaign.state.get("phase", "") == "route": return true
			var enemies: Array = []
			for enemy in world.actors:
				if is_instance_valid(enemy) and not enemy.is_player and not enemy.dead:
					enemies.append({"id": enemy.actor_id, "position": [enemy.position.x, enemy.position.y, enemy.position.z], "combat": enemy.combat.snapshot()})
			profile.data.run.battle = {"player": actor.combat.snapshot(), "invulnerability": actor.invulnerability, "position": [actor.position.x, actor.position.y, actor.position.z], "enemies": enemies, "elapsed": world.elapsed, "received_hits": world.received_hits, "transients": world.transient_snapshot(), "environment": world.interactions.snapshot() if world.interactions else {}}
			profile.data.run.battle["tally"] = battle_tally.snapshot()
	return true

func _notification(what: int) -> void:
	if _initializing: return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		_save(true)

func _exit_tree() -> void:
	if _initializing: return
	if profile and is_instance_valid(world) and is_instance_valid(world.player): _save(true)
	else: save_store.flush()

func _play_music(region: int, camp: bool) -> void:
	resource_audio.play_music(region, camp)

func _environment_action(kind: String, context: Dictionary) -> void:
	if _transitioning or _flow_locked(): return
	match kind:
		"trial_wave":
			hud.toast("试炼 %d / %d" % [int(context.wave), int(context.total)])
			_save()
		"trial_complete": _finish_chest_trial()
		"auto_loot":
			resource_audio.play_event("pickup_coin" if context.get("coin", false) else "pickup_material")
			_save()
		"npc": menus.open("npc", int(context.get("npc_id", 0)))
		"transition":
			if world.room_stage in ["entry", "protection", "fighting", "clearing", "rewards", "opening", "event_locked"] or world.fighting: hud.toast("通道尚未开放")
			elif not profile.data.run.active: menus.open("difficulty")
			elif campaign.state.phase == "route": _route()
			elif campaign.state.phase == "reward": _leave_room()
			elif not campaign.current_room().get("combat", false):
				if str(campaign.current_room().get("flow", "")) == "TreasureTrial":
					_finish_noncombat()
					_leave_room()
					return
				if str(campaign.current_room().get("flow", "")) in ["Entrance", "Shop", "Treasure", "Rest", "Event"]:
					_finish_noncombat()
					_leave_room()
				else: _room_action()
		"reward":
			if context.get("data", {}).has("TrialChestIndex"):
				_start_chest_trial(int(context.data.TrialChestIndex))
				return
			if context.get("sprites_altar", false):
				_request_spirit_altar(context)
				return
			if context.get("destroyable_reward", false):
				_claim_destroyable(context)
				return
			var ids: Array = context.get("drop_item_ids", [])
			var counts: Array = context.get("drop_item_counts", [])
			var point: Vector3 = context.get("position", world.player.position)
			for index in ids.size(): world.ground_loot.spawn(int(ids[index]), point + Vector3(index * 0.6, 0, 0), int(counts[index]) if index < counts.size() else 1, true)
			if str(context.get("type", "")) == "EEUT_AbilityItemTreasureBox" and profile.data.run.active:
				var key = "chest:" + _room_key + ":" + str(context.get("marker_id", ""))
				if not profile.data.run.counters.get(key, false):
					resource_audio.play_event("chest_open")
					profile.data.run.counters[key] = true
					profile.data.run.counters["world_treasure:" + _room_key] = true
					_drop_treasure(point, str(context.get("data", {}).get("TreasureType", "Normal")), int(context.get("data", {}).get("TreasureId", 1)))
			_save()

func _start_chest_trial(chest_index: int) -> void:
	if not is_instance_valid(world.player) or world.player.dead: return
	profile.data.run.health = world.player.combat.health
	var result: Dictionary = systems.start_chest_trial(campaign, chest_index)
	if not result.success:
		hud.toast(str(result.message))
		return
	hud.close_page()
	resource_audio.play_event("chest_open")
	world.trial_room.sync()
	_save()
	if campaign.trial_status().skipped:
		hud.toast("遗物使陷阱失效")
		_finish_chest_trial()
	else: _prepare_loaded_combat(str(campaign.current_room().name))

func _finish_chest_trial() -> void:
	if not is_instance_valid(world.player) or world.player.dead: return
	profile.data.run.health = world.player.combat.health
	var result: Dictionary = systems.claim_chest_trial_reward(campaign)
	if not result.success: return
	var point: Vector3 = world.trial_room.reward_position()
	for index in result.drops.size():
		var drop: Dictionary = result.drops[index]
		var angle = index * TAU / maxi(1, result.drops.size())
		world.ground_loot.spawn(int(drop.id), point + Vector3(cos(angle), 0, sin(angle)) * 0.9, int(drop.amount), bool(drop.material))
	world.trial_room.finish()
	_finish_room()

func _restore_curse_altars() -> void:
	if not profile.data.run.active: return
	for item in world.interactions._items.values():
		if not DungeonWorldInteractions._is_curse_altar(item): continue
		if profile.data.run.counters.get("curse_altar:" + _room_key + ":" + str(item.id), false): world.interactions.set_curse_altar_consumed(str(item.id))

func _request_curse_altar(context: Dictionary) -> void:
	if not profile.data.run.active or _transitioning or _flow_locked() or not is_instance_valid(world.player) or world.player.dead: return
	var marker_id := str(context.get("marker_id", ""))
	var item: Dictionary = world.interactions._items.get(marker_id, {})
	if item.is_empty() or not DungeonWorldInteractions._is_curse_altar(item) or not item.state.enabled: return
	var key := "curse_altar:" + _room_key + ":" + marker_id
	if profile.data.run.counters.get(key, false):
		world.interactions.set_curse_altar_consumed(marker_id)
		return
	if item.state.used: return
	var reward_index: int = profile.data.run.rewards.size()
	systems.effects.instant({"AddAttribute1": "SelectLootRemainCount_Curse", "AddAttributeValue1": 1})
	if profile.data.run.rewards.size() <= reward_index: return
	var reward: Dictionary = profile.data.run.rewards[reward_index]
	if reward.choices.is_empty():
		profile.data.run.rewards.remove_at(reward_index)
		hud.toast("没有可选的诅咒遗物")
		return
	reward.key = key
	profile.data.run.counters[key] = true
	profile.data.run.counters["SelectLootRemainCount_Curse"] = int(profile.data.run.counters.get("SelectLootRemainCount_Curse", 0)) + 1
	world.interactions.set_curse_altar_consumed(marker_id)
	_save()
	_rewards(key)

func _request_spirit_altar(context: Dictionary) -> void:
	if not profile.data.run.active: return
	var marker_id := str(context.get("marker_id", ""))
	var key := str(context.get("key", "altar:" + _room_key + ":" + marker_id))
	var created_key := "altar-created:" + key
	var choices: Array = []
	for reward in profile.data.run.rewards:
		if str(reward.key) == key: choices = reward.choices
	if choices.is_empty() and profile.data.run.counters.get(created_key, false): return
	if choices.is_empty():
		var count := maxi(1, 3 + int(systems.attributes().get("BlessingPlusSelectExtraCount", 0)))
		choices = systems.create_loot_reward(int(catalog.config.get("AbilityItemLootPoolId_Sprites", 30301)), key, count)
		if choices.is_empty(): choices = systems.create_loot_reward(int(catalog.config.get("AbilityItemLootGuaranteedPoolId_Sprites", 20112)), key, count)
		if choices.is_empty(): return
		profile.data.run.counters[created_key] = true
		profile.data.run.counters["SelectLootRemainCount_Sprites"] = int(profile.data.run.counters.get("SelectLootRemainCount_Sprites", 0)) + 1
	if not marker_id.is_empty(): world.interactions.set_altar_consumed(marker_id)
	else: world.ground_loot.remove_altar(key)
	_save()
	_rewards(key)

func _claim_destroyable(context: Dictionary) -> void:
	if not profile.data.run.active: return
	var key := "destroyable:" + _room_key + ":" + str(context.get("marker_id", ""))
	if profile.data.run.counters.get(key, false): return
	profile.data.run.counters[key] = true
	var drops: Array = preload("res://scripts/domain/breakable_rewards.gd").new(systems).destroyable(str(context.get("config_id", "")), systems.attributes())
	var point := DungeonWorld.vector(context.get("position", world.player.position))
	for index in drops.size():
		var drop: Dictionary = drops[index]
		if drop.has("counter"):
			var counter := str(drop.counter)
			profile.data.run.counters[counter] = int(profile.data.run.counters.get(counter, 0)) + int(drop.amount)
		elif drop.get("direct", false):
			systems.grant_material(int(drop.id), int(drop.amount))
			world.show_material_gain(point, int(drop.id), int(drop.amount))
		else:
			world.ground_loot.spawn(int(drop.id), point + Vector3(index * 0.35, 0, 0), int(drop.amount), bool(drop.material))
	_save()

func _drop_treasure(point: Vector3, quality := "Normal", treasure_id := 1) -> void:
	var drops = systems.treasure_drops(quality, treasure_id, int(campaign.current_room().get("FirstOrFinal", 0)) == 1)
	for index in drops.size():
		var drop: Dictionary = drops[index]
		var angle: float = index * TAU / maxi(1, drops.size())
		world.ground_loot.spawn(int(drop.id), point + Vector3(cos(angle), 0, sin(angle)) * 0.9, int(drop.amount), bool(drop.material))

func _smoke_begin() -> void:
	hud.close_page()
	if not profile.data.run.active: _primary()
	if campaign.state.phase == "route":
		if bool(campaign.state.get("region_selection", false)):
			var regions = campaign.region_choices()
			if not regions.is_empty(): campaign.select_region(int(regions[0].node_id))
		var options = campaign.choices()
		if not options.is_empty(): _enter_node(int(options[0].node_id))
	if not campaign.current_room().get("combat", false):
		_finish_noncombat()
		_action("next", 0, 0)
		if campaign.state.phase == "reward": _action("leave_unclaimed", 0, 0)
		if campaign.state.phase == "route":
			for option in campaign.choices():
				if option.get("combat", false):
					_enter_node(int(option.node_id))
					break
	hud.close_page()

func _smoke_end() -> void:
	_smoke = false
	_save(true)
	var report = {"engine": Engine.get_version_info(), "frames": Engine.get_frames_drawn(), "character": selected_character, "actors": world.actors.size(), "enemy_count": world._enemy_count(), "defeated": world.defeated_count, "health": world.player.combat.health, "room": campaign.current_room().get("node_id", 0), "display": DisplayServer.get_name(), "visual_loaded": world.player.visual_loaded, "weapon_loaded": is_instance_valid(world.player.weapon), "position": [world.player.position.x, world.player.position.y, world.player.position.z], "collisions": world.collision_report, "save_exists": FileAccess.file_exists(save_store.path), "diagnostics": world.diagnostics}
	report["wall_seconds"] = (Time.get_ticks_usec() - _wall_start) / 1000000.0
	report["peak_process_ms"] = _peak_process * 1000
	report["peak_physics_ms"] = _peak_physics * 1000
	report["renderer"] = RenderingServer.get_video_adapter_name()
	var file = FileAccess.open(_smoke_output.path_join("runtime-smoke.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	if not _capture_path.is_empty() and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(_capture_path)
	print("DUNGEON_SMOKE ", JSON.stringify(report))
	get_tree().quit()
