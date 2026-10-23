extends Node

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
var _save_queued := false
var _loading := false
var _transitioning := false
var _exit_after_reward := false
var room_loading: CanvasLayer
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
const DEFAULT_KEYS = {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "skill": [KEY_SPACE], "dodge": [KEY_SHIFT], "burst": [KEY_Q], "heavy": [KEY_R], "pause_game": [KEY_ESCAPE], "interact": [KEY_E]}

func _ready() -> void:
	var arguments = OS.get_cmdline_user_args()
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
		get_tree().quit(2)
		return
	profile = load("res://scripts/domain/profile.gd").new()
	dialogue.load_all()
	var saved = {} if _smoke else save_store.load_profile()
	if not saved.is_empty(): profile.data = saved
	_configure_input()
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
	hud = DungeonHud.new()
	add_child(hud)
	room_loading = preload("res://scripts/presentation/room_loading.gd").new()
	add_child(room_loading)
	world.hud = hud
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
	world.environment_action.connect(_environment_action)
	world.world_message.connect(func(message, context):
		if message == "camp_page":
			if context.page == "primary": _primary()
			else: menus.open(str(context.page))
		else: hud.toast(message))
	audio = AudioStreamPlayer.new()
	audio.volume_db = -15
	add_child(audio)
	_apply_settings()
	if profile.data.run.active and not profile.data.run.route.is_empty() and campaign.restore(profile.data.run.route):
		if campaign.state.phase in ["room", "reward"]: _load_room(true)
		else:
			_camp()
			_route()
	else: _camp()
	if not profile.data.get("dialogue_state", {}).is_empty(): _show_dialogue()
	if not save_store.warning.is_empty(): hud.toast(save_store.warning)
	if _smoke: _smoke_begin.call_deferred()

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
	world.auto_attack_enabled = bool(profile.data.get("auto_attack", true))
	world.camera_shake_enabled = bool(profile.data.get("camera_shake", true))
	world.low_effects = bool(profile.data.get("low_effects", false))
	world.presentation.audio_enabled = bool(profile.data.get("audio_enabled", true))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(profile.data.get("volume", 1.0)))))
	audio.stream_paused = not profile.data.get("audio_enabled", true)

func _input(event: InputEvent) -> void:
	if _transitioning: return
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
	if _transitioning: return
	if event.is_action_pressed("pause_game"):
		if ads.busy():
			ads.cancel()
			get_viewport().set_input_as_handled()
			return
		if hud.modal_open:
			_exit_after_reward = false
			hud.close_page()
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
			_rewards(str(entry.altar))
			return
		var magic_before = systems.material(102)
		var rewards_before = profile.data.run.rewards.size()
		var result = world.ground_loot.pickup(world.player.position, systems)
		hud.toast(menus.clean(result.message))
		if result.success:
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
	if not world or not world.player: return
	world.paused = hud.modal_open or _transitioning
	var combat = world.player.combat
	if profile.data.run.active:
		profile.data.run.health = maxf(0, combat.health)
		profile.data.run.max_health = combat.max_health
		profile.data.run.armor = combat.armor
		if systems.effects and not world.paused:
			systems.effects.advance(delta)
		_drain_buffs()
	autosave_time += delta
	if autosave_time >= 10:
		autosave_time = 0
		_save()
	var room: Dictionary = campaign.current_room() if profile.data.run.active else {}
	var title = str(room.get("name", "冒险者营地"))
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
		hud.primary.icon = DungeonStyle.texture(str(prompt[2]))
		hud.primary.add_theme_color_override("font_color", Color("74d8ff") if nearby.marker.get("Type", "") == "EEUT_AbilityItemTreasureBox" else DungeonStyle.GOLD)
	hud.show_pickup(loot, systems, hud.modal_open)
	hud.objective_guide.update_target(world, hud.modal_open or not profile.data.run.active or world.fighting)
	world.update_event_markers(not profile.data.run.active)
	hud.readiness_suspended = world.paused or world._background or hud.modal_open
	hud.low_effects = world.low_effects
	hud.update_combat(combat, not profile.data.run.active)
	for slot in hud.skill_buttons.size(): hud.skill_buttons[slot].queued = int(world.intent.pending.get("slot", -1)) == slot
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
	_loading = true
	world.load_environment(10000, true)
	world.create_player(_new_combat(), selected_character)
	_equip_visual()
	hud.close_page()
	active_page = ""
	_loading = false
	_play_music("maincity")

func _action(kind: String, id: Variant, extra: Variant) -> void:
	if _transitioning: return
	if kind == "close_page":
		_exit_after_reward = false
		if ads.busy(): ads.cancel()
		else: hud.close_page()
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
		if method in ["start_work", "cook_meal", "buy_room_offer", "choose_loot_reward", "resolve_event", "claim_npc_support"]: args.append(extra)
		if not systems.has_method(method):
			push_error("Missing UI operation: " + method)
			hud.toast("操作暂不可用")
			return
		var result = systems.callv(method, args)
		if result is Dictionary: hud.toast(str(result.get("message", "")))
		_apply_growth()
		menus.open(menus.current_page, menus.current_id)
		return
	match kind:
		"talk_next": _next_dialogue()
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
				difficulty = clampi(int(id), 0, 10)
				_save()
				menus.open("difficulty")
		"enter_node": _select_node(int(id))
		"auto_route":
			profile.data["auto_route"] = bool(id)
			_save()
			if bool(id) and campaign.state.get("phase", "") == "route" and campaign.choices().size() == 1 and (campaign.vertical_choices().is_empty() or not systems.route_shift_quote().success): _route()
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
			_apply_growth()
			if result.success and str(extra).begins_with("altar:"):
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
			_apply_growth()
			_save()
			if not systems.pending_character_talent_reward().is_empty(): _talent_rewards()
			elif _exit_after_reward: _leave_room()
			else: hud.close_page()
		"refresh_talent":
			hud.toast(str(systems.refresh_character_talent_reward(str(id)).message))
			_talent_rewards()
		"revive":
			var result = systems.revive()
			if result.get("success", false):
				world.player.dead = false
				world.player.collision_layer = 2
				_apply_growth()
				world.player.combat.health = float(profile.data.run.health)
				world.player.invulnerability = 2
				hud.close_page()
			else: hud.toast(str(result.get("message", "")))
		"retreat":
			if profile.data.run.active:
				world.ground_loot.settle_automatic(systems)
				systems.end_run(false)
				campaign.fail()
			_camp()
			_save()
		"save":
			hud.toast("进度已保存" if _save() else save_store.warning)
		"toggle_audio":
			profile.data["audio_enabled"] = not profile.data.get("audio_enabled", true)
			audio.stream_paused = not profile.data.audio_enabled
			world.presentation.audio_enabled = bool(profile.data.audio_enabled)
			_save()
		"volume":
			profile.data["volume"] = clampf(float(id), 0, 1)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, profile.data.volume)))
			_save()
		"auto_attack":
			profile.data["auto_attack"] = bool(id)
			world.auto_attack_enabled = bool(id)
			_save()
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
			_save()
			get_tree().quit()

func _primary() -> void:
	if not profile.data.run.active:
		_exit_after_reward = false
		var seed_value = 12345 if _smoke else int(Time.get_unix_time_from_system()) & 0x7fffffff
		var combat = _new_combat()
		var result = systems.begin_run(seed_value, selected_character, combat.max_health, difficulty)
		if not result.get("success", false):
			hud.toast(str(result.get("message", "")))
			return
		campaign.generate(seed_value, difficulty)
		_route()
		_save()
	elif world.player.dead: _player_defeated()
	elif campaign.state.phase == "route": _route()
	elif campaign.state.phase == "reward": _leave_room()
	elif campaign.room_ready(): _finish_room()
	elif not campaign.current_room().get("combat", false): _room_action()

func _route() -> void:
	var choices = campaign.choices()
	if choices.is_empty(): return
	var shift: Dictionary = systems.route_shift_quote()
	if bool(profile.data.get("auto_route", false)) and choices.size() == 1 and (campaign.vertical_choices().is_empty() or not shift.success):
		_select_node(int(choices[0].node_id))
		return
	var map: Array = campaign.route_map(true)
	var rows: Array = []
	for column in campaign.state.get("layers", []).size():
		var layer: Dictionary = campaign.state.layers[column]
		for room in map:
			if int(room.layer_index) != column: continue
			var node_id = int(room.node_id)
			var identity = column * 100000000 + int(node_id)
			var active = bool(room.available) or (bool(room.vertical) and bool(shift.success))
			var row = menus.item(str(room.get("Name", "")), "区域 %d" % int(room.Region), [menus.command("进入" if active else "已通过" if layer.complete else "未到达", "enter_node", int(node_id), 0, not active)])
			row.merge(room)
			row["available"] = active
			row["shift_cost"] = int(shift.cost)
			row["config_id"] = identity
			row["column"] = column
			row["icon"] = "menu_store" if room.Flow == "Shop" else "interaction_quest" if room.Flow in ["Event", "Curse"] else "menu_portal" if room.Flow == "Entrance" else "skill_attack"
			rows.append(row)
	var character = catalog.find("CharData", selected_character)
	hud.show_page("选择路线", rows, "route", {"first_layer": 0, "current_layer": int(campaign.state.layer_index), "portrait": character.get("square_icon_name", ""), "character": menus.name_of(character), "magic": systems.material(102), "search": shift.remaining, "search_max": shift.maximum, "shift_available": shift.success, "automatic": profile.data.get("auto_route", false)})

func _select_node(id: int) -> void:
	if _transitioning or campaign.state.get("phase", "") != "route": return
	var destination: Dictionary = {}
	for choice in campaign.choices() + campaign.vertical_choices():
		if int(choice.node_id) == id: destination = choice
	if destination.is_empty(): return
	if destination.get("vertical", false) and not systems.route_shift_quote().success:
		hud.toast("刻印圣典不足，无法上下换路")
		return
	_transitioning = true
	world.paused = true
	room_loading.begin(str(destination.get("Name", destination.get("name", "下一关"))))
	await get_tree().process_frame
	var path = world.asset_path("environments", destination.get("environment_id", destination.get("stage_id", "")))
	if path.is_empty(): path = str(world.catalog.get("defaults", {}).get("environment", ""))
	var prepared: Resource
	if not path.is_empty() and ResourceLoader.exists(path):
		var error = ResourceLoader.load_threaded_request(path)
		if error != OK:
			room_loading.finish()
			_transitioning = false
			world.paused = hud.modal_open
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
			world.paused = hud.modal_open
			hud.toast("关卡加载失败，请重试")
			return
	room_loading.set_progress(0.85)
	await get_tree().create_timer(0.3).timeout
	_enter_node(id)
	room_loading.set_progress(1.0)
	await get_tree().process_frame
	room_loading.finish()
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
	_load_room()
	_save()

func _load_room(resume := false) -> void:
	_loading = true
	var room: Dictionary = campaign.current_room()
	_room_key = "%d:%d:%d" % [int(profile.data.run.seed), int(campaign.state.layer_index), int(room.node_id)]
	world.load_environment(int(room.get("environment_id", room.stage_id)))
	var combat = _new_combat()
	var previous_hp = float(profile.data.run.health)
	if resume and not profile.data.run.battle.is_empty(): combat.restore(profile.data.run.battle.get("player", {}))
	else: combat.health = minf(combat.max_health, previous_hp)
	var actor = world.create_player(combat, selected_character, room.get("player_start", {}))
	_equip_visual()
	if resume and profile.data.run.battle.has("position"): actor.position = DungeonWorld.vector(profile.data.run.battle.position)
	profile.data.run.current_node = int(room.node_id)
	profile.data.run.region = int(room.region)
	hud.close_page()
	if room.get("combat", false) and campaign.state.phase == "room":
		if resume and profile.data.run.battle.has("enemies"):
			for saved_enemy in profile.data.run.battle.enemies:
				world.spawn_wave([{"enemy_id": int(saved_enemy.id), "position": saved_enemy.position}], difficulty, int(profile.data.run.seed))
				var enemy = world.actors.back()
				enemy.combat.restore(saved_enemy.combat)
				if enemy.combat.health <= 0: enemy.dead = true
			world.fighting = true
			world._wave_reported = false
			world.elapsed = float(profile.data.run.battle.get("elapsed", 0))
			world.received_hits = int(profile.data.run.battle.get("received_hits", 0))
			var bindings: Dictionary = {}
			for unit in world.actors: bindings[str(unit.combat.actor_key)] = unit.combat
			for unit in world.actors:
				for key in unit.combat.rebind_buff_casters(bindings): world._diagnostic("Unresolved saved caster: " + str(key))
		else: world.spawn_wave(room.enemies, difficulty, int(profile.data.run.seed))
	else: hud.toast("%s" % str(room.name))
	if resume:
		world.restore_transients(profile.data.run.battle.get("transients", {}))
		if profile.data.run.battle.has("environment"): world.interactions.restore(profile.data.run.battle.environment)
		world.elapsed = float(profile.data.run.battle.get("elapsed", 0))
		world.received_hits = int(profile.data.run.battle.get("received_hits", 0))
	world.interactions.set_exit_enabled(campaign.state.phase == "reward" or not room.get("combat", false))
	world.interactions.set_completion_chests_enabled(campaign.state.phase == "reward" or not room.get("combat", false))
	if not resume and systems.has_method("record_node_entry_effects"):
		systems.record_node_entry_resources(_room_key, str(room.node_type))
		systems.record_node_entry_effects(_room_key, str(room.node_type))
		combat.notify_gameplay("message", {"event_type": "EnterNode", "room_key": _room_key})
	_apply_growth()
	_loading = false
	_play_music("forest" if int(room.region) == 1 else "battle")

func _skill(slot: int, pressed: bool) -> void:
	if hud.modal_open: return
	var result = world.use_skill(slot, pressed)
	if slot > 1 and pressed and not result.get("success", false):
		hud.toast(str(result.get("message", "能量不足或冷却中")))

func _enemy_defeated(enemy_id: int) -> void:
	systems.record_kill(enemy_id, 0)
	if str(catalog.find("EnemyData", enemy_id).get("enemy_rate", "")) == "Boss":
		systems.record_boss_rating(enemy_id, 3 if world.received_hits == 0 else 1)
	_save()

func _wave_cleared() -> void:
	campaign.clear_wave()
	if campaign.room_ready(): _finish_room()
	else:
		world.spawn_wave(campaign.wave_spawns(int(campaign.state.waves_cleared) + 1), difficulty, int(profile.data.run.seed))
		hud.toast("下一波敌人出现")
	_save()

func _finish_room() -> void:
	if campaign.state.phase != "room": return
	var room = campaign.current_room()
	var result = campaign.complete_room(world.elapsed, world.received_hits, 100)
	if not result.get("success", false): return
	world.fighting = false
	world.interactions.set_exit_enabled(true)
	world.interactions.set_completion_chests_enabled(true)
	if str(room.flow) == "Treasure" and not profile.data.run.counters.get("world_treasure:" + _room_key, false): _drop_treasure(world.player.position + Vector3(1.5, 0, 0))
	systems.complete_node(_room_key, int(room.node_id), int(room.region), str(room.flow) == "Boss", str(room.node_type))
	systems.claim_node_materials(_room_key, int(room.region), str(room.flow) == "Boss")
	var altar_chance = int(catalog.config.get("IncrementRandomAppearChanceDic", {}).get("SpritesAltar", 350))
	if "SpritesAltar" in str(room.get("IncrementOptions", "")) and systems.next_random(1000) < altar_chance:
		var key = "altar:" + _room_key
		if not systems.create_loot_reward(int(catalog.config.AbilityItemLootPoolId_Sprites), key, 3).is_empty():
			world.ground_loot.spawn_altar(world.player.position + Vector3(-2.0, 0, 0), key)
	_save()
	hud.close_page()
	hud.toast("房间已完成，可拾取战利品后继续前进")

func _finish_noncombat() -> void:
	campaign.resolve_action()
	_finish_room()

func _leave_room(confirmed := false) -> void:
	if _transitioning or not profile.data.run.active or world.player.dead: return
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
	world.ground_loot.settle_materials(systems)
	var previous_region = int(campaign.current_room().get("region", 0))
	var chapter_end = int(campaign.current_room().get("FirstOrFinal", 0)) == 2
	var result = campaign.advance()
	if not result.get("success", false): return
	_exit_after_reward = false
	for unit in world.summon_units:
		if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
	world.summon_units.clear()
	if campaign.state.phase == "won":
		systems.end_run(true)
		_camp()
		hud.toast("冒险胜利！")
	else:
		var choices = campaign.choices()
		if chapter_end and not choices.is_empty() and int(choices[0].get("region", 0)) > previous_region:
			_select_node(int(choices[0].node_id))
		else: _route()
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
	if flow in ["Event", "Curse"] and systems.has_method("event_for_node"):
		var view = systems.event_for_node(int(room.node_id), int(profile.data.run.seed), _room_key)
		if view is Dictionary:
			rows.append(menus.item(str(view.get("name", room.name)), menus.clean(view.get("story", ""))))
			for choice in view.get("choices", []):
				rows.append(menus.item(str(choice.get("text", choice.get("name", "选择"))), "", [menus.command("选择", "event_choice", int(choice.get("id", 0)), 0, not choice.get("enabled", true))]))
	elif flow == "Shop" and systems.has_method("get_room_shop"):
		var shop = systems.get_room_shop(_room_key, int(room.region))
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
	_save()
	hud.show_page("冒险者倒下了", [menus.item("复苏", "", [menus.command("使用复苏宝石", "revive")]), menus.item("返回营地", "", [menus.command("结束本次冒险", "retreat")])])

func _start_dialogue(function_id: int) -> void:
	var status = systems.npc_function_status(function_id)
	if not status.success:
		hud.toast(status.message)
		return
	var row: Dictionary = catalog.find("NPCFunctionData", function_id)
	if str(row.get("func_msg_name", "")) == "Rogue_OpenShop":
		if profile.data.run.active: _room_action()
		else: menus.open("mall")
		return
	var seed_value = int(profile.data.run.get("seed", 0)) + systems.stat("npc:executions:" + str(function_id)) + function_id
	var lines = dialogue.read_story(str(row.get("talk_file_entry", "")), seed_value)
	profile.data["dialogue_state"] = {"function_id": function_id, "index": -1, "lines": lines}
	_next_dialogue()

func _next_dialogue() -> void:
	var state: Dictionary = profile.data.get("dialogue_state", {})
	if state.is_empty(): return
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
		var rows: Array = []
		for next_id in DungeonCatalog.ids(row.get("next_func_id_array", "")):
			var next: Dictionary = catalog.find("NPCFunctionData", next_id)
			var status = systems.npc_function_status(next_id)
			if status.get("success", false): rows.append(menus.item(str(next.get("btn_name", "")), "", [menus.command("交谈", "op:execute_npc_function", next_id)]))
		if rows.is_empty(): menus.open("npc", int(row.get("npc_index", 0)))
		else: hud.show_page(menus.name_of(catalog.find("NPCData", int(row.get("npc_index", 0)))), rows)
	_save()

func _show_dialogue() -> void:
	var state: Dictionary = profile.data.get("dialogue_state", {})
	var index = int(state.get("index", -1))
	if index < 0 or index >= state.get("lines", []).size(): return
	var line: Dictionary = state.lines[index]
	hud.show_page(str(line.get("Speaker", "")), [menus.item("", menus.clean(line.get("Text", "")), [menus.command("继续", "talk_next")])])

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
	_deferred_save.call_deferred()

func _deferred_save() -> void:
	_save_queued = false
	_save()

func _save() -> bool:
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
			var enemies: Array = []
			for enemy in world.actors:
				if is_instance_valid(enemy) and not enemy.is_player and not enemy.dead:
					enemies.append({"id": enemy.actor_id, "position": [enemy.position.x, enemy.position.y, enemy.position.z], "combat": enemy.combat.snapshot()})
			profile.data.run.battle = {"player": actor.combat.snapshot(), "position": [actor.position.x, actor.position.y, actor.position.z], "enemies": enemies, "elapsed": world.elapsed, "received_hits": world.received_hits, "transients": world.transient_snapshot(), "environment": world.interactions.snapshot() if world.interactions else {}}
	return save_store.save(profile.data)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		_save()

func _play_music(token: String) -> void:
	if not audio or not profile.data.get("audio_enabled", true): return
	var source: Dictionary = world.catalog.get("audio", {})
	for key in source:
		if token in str(key).to_lower() and ("bgm" in str(key).to_lower() or "music" in str(key).to_lower()):
			var stream = load(str(source[key]))
			if stream is AudioStream:
				audio.stream = stream
				audio.play()
				return

func _environment_action(kind: String, context: Dictionary) -> void:
	match kind:
		"auto_loot": _save()
		"npc": menus.open("npc", int(context.get("npc_id", 0)))
		"transition":
			if world.fighting: hud.toast("击败敌人后开放通道")
			elif not profile.data.run.active: _primary()
			elif campaign.state.phase == "route": _route()
			elif campaign.state.phase == "reward": _leave_room()
			elif not campaign.current_room().get("combat", false):
				if str(campaign.current_room().get("flow", "")) in ["Entrance", "Shop", "Treasure"]:
					_finish_noncombat()
					_leave_room()
				else: _room_action()
		"reward":
			var ids: Array = context.get("drop_item_ids", [])
			var counts: Array = context.get("drop_item_counts", [])
			var point: Vector3 = context.get("position", world.player.position)
			for index in ids.size(): world.ground_loot.spawn(int(ids[index]), point + Vector3(index * 0.6, 0, 0), int(counts[index]) if index < counts.size() else 1, true)
			if str(context.get("type", "")) == "EEUT_AbilityItemTreasureBox" and profile.data.run.active:
				var key = "chest:" + _room_key + ":" + str(context.get("marker_id", ""))
				if not profile.data.run.counters.get(key, false):
					profile.data.run.counters[key] = true
					profile.data.run.counters["world_treasure:" + _room_key] = true
					_drop_treasure(point, str(context.get("data", {}).get("TreasureType", "Normal")), int(context.get("data", {}).get("TreasureId", 1)))
			_save()

func _drop_treasure(point: Vector3, quality := "Normal", treasure_id := 1) -> void:
	if quality not in ["Normal", "Unusual", "Luxury", "Curse", "Curse_Final"]: quality = "Normal"
	var chance = int(catalog.config.get(quality + "TreasureBoxDropSelectCharaItemChance", 0))
	var scroll_allowed = treasure_id == 1 and int(campaign.current_room().get("FirstOrFinal", 0)) != 1
	if scroll_allowed and systems.next_random(1000) < chance:
		var scroll = int(catalog.config.get("AbilityItem_CharaTalentItem_Super" if quality == "Curse" else "AbilityItem_CharaTalentItem_Normal", 13103 if quality == "Curse" else 13102))
		world.ground_loot.spawn(scroll, point + Vector3(1.1, 0, 0))
	var rewards: Dictionary = catalog.config.get("TreasureBoxResDropData_" + quality, {})
	for field in ["GoldData", "MagicPointData", "MineralData"]:
		var reward: Dictionary = rewards.get(field, {})
		if systems.next_random(1000) >= int(reward.get("DropChance", 0)): continue
		var base = int(reward.get("DropBase", 0))
		var spread = int(reward.get("DropRandomFactor", 0))
		var amount = maxi(1, roundi(base * (1.0 + (systems.next_random(spread * 2 + 1) - spread) / 1000.0)))
		world.ground_loot.spawn(int(reward.DropMaterialType), point + Vector3(-0.7, 0, 0.7 * rewards.keys().find(field)), amount, true)

func _smoke_begin() -> void:
	hud.close_page()
	if not profile.data.run.active: _primary()
	if campaign.state.phase == "route":
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
	_save()
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
