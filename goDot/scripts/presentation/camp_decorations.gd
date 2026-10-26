extends RefCounted

const INDEX_PATH = "res://assets/environments/camp_decorations/index.json"
var index: Dictionary = {}
var installed: Dictionary = {}
var diagnostics: Array[String] = []
var _root_id := 0
var _scenes: Dictionary = {}

func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if parsed is Dictionary: index = parsed

func apply(root: Node3D, decorations) -> void:
	if _root_id != root.get_instance_id():
		installed.clear()
		_root_id = root.get_instance_id()
	for slot in decorations.slots():
		var slot_id := int(slot.slot_id)
		var selected := int(slot.display_id)
		var previous: Dictionary = installed.get(slot_id, {})
		if not previous.is_empty() and int(previous.id) == selected:
			_hide_baseline(previous.container, previous.children)
			continue
		if not previous.is_empty():
			previous.node.get_parent().remove_child(previous.node)
			previous.node.queue_free()
			installed.erase(slot_id)
		if selected in [int(slot.default_decoration_id), int(slot.locked_decoration_id)]: continue
		var placement: Dictionary = index.get("scene_placement", {}).get("slots", {}).get(str(slot_id), {}).get("baseline", {})
		var entry: Dictionary = index.get("decorations", {}).get(str(selected), {})
		var container = root.find_child(str(placement.get("exported_node_name", "")), true, false)
		if not container is Node3D or entry.is_empty():
			_diagnose("Missing decoration placement or prefab: %d" % selected)
			continue
		var path := str(entry.get("path", ""))
		if not _scenes.has(path): _scenes[path] = load(path)
		var source = _scenes[path]
		if not source is PackedScene:
			_diagnose("Decoration scene could not load: " + path)
			continue
		var node = source.instantiate()
		node.name = "CampDecoration_%d" % selected
		node.set_meta("camp_decoration_id", selected)
		container.add_child(node)
		if node is Node3D: node.transform = Transform3D.IDENTITY
		var children: Array = placement.get("replace_children", [])
		_hide_baseline(container, children)
		installed[slot_id] = {"id": selected, "node": node, "container": container, "children": children}

func _hide_baseline(container: Node, children: Array) -> void:
	for name in children:
		var child = container.get_node_or_null(NodePath(str(name)))
		if child is Node3D: child.visible = false

func _diagnose(message: String) -> void:
	if not diagnostics.has(message): diagnostics.append(message)
