class_name DungeonMenus
extends RefCounted

var game: Node
var catalog: RefCounted
var systems: RefCounted
var profile: RefCounted
var hud: DungeonHud
var current_page := "camp"
var current_id := 0
var _work_refresh := 0.0
var _work_signature := ""

func _init(host: Node) -> void:
	game = host
	catalog = host.catalog
	systems = host.systems
	profile = host.profile
	hud = host.hud

func command(text: String, action: String, id: Variant = 0, extra: Variant = 0, disabled := false) -> Dictionary:
	return {"text": text, "action": action, "id": id, "extra": extra, "disabled": disabled}

func item(title: String, description: String = "", buttons: Array = []) -> Dictionary:
	return {"title": title, "description": description, "buttons": buttons}

func name_of(row: Dictionary) -> String:
	return str(row.get("name", row.get("Name", row.get("title", row.get("GoodsName", row.get("id", ""))))))

func clean(value: Variant) -> String:
	return DungeonCatalog.clean(value)

func description(row: Dictionary) -> String:
	return clean(row.get("description", row.get("Description", row.get("effect_description", row.get("unlock_desc", "")))))

func loot_name(id: int) -> String:
	var row = catalog.find("LootData", id)
	var ability = catalog.find("AbilityItems", int(row.get("ability_item_id", id)))
	return name_of(ability) if not ability.is_empty() else str(id)

func price_text(price: Dictionary) -> String:
	return clean(systems.price_description(price))

func partner_name(id: int) -> String:
	var partner = catalog.find("MonsterPartnerData", id)
	return clean(name_of(catalog.find("EnemyData", int(partner.get("enemy_id", id)))))

func tick(delta: float) -> void:
	if not hud.modal_open or current_page != "work": return
	_work_refresh += delta
	if _work_refresh < 1.0: return
	_work_refresh = 0.0
	var states: Array = []
	for order in profile.data.work:
		var status = systems.work_status(int(order.work_id))
		states.append([order.work_id, maxi(0, ceili(float(status.get("next_claim_seconds", status.remaining_seconds)) / 60.0)), status.get("claimable_quantity", 0), status.completed_quantity, status.daily_remaining])
	var signature = str(states)
	if signature == _work_signature: return
	_work_signature = signature
	var scroll = hud.page.list_scroll.scroll_vertical
	open("work")
	hud.page.list_scroll.set_deferred("scroll_vertical", scroll)

func _camp_entry(label: String, destination: String) -> Dictionary:
	var state = systems.camp_feature_status(destination)
	var buttons = [command("查看", "page:" + destination)]
	var detail = ""
	if not state.available:
		detail = clean(state.reason)
		buttons.append(command("前往建设", "page:buildings", state.building_id))
	elif destination in ["characters", "weapons", "partners", "meals", "tasks", "archive", "awakening", "buildings", "talents", "work", "training"]:
		buttons.append(command("前往设施", "camp_navigate", destination))
	if destination == "work":
		var ready = 0
		for order in profile.data.work:
			if systems.work_status(int(order.work_id)).ready: ready += 1
		detail += "\n派遣中 %d · 可领取 %d" % [profile.data.work.size() - ready, ready]
	return item(label, detail.strip_edges(), buttons)

func _resource_routes(id: int) -> Array:
	match id:
		101: return [command("营地建设", "page:buildings"), command("委托任务", "page:tasks"), command("伙伴派遣", "page:work")]
		501, 503: return [command("角色升级", "page:characters"), command("委托任务", "page:tasks"), command("伙伴派遣", "page:work")]
		103: return [command("打造武器", "page:weapons"), command("伙伴派遣", "page:work")]
		90002: return [command("商城兑换", "page:mall"), command("出发冒险", "page:difficulty")]
		_: return [command("查看仓库", "page:storage")]

func open(page: String, id: int = 0) -> void:
	if game.resource_audio and (not hud.modal_open or current_page != page or current_id != id):
		game.resource_audio.play_event("page:" + page)
	current_page = page
	current_id = id
	if page == "npc":
		game._open_npc(id)
		return
	if not profile.data.get("dialogue_state", {}).is_empty():
		profile.data.dialogue_state = {}
		game._save(true)
	var rows: Array = []
	var title := "营地"
	match page:
		"camp":
			title = "冒险者营地"
			var entries = [["营地建设", "buildings"], ["主城装饰", "decorations"], ["资源与凭证", "resources"], ["角色", "characters"], ["武器", "weapons"], ["训练场", "training"], ["公会天赋", "talents"], ["伙伴", "partners"], ["伙伴派遣", "work"], ["猫饭料理", "meals"], ["居民与支援", "npcs"], ["觉醒", "awakening"], ["信物", "tokens"], ["增幅", "amplifiers"], ["委托任务", "tasks"], ["成就", "achievements"], ["战利品图鉴", "archive"], ["本地商城", "mall"], ["冒险难度", "difficulty"]]
			for entry in entries:
				rows.append(_camp_entry(entry[0], entry[1]))
			rows.push_front(item("继续冒险" if profile.data.run.active else "新的冒险", "", [command("继续" if profile.data.run.active else "出发", "primary" if profile.data.run.active else "page:difficulty")]))
		"training":
			title = "训练场"
			var feature = systems.camp_feature_status("training")
			var state: Dictionary = game.world.camp_training_status()
			var details = "命中 %d 次 · 总伤害 %.0f\n训练 %.1f 秒 · 每秒伤害 %.1f · 最高单次 %.0f" % [state.hits, state.total_damage, state.elapsed, state.dps, state.maximum_hit]
			var buttons: Array = []
			if state.active:
				buttons = [command("继续训练", "close_page"), command("重置统计", "reset_training"), command("结束训练", "end_training")]
			elif not feature.available:
				details += "\n" + clean(feature.reason)
				buttons = [command("前往建设", "page:buildings", 3)]
			else:
				if not str(state.reason).is_empty(): details += "\n" + str(state.reason)
				buttons = [command("前往训练场", "camp_navigate", "training"), command("开始训练", "start_training", 0, 0, not state.can_start)]
			rows.append(item("训练稻草人", details, buttons))
		"resources", "resource":
			title = "资源与凭证"
			for resource in systems.resource_summary():
				if page == "resource" and int(resource.id) != id: continue
				var details = clean(resource.description)
				if int(resource.id) == 501: details += "\n冒险结束后，结算经验也会转化为冒险凭证。"
				details += "\n累计获得 %d · 累计消耗 %d" % [resource.earned, resource.spent]
				rows.append(item("%s  ×%d" % [clean(resource.name), resource.amount], details, _resource_routes(int(resource.id))))
				rows.back()["material_id"] = int(resource.id)
			rows.append(item("仓库", "", [command("查看全部材料", "page:storage")]))
		"characters":
			title = "角色详情"
			for row in catalog.rows("CharData"):
				if row.get("available_state", "") != "Normal": continue
				var cid = int(row.id)
				if profile.data.run.active and cid != game.selected_character: continue
				var level = int(profile.data.character_levels.get(str(cid), 0))
				var buttons: Array = [command("选择" if game.selected_character != cid else "已选择", "select_character", cid, 0, level <= 0)]
				if not profile.data.run.active:
					var quote = systems.character_upgrade_status(cid)
					var recruitment = systems.character_recruit_status(cid)
					buttons.append(command("升级" if level > 0 else "招募", "op:" + ("upgrade_character" if level > 0 else "unlock_character"), cid, 0, not quote.can_upgrade if level > 0 else not recruitment.can_recruit))
				buttons.append(command("查看天赋", "page:character_talents", cid))
				rows.append(item(name_of(row) + "  Lv.%d" % level, description(row), buttons))
				if not profile.data.run.active and level > 0:
					var quote = systems.character_upgrade_status(cid)
					rows.back().description += "\n" + price_text(quote.price) + "\n" + clean(quote.reason)
				elif not profile.data.run.active:
					var feature = systems.camp_feature_status("recruit")
					var recruitment = systems.character_recruit_status(cid)
					rows.back().description += "\n" + price_text(recruitment.price) + "\n" + clean(recruitment.reason)
					if bool(row.get("is_cash_only_unlock", false)):
						buttons[1].text = "付费解锁"
						buttons[1].disabled = true
						rows.back().description += "\n需通过商城付费解锁"
						buttons.append(command("前往商城", "page:mall"))
					if not feature.available:
						rows.back().description += "\n" + clean(feature.reason)
						buttons[1].disabled = true
						buttons.append(command("前往建设", "page:buildings", 1))
				rows.back()["in_run"] = bool(profile.data.run.active)
				rows.back()["active_character"] = cid == game.selected_character
		"weapons":
			title = "武器"
			var character = catalog.find("CharData", id if id > 0 else game.selected_character)
			var allowed = str(character.get("can_equip_weapon_id_list", "")).split(",")
			for row in catalog.rows("WeaponData"):
				if not str(int(row.id)) in allowed: continue
				var rank = systems.stat("weapon:" + str(int(row.id)))
				var buttons: Array = []
				var details = description(row)
				if not profile.data.run.active:
					var quote = systems.weapon_upgrade_status(int(row.id))
					details += "\n" + price_text(quote.price) + "\n" + clean(quote.reason)
					buttons = [command("打造" if rank == 0 else "升级", "op:upgrade_weapon", int(row.id), 0, not quote.can_upgrade), command("已装备" if int(profile.data.selected_weapon) == int(row.id) else "装备", "equip_weapon", int(row.id), 0, rank == 0 or int(profile.data.selected_weapon) == int(row.id))]
				rows.append(item(name_of(row) + "  Lv.%d" % rank, details, buttons))
				rows.back()["weapon_id"] = int(row.id)
				rows.back()["in_run"] = bool(profile.data.run.active)
				rows.back()["active_character"] = int(profile.data.selected_weapon) == int(row.id)
				if not profile.data.run.active and not systems.camp_feature_status("weapons" if rank == 0 else "weapon_upgrade").available: rows.back().buttons.append(command("前往建设", "page:buildings", 3))
		"talents", "character_talents":
			title = "公会支援表" if page == "talents" else "角色天赋"
			var character_id = int(profile.data.run.character_id) if profile.data.run.active else id if id > 0 else game.selected_character
			for row in catalog.rows("TalentTreeData" if page == "talents" else "CharTalentData"):
				if page == "character_talents" and int(row.get("chara_id", 0)) != character_id: continue
				var ranks: Dictionary = profile.data.talents if page == "talents" else profile.data.run.talents
				var rank = int(ranks.get(str(int(row.id)), 0)) if page == "talents" or profile.data.run.active else 0
				var can_learn = profile.data.run.active and rank < DungeonCatalog.ids(row.get("level_data_id_list", "")).size() and systems.rank(profile.data.character_levels, character_id) >= int(row.get("unlock_chara_level", 0)) and systems.stat("talent:choices") > 0
				rows.append(item(name_of(row) + "  Lv.%d" % rank, description(row), [command("学习", "op:" + ("upgrade_global_talent" if page == "talents" else "learn_character_talent"), int(row.id), 0, page == "character_talents" and not can_learn)]))
				if page == "talents":
					var quote = systems.global_talent_status(int(row.id))
					rows.back().description += "\n" + price_text(quote.price) + "\n" + clean(quote.reason)
					rows.back().buttons[0].disabled = not quote.can_upgrade
		"partners":
			title = "伙伴"
			for row in catalog.rows("MonsterPartnerData"):
				var pid = int(row.id)
				var rank = int(profile.data.partners.get(str(pid), 0))
				var enemy = catalog.find("EnemyData", int(row.get("enemy_id", pid)))
				var progress = "击败 %s：%d / %s" % [name_of(enemy), systems.stat("kill:" + str(int(row.get("enemy_id", pid)))), str(row.get("unlock_need_kill_count", 0))]
				var buttons: Array = [command("解锁" if rank == 0 else "升级", "op:" + ("unlock_partner" if rank == 0 else "upgrade_partner"), pid)]
				if rank > 0: buttons.append(command("卸下" if pid in profile.data.equipped_partners else "装备", "op:" + ("unequip_partner" if pid in profile.data.equipped_partners else "equip_partner"), pid))
				rows.append(item(name_of(row) + "  Lv.%d" % rank, progress, buttons))
		"work":
			title = "伙伴派遣"
			for row in catalog.rows("MonsterWorkData"):
				var state = systems.work_status(int(row.id))
				var progress = "%s\n每次产出：%s ×%d\n耗时 %d 分钟 · 领取消耗：%s\n今日剩余 %d / %d 次" % [description(row), clean(systems.material_name(int(state.reward.id))), int(state.reward.amount), ceili(state.duration_seconds / 60.0), price_text(state.price), int(state.daily_remaining), int(state.daily_limit)]
				var buttons = [command("开始工作", "op:start_work", int(row.id), 0, not state.can_start), command("领取 %d 次" % int(state.claimable_quantity), "op:collect_work", int(row.id), 0, not state.ready), command("升级", "op:upgrade_work", int(row.id), 0, not state.can_upgrade)]
				if not state.order.is_empty():
					progress += "\n已储存 %d / %d 次" % [int(state.completed_quantity), int(state.queue_max)]
					if state.ready: progress += "\n本次领取消耗：" + price_text(state.claim_price)
					elif state.completed_quantity > 0: progress += "\n" + clean(state.claim_reason)
					else: progress += "\n下次产出 %d 分钟" % ceili(float(state.next_claim_seconds) / 60.0)
					buttons.append(command("停止派遣", "confirm_stop_work", int(row.id), 0, state.ready))
				else:
					if not state.can_start: progress += "\n" + clean(state.reason)
				if state.level + 1 < state.max_level:
					progress += "\n升级消耗：" + price_text(state.upgrade_price)
					if not state.can_upgrade: progress += "\n" + clean(state.upgrade_reason)
				if not state.unlocked: buttons.append(command("营地建设", "page:buildings", 6))
				var acceleration = game.ad_rewards.quote({"kind": "work", "id": int(row.id)})
				if acceleration.success:
					if game.ads.available(): buttons.append(command("看广告加速 30 分钟", "ad:work", int(row.id)))
					if game.ad_rewards.free_skips() > 0: buttons.append(command("免广告加速 30 分钟", "ad_skip:work", int(row.id)))
				rows.append(item(name_of(row) + "  Lv.%d / %d" % [state.level + 1, state.max_level], progress, buttons))
				rows.back()["commands_first"] = true
		"decorations":
			title = "主城装饰"
			var gate = systems.decorations.global_status()
			if not gate.available: rows.append(item("主城装饰尚未开放", gate.reason, [command("营地建设", "page:buildings")]))
			for slot in systems.decorations.slots():
				for option in slot.options:
					var text = str(option.row.get("description", ""))
					if option.selected: text += "\n使用中"
					elif not option.owned: text += "\n解锁消耗：" + price_text(option.price)
					if not str(option.reason).is_empty(): text += "\n" + str(option.reason)
					var buttons: Array = [command("使用中" if option.selected else "选用", "op:equip_camp_decoration", int(slot.slot_id), int(option.id), not option.can_equip or option.selected)] if option.owned else [command("解锁", "op:unlock_camp_decoration", int(option.id), 0, not option.can_unlock)]
					rows.append(item(str(option.row.get("name", "")), text, buttons))
					rows.back()["icon"] = str(option.row.get("icon_name", ""))
		"dispatch":
			title = "伙伴派遣"
			var state = systems.work_status(id)
			rows.append(item(state.name, "每次产出：%s ×%d\n领取消耗：%s\n储存上限 %d 次" % [clean(systems.material_name(int(state.reward.id))), state.reward.amount, price_text(state.price), int(state.queue_max)], [command("开始工作", "op:start_work", id, 0, not state.can_start), command("返回派遣", "page:work")]))
		"meals":
			title = "猫饭料理"
			var order = systems.meal_order_status()
			var order_lines: Array[String] = []
			for key in order.meals:
				order_lines.append("%s Lv.%d" % [name_of(catalog.find("CatMealData", int(key))), int(order.meals[key])])
			rows.append(item("本次餐单 %d / %d" % [int(order.count), int(order.limit)], "\n".join(order_lines) + "\n合计：" + price_text(order.price) + "\n" + clean(order.reason), [command("点餐", "op:buy_meal", 0, 0, not order.can_buy)]))
			rows.back()["icon"] = "icon_maincitybulid_restaurant"
			var last_order = systems.meal_order_status(true)
			if not last_order.meals.is_empty():
				var last_lines: Array[String] = []
				for key in last_order.meals:
					last_lines.append("%s Lv.%d" % [name_of(catalog.find("CatMealData", int(key))), int(last_order.meals[key])])
				var buttons = [command("金币复购", "op:recook_meal", 0, 0, not last_order.can_buy)]
				var ad_quote = game.ad_rewards.quote({"kind": "meal", "id": 0})
				if game.ads.available(): buttons.append(command("看广告复购", "ad:meal", 0, 0, not ad_quote.success))
				if game.ad_rewards.free_skips() > 0: buttons.append(command("免广告复购", "ad_skip:meal", 0, 0, not ad_quote.success))
				rows.append(item("上次餐单", "\n".join(last_lines) + "\n" + price_text(last_order.price) + "\n" + clean(last_order.reason), buttons))
				rows.back()["icon"] = "icon_maincitybulid_restaurant"
			for row in catalog.rows("CatMealData"):
				var meal_id = DungeonCatalog.row_id(row)
				var research = systems.meal_status(meal_id)
				var buttons: Array = [command("研究 Lv.%d" % (int(research.researched_level) + 1) if int(research.researched_level) < int(research.max_level) else "研究已满级", "op:research_meal", meal_id, 0, not research.can_research)]
				var details = "研究 Lv.%d / %d\n%s\n%s" % [int(research.researched_level), int(research.max_level), price_text(research.research_price), clean(research.research_reason)]
				for level in range(1, str(row.get("AbilityItemId", "")).split("|").size() + 1):
					var quote = systems.meal_status(meal_id, level)
					buttons.append(command(("移出" if quote.selected else "选择") + " Lv.%d" % level, "op:select_meal", meal_id, level, not quote.can_select))
					details += "\nLv.%d：%s%s\n%s" % [level, price_text(quote.price), " · 已生效" if quote.purchased else " · 餐单已选" if quote.selected else "", clean(quote.description)]
				rows.append(item(name_of(row), details, buttons))
				rows.back()["icon"] = str(row.get("IconName", ""))
		"meal_buffs":
			title = "料理效果"
			if profile.data.run.active:
				var purchased: Dictionary = systems.purchased_meals()
				var meal_ids = purchased.keys()
				meal_ids.sort_custom(func(a, b): return int(a) < int(b))
				for key in meal_ids:
					var meal_id = int(key)
					var level = int(purchased[key])
					var row = catalog.find("CatMealData", meal_id)
					var abilities = DungeonCatalog.ids(row.get("AbilityItemId", ""))
					if level < 1 or level > abilities.size(): continue
					rows.append(item(name_of(row) + "  Lv.%d" % level, clean(systems._part(row.get("Description", ""), level - 1))))
					rows.back()["meal_id"] = meal_id
					rows.back()["meal_level"] = level
					rows.back()["ability_id"] = abilities[level - 1]
					rows.back()["icon"] = str(row.get("IconName", ""))
			if rows.is_empty(): rows.append(item("暂无生效料理"))
		"buildings":
			title = "营地建设"
			var buildings = catalog.rows("Buildings").duplicate()
			buildings.sort_custom(func(a, b): return int(a.sort_index) < int(b.sort_index))
			for row in buildings:
				if int(row.max_level) <= 0: continue
				var state = systems.building_status(int(row.id))
				var text = "Lv.%d / %d\n%s" % [state.level, state.max_level, clean(state.description)]
				if not state.complete:
					text += "\n" + price_text(state.price)
					for requirement in state.requirements:
						text += "\n" + clean(systems.unlock_reason(int(requirement.id)))
					if not state.can_upgrade: text += "\n" + clean(state.reason)
				var buttons = [command("已满级" if state.complete else "建设" if state.level == 0 else "升级", "op:upgrade_building", int(row.id), 0, not state.can_upgrade)]
				var facility = {1: "characters", 2: "talents", 3: "weapons", 4: "archive", 5: "tasks", 6: "work", 7: "meals"}.get(int(row.id), "camp")
				if state.level > 0: buttons.append(command("进入设施", "page:" + facility))
				buttons.append(command("查看资源", "page:resources"))
				for stage in int(row.max_level):
					text += "\n\n%s %d级 · %s\n%s" % ["已建成" if stage < int(state.level) else "待建设", stage + 1, clean(systems._part(name_of(row), stage)), clean(systems._part(row.description, stage))]
				rows.append(item(clean(state.name), text, buttons))
		"npcs":
			title = "营地居民"
			for row in catalog.rows("NPCData"):
				rows.append(item(name_of(row), str(row.get("title", "")), [command("交谈", "page:npc", int(row.id)), command("赠礼", "op:give_npc_gift", int(row.id))]))
		"npc":
			var npc = catalog.find("NPCData", id)
			title = name_of(npc)
			rows.append(item(str(npc.get("title", "")), "好感 %d" % systems.stat("relationship:" + str(id)), [command("赠礼", "op:give_npc_gift", id)]))
			for row in catalog.rows("NPCFunctionData"):
				if int(row.get("npc_index", 0)) != id: continue
				rows.append(item(str(row.get("btn_name", name_of(row))), description(row), [command("交谈", "op:execute_npc_function", int(row.id))]))
		"awakening":
			title = "角色觉醒"
			var awake = systems.awakening_progress()
			rows.append(item("觉醒等级", "", [command("混沌奖励", "page:difficulty", 10)]))
			rows.back()["presentation_role"] = "awakening_summary"
			rows.back()["description"] = "Lv.%d · 潜能点 %d\n觉醒结晶 %d · 下一级 %d / %d" % [int(awake.level), int(awake.points), int(awake.total), int(awake.progress), int(awake.required)]
			var character_id = int(profile.data.run.character_id) if profile.data.run.active else id if id > 0 else game.selected_character
			for row in catalog.rows("CharaTalentAwakeTreeData"):
				var owner = int(row.get("chara_id", row.get("character_id", game.selected_character)))
				if owner != character_id or bool(row.get("is_admin_mode", false)): continue
				var status = systems.awakening_status(int(row.id))
				var details = description(row) + "\n消耗潜能点 %d · 已用 %d / %d" % [status.cost_points, status.used_points, status.points]
				if not status.unlocked: details += "\n" + price_text(status.price)
				if not str(status.reason).is_empty(): details += "\n" + clean(status.reason)
				elif not str(status.activation_reason).is_empty(): details += "\n" + clean(status.activation_reason)
				rows.append(item(name_of(row), details, [command("已解锁" if status.unlocked else "解锁", "op:unlock_awakening", int(row.id), 0, not status.can_unlock), command("停用" if status.active else "激活", "op:toggle_awakening", int(row.id), 0, not status.can_toggle)]))
		"tokens":
			title = "信物"
			rows.append(item("信物槽位", "", [command("解锁槽位", "op:unlock_token_slot")]))
			var seen: Array = []
			for row in catalog.rows("RelationshipTokenData"):
				var token_id = int(row.get("material_id", row.get("token_material_id", row.get("id", 0))))
				if token_id in seen: continue
				seen.append(token_id)
				rows.append(item(name_of(row), description(row), [command("强化", "op:upgrade_token", token_id), command("装备", "op:equip_token", token_id)]))
		"amplifiers":
			title = "增幅"
			rows.append(item("增幅槽位", "", [command("解锁槽位", "op:unlock_amplifier_slot"), command("重选", "op:reroll_amplifier")]))
			for row in catalog.rows("RelationshipAmplifyData"):
				rows.append(item(name_of(row), description(row), [command("装备", "op:equip_amplifier", int(row.id)), command("合成", "op:compose_amplifier", int(row.id))]))
		"achievements":
			title = "委托板"
			for row in catalog.rows("AchieveData"):
				var total = 0
				var finished = 0
				for task in catalog.rows("SubAchieveData"):
					if int(task.group_id) == int(row.id):
						total += 1
						if int(task.id) in profile.data.claimed_tasks: finished += 1
				rows.append(item(name_of(row) + "  %d / %d" % [finished, total], description(row), [command("查看任务", "page:tasks", int(row.id)), command("已领取" if int(row.id) in profile.data.claimed_achievements else "领取成就奖励", "op:claim_achievement", int(row.id), 0, int(row.id) in profile.data.claimed_achievements)]))
		"tasks":
			title = "委托板"
			for row in catalog.rows("SubAchieveData"):
				if id != 0 and int(row.group_id) != id: continue
				var status = systems.task_status(int(row.id))
				var state_text = "已领取" if status.claimed else "领取奖励"
				var rewards: Array[String] = []
				var materials = systems.costs(row.get("reward_get_materials", ""))
				for material_id in materials: rewards.append("%s ×%d" % [clean(systems.material_name(int(material_id))), int(materials[material_id])])
				rows.append(item(name_of(row), "%s\n%s / %s\n奖励：%s" % [clean(status.get("description", "")), str(status.current), str(status.required), "、".join(rewards)], [command(state_text, "op:claim_task", int(row.id), 0, status.claimed or not status.available or not status.complete)]))
		"storage":
			title = "仓库"
			for key in profile.data.materials:
				var amount = int(profile.data.materials[key])
				if amount <= 0: continue
				rows.append(item(clean(systems.material_name(int(key))) + "  ×%d" % amount))
				rows.back()["material_id"] = int(key)
		"inventory", "archive":
			title = "角色详情" if page == "inventory" else "战利品图鉴  %d / 358" % profile.data.discovered_loot.size()
			if page == "inventory":
				for box_id in [801, 802, 803, 901, 902, 903]:
					if systems.material(box_id) > 0:
						rows.append(item(clean(systems.material_name(box_id)) + "  ×%d" % systems.material(box_id), "", [command("开启", "op:open_material_box", box_id)]))
						rows.back()["material_id"] = box_id
			for row in catalog.rows("LootData"):
				var count = int(profile.data.run.inventory.get(str(int(row.id)), 0))
				if page == "inventory" and count <= 0: continue
				var ability = catalog.find("AbilityItems", int(row.get("ability_item_id", row.id)))
				rows.append(item(loot_name(int(row.id)) + ("  ×%d" % count if count > 0 else ""), description(ability)))
				rows.back()["loot_id"] = int(row.id)
		"mall":
			title = "商城"
			for row in catalog.rows("MallTradeData"):
				if not row.get("Enable", false): continue
				var offer_id = DungeonCatalog.row_id(row)
				var payment = str(row.get("GoodsPayType", ""))
				if payment == "Ad":
					var ad_quote = game.ad_rewards.quote({"kind": "mall", "id": offer_id})
					var commands = [command("看广告领取", "ad:mall", offer_id, 0, not ad_quote.success or not game.ads.available())]
					if game.ad_rewards.free_skips() > 0: commands.append(command("免广告领取 (%d)" % game.ad_rewards.free_skips(), "ad_skip:mall", offer_id, 0, not ad_quote.success))
					var details = description(row)
					if not ad_quote.success: details += "\n" + clean(ad_quote.get("message", ""))
					rows.append(item(name_of(row), details, commands))
					rows.back()["payment_type"] = payment
					continue
				var quote = systems.offer_quote(offer_id)
				var price = ""
				match payment:
					"Gold", "PurchaseCion", "FreeCion": price = "%d %s" % [int(quote.get("price", row.get("Price", 0))), clean(systems.material_name(int(quote.get("currency", 101 if payment == "Gold" else 90001 if payment == "PurchaseCion" else 90002))))]
					"Money": price = "付费购买 · 标价 %s" % str(quote.get("payment_price", row.get("Price", 0)))
					_: price = "特殊商品"
				var details = description(row) + "\n" + price
				if not quote.get("success", false): details += "\n" + clean(quote.get("message", "商品不可购买"))
				rows.append(item(name_of(row), details, [command("购买" if payment == "Money" else "兑换", "op:buy_mall", offer_id, 0, not quote.get("success", false))]))
				rows.back()["payment_type"] = payment
				rows.back()["offer_quote"] = quote
		"difficulty":
			title = "冒险难度"
			for level in range(11):
				var status = systems.difficulty_status(level)
				rows.append(item(status.name, status.description, [command("已选择" if game.difficulty == level else "选择" if status.unlocked else "未解锁", "difficulty", level, 0, not status.unlocked or profile.data.run.active)]))
				rows.back()["difficulty_status"] = status
		"settings":
			title = "设置"
			rows.append({"title": "语言", "controls": [{"type": "language", "action": "language", "value": DungeonLocale.current_locale()}]})
			if game.ads.available(): rows.append(item("广告隐私", "", [command("隐私选项", "privacy_ads")]))
			var visual = DungeonStyle.read_options()
			rows.append({"title": "画面质量", "options": [command("中", "visual:quality", 0), command("高", "visual:quality", 1), command("超高", "visual:quality", 2)]})
			rows.append({"title": "显示阴影", "options": [command("开启", "visual:shadows", true), command("关闭", "visual:shadows", false)]})
			rows.append({"title": "帧率上限", "options": [command("30", "visual:fps", 30), command("45", "visual:fps", 45), command("60", "visual:fps", 60), command("无限制", "visual:fps", 0)]})
			for row in rows:
				for option in row.get("options", []): option["selected"] = visual[option.action.trim_prefix("visual:")] == option.id
			rows.append(item("声音", "", [command("开启 / 关闭", "toggle_audio")]))
			rows.append({"title": "音量", "controls": [{"type": "slider", "action": "volume", "value": float(profile.data.get("volume", 1.0))}]})
			var attack_options = [command("普攻", "auto_attack_mode", "normal"), command("重击", "auto_attack_mode", "heavy"), command("关闭", "auto_attack_mode", "off")]
			for option in attack_options: option["selected"] = option.id == DungeonProfile.attack_mode(profile.data)
			rows.append({"title": "自动攻击", "options": attack_options})
			rows.append({"title": "战斗表现", "controls": [{"type": "toggle", "text": "镜头震动", "action": "camera_shake", "value": bool(profile.data.get("camera_shake", true))}, {"type": "toggle", "text": "精简特效", "action": "low_effects", "value": bool(profile.data.get("low_effects", false))}]})
			var key_names = {"move_left": "左移", "move_right": "右移", "move_up": "前进", "move_down": "后退", "skill": "战技", "dodge": "闪避", "burst": "爆发", "heavy": "重击", "interact": "交互", "pause_game": "暂停", "map": "路线地图"}
			for key in key_names:
				var names: Array[String] = []
				for event in InputMap.action_get_events(key):
					if event is InputEventKey: names.append(OS.get_keycode_string(event.physical_keycode))
				rows.append(item(key_names[key], " / ".join(names), [command("更改按键", "bind_key", key)]))
			rows.append(item("操作配置", "", [command("恢复默认按键", "reset_keys")]))
			rows.append(item("祝福", "", [command("关闭", "op:set_blessing_mode", 0), command("祝福", "op:set_blessing_mode", 1), command("高阶祝福", "op:set_blessing_mode", 2)]))
			rows.append(item("冒险", "", [command("保存", "save"), command("返回主城", "retreat"), command("退出游戏", "quit")]))
		_:
			open("camp")
			return
	if rows.is_empty(): rows.append(item("暂无可用项目"))
	if not profile.data.run.active and page in ["talents", "partners", "meals", "archive"]:
		var feature = systems.camp_feature_status(page)
		if not feature.available:
			for row in rows:
				row.description = clean(feature.reason) + "\n" + str(row.get("description", ""))
				for button in row.get("buttons", []):
					if str(button.action).begins_with("op:"): button.disabled = true
				row.buttons.append(command("前往建设", "page:buildings", feature.building_id))
	_enrich(page, rows)
	var specialized = {"inventory": "inventory", "storage": "inventory", "characters": "character", "weapons": "weapon", "settings": "settings", "talents": "guild", "tasks": "commission", "achievements": "commission", "character_talents": "tree", "awakening": "awakening", "buildings": "buildings", "difficulty": "prepare", "mall": "shop"}
	var layout = str(specialized.get(page, "model" if page == "partners" else "grid" if page in ["camp", "inventory", "archive", "tokens", "amplifiers", "meals"] else "list"))
	var context: Dictionary = {"page": page, "selected_id": id, "camp": not profile.data.run.active}
	if page == "settings" and hud.modal_open and is_instance_valid(hud.page):
		context["settings_section"] = hud.page.page_context.get("settings_section", "画面")
	if layout in ["buildings", "guild", "commission", "character", "weapon", "shop"]:
		context["systems"] = systems
		context["catalog"] = catalog
		context["group_id"] = id
		context["character_id"] = game.selected_character
		if hud.modal_open and is_instance_valid(hud.page) and current_page == str(hud.page.page_context.get("page", "")):
			for key in ["group_id", "category", "selected_talent", "selected_character", "character_mode", "use_model", "mall_category", "selected_offer", "mall_box_count"]:
				if key == "group_id" and id > 0: continue
				if hud.page.page_context.has(key): context[key] = hud.page.page_context[key]
		if page == "characters" and id > 0: context["selected_character"] = id
	if page == "difficulty":
		context["in_run"] = profile.data.run.active
		context["difficulty"] = game.difficulty
		context["preparation"] = systems.adventure_preparation_status(game.difficulty)
		context["systems"] = systems
		context["catalog"] = catalog
	if page in ["inventory", "characters", "weapons", "storage"]:
		context["resources"] = [["material:101", str(systems.material(101))], ["material:102", str(systems.material(102))], ["loot:12101", "%d/%d" % [systems.search_point_count(), systems.search_point_max()]], ["material:10501", str(systems.material(10501))]]
	if not profile.data.run.active and page not in ["inventory", "characters", "weapons", "storage"]:
		context["resources"] = [["sprite_materialicon_101", str(systems.material(101))], ["sprite_materialicon_501", str(systems.material(501))], ["sprite_materialicon_90002", str(systems.material(90002))]]
		if page == "difficulty": context["resources"] = [["sprite_materialicon_101", str(systems.material(101))], ["sprite_materialicon_90002", str(systems.material(90002))]]
	if page == "mall": context["resources"] = [["sprite_materialicon_90002", str(systems.material(90002))]]
	hud.show_page(title, rows, layout, context)

func _enrich(page: String, rows: Array) -> void:
	var tables = {"characters": "CharData", "weapons": "WeaponData", "partners": "MonsterPartnerData", "talents": "TalentTreeData", "character_talents": "CharTalentData", "tokens": "RelationshipTokenData", "amplifiers": "RelationshipAmplifyData", "meals": "CatMealData", "achievements": "AchieveData", "tasks": "SubAchieveData", "work": "MonsterWorkData", "buildings": "Buildings", "awakening": "CharaTalentAwakeTreeData", "mall": "MallTradeData", "inventory": "LootData", "archive": "LootData"}
	var table = str(tables.get(page, ""))
	for row in rows:
		var source: Dictionary = {}
		var id = 0
		var commands: Array = row.get("buttons", [])
		if not commands.is_empty() and (commands[0].get("id", 0) is int or commands[0].get("id", 0) is float): id = int(commands[0].get("id", 0))
		if not table.is_empty() and id > 0: source = catalog.find(table, id)
		if page in ["inventory", "archive"]:
			id = int(row.get("loot_id", 0))
			source = catalog.find("LootData", id)
		elif page == "weapons":
			id = int(row.get("weapon_id", id))
			source = catalog.find("WeaponData", id)
		elif page == "meal_buffs":
			id = int(row.get("meal_id", 0))
			source = catalog.find("CatMealData", id)
		row["config_id"] = id
		if page == "awakening" and row.get("presentation_role", "") != "awakening_summary":
			row["node_label"] = "Lv.%d\n%d点" % [int(source.get("unlock_awake_tree_level", 0)), int(source.get("active_need_awake_point", 0))]
			row["node_level"] = int(source.get("unlock_awake_tree_level", 0))
			row["active"] = profile.data.active_awakenings.has(id)
		row["artwork"] = str(source.get("full_icon_name", ""))
		row["parents"] = []
		for parent in str(source.get("parent_id_list", "")).replace("|", ",").split(",", false):
			if parent.is_valid_int(): row.parents.append(int(parent))
		if page == "characters":
			row["stats"] = [["生命", source.get("hp", 0)], ["攻击", source.get("atk", 0)], ["防御", source.get("def", 0)], ["暴击率", "%.1f%%" % (float(source.get("criti_rate", 0)) / 10)], ["暴击伤害", "%.0f%%" % (float(source.get("criti_mult", 0)) / 10)]]
			if not row.get("in_run", false):
				var preview = DungeonCombat.new()
				preview.configure(null, systems, id)
				preview.set_external_attributes(systems.attributes(id))
				var binding = systems.progression_buff_bindings(id)
				preview.set_progression_buffs(binding.roots, binding.externally_counted_numeric_ids)
				var defense = (preview.defense + preview.attribute("BaseDef") + preview.attribute("DefAddFixed")) * (1.0 + preview.attribute("DefAddRate") / 1000.0)
				row["stats"] = [["生命", str(ceili(preview.max_health))], ["攻击", str(roundi(preview.effective_attack_power()))], ["防御", str(roundi(defense))], ["暴击率", "%.1f%%" % ((float(preview.fighter.get("critRate", 0)) + preview.attribute("CriticalRate") / 1000.0) * 100)], ["暴击伤害", "%.0f%%" % ((float(preview.fighter.get("critMultiplier", 1.5)) + preview.attribute("CriticalMulti") / 1000.0) * 100)]]
				row["stats_bonus"] = ["%+d" % (ceili(preview.max_health) - int(source.get("hp", 0))), "%+d" % (roundi(preview.effective_attack_power()) - int(source.get("atk", 0))), "%+d" % (roundi(defense) - int(source.get("def", 0))), "%+.1f%%" % (preview.attribute("CriticalRate") / 10.0), "%+.0f%%" % (preview.attribute("CriticalMulti") / 10.0)]
				for index in row.stats_bonus.size():
					if str(row.stats_bonus[index]) in ["+0", "+0.0%", "+0%", "-0.0%"]: row.stats_bonus[index] = ""
				preview.drain_events()
				preview._pending.clear()
				preview.statuses.clear()
			if row.get("in_run", false) and is_instance_valid(game.world.player):
				var combat: DungeonCombat = game.world.player.combat
				var defense = (combat.defense + combat.attribute("BaseDef") + combat.attribute("DefAddFixed")) * (1.0 + combat.attribute("DefAddRate") / 1000.0)
				row["stats"] = [["生命", "%d / %d" % [ceili(combat.health), ceili(combat.max_health)]], ["攻击", str(roundi(combat.effective_attack_power()))], ["防御", str(roundi(defense))], ["暴击率", "%.1f%%" % ((float(combat.fighter.get("critRate", 0)) + combat.attribute("CriticalRate") / 1000.0) * 100)], ["暴击伤害", "%.0f%%" % ((float(combat.fighter.get("critMultiplier", 1.5)) + combat.attribute("CriticalMulti") / 1000.0) * 100)]]
		if page == "weapons": row.description += "\n" + clean(source.get("effect_description", "")).replace("|", "\n")
		if page == "settings":
			var title = str(row.title)
			row["section"] = "语言" if title == "语言" else "声音" if title in ["声音", "音量"] else "画面" if title in ["战斗表现", "画面质量", "帧率上限", "显示阴影"] else "存档" if title == "冒险" else "指南" if title in ["操作配置", "左移", "右移", "前进", "后退", "战技", "闪避", "爆发", "重击", "交互", "暂停"] else "游戏性"
		row["icon"] = str(row.get("icon", "menu_adventure"))
		if page in ["inventory", "archive"] and not source.is_empty(): row.icon = "loot:" + str(id)
		if page == "work":
			var material_id = int(source.get("materia_id", 0))
			row.icon = "sprite_mosterwork_%d" % (0 if material_id <= 9999 else int((material_id % 10000) / 100))
		if row.has("material_id"): row.icon = "material:" + str(row.material_id)
		for field in ["square_icon_name", "icon_name", "icon", "Icon", "IconName", "sprite_name"]:
			var key = str(source.get(field, ""))
			if page == "buildings": key = systems._part(key, mini(int(profile.data.buildings.get(str(id), 0)), maxi(0, int(source.get("max_level", 1)) - 1)))
			if not key.is_empty() and DungeonStyle.texture(key):
				row.icon = key
				break
		if page in ["characters", "weapons", "partners"] and id > 0:
			var kind = "characters" if page == "characters" else "weapons" if page == "weapons" else "enemies"
			var model_id = int(source.get("enemy_id", id)) if page == "partners" else id
			row["model"] = game.world.asset_path(kind, model_id)
			if page == "partners": row.title = name_of(catalog.find("EnemyData", model_id)) + "  Lv.%d" % int(profile.data.partners.get(str(id), 0))
		if page == "camp" and not commands.is_empty():
			var destination = str(commands[0].action).trim_prefix("page:")
			row.icon = {"characters": "menu_character", "talents": "skill_sword_whirl", "partners": "menu_character", "work": "reward_clock", "meals": "menu_store", "buildings": "menu_portal", "npcs": "interaction_quest", "awakening": "skill_sword_slash", "tokens": "gold_corner", "amplifiers": "hud_charge_diamond", "achievements": "interaction_quest", "archive": "interaction_weapon", "mall": "menu_store", "difficulty": "menu_difficulty"}.get(destination, "menu_adventure")
			if destination == "resources": row.icon = "material:501"
			elif destination == "buildings": row.icon = "icon_maincitybulid_blacksmith"
