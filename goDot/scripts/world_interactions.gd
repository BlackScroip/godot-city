class_name DungeonWorldInteractions
extends RefCounted

signal transition_requested(context: Dictionary)
signal npc_requested(npc_id: String, context: Dictionary)
signal reward_requested(context: Dictionary)
signal trap_triggered(context: Dictionary)
signal message_requested(name: String, context: Dictionary)
signal object_changed(marker_id: String, state: Dictionary)
signal diagnostic_reported(context: Dictionary)
signal effect_requested(context: Dictionary)
signal sound_requested(name: String)
signal presentation_requested(kind: String, context: Dictionary)
signal player_trigger_entered(trigger_id: int, context: Dictionary)

const RULES_PATH := "res://assets/environment_rules.json"
const AltarBillboards = preload("res://scripts/presentation/altar_billboards.gd")
const INTERACTIVE := ["EEUT_DoorController", "EEUT_StageChangeDoor", "EEUT_AbilityItemTreasureBox", "EEUT_NPC", "EEUT_Special_Trader", "EEUT_Special_GemShopMan", "EEUT_Special_MonsterWork", "EEUT_BillBoard", "EEUT_UIInteractable", "EEUT_Protal", "EEUT_ProtectTarget"]
const PASSIVE := ["EEUT_AreaInfoMarker", "EEUT_Door", "EEUT_CloseArea"]
const PHASES := ["idle", "starting", "active", "ending", "finished", "destroyed"]
const SPRITES_ALTAR := "EnvUnit_MonoData_BtnDisplayName_SpritesAltar"
const CURSE_ALTAR := "EnvUnit_MonoData_BtnDisplayName_CurseAltar"
const OLD_DAY_ALTAR := "EnvUnit_MonoData_BtnDisplayName_OldDayAltar"
const SACRIFICIAL_ALTAR := "EnvUnit_MonoData_BtnDisplayName_SacrificialAltar"
const PARTNER_SELECTOR := "EnvUnit_MonoData_BtnDisplayName_MonsterPartnerSkillSelector"
const SPRING := "EnvUnit_MonoData_BtnDisplayName_Spring"
const ADVENTURE_EVENT := "EnvUnit_MonoData_BtnDisplayName_RogueAdventureEvent"
const SPECIAL_EVENT := "EnvUnit_MonoData_BtnDisplayName_RogueAdventureEvent_Special"
const MEAL_SHOP := "EnvUnit_MonoData_BtnDisplayName_CatMeal_Shop"
const ALTAR_EGG := "sprite_abilityitemicon_14104"
const ROOM_ACTIONS := {ADVENTURE_EVENT: "冒险事件", SPECIAL_EVENT: "特殊事件", OLD_DAY_ALTAR: "旧日祭坛", CURSE_ALTAR: "诅咒祭坛", SACRIFICIAL_ALTAR: "献祭祭坛", PARTNER_SELECTOR: "伙伴技能", SPRING: "饮用泉水", MEAL_SHOP: "猫饭料理"}

var diagnostics: Array[Dictionary] = []
var scene := ""
var _root: Node3D
var _services: Dictionary = {}
var _items: Dictionary = {}
var _nodes: Dictionary = {}
var _bindings: Dictionary = {}
var _definitions: Dictionary = {}
var _fingerprint := ""
var _diagnostic_keys: Dictionary = {}

func setup(environment_root: Node3D, markers: Array, services: Dictionary = {}) -> void:
	_root = environment_root
	_services = services
	_items.clear()
	_nodes.clear()
	_bindings.clear()
	_definitions.clear()
	diagnostics.clear()
	_diagnostic_keys.clear()
	scene = str(services.get("scene", markers[0].get("SceneName", "") if not markers.is_empty() else ""))
	_index_nodes(_root)
	var rules: Dictionary = services.get("rules", {})
	if rules.is_empty() and FileAccess.file_exists(RULES_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		if parsed is Dictionary: rules = parsed
	for binding in rules.get("Bindings", []):
		_bindings[str(binding.SceneName) + ":" + str(binding.SourceGameObjectId)] = binding
	for definition in rules.get("Definitions", []):
		_definitions[str(definition.ID)] = definition
	var identities: Array = []
	for marker in markers:
		var id := str(marker.get("SourceGameObjectId", ""))
		if id.is_empty() or _items.has(id):
			_diagnose(id, "invalid_identity", "Missing or duplicate source GameObject identity")
			continue
		var data = JSON.parse_string(str(marker.get("DataJson", "{}")))
		if not data is Dictionary:
			_diagnose(id, "invalid_data", "Marker DataJson is not an object")
			data = {}
		var binding: Dictionary = _bindings.get(scene + ":" + id, {})
		var definition: Dictionary = _definitions.get(str(binding.get("ConfigId", "")), {})
		var item := {"id": id, "marker": marker, "data": data, "binding": binding, "definition": definition,
			"visual": _nodes.get(str(marker.get("exported_node_name", ""))), "colliders": [], "bodies": [],
			"position": _vector(marker.get("world_position", [])), "visible": true,
			"state": {"enabled": bool(data.get("InitActive", data.get("IsInitStateActive", true))), "opened": false,
				"used": false, "broken": false, "breaking": false, "hp": maxf(0, float(definition.get("Durablity", 0))),
				"break_remaining": 0.0, "phase": "idle", "phase_time": 0.0, "idle_remaining": maxf(0, float(binding.get("FirstTriggerDelayTime", 0))),
				"cycle": 0, "hits_once": {}, "hit_cooldowns": {}, "inside": false, "talk_delay": maxf(0, float(data.get("FirstTriggerDelayTime", 0)))}}
		if is_instance_valid(item.visual): item.visible = item.visual.visible
		else: _diagnose(id, "missing_visual", "Exported node identity is absent")
		if str(marker.get("Type", "")) == "EEUT_CloseArea": item.state.enabled = false
		if str(marker.get("Type", "")) == "EEUT_ProtectTarget": item.state.enabled = false
		item["effect_states"] = {}
		item["altar_eggs"] = []
		item["curse_parts"] = []
		if is_instance_valid(item.visual) and (_is_sprites_altar(item) or str(data.get("UIBtnName", "")) in [CURSE_ALTAR, OLD_DAY_ALTAR, SACRIFICIAL_ALTAR]):
			for node in item.visual.find_children("*", "Node3D", true, false):
				if str(node.name) == ALTAR_EGG or str(node.name).begins_with(ALTAR_EGG + "_u") or str(node.name).begins_with(ALTAR_EGG + "__u"):
					AltarBillboards.restore(node, str(data.get("UIBtnName", "")))
					item.altar_eggs.append({"node": node, "visible": node.visible})
		if is_instance_valid(item.visual) and _is_choice_altar(item):
			for node in item.visual.find_children("*", "Node3D", true, false):
				for part in ["Box_BillBoard", "Box_Effect", "Box_TiggerEnter"]:
					if str(node.name) == part or str(node.name).begins_with(part + "_u") or str(node.name).begins_with(part + "__u"):
						item.curse_parts.append({"node": node, "visible": node.visible})
		if is_instance_valid(item.visual) and str(data.get("UIBtnName", "")) == SPRING:
			for node in item.visual.find_children("*", "Node3D", true, false):
				for part in ["24041501_fx_env_healingwater_symbol", "Box_TiggerEnter"]:
					if str(node.name) == part or str(node.name).begins_with(part + "_"):
						item.curse_parts.append({"node": node, "visible": node.visible})
		if is_instance_valid(item.visual) and str(marker.get("Type", "")) == "EEUT_DoorController":
			for node in item.visual.find_children("*", "Node3D", true, false):
				for address in ["24040301_fx_env_switch_on", "24040301_fx_env_switch_off"]:
					if str(node.name) == address or str(node.name).begins_with(address + "_u"):
						item.effect_states[address] = node
		var path := scene + "/" + "/".join(marker.get("Path", []))
		for collider in services.get("colliders", []):
			var collider_path := str(collider.get("path", ""))
			if collider_path != path and not collider_path.begins_with(path + "/"): continue
			item.colliders.append(collider)
			var body = _nodes.get("Collider_" + str(collider.get("fileID", "")))
			if body is CollisionObject3D: item.bodies.append({"node": body, "layer": body.collision_layer, "mask": body.collision_mask})
		_items[id] = item
		identities.append([id, str(marker.get("Type", "")), data, str(binding.get("ConfigId", ""))])
		_validate_binding(item)
		_apply(item)
	_fingerprint = JSON.stringify([scene, identities]).sha256_text()

func _index_nodes(node: Node) -> void:
	if not is_instance_valid(node): return
	_nodes[str(node.name)] = node
	for child in node.get_children(): _index_nodes(child)

func _validate_binding(item: Dictionary) -> void:
	var kind := str(item.marker.get("Type", ""))
	if kind in ["EEUT_DestoryableItem", "EEUT_TriggerTrap"]:
		if item.definition.is_empty() or str(item.definition.get("Type", "")) != kind or not item.binding.get("SupportsRules", false):
			item.state.enabled = false
			_diagnose(item.id, "missing_config", "No exact source ResId binding for " + kind)
		var gate := str(item.binding.get("CheckDisplayUnlockDataId", ""))
		if not gate.is_empty():
			var predicate = _services.get("is_unlocked")
			if predicate is Callable: item.state.enabled = bool(predicate.call(gate))
			else:
				item.state.enabled = false
				_diagnose(item.id, "missing_unlock_adapter", gate)
		if kind == "EEUT_TriggerTrap":
			for role in ["Container_EnterTrigger", "Container_EffectTrigger"]:
				if _volumes(item, role).is_empty(): _diagnose(item.id, "missing_volume", role)
	elif kind in ["EEUT_NPC", "EEUT_Special_Trader", "EEUT_Special_GemShopMan"]:
		var npc_id := str(item.data.get("NpcId", ""))
		var catalog = _services.get("catalog")
		if npc_id.is_empty(): _diagnose(item.id, "missing_npc_id", "No configured NPC identity")
		elif catalog == null or not catalog.has_method("find") or catalog.find("NPCData", npc_id).is_empty():
			_diagnose(item.id, "missing_npc_config", npc_id)
	elif kind == "EEUT_UIInteractable":
		if not _is_sprites_altar(item) and not CAMP_ACTIONS.has(str(item.data.get("UIBtnName", ""))) and not ROOM_ACTIONS.has(str(item.data.get("UIBtnName", ""))): _diagnose(item.id, "missing_message_binding", str(item.data.get("UIBtnName", "")))
	elif kind not in INTERACTIVE and kind not in PASSIVE and kind not in ["EEUT_PlayerTrigger", "EEUT_SimpleTalkTrigger"]:
		_diagnose(item.id, "unsupported_marker", kind)

func interact_nearest(position: Vector3, radius: float = 3.0) -> Dictionary:
	var nearest := nearest_interaction(position, radius)
	if nearest.is_empty(): return {"success": false, "reason": "no_interaction"}
	return interact(str(nearest.id))

func nearest_interaction(position: Vector3, radius: float = 3.0) -> Dictionary:
	var candidates := available_interactions(position, radius)
	return candidates[0] if not candidates.is_empty() else {}

func is_interaction_available(item: Dictionary) -> bool:
	if item.is_empty() or not item.state.enabled or item.state.broken or item.state.phase == "destroyed" or item.marker.get("Type", "") not in INTERACTIVE: return false
	if item.state.opened or (item.state.used and not item.data.get("CanRepeatDeactive", false)): return false
	var kind := str(item.marker.get("Type", ""))
	if kind == "EEUT_StageChangeDoor" and float(item.state.idle_remaining) > 0: return false
	if kind in ["EEUT_NPC", "EEUT_Special_Trader", "EEUT_Special_GemShopMan"]:
		var catalog = _services.get("catalog")
		var npc_id := str(item.data.get("NpcId", ""))
		if npc_id.is_empty() or catalog == null or not catalog.has_method("find") or catalog.find("NPCData", npc_id).is_empty(): return false
	if kind == "EEUT_UIInteractable" and not _is_sprites_altar(item) and not CAMP_ACTIONS.has(str(item.data.get("UIBtnName", ""))) and not ROOM_ACTIONS.has(str(item.data.get("UIBtnName", ""))): return false
	return true

func can_interact_at(marker_id: String, position: Vector3, radius: float = 3.0) -> bool:
	if not position.is_finite() or not is_finite(radius) or radius < 0: return false
	var item: Dictionary = _items.get(marker_id, {})
	if not is_interaction_available(item): return false
	var kind := str(item.marker.get("Type", ""))
	if bool(_services.get("camp", false)):
		var role := "Box_TriggerArea" if kind == "EEUT_BillBoard" else "Box_TiggerEnter"
		if not _volumes(item, role).is_empty():
			# Camp triggers extend down to the feet, including the sunken work stone.
			return _contains(item, position + Vector3.UP * 0.35, 0.35, role)
	if kind == "EEUT_UIInteractable" and ROOM_ACTIONS.has(str(item.data.get("UIBtnName", ""))) and not _volumes(item, "Box_TiggerEnter").is_empty():
		return _contains(item, position + Vector3.UP * 0.8, 0.35, "Box_TiggerEnter")
	if kind == "EEUT_StageChangeDoor" and not _volumes(item, "Box_TiggerEnter").is_empty() and not _contains(item, position + Vector3.UP * 0.8, 0.35, "Box_TiggerEnter"): return false
	if kind == "EEUT_ProtectTarget" and not _contains(item, position + Vector3.UP * 0.8, 0, "Box_InteractArea"): return false
	return position.distance_to(_world_position(item.position)) <= radius

func available_interactions(position: Vector3, radius: float = 3.0) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for item in _items.values():
		if can_interact_at(str(item.id), position, radius): candidates.append(item)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		var first := position.distance_squared_to(_world_position(a.position))
		var second := position.distance_squared_to(_world_position(b.position))
		return str(a.id).naturalnocasecmp_to(str(b.id)) < 0 if is_equal_approx(first, second) else first < second)
	return candidates

const CAMP_ACTIONS := {
	"camp_training": ["训练场", "training", "sprite_conversation_Scarecrow"],
	"EnvUnit_MonoData_BtnDisplayName_ItemArchieve": ["遗物图鉴", "archive", "interaction_weapon"],
	"keyword_Records": ["冒险档案", "history", "interaction_quest"],
	"EnvUnit_MonoData_BtnDisplayName_SelectWeapon": ["选择武器", "weapons", "interaction_weapon"],
	"EnvUnit_MonoData_BtnDisplayName_MonsterPartner": ["怪物伙伴", "partners", "interaction_quest"],
	"EnvUnit_MonoData_BtnDisplayName_ChangeChara": ["选择角色", "characters", "interaction_quest"],
	"EnvUnit_MonoData_BtnDisplayName_MainCityDeveloper": ["营地建设", "buildings", "interaction_blacksmith"],
	"EnvUnit_MonoData_BtnDisplayName_Quest": ["委托板", "tasks", "sprite_conversation_mission"],
	"EnvUnit_MonoData_BtnDisplayName_CatMeal": ["猫饭料理", "meals", "interaction_quest"],
	"EnvUnit_MonoData_BtnDisplayName_StartNewRun": ["出发冒险", "primary", "interaction_weapon"],
	"EnvUnit_MonoData_BtnDisplayName_TalentTree": ["角色觉醒", "awakening", "interaction_quest"],
	"EnvUnit_MonoData_BtnDisplayName_DifficultlyLevel": ["冒险难度", "difficulty", "interaction_weapon"],
	"ATPanel_RelationshipToken_Title": ["关系信物", "tokens", "interaction_quest"],
	"Keyword_ExtraChallenge": ["悬赏委托", "extra_challenges", "sprite_conversation_Extra challenges"]}

func prompt_for(item: Dictionary) -> Array:
	var key := str(item.data.get("UIBtnName", ""))
	if _is_sprites_altar(item): return ["精灵祭坛", "", str(item.data.get("UIBtnIcon", "sprite_conversation_get"))]
	if key in [CURSE_ALTAR, OLD_DAY_ALTAR, SACRIFICIAL_ALTAR]: return [ROOM_ACTIONS[key], "", str(item.data.get("UIBtnIcon", "sprite_conversation_get"))]
	if CAMP_ACTIONS.has(key): return CAMP_ACTIONS[key]
	if ROOM_ACTIONS.has(key): return [ROOM_ACTIONS[key], "", "interaction_quest"]
	match str(item.marker.get("Type", "")):
		"EEUT_Special_MonsterWork": return ["怪物工作", "work", "sprite_conversation_monsterwork"]
		"EEUT_ProtectTarget": return ["启动守护", "", "interaction_quest"]
		"EEUT_NPC", "EEUT_Special_Trader", "EEUT_Special_GemShopMan": return ["交谈", "npc", "interaction_quest"]
		"EEUT_AbilityItemTreasureBox": return ["普通宝箱" if str(item.data.get("TreasureType", "Normal")) == "Normal" else "珍贵宝箱", "", "interaction_quest"]
		"EEUT_DoorController": return ["开启机关", "", "interaction_blacksmith"]
		"EEUT_StageChangeDoor", "EEUT_Protal": return ["进入通道", "", "interaction_weapon"]
	return ["查看告示", "", "interaction_quest"]

func interact(marker_id: String) -> Dictionary:
	var item: Dictionary = _items.get(marker_id, {})
	if item.is_empty() or not item.state.enabled or item.state.broken: return {"success": false, "reason": "unavailable"}
	var data: Dictionary = item.data
	var context := _context(item)
	match str(item.marker.get("Type", "")):
		"EEUT_Special_MonsterWork":
			context["page"] = "work"
			message_requested.emit("camp_page", context)
			return {"success": true, "context": context}
		"EEUT_ProtectTarget":
			if item.state.used: return {"success": false, "reason": "already_used"}
			item.state.used = true
			_changed(item)
			presentation_requested.emit("protect_activate", context)
			message_requested.emit("EnvUnit_InteractProtectTarget", context)
			return {"success": true, "context": context}
		"EEUT_DoorController":
			if item.state.used and not data.get("CanRepeatDeactive", false): return {"success": false, "reason": "already_used"}
			var found := 0
			for door in _items.values():
				if door.marker.get("Type", "") != "EEUT_Door" or int(door.data.get("DoorId", -1)) != int(data.get("ControllDoorId", -2)): continue
				door.state.enabled = false
				_changed(door)
				found += 1
			if found == 0:
				_diagnose(item.id, "missing_door", str(data.get("ControllDoorId", "")))
				return {"success": false, "reason": "missing_door"}
			item.state.used = true
			context["doors_opened"] = found
			context["active_anim_time_source"] = data.get("ActiveAnimTime", 0)
		"EEUT_AbilityItemTreasureBox":
			if item.state.opened: return {"success": false, "reason": "already_opened"}
			item.state.opened = true
			_changed(item)
			presentation_requested.emit("chest_open", context)
			reward_requested.emit(context)
			return {"success": true, "context": context}
		"EEUT_StageChangeDoor", "EEUT_Protal":
			if str(item.marker.get("Type", "")) == "EEUT_StageChangeDoor":
				if float(item.state.idle_remaining) > 0: return {"success": false, "reason": "interaction_cooldown"}
				item.state.idle_remaining = 0.5
			transition_requested.emit(context)
		"EEUT_NPC", "EEUT_Special_Trader", "EEUT_Special_GemShopMan":
			var npc_id := str(data.get("NpcId", ""))
			var catalog = _services.get("catalog")
			if npc_id.is_empty() or catalog == null or not catalog.has_method("find") or catalog.find("NPCData", npc_id).is_empty():
				return {"success": false, "reason": "missing_npc_config"}
			npc_requested.emit(npc_id, context)
		"EEUT_BillBoard": message_requested.emit(str(data.get("Text", "")), context)
		"EEUT_UIInteractable":
			if ROOM_ACTIONS.has(str(data.get("UIBtnName", ""))):
				if item.state.used: return {"success": false, "reason": "already_used"}
				message_requested.emit("room_action", context)
				return {"success": true, "context": context}
			if _is_sprites_altar(item):
				if item.state.used: return {"success": false, "reason": "already_used"}
				context["sprites_altar"] = true
				reward_requested.emit(context)
				return {"success": true, "context": context}
			if CAMP_ACTIONS.has(str(data.get("UIBtnName", ""))):
				context["page"] = CAMP_ACTIONS[str(data.UIBtnName)][1]
				message_requested.emit("camp_page", context)
				return {"success": true, "context": context}
			message_requested.emit(str(data.get("UIBtnName", "")), context)
			return {"success": false, "reason": "missing_message_binding", "context": context}
		_: return {"success": false, "reason": "unsupported_marker"}
	_changed(item)
	return {"success": true, "context": context}

func damage_near(position: Vector3, radius: float, amount: float, source_camp: int = 2, hit_id := "") -> Array:
	var damaged: Array = []
	if not is_finite(amount) or not is_finite(radius) or amount <= 0 or radius < 0: return damaged
	for item in _items.values():
		if item.marker.get("Type", "") != "EEUT_DestoryableItem" or not item.state.enabled or item.state.broken or item.state.breaking: continue
		if not _contains(item, position, radius, "", true): continue
		if damage_marker(str(item.id), amount, source_camp, hit_id): damaged.append(str(item.id))
	return damaged

func damage_marker(marker_id: String, acc_tenacity: float, source_camp: int = 2, hit_id := "") -> bool:
	var item: Dictionary = _items.get(marker_id, {})
	if item.is_empty() or str(item.marker.get("Type", "")) != "EEUT_DestoryableItem": return false
	if not is_finite(acc_tenacity) or int(acc_tenacity) <= 0 or not item.state.enabled or item.state.broken or item.state.breaking: return false
	var definition: Dictionary = item.definition
	if not definition.get("CanBeAttack", false) or not camp_allows(str(definition.get("CanBeAttackCamp", "")), source_camp): return false
	if not hit_id.is_empty():
		if item.state.hits_once.has(hit_id): return false
		item.state.hits_once[hit_id] = true
	# Unity HitFeedBackData_EnvUnit.AccTenacity is an integer; HP damage is independent.
	item.state.hp = maxf(0, float(item.state.hp) - int(acc_tenacity))
	_effect(item, "BeAttackEffect")
	_sound(item, "BeAttackSound")
	if item.state.hp <= 0:
		item.state.breaking = true
		item.state.break_remaining = maxf(0, float(definition.get("BreakDelayTime", 0)))
		if item.state.break_remaining > 0:
			_effect(item, "BreakDelayVfxName")
			_sound(item, "BreakDelaySoundName")
		if item.state.break_remaining <= 0: _finish_break(item)
	_changed(item)
	return true

func damage_collider(collider: CollisionObject3D, acc_tenacity: float, source_camp: int = 2, hit_id := "") -> bool:
	if not is_instance_valid(collider): return false
	for item in _items.values():
		for body in item.bodies:
			if body.node == collider: return damage_marker(str(item.id), acc_tenacity, source_camp, hit_id)
	return false

func damage_segment(from: Vector3, to: Vector3, radius: float, acc_tenacity: float, source_camp: int = 2, hit_id := "") -> Array:
	var damaged: Array = []
	if not from.is_finite() or not to.is_finite() or not is_finite(radius) or radius < 0: return damaged
	# Sample a swept hit at half-radius intervals so fast bullets cannot skip narrow pots.
	var steps := maxi(1, ceili(from.distance_to(to) / maxf(0.1, radius * 0.5)))
	for item in _items.values():
		if str(item.marker.get("Type", "")) != "EEUT_DestoryableItem" or not item.state.enabled or item.state.broken or item.state.breaking: continue
		for step in range(steps + 1):
			if not _contains(item, from.lerp(to, float(step) / steps), radius, "", true): continue
			if damage_marker(str(item.id), acc_tenacity, source_camp, hit_id): damaged.append(str(item.id))
			break
	return damaged

func tick(delta: float, player_position: Vector3, targets: Array = []) -> void:
	if not is_finite(delta) or delta <= 0: return
	var all_targets: Array = [{"id": "player", "position": player_position, "camp": 2}]
	all_targets.append_array(targets)
	var remaining := delta
	var frame_hits: Dictionary = {}
	while remaining > 0:
		var step := minf(0.02, remaining)
		remaining -= step
		for item in _items.values():
			if not item.state.enabled or item.state.broken: continue
			match str(item.marker.get("Type", "")):
				"EEUT_StageChangeDoor":
					item.state.idle_remaining = maxf(0.0, float(item.state.idle_remaining) - step)
				"EEUT_DestoryableItem":
					var touching := _contains(item, player_position + Vector3.UP * 0.8, 0.35)
					if touching and not item.state.inside:
						_effect(item, "TriggerTouchUnitPlayEffect")
						_sound(item, "TriggerTouchUnitSoundName")
					item.state.inside = touching
					if item.state.breaking:
						item.state.break_remaining = maxf(0, float(item.state.break_remaining) - step)
						if item.state.break_remaining <= 0: _finish_break(item)
				"EEUT_TriggerTrap":
					_advance_trap(item, step, _contains(item, player_position + Vector3.UP * 0.8, 0.35, "Container_EnterTrigger"))
					if item.state.phase != "active": continue
					for target in all_targets:
						if not target.get("position") is Vector3: continue
						if not _contains(item, target.position + Vector3.UP * 0.8, 0.35, "Container_EffectTrigger"): continue
						_affect(item, target, frame_hits)
				"EEUT_PlayerTrigger", "EEUT_SimpleTalkTrigger":
					item.state.talk_delay = maxf(0, float(item.state.talk_delay) - step)
					var inside := _contains(item, player_position + Vector3.UP * 0.8, 0.35)
					if inside and not item.state.inside and item.state.talk_delay <= 0:
						var name := str(item.data.get("TriggerFuncMsg_Name", "UI_PlaySimpleTalk"))
						var context := _context(item)
						if item.data.get("ActivedSwitchFalse", false): item.state.enabled = false
						item.state.used = true
						_changed(item)
						if str(item.marker.get("Type", "")) == "EEUT_PlayerTrigger":
							player_trigger_entered.emit(int(item.data.get("TriggerId", -1)), context)
						if not name.is_empty(): message_requested.emit(name, context)
					item.state.inside = inside

func _advance_trap(item: Dictionary, delta: float, inside: bool) -> void:
	var state: Dictionary = item.state
	var definition: Dictionary = item.definition
	for target_id in state.hit_cooldowns: state.hit_cooldowns[target_id] = maxf(0, float(state.hit_cooldowns[target_id]) - delta)
	var remaining := delta
	for iteration in 32:
		if state.phase in ["finished", "destroyed"]: return
		if state.phase == "idle":
			var idle_used := minf(float(state.idle_remaining), remaining)
			state.idle_remaining -= idle_used
			remaining -= idle_used
			if state.idle_remaining > 0 or (definition.get("TriggerCondition", "") != "Auto" and not inside): return
			state.phase = "starting"
			state.phase_time = 0.0
			state.cycle += 1
			state.hits_once.clear()
			state.hit_cooldowns.clear()
			_effect(item, "TriggerStartEffectName")
			_sound(item, "TriggerStartSound")
		var key := "TriggerStartTime" if state.phase == "starting" else "TriggerLastingTime" if state.phase == "active" else "TriggerEndTime"
		var duration := maxf(0, float(definition.get(key, 0)))
		var used := minf(remaining, maxf(0, duration - float(state.phase_time)))
		state.phase_time += used
		remaining -= used
		if float(state.phase_time) + 0.0000001 < duration: return
		state.phase_time = 0.0
		match str(state.phase):
			"starting":
				state.phase = "active"
				if duration == 0 or remaining <= 0: return
			"active": state.phase = "ending"
			"ending":
				match str(definition.get("TriggerEndAct", "")):
					"Destroy":
						state.phase = "destroyed"
						_changed(item)
						return
					"ResetToBeforeTrigger":
						state.phase = "idle"
						state.idle_remaining = maxf(0, float(item.binding.get("TriggerIdleTime", 0)))
					_: state.phase = "finished"
				if remaining <= 0: return
	_diagnose(item.id, "invalid_trap_cycle", "Zero-duration trap cycle exceeds transition limit")

func _affect(item: Dictionary, target: Dictionary, frame_hits: Dictionary) -> void:
	var definition: Dictionary = item.definition
	var id := str(target.get("id", ""))
	if id.is_empty() or not camp_allows(str(definition.get("TargetCampString", "")), int(target.get("camp", 0))): return
	if item.state.hits_once.get(id, false) or float(item.state.hit_cooldowns.get(id, 0)) > 0.0000001: return
	var mode := str(definition.get("TriggerTimesType", ""))
	if mode == "OnlyOncePerUnit": item.state.hits_once[id] = true
	elif mode == "CustomTimeInterval":
		var interval := float(definition.get("TriggerCustomParam1", "0"))
		if not is_finite(interval) or interval <= 0:
			_diagnose(item.id, "invalid_trap_interval", str(definition.get("TriggerCustomParam1", "")))
			return
		item.state.hit_cooldowns[id] = interval
	elif mode == "PerFrame":
		var frame_key := str(item.id) + ":" + id
		if frame_hits.has(frame_key): return
		frame_hits[frame_key] = true
	else:
		_diagnose(item.id, "unsupported_trap_mode", mode)
		return
	var buff: Dictionary = definition.get("AddBuffData", {})
	if str(buff.get("BuffTriggerId", "")).is_empty():
		_diagnose(item.id, "missing_buff", "Trap AddBuffData has no BuffTriggerId")
		return
	var context := _context(item)
	context.merge({"target_id": id, "buff_id": str(buff.BuffTriggerId), "layers": int(buff.get("BuffAddLayer", 1)), "camp_mask": definition.get("TargetCampString", ""), "cycle": item.state.cycle})
	trap_triggered.emit(context)

func _finish_break(item: Dictionary) -> void:
	if item.state.broken: return
	_effect(item, "BreakEffect", "BreakEffectPosOffset")
	_sound(item, "BreakSoundTrigger")
	item.state.broken = true
	item.state.break_remaining = 0.0
	_changed(item)
	var definition: Dictionary = item.definition
	var buff: Dictionary = definition.get("BuffTriggerDef", {})
	if definition.get("IsBoomBucket", false) and float(definition.get("TriggerEffectRadius", 0)) > 0 and not str(buff.get("BuffTriggerId", "")).is_empty():
		var context := _context(item)
		context.merge({"target_id": "", "buff_id": str(buff.BuffTriggerId), "layers": int(buff.get("BuffAddLayer", 1)), "radius": float(definition.TriggerEffectRadius), "camp_mask": str(definition.get("BoomBucketTargetCampString", "")), "explosion": true})
		trap_triggered.emit(context)
	if not definition.get("DropItemIdList", []).is_empty():
		var context := _context(item)
		context["drop_item_ids"] = definition.DropItemIdList
		context["drop_item_counts"] = definition.get("DropItemCountList", [])
		reward_requested.emit(context)
	if str(item.binding.get("ConfigId", "")).is_valid_int():
		var context := _context(item)
		context["destroyable_reward"] = true
		reward_requested.emit(context)

static func _is_sprites_altar(item: Dictionary) -> bool:
	return str(item.get("marker", {}).get("Type", "")) == "EEUT_UIInteractable" and str(item.get("data", {}).get("UIBtnName", "")) == SPRITES_ALTAR

static func _is_curse_altar(item: Dictionary) -> bool:
	return str(item.get("marker", {}).get("Type", "")) == "EEUT_UIInteractable" and str(item.get("data", {}).get("UIBtnName", "")) == CURSE_ALTAR

static func _is_choice_altar(item: Dictionary) -> bool:
	return str(item.get("marker", {}).get("Type", "")) == "EEUT_UIInteractable" and str(item.get("data", {}).get("UIBtnName", "")) in [CURSE_ALTAR, OLD_DAY_ALTAR, SACRIFICIAL_ALTAR, PARTNER_SELECTOR]

func set_room_action_consumed(marker_id: String) -> bool:
	var item: Dictionary = _items.get(marker_id, {})
	if item.is_empty() or not ROOM_ACTIONS.has(str(item.data.get("UIBtnName", ""))) or item.state.used: return false
	item.state.used = true
	_changed(item)
	return true

func set_curse_altar_consumed(marker_id: String) -> bool:
	var item: Dictionary = _items.get(marker_id, {})
	if item.is_empty() or not _is_curse_altar(item) or item.state.used: return false
	item.state.used = true
	_changed(item)
	return true

func set_altar_consumed(marker_id: String) -> bool:
	var item: Dictionary = _items.get(marker_id, {})
	if item.is_empty() or not _is_sprites_altar(item) or item.state.used: return false
	item.state.used = true
	_changed(item)
	return true

func set_trigger_active(trigger_id: int, active: bool) -> int:
	var changed := 0
	for item in _items.values():
		if str(item.marker.get("Type", "")) not in ["EEUT_PlayerTrigger", "EEUT_SimpleTalkTrigger"]: continue
		if int(item.data.get("TriggerId", -1)) != trigger_id: continue
		item.state.enabled = active
		_changed(item)
		changed += 1
	return changed

func set_battle_boundaries_active(active: bool) -> void:
	for item in _items.values():
		if str(item.marker.get("Type", "")) != "EEUT_CloseArea" or int(item.data.get("TriggerId", -1)) not in [1, 2]: continue
		item.state.enabled = active
		_changed(item)

func set_protection_enabled(active: bool) -> void:
	for item in _items.values():
		if str(item.marker.get("Type", "")) != "EEUT_ProtectTarget": continue
		item.state.enabled = active
		_changed(item)

func complete_protection() -> void:
	for item in _items.values():
		if str(item.marker.get("Type", "")) != "EEUT_ProtectTarget" or not item.state.used or item.state.phase == "destroyed": continue
		item.state.phase = "destroyed"
		item.state.enabled = false
		_changed(item)
		presentation_requested.emit("protect_complete", _context(item))

func set_exit_enabled(active: bool) -> void:
	for item in _items.values():
		if str(item.marker.get("Type", "")) not in ["EEUT_StageChangeDoor", "EEUT_Protal"]: continue
		item.state.enabled = active
		_changed(item)

func set_completion_chest_quality(quality: String) -> void:
	if quality not in ["None", "Normal", "Unusual", "Luxury", "Curse", "Curse_Final"]: return
	for item in _items.values():
		if str(item.marker.get("Type", "")) != "EEUT_AbilityItemTreasureBox" or int(item.data.get("TreasureId", 0)) != 1 or item.data.has("TrialChestIndex"): continue
		item.data["CompletionRewardAvailable"] = quality != "None"
		if quality != "None": item.data["TreasureType"] = quality
		else: item.state.enabled = false
		_changed(item)

func set_completion_chests_enabled(active: bool) -> void:
	for item in _items.values():
		if str(item.marker.get("Type", "")) != "EEUT_AbilityItemTreasureBox" or int(item.data.get("TreasureId", 0)) != 1: continue
		if item.data.has("TrialChestIndex"): continue
		item.state.enabled = active and bool(item.data.get("CompletionRewardAvailable", true))
		_changed(item)

func setup_trial_chests(side_offset: float) -> Vector3:
	for item in _items.values():
		if str(item.marker.get("Type", "")) != "EEUT_AbilityItemTreasureBox" or int(item.data.get("TreasureId", 0)) != 1: continue
		item.data["TrialChestIndex"] = 1
		item.data["TreasureType"] = "Unusual"
		for index in [0, 2]:
			var copy: Dictionary = item.duplicate(true)
			copy.id = str(item.id) + ":trial:" + str(index)
			copy.data["TrialChestIndex"] = index
			copy.data["TreasureType"] = "Normal" if index == 0 else "Luxury"
			copy.position = item.position + Vector3.RIGHT * side_offset * (index - 1)
			copy.colliders = []
			copy.bodies = []
			if is_instance_valid(item.visual):
				copy.visual = item.visual.duplicate()
				item.visual.get_parent().add_child(copy.visual)
				copy.visual.global_position = _world_position(copy.position)
			_items[copy.id] = copy
			_changed(copy)
		_changed(item)
		return _world_position(item.position)
	return Vector3.INF

func sync_trial_chests(chest_index: int) -> void:
	for item in _items.values():
		if not item.data.has("TrialChestIndex"): continue
		var selected = int(item.data.TrialChestIndex) == chest_index
		if item.state.enabled == (chest_index == -1 or selected) and item.state.opened == selected: continue
		item.state.enabled = chest_index == -1 or selected
		item.state.opened = selected
		_changed(item)

func apply_room_appearance(decisions: Dictionary) -> void:
	for id in decisions:
		if not _items.has(str(id)) or not decisions[id] is bool: continue
		var item: Dictionary = _items[str(id)]
		item.state.enabled = bool(item.state.enabled) and bool(decisions[id])
		_changed(item)

func snapshot() -> Dictionary:
	var objects: Dictionary = {}
	for id in _items: objects[id] = _items[id].state.duplicate(true)
	return {"schema": 1, "scene": scene, "fingerprint": _fingerprint, "objects": objects}

func restore(saved: Dictionary) -> bool:
	if int(saved.get("schema", 0)) != 1 or saved.get("scene", "") != scene or saved.get("fingerprint", "") != _fingerprint: return false
	var objects = saved.get("objects")
	if not objects is Dictionary or objects.size() != _items.size(): return false
	for id in _items:
		if not objects.has(id) or not _valid_state(objects[id], _items[id]): return false
	for id in _items:
		_items[id].state = objects[id].duplicate(true)
		_items[id]["chest_open_remaining"] = 0.0
		_apply(_items[id])
	return true

func _valid_state(state: Variant, item: Dictionary) -> bool:
	if not state is Dictionary or state.size() != item.state.size(): return false
	for key in ["enabled", "opened", "used", "broken", "breaking", "inside"]:
		if not state.get(key) is bool: return false
	for key in ["hp", "break_remaining", "phase_time", "idle_remaining", "talk_delay", "cycle"]:
		var value = state.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: return false
	if float(state.hp) > maxf(0, float(item.definition.get("Durablity", 0))): return false
	if (state.broken and not state.breaking) or (state.breaking and state.hp > 0): return false
	if state.get("phase", "") not in PHASES: return false
	if not state.get("hits_once") is Dictionary or not state.get("hit_cooldowns") is Dictionary: return false
	for value in state.hits_once.values():
		if not value is bool: return false
	for value in state.hit_cooldowns.values():
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: return false
	return true

func state_for(marker_id: String) -> Dictionary:
	return _items[marker_id].state.duplicate(true) if _items.has(marker_id) else {}

func _changed(item: Dictionary) -> void:
	if item.get("chest_presentation", false) and item.state.opened and is_instance_valid(item.visual) and not item.visual.get_meta("interaction_opened", false):
		item["chest_open_remaining"] = 1.25
	_apply(item)
	object_changed.emit(str(item.id), item.state.duplicate(true))

func _apply(item: Dictionary) -> void:
	var active: bool = item.state.enabled and not item.state.broken and item.state.phase != "destroyed"
	if str(item.marker.get("Type", "")) == "EEUT_AbilityItemTreasureBox" and item.state.opened:
		active = false
	if is_instance_valid(item.visual):
		item.visual.visible = bool(item.visible) and active
		if item.get("chest_open_remaining", 0.0) > 0.0 and item.state.enabled and not item.state.broken:
			item.visual.visible = bool(item.visible)
		item.visual.set_meta("interaction_opened", item.state.opened)
		if str(item.marker.get("Type", "")) == "EEUT_StageChangeDoor":
			# The source locks interaction/effects, retaining the physical doorway.
			_set_source_active(item.visual, not item.state.broken)
			item.visual.set_meta("interaction_enabled", active)
		elif str(item.marker.get("Type", "")) in ["EEUT_Protal", "EEUT_CloseArea"]:
			_set_source_active(item.visual, active)
		elif str(item.marker.get("Type", "")) == "EEUT_ProtectTarget":
			_set_source_active(item.visual, not item.state.broken)
			var completed: bool = item.state.phase == "destroyed"
			for node in item.visual.find_children("*", "Node3D", true, false):
				for prefix in ["Container_UnActive", "Container_Active", "Container_Destory"]:
					if str(node.name) == prefix or str(node.name).begins_with(prefix + "_"):
						_set_source_active(node, (not item.state.used and not completed if prefix == "Container_UnActive" else item.state.used and not completed if prefix == "Container_Active" else completed))
		elif str(item.marker.get("Type", "")) == "EEUT_DestoryableItem":
			item.visual.set_meta("unityActive", active)
	for egg in item.get("altar_eggs", []):
		if is_instance_valid(egg.node):
			_set_source_active(egg.node, active and not item.state.used and bool(egg.visible))
	for part in item.get("curse_parts", []):
		if is_instance_valid(part.node): _set_source_active(part.node, active and not item.state.used and bool(part.visible))
	for address in item.get("effect_states", {}):
		var on: bool = address == "24040301_fx_env_switch_on"
		_set_source_active(item.effect_states[address], active and (bool(item.state.used) == on))
	for body in item.bodies:
		if is_instance_valid(body.node):
			var solid: bool = not item.state.broken and item.state.phase != "destroyed" if str(item.marker.get("Type", "")) in ["EEUT_StageChangeDoor", "EEUT_ProtectTarget"] else active
			body.node.collision_layer = int(body.layer) if solid else 0
			body.node.collision_mask = int(body.mask) if solid else 0

static func _set_source_active(node: Node3D, active: bool) -> void:
	if not is_instance_valid(node): return
	node.visible = active
	node.set_meta("unityActive", active)

func _context(item: Dictionary) -> Dictionary:
	return {"marker_id": str(item.id), "scene": scene, "type": str(item.marker.get("Type", "")), "data": item.data.duplicate(true), "config_id": str(item.binding.get("ConfigId", "")), "position": _world_position(item.position), "definition": item.definition.duplicate(true)}

func _effect(item: Dictionary, field: String, offset_field := "") -> void:
	var address := str(item.definition.get(field, ""))
	if address.is_empty(): return
	var local_point: Vector3 = item.position
	if not offset_field.is_empty(): local_point += _vector(item.definition.get(offset_field, {}))
	effect_requested.emit({"address": address, "position": _world_position(local_point), "marker_id": str(item.id), "source_field": field})

func _sound(item: Dictionary, field: String) -> void:
	var value: Variant = item.definition.get(field, {})
	var name := str(value.get("SoundName", "")) if value is Dictionary else str(value)
	if not name.is_empty(): sound_requested.emit(name)

func _volumes(item: Dictionary, role: String) -> Array:
	if role.is_empty(): return item.colliders
	return item.colliders.filter(func(collider): return ("/" + str(collider.get("path", "")) + "/").contains("/" + role + "/"))

func _contains(item: Dictionary, position: Vector3, actor_radius: float = 0, role: String = "", solids_only: bool = false) -> bool:
	var local_position := _root.global_transform.affine_inverse() * position if is_instance_valid(_root) and _root.is_inside_tree() else position
	for collider in _volumes(item, role):
		var properties: Dictionary = collider.get("properties", {})
		if not collider.get("active", true) or not properties.get("m_Enabled", 1) or (solids_only and properties.get("m_IsTrigger", 0)): continue
		var matrix := _matrix(collider.get("world_matrix", []))
		if absf(matrix.basis.determinant()) < 0.00000001: continue
		var center := _vector(properties.get("m_Center", {}))
		var scale := matrix.basis.get_scale().abs()
		var point := matrix.affine_inverse() * local_position - center
		match int(collider.get("kind", 0)):
			65:
				var half := _vector(properties.get("m_Size", {})).abs() * 0.5
				var offset := (point.abs() - half).max(Vector3.ZERO) * scale
				if offset.length_squared() <= actor_radius * actor_radius: return true
			135:
				var radius := float(properties.get("m_Radius", 0)) * maxf(scale.x, maxf(scale.y, scale.z))
				if local_position.distance_to(matrix * center) <= radius + actor_radius: return true
			136:
				var axis := int(properties.get("m_Direction", 1))
				var radius := float(properties.get("m_Radius", 0)) * maxf(scale[(axis + 1) % 3], scale[(axis + 2) % 3])
				var half_length := maxf(0, float(properties.get("m_Height", 0)) * scale[axis] * 0.5 - radius)
				var world_axis := matrix.basis[axis].normalized()
				var relative := local_position - matrix * center
				if (relative - world_axis * clampf(relative.dot(world_axis), -half_length, half_length)).length() <= radius + actor_radius: return true
			64: _diagnose(item.id, "unsupported_interaction_mesh_volume", str(collider.get("fileID", "")))
	return false

func _world_position(position: Vector3) -> Vector3:
	return _root.global_transform * position if is_instance_valid(_root) and _root.is_inside_tree() else position

static func camp_allows(mask: String, camp: int) -> bool:
	if mask.length() != 3: return false
	for character in mask:
		if character not in ["0", "1"]: return false
	var slot := 0 if camp == 2 else 1 if camp == 1 else 2 if camp == 3 else -1
	return slot >= 0 and mask[slot] == "1"

static func _matrix(values: Array) -> Transform3D:
	if values.size() != 16: return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(values[0], values[4], values[8]), Vector3(values[1], values[5], values[9]), Vector3(values[2], values[6], values[10])), Vector3(values[3], values[7], values[11]))

static func _vector(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3: return Vector3(value[0], value[1], value[2])
	if value is Dictionary: return Vector3(float(value.get("x", 0)), float(value.get("y", 0)), float(value.get("z", 0)))
	return Vector3.ZERO

func _diagnose(marker_id: String, code: String, detail: String) -> void:
	var key := marker_id + ":" + code + ":" + detail
	if _diagnostic_keys.has(key): return
	_diagnostic_keys[key] = true
	var diagnostic := {"scene": scene, "marker_id": marker_id, "code": code, "detail": detail}
	diagnostics.append(diagnostic)
	diagnostic_reported.emit(diagnostic)
