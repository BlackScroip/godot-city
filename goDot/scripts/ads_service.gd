extends Node

signal message(text: String)
signal finished

var bridge: Object
var configuration: Dictionary = {}
var pending: Dictionary = {}
var initialized := false
var ad_ready := false
var initializing := false
var clock := 0.0
var sequence := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var platform = "android" if OS.get_name() == "Android" else "ios" if OS.get_name() == "iOS" else ""
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ads.json"))
	if data is Dictionary: configuration = data.get(platform, {})
	if Engine.has_singleton("DungeonAds"): bridge = Engine.get_singleton("DungeonAds")
	elif ClassDB.class_exists("DungeonAds"): bridge = ClassDB.instantiate("DungeonAds")

func available() -> bool:
	return bridge != null and not configuration.get("rewarded_placement_id", "").is_empty()

func busy() -> bool:
	return not pending.is_empty()

func request(scene: String, grant: Callable) -> bool:
	if busy(): return false
	if not available():
		message.emit("当前版本暂不支持广告")
		return false
	sequence += 1
	pending = {"id": str(Time.get_ticks_usec()) + "-" + str(sequence), "scene": scene, "grant": grant, "earned": false, "showing": false}
	clock = 0.0
	message.emit("广告准备中")
	if not initialized:
		if not initializing:
			initializing = true
			bridge.call("configure", str(configuration.app_id), str(configuration.app_key), str(configuration.rewarded_placement_id))
	elif ad_ready: _show()
	else: bridge.call("load_rewarded")
	return true

func cancel() -> void:
	if pending.get("showing", false): return
	pending.clear()
	finished.emit()

func _show() -> void:
	if pending.is_empty() or pending.showing: return
	pending.showing = true
	ad_ready = false
	bridge.call("show_rewarded", str(pending.id), str(pending.scene))

func _process(delta: float) -> void:
	if bridge == null: return
	var events = JSON.parse_string(str(bridge.call("poll_events")))
	if events is Array:
		for event in events:
			if event is Dictionary: handle_event(event)
	if busy() and not pending.showing:
		clock += delta
		if clock > 60.0:
			message.emit("广告准备超时，请稍后重试")
			initializing = false
			if bridge.has_method("reset_preparation"): bridge.call("reset_preparation")
			cancel()

func handle_event(event: Dictionary) -> void:
	var kind = str(event.get("type", ""))
	if kind == "initialized":
		initializing = false
		initialized = true
		bridge.call("load_rewarded")
	elif kind == "ready":
		ad_ready = true
		_show()
	elif kind in ["init_failed", "load_failed"]:
		if kind == "init_failed": initializing = false
		ad_ready = false
		if busy() and not pending.showing:
			message.emit("广告暂不可用，请稍后重试")
			cancel()
	elif busy() and str(event.get("id", "")) == str(pending.id):
		if kind == "reward" and pending.showing and not pending.earned:
			pending.earned = true
			pending.grant.call()
		elif kind in ["closed", "show_failed"]:
			if not pending.earned: message.emit("未获得广告奖励")
			pending.clear()
			finished.emit()
			bridge.call("load_rewarded")
