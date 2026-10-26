extends SceneTree

const Effect = preload("res://scripts/presentation/authored_effect.gd")
const CASES = [
	{"effect": "25011002_fx_enemy_sishen_attck2_slash", "layer": "25011001_slash_fog", "soft_boundary": true, "ground_fade": true, "edges": [Vector2(0.01, 0.5), Vector2(0.99, 0.5), Vector2(0.5, 0.01), Vector2(0.5, 0.99)]},
	{"effect": "240821_fx_satk_wand_test", "layer": "23082401_blast_blast3", "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99), Vector2(0.99, 0.5)]},
	{"effect": "24091101_fx_orb_satk_launch", "layer": "24091101_launch_diffusion", "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99), Vector2(0.99, 0.5)]},
	{"effect": "24091101_fx_orb_satk_launch", "layer": "24091101_launch_flash", "edges": [Vector2(0.01, 0.01), Vector2(0.99, 0.99)]},
	{"effect": "24091101_fx_orb_satk_accumulation", "layer": "24091101_accumulation_line", "edges": [Vector2(0.5, 0.01)]},
	{"effect": "24091101_fx_orb_satk_accumulation", "layer": "24091101_accumulation_shrinkring", "inactive": true, "edges": [Vector2(0.01, 0.01), Vector2(0.99, 0.99)]},
	{"effect": "24091101_fx_orb_satk_accumulation", "layer": "24091101_accumulation_prickring", "edges": [Vector2(0.01, 0.01), Vector2(0.99, 0.99)]},
	{"effect": "24091101_fx_orb_satk_blackholemobile", "layer": "24091101_blackholemobile_helix", "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99)]},
	{"effect": "24091101_fx_orb_satk_around", "layer": "24091101_around_airwave", "soft_boundary": true, "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99)]},
	{"effect": "26072501_fx_lance_satk_blast3", "layer": "23090801_accumulation3_smokelight", "edges": [Vector2(0.5, 0.01)]},
	{"effect": "26072501_fx_lance_satk_blast3", "layer": "23090801_accumulation3_sidsmokeright", "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99), Vector2(0.99, 0.5)]},
	{"effect": "26072501_fx_lance_satk_blast3", "layer": "26072501_accumulation3_qiliu", "edges": [Vector2(0.5, 0.01)]},
	{"effect": "26072501_fx_lance_satk_blast3", "layer": "26072501_accumulation3_smokewhite", "soft_boundary": true, "edges": [Vector2(0.01, 0.5), Vector2(0.99, 0.5), Vector2(0.5, 0.01), Vector2(0.5, 0.99)]},
	{"effect": "25123101_fx_lance_satk_spear", "layer": "25123101_spear_airflow", "soft_boundary": true, "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99)]},
	{"effect": "25123101_fx_lance_satk_spear", "layer": "25123101_spear_floorsmoke", "soft_boundary": true, "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99)]},
	{"effect": "25123101_fx_lance_satk_sprint", "layer": "25123101_sprint_sidesmoke", "soft_boundary": true, "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99)]},
	{"effect": "25123101_fx_lance_satk_spearice", "layer": "25123101_spearice_smoke", "alpha_texture": true, "edges": [Vector2(0.5, 0.01), Vector2(0.5, 0.99), Vector2(0.99, 0.5)]}
]

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var media: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat_presentation/catalog.json"))
	var textures: Dictionary = {}
	for key in media.texture_sources:
		var path = "res://assets/combat_presentation/" + str(key)
		textures[path] = load(path)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2
	viewport.add_child(camera)
	camera.position.z = 2
	var quad = MeshInstance3D.new()
	var mesh = QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	viewport.add_child(quad)
	var render_check = DisplayServer.get_name() != "headless"
	for test in CASES:
		var effect = Effect.new()
		root.add_child(effect)
		effect.configure(media.effects[test.effect], false, textures)
		var selected: ShaderMaterial
		for emitter in effect.emitters:
			if str(emitter.node.get_parent().get_meta("source_layer", "")) == str(test.layer):
				selected = emitter.node.material_override.duplicate()
				break
		if test.get("inactive", false):
			var source_layer: Dictionary = {}
			for layer in media.effects[test.effect].layers:
				if str(layer.get("name", "")) == str(test.layer):
					source_layer = layer
					break
			check(not source_layer.is_empty() and source_layer.get("active", true) == false, "%s remains disabled in the authored source" % test.layer)
			check(selected == null, "%s does not create a renderer for its disabled source layer" % test.layer)
			effect.free()
			continue
		check(selected != null, "%s retains an authored source material" % test.layer)
		if selected == null:
			effect.free()
			continue
		if test.get("alpha_texture", false):
			var texture: Texture2D = selected.get_shader_parameter("main_texture")
			check(texture.get_image().get_pixel(0, 0).a == 0, "Smoke atlas retains the original alpha channel")
		elif test.get("soft_boundary", false):
			check(selected.get_shader_parameter("edge_feather").length() > 0, "%s tapers the boundary of its recovered smoke mesh" % test.layer)
		else:
			check(selected.get_shader_parameter("use_opacity_mask") == true, "%s restores its original MASK_ON binding" % test.layer)
			check(selected.get_shader_parameter("opacity_mask") is Texture2D, "%s resolves its original mask texture" % test.layer)
		selected.set_shader_parameter("billboard", false)
		if test.get("ground_fade", false): check(selected.get_shader_parameter("ground_feather") == 0.5, "Monster fog enables its isolated reconstructed ground fade")
		selected.set_shader_parameter("vertical_billboard", false)
		selected.set_shader_parameter("stretched_billboard", false)
		selected.set_shader_parameter("use_motion_curve", false)
		selected.set_shader_parameter("initial_rotation", Vector2.ZERO)
		quad.material_override = selected
		effect.free()
		if not render_check: continue
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image = viewport.get_texture().get_image()
		image.save_png("res://reports/particle-opacity-%s.png" % test.layer)
		var maximum := 0.0
		for y in range(0, 256, 4):
			for x in range(0, 256, 4): maximum = maxf(maximum, image.get_pixel(x, y).a)
		check(maximum > 0.05, "%s preserves a visible source silhouette" % test.layer)
		if test.get("ground_fade", false): check(image.get_pixel(128, 128).a < 0.04, "Monster fog becomes transparent at its ground intersection while upper pixels remain visible")
		for uv in test.edges:
			var alpha = image.get_pixel(clampi(int(uv.x * 256), 0, 255), clampi(int(uv.y * 256), 0, 255)).a
			check(alpha < 0.04, "%s source transparent boundary remains transparent at %s (%.3f)" % [test.layer, uv, alpha])
	var report = {"checks": checks, "failures": failures, "source_materials": CASES.size(), "render_check": render_check}
	FileAccess.open("res://reports/particle-opacity-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PARTICLE_OPACITY ", JSON.stringify(report))
	viewport.free()
	quit(0 if failures.is_empty() else 1)
