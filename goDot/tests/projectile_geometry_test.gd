extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _run() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.paused = true
	world.presentation.audio_enabled = false
	var actor := DungeonActor.new()
	actor.combat = DungeonCombat.new()
	actor.combat.configure_enemy(13001)
	root.add_child(actor)
	var key := "25032101_fx_enemy_zhadanchuanshanjia_support1"
	var definition: Dictionary = world.presentation.media.effects[key]
	var original: Node3D = load(definition.models[0].scene).instantiate()
	var source_meshes: Dictionary = {}
	for mesh: MeshInstance3D in original.find_children("*", "MeshInstance3D", true, false):
		source_meshes[mesh.name] = {"mesh": mesh.mesh, "shadow": mesh.cast_shadow}
	check(not source_meshes.is_empty(), "The fixture uses a real recovered APK model")
	var event := {"damage": 10.0, "sequence": 1, "source_key": "fixture", "definition": {"raw": JSON.stringify({"MotionAnimatorType": "EMAT_Line", "MotionAnimatorProperty": {"Speed": 8, "MaxLifetime": 4}, "EntityProperty": {"ModlePrefab": key, "MaxPassNum": 3, "ColliderType": "Sphere", "ModelBoxColliderSize": {"x": 1.2, "y": 1.2, "z": 1.2}}})}}
	var projectile := DungeonProjectile.new()
	projectile.configure(event, Vector3.UP, Vector3.FORWARD, Vector3.FORWARD * 3)
	projectile.source_key = "fixture"
	var before := projectile.snapshot()
	world._add_projectile_visual(projectile, actor)
	var fallback: MeshInstance3D = world.projectiles.back().visual
	check(fallback.mesh == world._projectile_mesh, "Fallback projectiles share their geometry")
	check(world._projectile_mesh.get_faces().size() / 3 == 168, "The tiny fallback sphere has 168 triangles")
	check(is_equal_approx(world._projectile_mesh.radius, 0.13) and is_equal_approx(world._projectile_mesh.height, 0.26), "Fallback sphere dimensions are preserved")
	check(fallback.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Only the fallback sphere skips its shadow pass")
	check(projectile.snapshot() == before, "Attaching visual geometry does not change projectile state")
	check(is_equal_approx(projectile.radius, 0.6) and projectile.entity.ColliderType == "Sphere", "Authored collision size stays independent of the visual sphere")
	check(not world.presentation.active.is_empty(), "The recovered projectile model remains emitted")
	var authored: Node3D = world.presentation.active.back().authored
	check(authored != null, "The projectile retains its authored model renderer")
	if authored:
		var actual := 0
		for mesh: MeshInstance3D in authored.find_children("*", "MeshInstance3D", true, false):
			if not source_meshes.has(mesh.name): continue
			actual += 1
			check(mesh.mesh == source_meshes[mesh.name].mesh, "Recovered model geometry remains shared and unchanged")
			check(mesh.cast_shadow == source_meshes[mesh.name].shadow, "Recovered model shadow mode is preserved")
		check(actual == source_meshes.size(), "Every recovered source mesh remains present")
	print("PROJECTILE_GEOMETRY ", JSON.stringify({"checks": checks, "failures": failures}))
	original.free()
	actor.queue_free()
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
