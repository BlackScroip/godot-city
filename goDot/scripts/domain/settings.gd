class_name DungeonSettings
extends RefCounted

const DEFAULTS = {
	"damage_numbers": 0, "healing_numbers": 0, "hit_stop": 100,
	"slow_motion": true, "camera_shake": 100, "flash_strength": 10,
	"ui_speed": 1, "show_timer": false, "joystick_fixed": false,
	"target_mode": 0, "attack_priority": 0, "dodge_priority": 1,
	"auto_pickup_relic": false, "auto_pickup_ornament": false, "auto_pickup_consumable": false,
	"ui_width": 0, "ui_height": 0, "brightness": 0,
	"quality": 2, "dynamic_resolution": false, "shadows": true,
	"bloom": false, "dof": false, "motion_blur": true,
	"effects_density": 2, "reduce_player_effects": false, "scene_detail": 2,
	"idle_power_saving": true, "effects_opacity": 100,
	"volume_master": 100, "volume_music": 100,
	"volume_effects": 100, "volume_voice": 100, "fps": 45,
}
const CHOICES = {
	"damage_numbers": [0, 1, 2], "healing_numbers": [0, 1, 2],
	"hit_stop": [100, 50, 0], "camera_shake": [100, 50],
	"ui_speed": [1, 2], "quality": [0, 1, 2, 3], "fps": [30, 45, 60, 0],
	"target_mode": [0, 1, 2], "attack_priority": [0, 1], "dodge_priority": [0, 1, 2],
	"effects_density": [0, 1, 2], "scene_detail": [0, 1, 2],
}
const RANGES = {
	"flash_strength": Vector2(0, 10), "ui_width": Vector2(0, 100),
	"ui_height": Vector2(0, 50), "brightness": Vector2(-100, 100),
	"effects_opacity": Vector2(0, 100),
	"volume_master": Vector2(0, 100), "volume_music": Vector2(0, 100),
	"volume_effects": Vector2(0, 100), "volume_voice": Vector2(0, 100),
}
static var settings_path := "user://settings.cfg"
static var _loaded_path := ""
static var _values: Dictionary = {}
static var _stored_keys: Array[String] = []

static func read_options() -> Dictionary:
	if _loaded_path != settings_path:
		_values = DEFAULTS.duplicate(true)
		_stored_keys.clear()
		var config := ConfigFile.new()
		if config.load(settings_path) == OK:
			for key in DEFAULTS:
				if config.has_section_key("settings", key):
					_values[key] = normalize(key, config.get_value("settings", key))
					_stored_keys.append(key)
		_loaded_path = settings_path
	return _values.duplicate(true)

static func normalize(key: String, value: Variant) -> Variant:
	if not DEFAULTS.has(key): return null
	if DEFAULTS[key] is bool: return value if value is bool else DEFAULTS[key]
	if not (value is int or value is float) or not is_finite(float(value)): return DEFAULTS[key]
	var number := roundi(float(value))
	if CHOICES.has(key): return number if number in CHOICES[key] else DEFAULTS[key]
	if RANGES.has(key): return clampi(number, int(RANGES[key].x), int(RANGES[key].y))
	return number

static func set_option(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key): return false
	read_options()
	var next := _values.duplicate(true)
	next[key] = normalize(key, value)
	var config := ConfigFile.new()
	for name in next: config.set_value("settings", name, next[name])
	var temporary := settings_path + ".tmp"
	if config.save(temporary) != OK: return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(settings_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	_values = next
	if key not in _stored_keys: _stored_keys.append(key)
	return true

static func migrate_legacy(profile: Dictionary) -> void:
	read_options()
	if not _stored_keys.is_empty(): return
	if profile.has("volume"): _values.volume_master = clampi(roundi(float(profile.volume) * 100), 0, 100)
	if not bool(profile.get("audio_enabled", true)): _values.volume_master = 0
	if profile.has("camera_shake"): _values.camera_shake = 100 if bool(profile.camera_shake) else 50
	var visual := ConfigFile.new()
	if visual.load("user://presentation.cfg") == OK:
		for key in ["quality", "shadows", "fps"]:
			if visual.has_section_key("visual", key): _values[key] = normalize(key, visual.get_value("visual", key))

static func rows() -> Array:
	var values := read_options()
	var result: Array = []
	result.append(choice("游戏性", "damage_numbers", "伤害冒字", ["开启", "简写", "关闭"], [0, 1, 2], values))
	result.append(choice("游戏性", "healing_numbers", "治疗冒字", ["开启", "简写", "关闭"], [0, 1, 2], values))
	result.append(choice("游戏性", "hit_stop", "击中顿帧", ["强", "弱", "无"], [100, 50, 0], values))
	result.append(choice("游戏性", "slow_motion", "全局慢放演出", ["开启", "关闭"], [true, false], values))
	result.append(choice("游戏性", "camera_shake", "相机震动", ["默认", "弱"], [100, 50], values))
	result.append(slider("游戏性", "flash_strength", "屏幕演出闪光强度", values))
	result.append(choice("游戏性", "ui_speed", "UI播放速度", ["默认", "倍速"], [1, 2], values))
	result.append(choice("游戏性", "show_timer", "显示关卡计时", ["开启", "关闭"], [true, false], values))
	result.append(choice("游戏性", "joystick_fixed", "摇杆固定模式", ["动态", "固定"], [false, true], values))
	result.append(choice("游戏性", "target_mode", "索敌模式", ["摇杆方向", "就近", "无锁定"], [0, 1, 2], values))
	result.append(choice("游戏性", "attack_priority", "自动攻击模式优先级", ["优先攻击", "优先移动"], [0, 1], values))
	result.append(choice("游戏性", "dodge_priority", "闪避攻击优先级", ["自动衔接", "默认", "屏蔽"], [0, 1, 2], values))
	result.append({"section": "游戏性", "title": "自动拾取规则", "controls": [
		{"type": "toggle", "key": "auto_pickup_relic", "text": "遗物", "value": values.auto_pickup_relic},
		{"type": "toggle", "key": "auto_pickup_ornament", "text": "装饰品", "value": values.auto_pickup_ornament},
		{"type": "toggle", "key": "auto_pickup_consumable", "text": "消耗品", "value": values.auto_pickup_consumable}]})
	result.append({"section": "游戏性", "title": "自定义操作按钮", "buttons": [
		{"text": "打开自定义", "action": "customize_controls"}, {"text": "重置", "action": "reset_touch_controls"}]})
	result.append(slider("画面", "ui_width", "用户界面宽度适配", values, "调整屏幕用户界面和画面边缘的距离。"))
	result.append(slider("画面", "ui_height", "UI高度适配", values, "*调整屏幕UI和画面顶部边缘的距离"))
	result.append(slider("画面", "brightness", "全局光照亮度", values, "*调整全局光照亮度"))
	result.append(choice("画面", "quality", "画面质量", ["中", "高", "超高", "原生"], [0, 1, 2, 3], values, "*游戏卡顿时请打开手机的游戏模式"))
	result.append(choice("画面", "dynamic_resolution", "低帧率下启用动态分辨率", ["开启", "关闭"], [true, false], values))
	result.append(choice("画面", "shadows", "显示阴影", ["开启", "关闭"], [true, false], values))
	result.append(choice("画面", "bloom", "启用Bloom眩光", ["开启", "关闭"], [true, false], values))
	result.append(choice("画面", "dof", "启用景深", ["开启", "关闭"], [true, false], values))
	result.append(choice("画面", "motion_blur", "动态演出模糊", ["开启", "关闭"], [true, false], values))
	result.append(choice("画面", "fps", "帧率上限", ["30", "45", "60", "无限制"], [30, 45, 60, 0], values))
	result.append(choice("画面", "effects_density", "特效密度", ["极少", "中等", "全部"], [0, 1, 2], values))
	result.append(choice("画面", "reduce_player_effects", "减少玩家特效", ["开启", "关闭"], [true, false], values))
	result.append(choice("画面", "scene_detail", "场景细节", ["极少", "中等", "全部"], [0, 1, 2], values))
	result.append(choice("画面", "idle_power_saving", "无操作时进入省电模式", ["开启", "关闭"], [true, false], values))
	result.append(slider("画面", "effects_opacity", "特效透明度", values))
	for item in [["volume_master", "主音量"], ["volume_music", "音乐音量"], ["volume_effects", "音效音量"], ["volume_voice", "语音音量"]]:
		result.append(slider("声音", item[0], item[1], values))
	return result

static func choice(section: String, key: String, title: String, labels: Array, ids: Array, values: Dictionary, description := "") -> Dictionary:
	var options: Array = []
	for index in labels.size():
		options.append({"text": labels[index], "action": "setting:" + key, "id": ids[index], "selected": values[key] == ids[index]})
	return {"section": section, "key": key, "title": title, "description": description, "options": options}

static func slider(section: String, key: String, title: String, values: Dictionary, description := "") -> Dictionary:
	return {"section": section, "key": key, "title": title, "description": description,
		"controls": [{"type": "slider", "action": "setting:" + key, "value": values[key], "min": RANGES[key].x, "max": RANGES[key].y, "step": 1}]}
