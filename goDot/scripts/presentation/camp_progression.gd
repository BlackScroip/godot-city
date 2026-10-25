extends RefCounted

# Both ArtLayer and EnvFunc contain these exact APK names. Their shared whitebox
# collision layer has no per-building variants and must remain unchanged.
const VARIANTS := {
	1: ["居所Container", "居所废墟", "居所"],
	2: ["冒险者协会Container", "冒险者协会废墟", "冒险者协会"],
	3: ["铁匠铺Container", "铁匠铺废墟", "铁匠铺"],
	4: ["遗物图鉴Container", "遗物图鉴废墟", "遗物图鉴"],
	5: ["任务板Container", "任务板废墟", "任务板"],
	6: ["怪物工作点Container", "怪物工作废墟", "怪物工作"],
	7: ["篝火酒馆Container", "篝火酒馆废墟", "篝火酒馆"]
}

var active_nodes: Dictionary = {}
var variant_nodes: Dictionary = {}
var variants: Array[Dictionary] = []
var signature := ""
var _levels: Dictionary = {}

func apply(root: Node3D, levels: Dictionary) -> void:
	active_nodes.clear()
	variant_nodes.clear()
	variants.clear()
	_levels = levels
	var ranks: Array = []
	for id in VARIANTS: ranks.append(int(levels.get(str(id), 0)))
	signature = JSON.stringify(ranks)
	_walk(root, "", true, false)

func _walk(node: Node, parent_name: String, parent_active: bool, inside_variant: bool) -> void:
	var extras: Dictionary = node.get_meta("extras", {})
	var source_name := str(extras.get("unityName", str(node.name)))
	var active := bool(extras.get("unityActive", true))
	for id in VARIANTS:
		var pair: Array = VARIANTS[id]
		if parent_name != pair[0] or source_name not in [pair[1], pair[2]]: continue
		var built: bool = source_name == pair[2]
		active = built == (int(_levels.get(str(id), 0)) >= 1)
		inside_variant = true
		if node is Node3D:
			node.visible = active
			node.set_meta("unityActive", active)
		variants.append({"building_id": id, "built": built, "node": node, "active": active})
		break
	var effective := parent_active and active
	if inside_variant and node is Node3D:
		node.visible = active
	active_nodes[str(node.name)] = effective
	if inside_variant: variant_nodes[str(node.name)] = true
	for child in node.get_children(): _walk(child, source_name, effective, inside_variant)

func controls(node_name: String) -> bool:
	return variant_nodes.has(node_name)

func collider_active(marker: Dictionary) -> bool:
	var node_name := str(marker.get("exported_node_name", ""))
	if not controls(node_name): return bool(marker.get("active", true))
	return bool(active_nodes.get(node_name, false))
