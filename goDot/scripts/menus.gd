class_name DungeonMenus
extends RefCounted

var game: Node
var catalog: RefCounted
var systems: RefCounted
var profile: RefCounted
var hud: DungeonHud
var current_page := "camp"
var current_id := 0

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

func open(page: String, id: int = 0) -> void:
	current_page = page
	current_id = id
	var rows: Array = []
	var title := "营地"
	match page:
		"camp":
			title = "冒险者营地"
			var entries = [["角色与武器", "characters"], ["公会天赋", "talents"], ["伙伴", "partners"], ["伙伴派遣", "work"], ["猫饭料理", "meals"], ["营地建设", "buildings"], ["居民与支援", "npcs"], ["觉醒", "awakening"], ["信物", "tokens"], ["增幅", "amplifiers"], ["任务与成就", "achievements"], ["战利品图鉴", "archive"], ["本地商城", "mall"], ["冒险难度", "difficulty"]]
			for entry in entries:
				rows.append(item(entry[0], "", [command("查看", "page:" + entry[1])]))
			rows.push_front(item("继续冒险" if profile.data.run.active else "新的冒险", "", [command("继续" if profile.data.run.active else "出发", "primary")]))
		"characters":
			title = "角色详情"
			for row in catalog.rows("CharData"):
				if row.get("available_state", "") != "Normal": continue
				var cid = int(row.id)
				if profile.data.run.active and cid != game.selected_character: continue
				var level = int(profile.data.character_levels.get(str(cid), 0))
				var buttons: Array = [command("选择" if game.selected_character != cid else "已选择", "select_character", cid, 0, level <= 0)]
				if not profile.data.run.active:
					buttons.append(command("升级" if level > 0 else "招募", "op:" + ("upgrade_character" if level > 0 else "unlock_character"), cid))
				buttons.append(command("查看天赋", "page:character_talents", cid))
				rows.append(item(name_of(row) + "  Lv.%d" % level, description(row), buttons))
				rows.back()["in_run"] = bool(profile.data.run.active)
				rows.back()["active_character"] = cid == game.selected_character
		"weapons":
			title = "武器"
			var character = catalog.find("CharData", id if id > 0 else game.selected_character)
			var allowed = str(character.get("can_equip_weapon_id_list", "")).split(",")
			for row in catalog.rows("WeaponData"):
				if not str(int(row.id)) in allowed: continue
				var rank = systems.stat("weapon:" + str(int(row.id)))
				rows.append(item(name_of(row) + "  Lv.%d" % rank, description(row), [command("打造" if rank == 0 else "升级", "op:upgrade_weapon", int(row.id)), command("装备", "equip_weapon", int(row.id), 0, rank == 0)]))
		"talents", "character_talents":
			title = "公会天赋" if page == "talents" else "角色天赋"
			for row in catalog.rows("TalentTreeData" if page == "talents" else "CharTalentData"):
				if page == "character_talents" and int(row.get("chara_id", 0)) != game.selected_character: continue
				var ranks: Dictionary = profile.data.talents if page == "talents" else profile.data.run.talents
				var rank = int(ranks.get(str(int(row.id)), 0))
				rows.append(item(name_of(row) + "  Lv.%d" % rank, description(row), [command("学习", "op:" + ("upgrade_global_talent" if page == "talents" else "learn_character_talent"), int(row.id))]))
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
				var order: Dictionary = {}
				for existing in profile.data.work:
					if int(existing.get("work_id", 0)) == int(row.id): order = existing
				var progress = description(row)
				if not order.is_empty(): progress += "\n剩余 %d 分钟" % maxi(0, ceili((float(order.get("due_utc", 0)) - Time.get_unix_time_from_system()) / 60.0))
				var buttons = [command("选择伙伴", "page:dispatch", int(row.id)), command("领取", "op:collect_work", int(row.id)), command("升级", "op:upgrade_work", int(row.id))]
				var acceleration = game.ad_rewards.quote({"kind": "work", "id": int(row.id)})
				if acceleration.success:
					if game.ads.available(): buttons.append(command("看广告加速 30 分钟", "ad:work", int(row.id)))
					if game.ad_rewards.free_skips() > 0: buttons.append(command("免广告加速 30 分钟", "ad_skip:work", int(row.id)))
				rows.append(item(name_of(row), progress, buttons))
		"dispatch":
			title = "选择派遣伙伴"
			for row in catalog.rows("MonsterPartnerData"):
				if int(profile.data.partners.get(str(int(row.id)), 0)) <= 0: continue
				rows.append(item(name_of(row), "", [command("派遣", "op:start_work", id, int(row.id))]))
		"meals":
			title = "猫饭料理"
			for row in catalog.rows("CatMealData"):
				var buttons: Array = []
				for level in range(1, str(row.get("AbilityItemId", "")).split("|").size() + 1):
					buttons.append(command("料理 Lv.%d" % level, "op:cook_meal", DungeonCatalog.row_id(row), level))
					if systems.rank(profile.data.recipes, DungeonCatalog.row_id(row)) >= level:
						if game.ads.available(): buttons.append(command("看广告点餐 Lv.%d" % level, "ad:meal", DungeonCatalog.row_id(row), level))
						if game.ad_rewards.free_skips() > 0: buttons.append(command("免广告点餐 Lv.%d" % level, "ad_skip:meal", DungeonCatalog.row_id(row), level))
				rows.append(item(name_of(row), description(row), buttons))
		"buildings":
			title = "营地建设"
			for row in catalog.rows("Buildings"):
				var level = int(profile.data.buildings.get(str(int(row.id)), 0))
				var complete = level >= int(row.get("max_level", 0))
				var stage = mini(level, maxi(0, int(row.get("max_level", 1)) - 1))
				var price = systems.costs(systems._part(row.get("need_materials", ""), stage, ";"))
				price[101] = int(price.get(101, 0)) + int(systems._part(row.get("need_gold", ""), stage))
				var available = systems.is_unlocked(int(systems._part(row.get("unlock_data_id", ""), stage)))
				var text = "Lv.%d / %d\n%s" % [level, int(row.get("max_level", 0)), clean(systems._part(row.get("description", ""), stage))]
				if not complete:
					for material_id in price:
						if int(price[material_id]) <= 0: continue
						text += "\n%s %d / %d" % [systems.material_name(int(material_id)), systems.material(int(material_id)), int(price[material_id])]
						available = available and systems.material(int(material_id)) >= int(price[material_id])
				rows.append(item(systems._part(name_of(row), stage), text, [command("已完成" if complete else "建设" if available else "条件不足", "op:upgrade_building", int(row.id), 0, complete or not available)]))
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
			rows.append(item("觉醒等级", "", [command("提升", "op:upgrade_awakening_level", game.selected_character)]))
			rows.back()["presentation_role"] = "awakening_summary"
			rows.back()["description"] = "Lv.%d" % systems.stat("awake:level:" + str(game.selected_character))
			for row in catalog.rows("CharaTalentAwakeTreeData"):
				var owner = int(row.get("chara_id", row.get("character_id", game.selected_character)))
				if owner != game.selected_character: continue
				rows.append(item(name_of(row), description(row), [command("解锁", "op:unlock_awakening", int(row.id)), command("激活 / 停用", "op:toggle_awakening", int(row.id))]))
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
			title = "成就  %d / 62" % profile.data.claimed_achievements.size()
			for row in catalog.rows("AchieveData"):
				var total = 0
				var finished = 0
				for task in catalog.rows("SubAchieveData"):
					if int(task.group_id) == int(row.id):
						total += 1
						if int(task.id) in profile.data.claimed_tasks: finished += 1
				rows.append(item(name_of(row) + "  %d / %d" % [finished, total], description(row), [command("查看任务", "page:tasks", int(row.id)), command("已领取" if int(row.id) in profile.data.claimed_achievements else "领取成就奖励", "op:claim_achievement", int(row.id), 0, int(row.id) in profile.data.claimed_achievements)]))
		"tasks":
			title = "委托任务" if id == 0 else name_of(catalog.find("AchieveData", id))
			for row in catalog.rows("SubAchieveData"):
				if id != 0 and int(row.group_id) != id: continue
				var status = systems.task_status(int(row.id))
				var state_text = "已领取" if status.claimed else "领取奖励"
				rows.append(item(name_of(row), "%s\n%s / %s    奖励 %s" % [str(status.get("description", "")), str(status.current), str(status.required), str(row.get("reward_get_materials", ""))], [command(state_text, "op:claim_task", int(row.id), 0, status.claimed or not status.available or not status.complete)]))
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
			title = "本地商城"
			for row in catalog.rows("MallTradeData"):
				var offer_id = DungeonCatalog.row_id(row)
				if row.get("GoodsPayType", "") == "Ad":
					var ad_quote = game.ad_rewards.quote({"kind": "mall", "id": offer_id})
					var commands = [command("看广告领取", "ad:mall", offer_id, 0, not ad_quote.success or not game.ads.available())]
					if game.ad_rewards.free_skips() > 0: commands.append(command("免广告领取 (%d)" % game.ad_rewards.free_skips(), "ad_skip:mall", offer_id, 0, not ad_quote.success))
					rows.append(item(name_of(row), description(row), commands))
					continue
				var quote = systems.offer_quote(offer_id)
				var price = "%d %s" % [int(quote.get("price", 0)), systems.material_name(int(quote.get("currency", 101)))]
				rows.append(item(name_of(row), description(row) + "\n" + price, [command("兑换", "op:buy_mall", offer_id, 0, not quote.get("success", false))]))
		"difficulty":
			title = "冒险难度"
			for level in range(11): rows.append(item("难度 %d" % level, "", [command("已选择" if game.difficulty == level else "选择", "difficulty", level, 0, profile.data.run.active)]))
		"settings":
			title = "设置"
			if game.ads.available(): rows.append(item("广告隐私", "", [command("隐私选项", "privacy_ads")]))
			var visual = DungeonStyle.read_options()
			rows.append({"title": "画面质量", "options": [command("中", "visual:quality", 0), command("高", "visual:quality", 1), command("超高", "visual:quality", 2)]})
			rows.append({"title": "显示阴影", "options": [command("开启", "visual:shadows", true), command("关闭", "visual:shadows", false)]})
			rows.append({"title": "帧率上限", "options": [command("30", "visual:fps", 30), command("45", "visual:fps", 45), command("60", "visual:fps", 60), command("无限制", "visual:fps", 0)]})
			for row in rows:
				for option in row.options: option["selected"] = visual[option.action.trim_prefix("visual:")] == option.id
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
	_enrich(page, rows)
	var specialized = {"inventory": "inventory", "storage": "inventory", "characters": "character", "weapons": "weapon", "settings": "settings", "talents": "tree", "character_talents": "tree", "awakening": "awakening", "buildings": "buildings", "difficulty": "prepare", "mall": "shop"}
	var layout = str(specialized.get(page, "model" if page == "partners" else "grid" if page in ["camp", "inventory", "archive", "tokens", "amplifiers", "meals"] else "list"))
	var context: Dictionary = {"page": page}
	if page == "difficulty":
		context["in_run"] = profile.data.run.active
		context["difficulty"] = game.difficulty
	if page in ["inventory", "characters", "weapons", "storage"]:
		context["resources"] = [["material:101", str(systems.material(101))], ["material:102", str(systems.material(102))], ["loot:12101", "%d/%d" % [systems.search_point_count(), systems.search_point_max()]], ["material:10501", str(systems.material(10501))]]
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
			if row.get("in_run", false) and is_instance_valid(game.world.player):
				var combat: DungeonCombat = game.world.player.combat
				var defense = (combat.defense + combat.attribute("BaseDef") + combat.attribute("DefAddFixed")) * (1.0 + combat.attribute("DefAddRate") / 1000.0)
				row["stats"] = [["生命", "%d / %d" % [ceili(combat.health), ceili(combat.max_health)]], ["攻击", str(roundi(combat.effective_attack_power()))], ["防御", str(roundi(defense))], ["暴击率", "%.1f%%" % ((float(combat.fighter.get("critRate", 0)) + combat.attribute("CriticalRate") / 1000.0) * 100)], ["暴击伤害", "%.0f%%" % ((float(combat.fighter.get("critMultiplier", 1.5)) + combat.attribute("CriticalMulti") / 1000.0) * 100)]]
		if page == "weapons": row.description += "\n" + clean(source.get("effect_description", "")).replace("|", "\n")
		if page == "settings":
			var title = str(row.title)
			row["section"] = "声音" if title in ["声音", "音量"] else "画面" if title in ["战斗表现", "画面质量", "帧率上限", "显示阴影"] else "存档" if title == "冒险" else "指南" if title in ["操作配置", "左移", "右移", "前进", "后退", "战技", "闪避", "爆发", "重击", "交互", "暂停"] else "游戏性"
		row["icon"] = "menu_adventure"
		if page in ["inventory", "archive"] and not source.is_empty(): row.icon = "loot:" + str(id)
		if row.has("material_id"): row.icon = "material:" + str(row.material_id)
		for field in ["square_icon_name", "icon_name", "icon", "Icon", "sprite_name"]:
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
