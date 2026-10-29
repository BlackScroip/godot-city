extends SceneTree

const Interactions = preload("res://scripts/world_interactions.gd")

var checks := 0
var failures: Array[String] = []

class ReferenceInteractions extends DungeonWorldInteractions:
	func _volumes(item: Dictionary, role: String) -> Array:
		if role.is_empty(): return item.colliders
		return item.colliders.filter(func(collider): return ("/" + str(collider.get("path", "")) + "/").contains("/" + role + "/"))

	func _contains(item: Dictionary, position: Vector3, actor_radius: float = 0, role: String = "", solids_only: bool = false) -> bool:
		var local_position := _root.global_transform.affine_inverse() * position if is_instance_valid(_root) and _root.is_inside_tree() else position
		for collider in _volumes(item, role):
			var properties: Dictionary = collider.get("properties", {})
			var active_trap_volume := role == "Container_EffectTrigger" and str(item.marker.get("Type", "")) == "EEUT_TriggerTrap" and str(item.state.phase) == "active"
			if not collider.get("active", true) or (not properties.get("m_Enabled", 1) and not active_trap_volume) or (solids_only and properties.get("m_IsTrigger", 0)): continue
			var matrix := _matrix(collider.get("world_matrix", []))
			if absf(matrix.basis.determinant()) < 0.00000001: continue
			var center := _vector(properties.get("m_Center", {}))
			var scale := matrix.basis.get_scale().abs()
			var point := matrix.affine_inverse() * local_position - center
			match int(collider.get("kind", 0)):
				65:
					var half := _vector(properties.get("m_Size", {})).abs() * 0.5
					var offset := (point.abs() - half).max(Vector3.ZERO) * scale
					if offset.length_squared() <= actor_radius * actor_radius: return true
				135:
					var radius := float(properties.get("m_Radius", 0)) * maxf(scale.x, maxf(scale.y, scale.z))
					if local_position.distance_to(matrix * center) <= radius + actor_radius: return true
				136:
					var axis := int(properties.get("m_Direction", 1))
					var radius := float(properties.get("m_Radius", 0)) * maxf(scale[(axis + 1) % 3], scale[(axis + 2) % 3])
					var half_length := maxf(0, float(properties.get("m_Height", 0)) * scale[axis] * 0.5 - radius)
					var world_axis := matrix.basis[axis].normalized()
					var relative := local_position - matrix * center
					if (relative - world_axis * clampf(relative.dot(world_axis), -half_length, half_length)).length() <= radius + actor_radius: return true
				64: _diagnose(item.id, "unsupported_interaction_mesh_volume", str(collider.get("fileID", "")))
		return false

	func tick(delta: float, player_position: Vector3, targets: Array = []) -> void:
		if not is_finite(delta) or delta <= 0: return
		var all_targets: Array = [{"id": "player", "position": player_position, "camp": 2}]
		all_targets.append_array(targets)
		var remaining := delta
		var frame_hits: Dictionary = {}
		while remaining > 0:
			var step := minf(0.02, remaining)
			remaining -= step
			for item in _ticked_items:
				if not item.state.enabled or item.state.broken: continue
				match str(item.marker.get("Type", "")):
					"EEUT_StageChangeDoor":
						item.state.idle_remaining = maxf(0.0, float(item.state.idle_remaining) - step)
					"EEUT_DestoryableItem":
						var touching := _contains(item, player_position + Vector3.UP * 0.8, 0.35)
						if touching and not item.state.inside:
							_effect(item, "TriggerTouchUnitPlayEffect")
							_sound(item, "TriggerTouchUnitSoundName")
						item.state.inside = touching
						if item.state.breaking:
							item.state.break_remaining = maxf(0, float(item.state.break_remaining) - step)
							if item.state.break_remaining <= 0: _finish_break(item)
					"EEUT_TriggerTrap":
						var trigger_inside := all_targets.any(func(target): return target.get("position") is Vector3 and camp_allows(str(item.definition.get("TargetCampString", "")), int(target.get("camp", 0))) and _contains(item, target.position + Vector3.UP * 0.8, 0.35, "Container_EnterTrigger"))
						_advance_trap(item, step, trigger_inside)
						if item.state.phase != "active": continue
						_affect_trap_environment(item)
						if float(item.state.hit_cooldowns.get("*", 0)) > 0.0000001: continue
						var affected := false
						for target in all_targets:
							if not target.get("position") is Vector3: continue
							if not _contains(item, target.position + Vector3.UP * 0.8, 0.35, "Container_EffectTrigger"): continue
							affected = _affect(item, target, frame_hits) or affected
						if affected and str(item.definition.get("TriggerTimesType", "")) == "CustomTimeInterval":
							item.state.hit_cooldowns["*"] = float(item.definition.TriggerCustomParam1)
					"EEUT_AttractTrap":
						_attract(item, step, all_targets)
						player_position = all_targets[0].position
					"EEUT_PlayerTrigger", "EEUT_SimpleTalkTrigger":
						item.state.talk_delay = maxf(0, float(item.state.talk_delay) - step)
						var inside := _contains(item, player_position + Vector3.UP * 0.8, 0.35)
						if inside and not item.state.inside and item.state.talk_delay <= 0:
							var name := str(item.data.get("TriggerFuncMsg_Name", "UI_PlaySimpleTalk"))
							var context := _context(item)
							if item.data.get("ActivedSwitchFalse", false): item.state.enabled = false
							item.state.used = true
							_changed(item)
							if str(item.marker.get("Type", "")) == "EEUT_PlayerTrigger":
								player_trigger_entered.emit(int(item.data.get("TriggerId", -1)), context)
							if not name.is_empty(): message_requested.emit(name, context)
						item.state.inside = inside

class TracedCurrent extends DungeonWorldInteractions:
	var calls: Array = []
	func _contains(item: Dictionary, position: Vector3, actor_radius: float = 0, role: String = "", solids_only: bool = false) -> bool:
		calls.append([item.id, position, actor_radius, role, solids_only])
		return super(item, position, actor_radius, role, solids_only)

class TracedReference extends ReferenceInteractions:
	var calls: Array = []
	func _contains(item: Dictionary, position: Vector3, actor_radius: float = 0, role: String = "", solids_only: bool = false) -> bool:
		calls.append([item.id, position, actor_radius, role, solids_only])
		return super(item, position, actor_radius, role, solids_only)

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _matrix_at(x: float = 0) -> Array:
	return [1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]

func _volume(kind: int, path: String = "Test/object/Container_EffectTrigger", x: float = 0) -> Dictionary:
	return {"fileID": str(kind) + path, "path": path, "kind": kind, "active": true, "world_matrix": _matrix_at(x), "properties": {"m_Center": {"x": 0.0, "y": 0.0, "z": 0.0}, "m_Size": {"x": 2.0, "y": 2.0, "z": 2.0}, "m_Radius": 1.0, "m_Height": 4.0, "m_Direction": 1, "m_IsTrigger": 0, "m_Enabled": 1}}

func _item(colliders: Array, kind: String = "EEUT_TriggerTrap") -> Dictionary:
	return {"id": "object", "marker": {"Type": kind}, "state": {"phase": "idle"}, "colliders": colliders}

func _setup(interactions: DungeonWorldInteractions, environment: Node3D) -> void:
	interactions.setup(environment, [], {"scene": "Test", "rules": {"Bindings": [], "Definitions": []}, "colliders": []})

func _compare(current: DungeonWorldInteractions, reference: DungeonWorldInteractions, item: Dictionary, position: Vector3, radius: float, role: String, solids: bool, label: String) -> void:
	check(current._contains(item, position, radius, role, solids) == reference._contains(item, position, radius, role, solids), label)
	check(current.diagnostics == reference.diagnostics, label + " diagnostics")

func _test_volumes_and_shapes() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var environment := Node3D.new()
	parent.add_child(environment)
	var current := Interactions.new()
	var reference := ReferenceInteractions.new()
	_setup(current, environment)
	_setup(reference, environment)
	var collider := _volume(65)
	var item := _item([collider])
	check(is_same(current._volumes(item, ""), item.colliders), "Empty role retains the original collider array")
	var filtered := _item([_volume(65, "Test/object/Container_EffectTrigger"), _volume(65, "Test/object/Container_EffectTrigger/child"), _volume(65, "Test/object/Container_EffectTriggerExtra"), _volume(135, "Container_EffectTrigger")])
	for role in ["Container_EffectTrigger", "object/Container_EffectTrigger", "missing"]:
		check(current._volumes(filtered, role) == reference._volumes(filtered, role), "Role filtering retains the original collider order: " + role)
	check(current._volumes(filtered, "Container_EffectTrigger").size() == 3, "Role matching uses complete path segments")
	for kind in [65, 135, 136]:
		collider.kind = kind
		var boundary := Vector3(1.5, 0, 0)
		check(current._contains(item, boundary, 0.5), "Shape %d includes its exact outer boundary" % kind)
		check(not current._contains(item, boundary + Vector3(0.001, 0, 0), 0.5), "Shape %d excludes a point outside the boundary" % kind)
		if kind == 136: check(current._contains(item, Vector3(0, 2.5, 0), 0.5), "Capsule includes its exact end boundary")
		for radius in [0.0, 0.35, 0.5, -0.1]:
			for point in [Vector3.ZERO, Vector3(1, 0, 0), Vector3(1.5, 0, 0), Vector3(0, 2.5, 0), Vector3(4, 0, 4)]:
				for role in ["", "Container_EffectTrigger", "missing"]:
					_compare(current, reference, item, point, radius, role, false, "shape %d radius %s role %s" % [kind, radius, role])
	for index in 3:
		parent.position = [Vector3.ZERO, Vector3(4, 2, -3), Vector3(-5, 3, 8)][index]
		parent.rotation = [Vector3.ZERO, Vector3(0.2, 0.7, 0.1), Vector3(-0.3, -0.2, 0.4)][index]
		parent.scale = [Vector3.ONE, Vector3(1.2, 0.8, 1.6), Vector3(0.7, 1.3, 0.9)][index]
		environment.position = Vector3(index, -index, 0.5 * index)
		environment.rotation = Vector3(0, 0.2 * index, 0)
		environment.scale = Vector3(1.0 + index * 0.2, 1.0, 1.0 - index * 0.1)
		for kind in [65, 135, 136]:
			collider.kind = kind
			for point in [Vector3.ZERO, Vector3(1.4, 0, 0), Vector3(3, 2, -1)]:
				_compare(current, reference, item, environment.global_transform * point, 0.35, "Container_EffectTrigger", false, "parent/root transform %d shape %d" % [index, kind])
	parent.remove_child(environment)
	_compare(current, reference, item, Vector3.ZERO, 0.35, "", false, "Detached root uses untransformed position")
	parent.add_child(environment)
	_compare(current, reference, item, Vector3.ZERO, 0.35, "", false, "Reattached root observes its current transform")
	var replacement := Node3D.new()
	parent.add_child(replacement)
	replacement.position = Vector3(8, 0, -2)
	_setup(current, replacement)
	_setup(reference, replacement)
	_compare(current, reference, item, replacement.global_transform * Vector3.ZERO, 0.35, "", false, "Setup invalidates the old root inverse")
	parent.free()

func _test_dynamic_colliders() -> void:
	var environment := Node3D.new()
	root.add_child(environment)
	var current := Interactions.new()
	var reference := ReferenceInteractions.new()
	_setup(current, environment)
	_setup(reference, environment)
	var collider := _volume(65)
	var item := _item([collider])
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "Initial collider")
	collider.world_matrix[3] = 4.0
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "In-place matrix change")
	check(not current._contains(item, Vector3.ZERO), "Moved collider no longer contains its previous center")
	collider.world_matrix = [0.0, 0.0, 1.0, 4.0, 0.0, 1.5, 0.0, 0.0, -2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0]
	_compare(current, reference, item, Vector3(4, 0, 1), 0.35, "Container_EffectTrigger", false, "Rotated and nonuniform collider matrix")
	collider.world_matrix = _matrix_at(4.0)
	collider.properties.m_Center.x = -4.0
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "In-place center change")
	check(current._contains(item, Vector3.ZERO), "Changed center takes effect immediately")
	collider.properties.m_Size.x = 0.2
	_compare(current, reference, item, Vector3(0.5, 0, 0), 0, "", false, "In-place box size change")
	collider.kind = 135
	collider.properties.m_Radius = 0.1
	_compare(current, reference, item, Vector3(0.5, 0, 0), 0, "", false, "Changed kind and sphere radius")
	collider.kind = 136
	collider.properties.m_Height = 0.5
	collider.properties.m_Direction = 0
	_compare(current, reference, item, Vector3(0.3, 0, 0), 0, "", false, "Changed capsule height and direction")
	collider.active = false
	_compare(current, reference, item, Vector3.ZERO, 0, "", false, "Inactive collider")
	collider.active = true
	collider.properties.m_Enabled = 0
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "Disabled idle trap volume")
	item.state.phase = "active"
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "Active trap permits its disabled effect volume")
	check(current._contains(item, Vector3.ZERO, 0, "Container_EffectTrigger"), "Active phase updates the effect volume immediately")
	collider.properties.m_IsTrigger = 1
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", true, "Solid-only skips trigger collider")
	collider.path = "Test/object/Box_TiggerEnter"
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "Mutated role path is observed")
	collider.properties.m_Enabled = 1
	_compare(current, reference, item, Vector3.ZERO, 0, "Box_TiggerEnter", false, "Mutated role matches its new path")
	item.colliders = []
	_compare(current, reference, item, Vector3.ZERO, 0, "", false, "Empty collider array")
	check(not current._contains(item, Vector3.ZERO), "Empty collider array never contains a point")
	item.colliders.append(_volume(64))
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "Mesh diagnostics")
	check(current.diagnostics.size() == 1 and current.diagnostics[0].code == "unsupported_interaction_mesh_volume", "Active mesh emits the original diagnostic")
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "Mesh diagnostics are deduplicated")
	item.colliders[0].world_matrix[0] = 0.0
	_compare(current, reference, item, Vector3.ZERO, 0, "Container_EffectTrigger", false, "Degenerate matrix remains ignored")
	environment.free()

func _test_callback_root_and_phase() -> void:
	var current_root := Node3D.new()
	var reference_root := Node3D.new()
	root.add_child(current_root)
	root.add_child(reference_root)
	var current := Interactions.new()
	var reference := ReferenceInteractions.new()
	_setup(current, current_root)
	_setup(reference, reference_root)
	var current_box := _volume(65)
	current_box.properties.m_Enabled = 0
	var reference_box := current_box.duplicate(true)
	var current_item := _item([_volume(64), current_box])
	var reference_item := _item([_volume(64), reference_box])
	current.diagnostic_reported.connect(func(_diagnostic): current_root.position.x = 5; current_item.state.phase = "active")
	reference.diagnostic_reported.connect(func(_diagnostic): reference_root.position.x = 5; reference_item.state.phase = "active")
	check(current._contains(current_item, Vector3.ZERO, 0, "Container_EffectTrigger"), "A synchronous diagnostic callback changes the next collider phase in the same call")
	check(reference._contains(reference_item, Vector3.ZERO, 0, "Container_EffectTrigger"), "Reference observes the same callback phase")
	check(not current._contains(current_item, Vector3.ZERO, 0, "Container_EffectTrigger"), "The next call observes a synchronous root transform change")
	check(not reference._contains(reference_item, Vector3.ZERO, 0, "Container_EffectTrigger"), "Reference observes the root transform change")
	check(current.diagnostics == reference.diagnostics, "Synchronous callback diagnostic ordering matches")
	current_root.free()
	reference_root.free()

func _marker(id: String, kind: String, data: Dictionary = {}) -> Dictionary:
	return {"SceneName": "Test", "SourceGameObjectId": id, "Type": kind, "Path": [id], "DataJson": JSON.stringify(data), "exported_node_name": id}

func _tick_fixture(interactions: DungeonWorldInteractions) -> Dictionary:
	var environment := Node3D.new()
	root.add_child(environment)
	for id in ["attract", "player_trigger", "trap"]:
		var visual := Node3D.new()
		visual.name = id
		environment.add_child(visual)
	var markers := [_marker("attract", "EEUT_AttractTrap"), _marker("player_trigger", "EEUT_PlayerTrigger", {"TriggerId": 7, "TriggerFuncMsg_Name": "TestMessage"}), _marker("trap", "EEUT_TriggerTrap")]
	var bindings := [{"SceneName": "Test", "SourceGameObjectId": "attract", "ConfigId": "attract", "SupportsRules": true, "AttractTargetPosition": [0, 0, 0], "AttractTargetForward": [1, 0, 0]}, {"SceneName": "Test", "SourceGameObjectId": "trap", "ConfigId": "trap", "SupportsRules": true}]
	var definitions := [{"ID": "attract", "Type": "EEUT_AttractTrap", "EffectCamp": "100", "DirType": "Dir", "AttractForce": 100.0}, {"ID": "trap", "Type": "EEUT_TriggerTrap", "TriggerCondition": "PlayerTriggerEnter", "TriggerStartTime": 0.1, "TriggerLastingTime": 0.4, "TriggerEndTime": 0.1, "TriggerTimesType": "OnlyOncePerUnit", "TargetCampString": "111", "AddBuffData": {"BuffTriggerId": "test", "BuffAddLayer": 1}}]
	var colliders := [_volume(65, "Test/attract/Container_EffectTrigger"), _volume(65, "Test/player_trigger/Box", 10), _volume(65, "Test/trap/Container_EnterTrigger", 10), _volume(65, "Test/trap/Container_EffectTrigger", 10)]
	var events: Array = []
	interactions.attraction_requested.connect(func(context): events.append(["attract", context.target_id]); context["position_after"] = Vector3(10, 0, 0))
	interactions.player_trigger_entered.connect(func(id, _context): events.append(["trigger", id]))
	interactions.message_requested.connect(func(name, _context): events.append(["message", name]))
	interactions.setup(environment, markers, {"rules": {"Bindings": bindings, "Definitions": definitions}, "colliders": colliders})
	return {"environment": environment, "interactions": interactions, "events": events}

func _test_tick_order_and_callbacks() -> void:
	var current := _tick_fixture(TracedCurrent.new())
	var reference := _tick_fixture(TracedReference.new())
	var targets := [{"id": "enemy", "position": Vector3(10, 0, 0), "camp": 3}]
	current.interactions.tick(0.04, Vector3.ZERO, targets.duplicate(true))
	reference.interactions.tick(0.04, Vector3.ZERO, targets.duplicate(true))
	check(current.events == reference.events, "Attraction, trigger and message signal order matches")
	check(current.events == [["attract", "player"], ["trigger", 7], ["message", "TestMessage"]], "Attraction callback position is observed by the following trigger in the same substep")
	check(current.interactions.snapshot() == reference.interactions.snapshot(), "Attraction and trap state match after multiple substeps")
	check(current.interactions.state_for("trap").phase == "starting", "The trap tests the callback-updated player position")
	check(current.interactions.calls == reference.interactions.calls, "Collider checks retain substep and item order")
	current.environment.free()
	reference.environment.free()
	current = _tick_fixture(TracedCurrent.new())
	reference = _tick_fixture(TracedReference.new())
	targets = [{"id": "outside", "position": Vector3(80, 0, 0), "camp": 3}, {"id": "inside", "position": Vector3(10, 0, 0), "camp": 3}, {"id": "later", "position": Vector3(10, 0, 0), "camp": 3}]
	current.interactions.tick(0.02, Vector3(100, 0, 0), targets.duplicate(true))
	reference.interactions.tick(0.02, Vector3(100, 0, 0), targets.duplicate(true))
	check(current.interactions.calls == reference.interactions.calls, "Trigger scan preserves the original short-circuit order")
	var enter_calls: Array = current.interactions.calls.filter(func(call): return call[0] == "trap" and call[3] == "Container_EnterTrigger")
	check(enter_calls.size() == 3, "Trigger scan stops at the first eligible target inside")
	check(current.interactions.snapshot() == reference.interactions.snapshot(), "Short-circuited trap state matches")
	current.environment.free()
	reference.environment.free()

func _test_camp_masks() -> void:
	for mask in ["", "000", "111", "100", "010", "001", "10X", "1 0", "二00", "1111", "1"]:
		for camp in [-1, 0, 1, 2, 3, 4]:
			var expected := false
			if mask.length() == 3:
				var valid := true
				for character in mask:
					if character not in ["0", "1"]: valid = false
				var slot := 0 if camp == 2 else 1 if camp == 1 else 2 if camp == 3 else -1
				expected = valid and slot >= 0 and mask[slot] == "1"
			check(Interactions.camp_allows(mask, camp) == expected, "Camp mask %s camp %d" % [mask, camp])

func _benchmark() -> void:
	var environment := Node3D.new()
	root.add_child(environment)
	environment.position = Vector3(4, 2, -1)
	environment.rotation = Vector3(0.1, 0.4, -0.1)
	environment.scale = Vector3(1.1, 0.8, 1.2)
	var cases := {"legacy": ReferenceInteractions.new(), "current": Interactions.new()}
	for instance in cases.values(): _setup(instance, environment)
	var scenarios := {"single_box": {"item": _item([_volume(65)]), "role": ""}, "trap_role": {"item": _item([_volume(65, "Test/object/Container_EnterTrigger"), _volume(65), _volume(65, "Test/object/disabled"), _volume(65, "Test/object/solid")]), "role": "Container_EnterTrigger"}, "empty": {"item": _item([]), "role": ""}}
	for scenario in scenarios:
		var item: Dictionary = scenarios[scenario].item
		var role: String = scenarios[scenario].role
		var totals := {"legacy": [], "current": []}
		for instance in cases.values():
			for index in 2000: instance._contains(item, Vector3(100, 0, 100), 0.35, role)
		for round in 6:
			var order := ["legacy", "current"] if round % 2 == 0 else ["current", "legacy"]
			for name in order:
				var start := Time.get_ticks_usec()
				for index in 20000: cases[name]._contains(item, Vector3(100, 0, 100), 0.35, role)
				totals[name].append(Time.get_ticks_usec() - start)
		for name in totals: totals[name].sort()
		var median := {}
		for name in totals: median[name] = (totals[name][2] + totals[name][3]) * 0.5
		print("INTERACTION_CONTAINS_BENCHMARK ", JSON.stringify({"scenario": scenario, "calls_per_round": 20000, "rounds": 6, "median_us": median, "samples_us": totals, "scope": "Headless desktop; isolated contains calls on one transformed root, not device frame rate or total battle CPU."}))
	environment.free()

func _run() -> void:
	_test_volumes_and_shapes()
	_test_dynamic_colliders()
	_test_callback_root_and_phase()
	_test_tick_order_and_callbacks()
	_test_camp_masks()
	if OS.get_cmdline_user_args().has("--benchmark"): _benchmark()
	print("INTERACTION_CPU_EQUIVALENCE ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
