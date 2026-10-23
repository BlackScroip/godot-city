class_name DungeonItemArt
extends RefCounted

static var cache: Dictionary = {}
static var relics: Dictionary = {}
static var relics_loaded := false

static func _load_relics() -> void:
	if relics_loaded: return
	relics_loaded = true
	var path = "res://assets/art_generated/relics/manifest.json"
	if not FileAccess.file_exists(path): return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary: return
	for item in manifest.get("items", []): relics[int(item.id)] = item

static func relic_info(id: int) -> Dictionary:
	_load_relics()
	return relics.get(id, {})

static func texture(id: int, material := false) -> Texture2D:
	var key = "%s:%d" % [material, id]
	if cache.has(key): return cache[key]
	if not material:
		var relic = relic_info(id)
		if not relic.is_empty() and ResourceLoader.exists(str(relic.path)):
			cache[key] = load(str(relic.path)) as Texture2D
			return cache[key]
	var color = Color.from_hsv(fposmod(id * 0.137, 1.0), 0.65, 0.95).to_html(false)
	var shape = ""
	if material and id == 101:
		shape = '<circle cx="64" cy="65" r="43" fill="#e9b63b"/><circle cx="64" cy="65" r="33" fill="none" stroke="#ffe898" stroke-width="5"/><path d="M64 39L83 64L64 90L45 64Z" fill="#fff09a"/>'
	elif material and id == 102:
		shape = '<circle cx="64" cy="68" r="40" fill="#224ddc"/><path d="M37 76Q65 94 88 51Q96 93 57 99Z" fill="#61bfff"/><ellipse cx="48" cy="47" rx="12" ry="18" fill="#c8faff" transform="rotate(32 48 47)"/>'
	elif id == 12101:
		shape = '<path d="M64 12L99 38L107 80L64 114L21 80L29 38Z" fill="#40d96e"/><path d="M42 58Q25 34 44 31Q59 27 64 41Q74 26 87 33Q104 46 64 81Z" fill="#d8ffb2"/><path d="M25 91Q87 111 106 35" fill="none" stroke="#e4ffd4" stroke-width="5"/>'
	elif material and id == 10501 or id in [10100, 10101, 10102]:
		shape = '<path d="M48 20L80 20L80 43Q104 59 99 98Q65 116 29 98Q24 60 48 43Z" fill="#d1cbea"/><path d="M34 72Q65 61 95 72L92 95Q64 108 36 95Z" fill="#8842df"/><path d="M46 12L82 12L82 29L46 29Z" fill="#ceb67c"/><path d="M41 57L38 83" stroke="#ffffff" stroke-width="6"/>'
	elif id == 20103:
		shape = '<path d="M100 108Q54 93 30 26Q71 35 80 79Q52 49 58 12Q99 46 80 85Z" fill="#b5d56c"/><path d="M100 108Q65 82 42 43M80 85Q73 48 60 22" fill="none" stroke="#546b36" stroke-width="5"/>'
	elif id >= 20210 and id <= 20312:
		color = {20210:"f57b2c",20220:"4dc9f5",20230:"82c943",20240:"ebd552",20250:"ffe699",20260:"a15bea",20300:"e7b743"}.get(id / 10 * 10, color)
		shape = '<path d="M48 39Q28 18 65 8Q47 27 78 27Q101 35 88 50Q110 70 96 94L80 108L64 101L47 108L29 91Q18 60 48 39Z" fill="#%s"/><path d="M42 64L54 68L52 81L43 79ZM74 68L86 64L85 79L76 81Z" fill="#fff3bc" stroke="none"/><path d="M39 48Q60 32 86 49" fill="none" stroke="#ffffff" stroke-opacity=".45" stroke-width="5"/>' % color
	else:
		shape = '<path d="M64 12L103 40L108 82L64 114L20 82L25 40Z" fill="#%s"/><path d="M64 12L75 47L103 40M75 47L64 114L46 72L25 40M46 72L108 82" fill="none" stroke="#ffffff" stroke-opacity=".55" stroke-width="3"/><circle cx="59" cy="54" r="12" fill="#ffffff" fill-opacity=".8"/>' % color
	var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><g stroke="#27352e" stroke-width="5" stroke-linejoin="round">%s</g></svg>' % shape
	var image = Image.new()
	image.load_svg_from_string(svg)
	cache[key] = ImageTexture.create_from_image(image)
	return cache[key]
