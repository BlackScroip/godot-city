class_name DungeonItemArt
extends RefCounted

static var cache: Dictionary = {}
static var relics: Dictionary = {}
static var relics_loaded := false

static func source_texture(id: int, material := false) -> Texture2D:
	var key := "source:%s:%d" % [material, id]
	if cache.has(key): return cache[key]
	var path := "res://assets/ui/pickup/sprite_%sicon_%d.png" % ["material" if material else "abilityitem", id]
	cache[key] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return cache[key]

static func ground_texture(id: int, material := false) -> Texture2D:
	var source := source_texture(id, material)
	if source: return source
	return texture(id, material)

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
	var source := source_texture(id, material)
	if source:
		cache[key] = source
		return source
	var color = Color.from_hsv(fposmod(id * 0.137, 1.0), 0.65, 0.95).to_html(false)
	var shape = ""
	if material and id == 101:
		shape = '<circle cx="64" cy="65" r="43" fill="#e9b63b"/><circle cx="64" cy="65" r="33" fill="none" stroke="#ffe898" stroke-width="5"/><path d="M64 39L83 64L64 90L45 64Z" fill="#fff09a"/>'
	elif material and id == 102:
		shape = '<circle cx="64" cy="68" r="40" fill="#224ddc"/><path d="M37 76Q65 94 88 51Q96 93 57 99Z" fill="#61bfff"/><ellipse cx="48" cy="47" rx="12" ry="18" fill="#c8faff" transform="rotate(32 48 47)"/>'
	elif not material and id == 11005:
		shape = '<path d="M56 65L29 113Q29 119 36 118L65 70Z" fill="#e9d2aa"/><path d="M37 108L59 70" stroke="#fff4d7" stroke-width="2"/><circle cx="77" cy="40" r="30" fill="url(#candy)"/><circle cx="77" cy="40" r="25" fill="none" stroke="#f6bbd8" stroke-width="3"/><path d="M76 19C49 22 52 58 77 59C100 59 104 28 83 27C65 23 61 46 76 48C88 52 94 36 82 35C75 33 71 41 78 42" fill="none" stroke="#fff0c8" stroke-width="4"/><path d="M60 70C43 57 34 65 44 76C28 78 35 90 57 77C70 96 81 88 69 77C88 76 80 62 65 70Z" fill="#9b7da9"/><path d="M57 74L45 96L57 91L62 96L65 76" fill="#b795c4"/><ellipse cx="61" cy="72" rx="7" ry="6" fill="#dbb4d5"/>'
	elif not material and id in [11101, 11102, 11103]:
		shape = '<path d="M49 21C21 25 14 52 29 66C25 46 35 35 49 21ZM84 17C109 24 117 47 104 62C107 42 96 29 84 17ZM91 88C67 113 42 103 36 87C55 97 77 96 91 88Z" fill="#9ce9ed" stroke="#5b95ae" stroke-width="2"/><circle cx="65" cy="62" r="24" fill="url(#magic)"/><path d="M49 73C58 85 81 77 85 58C89 79 70 91 54 83Z" fill="#3553e3" stroke="none"/><ellipse cx="56" cy="49" rx="7" ry="10" fill="#a2f5ff" stroke="none" transform="rotate(34 56 49)"/><circle cx="48" cy="66" r="3" fill="#e9ffff" stroke="none"/>'
	elif not material and id == 16101:
		shape = '<path d="M48 17L43 9L29 15L14 32L20 53L34 55L36 79L29 107L49 116L64 105L79 116L99 107L92 79L94 55L108 53L114 32L99 15L85 9L80 17L64 22Z" fill="url(#bronze)"/><path d="M48 17L47 38L64 45L81 38L80 17M34 55L48 59L64 54L80 59L94 55M36 79L51 84L64 80L77 84L92 79M31 98L51 103L64 98L77 103L97 98M51 84L49 116M77 84L79 116" fill="none" stroke="#78554d" stroke-width="3"/><path d="M29 15L35 35L27 47M99 15L93 35L101 47M53 28L62 32L74 28M49 61L49 75M79 61L79 75" fill="none" stroke="#e6bfa0" stroke-width="4"/><path d="M61 47L61 78M43 88L40 96M85 88L88 96" stroke="#b17e6e" stroke-width="3"/>'
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
	var definitions = '<defs><radialGradient id="candy" cx=".35" cy=".3"><stop stop-color="#fff1bc"/><stop offset=".65" stop-color="#e6a5c6"/><stop offset="1" stop-color="#a676b2"/></radialGradient><radialGradient id="magic" cx=".3" cy=".2"><stop stop-color="#39cbfc"/><stop offset=".55" stop-color="#1246d9"/><stop offset="1" stop-color="#12266f"/></radialGradient><linearGradient id="bronze" x2="1" y2="1"><stop stop-color="#d7aa8d"/><stop offset=".45" stop-color="#b38270"/><stop offset="1" stop-color="#875a51"/></linearGradient></defs>'
	var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">%s<g stroke="#27352e" stroke-width="5" stroke-linejoin="round">%s</g></svg>' % [definitions, shape]
	var image = Image.new()
	image.load_svg_from_string(svg)
	cache[key] = ImageTexture.create_from_image(image)
	return cache[key]
