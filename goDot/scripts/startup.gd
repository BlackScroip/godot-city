extends Node

signal progress_changed(value: float)
signal game_started

const START_SCREEN = preload("res://scripts/presentation/start_screen.gd")
const LOADING_SCREEN = preload("res://scripts/presentation/room_loading.gd")

var home: CanvasLayer
var loading: CanvasLayer
var game: Node
var game_scene_path := "res://scenes/main.tscn"
var game_save_store: RefCounted
var starting := false
var progress := 0.0
var _failure := ""

func _ready() -> void:
	home = START_SCREEN.new()
	add_child(home)
	home.start_requested.connect(start_game)
	# Automated gameplay and stress runs keep their existing command-line entry.
	var arguments := OS.get_cmdline_user_args()
	if "--smoke" in arguments or "--combat-stress" in arguments or OS.has_feature("combat_stress"):
		start_game.call_deferred()

func start_game() -> void:
	if starting or is_instance_valid(game): return
	starting = true
	_failure = ""
	progress = 0.0
	if not is_instance_valid(loading):
		loading = LOADING_SCREEN.new()
		add_child(loading)
		loading.layer = 120
		loading.background.texture = DungeonStyle.texture("res://assets/ui/startup/e76a9cb5b6a12219.png")
		loading.spinner.texture = DungeonStyle.texture("res://assets/ui/startup/defcfb2d44073301.png")
		for state in ["background", "fill"]:
			var style := StyleBoxTexture.new()
			style.texture = DungeonStyle.texture("res://assets/ui/startup/" + ("26fe7e0733f7d881.png" if state == "background" else "a3280fd8712d6865.png"))
			loading.progress_bar.add_theme_stylebox_override(state, style)
	loading.begin("进入游戏")
	home.hide()
	_set_progress(0.0)
	await get_tree().process_frame
	if not ResourceLoader.exists(game_scene_path):
		_fail("游戏资源加载失败，请重试")
		return
	var result := ResourceLoader.load_threaded_request(game_scene_path)
	if result != OK:
		_fail("游戏资源加载失败，请重试")
		return
	var resource_progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(game_scene_path, resource_progress)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_set_progress(float(resource_progress[0]) * 0.3 if not resource_progress.is_empty() else 0.0)
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(game_scene_path, resource_progress)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_fail("游戏资源加载失败，请重试")
		return
	var scene := ResourceLoader.load_threaded_get(game_scene_path) as PackedScene
	if not scene:
		_fail("游戏场景无法打开，请重试")
		return
	_set_progress(0.3)
	await get_tree().process_frame
	game = scene.instantiate()
	if "--combat-stress" in OS.get_cmdline_user_args() or OS.has_feature("combat_stress"):
		add_child(game)
		_complete()
		return
	game.startup_loading = true
	if game_save_store: game.save_store = game_save_store
	game.initialization_progress.connect(func(value: float): _set_progress(0.3 + value * 0.6))
	game.initialization_failed.connect(func(message: String): _failure = message)
	add_child(game)
	var deadline := Time.get_ticks_msec() + 60000
	while (not game.initialized or game._transitioning) and _failure.is_empty():
		if Time.get_ticks_msec() >= deadline:
			_failure = "进入游戏超时，请重试"
			break
		await get_tree().process_frame
	if not _failure.is_empty():
		_fail(_failure)
		return
	_set_progress(1.0)
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	_complete()

func _set_progress(value: float) -> void:
	progress = maxf(progress, clampf(value, 0.0, 1.0))
	loading.set_progress(progress)
	progress_changed.emit(progress)

func _complete() -> void:
	game.startup_loading = false
	loading.finish()
	home.queue_free()
	starting = false
	game_started.emit()

func _fail(message: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		game = null
	loading.finish()
	starting = false
	home.show_error(message)
