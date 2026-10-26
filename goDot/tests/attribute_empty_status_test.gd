extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_empty_cases()
	_transition_cases()
	_recursive_cases()
	print("ATTRIBUTE_EMPTY_STATUS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _empty_cases() -> void:
	var actor = Combat.new()
	var external := {"MoveSpeedRate": 250, "AtkAddFixed": -7.5, "CriticalRate": 0}
	actor.set_external_attributes(external)
	external.MoveSpeedRate = 999
	var expected := {"MoveSpeedRate": 250.0, "AtkAddFixed": -7.5, "CriticalRate": 0.0, "Missing": 0.0}
	var guards := [{}, {"MoveSpeedRate": true}, {"Other": true}, {"MoveSpeedRate": false, "Other": 17}]
	for guard in guards:
		actor._attribute_stack = guard.duplicate()
		for name in expected:
			check(actor.attribute(name) == expected[name], "Empty statuses preserve external value %s with guard %s" % [name, guard])
			check(actor._attribute_stack == guard, "Empty reads leave the existing recursion guard unchanged %s/%s" % [name, guard])
	check(actor._external == {"MoveSpeedRate": 250, "AtkAddFixed": -7.5, "CriticalRate": 0}, "Empty reads preserve the copied external attribute dictionary")
	check(actor.statuses.is_empty(), "Empty reads cannot create statuses")

func _transition_cases() -> void:
	var actor = Combat.new()
	check(actor.configure_enemy(11001, 731).success, "Real source enemy fixture loads")
	check(actor.statuses.is_empty(), "Source enemy starts without statuses")
	actor.set_external_attributes({"MoveSpeedRate": 250, "AtkAddFixed": -7.5})
	check(actor.attribute("MoveSpeedRate") == 250, "Empty source enemy uses external movement")
	check(actor.add_buff("119902"), "Source movement debuff applies")
	check(actor.attribute("MoveSpeedRate") == 235, "Nonempty path adds source negative numerical value")
	check(actor.attribute("AtkAddFixed") == -7.5 and actor.attribute("Missing") == 0, "Unrelated external and absent attributes survive a numerical buff")
	check(actor.add_buff("119902", 2) and actor.buff_layers("119902") == 3, "Source movement debuff gains its authored layers")
	check(actor.attribute("MoveSpeedRate") == 205, "Numerical values scale with source buff layers")
	check(actor.add_buff("100100101") and actor.attribute("MoveSpeedRate") == 305, "Positive and negative source numerical buffs combine with external values")
	actor._attribute_stack = {"Other": true}
	check(actor.attribute("MoveSpeedRate") == 305 and actor._attribute_stack == {"Other": true}, "Nonempty reads preserve an unrelated recursion guard")
	actor._attribute_stack = {"MoveSpeedRate": true, "Other": true}
	check(actor.attribute("MoveSpeedRate") == 250 and actor._attribute_stack == {"MoveSpeedRate": true, "Other": true}, "Existing requested-name guard still suppresses recursive numerical additions")
	actor._attribute_stack.clear()
	actor._external_numeric_buffs = ["100100101"]
	check(actor.attribute("MoveSpeedRate") == 205, "Externally counted source numerical buffs still avoid double counting")
	actor._external_numeric_buffs.clear()
	actor.remove_buff("119902")
	check(actor.attribute("MoveSpeedRate") == 350, "Removing one numerical buff preserves the other")
	actor.remove_buff("100100101")
	check(actor.statuses.is_empty() and actor.attribute("MoveSpeedRate") == 250, "Removing the final buff returns immediately to the external value")
	check(actor.add_buff("119902") and actor.attribute("MoveSpeedRate") == 235, "A new buff after the empty fast path is visible immediately")
	actor.set_external_attributes({"MoveSpeedRate": -50, "AtkAddFixed": -7.5})
	check(actor.attribute("MoveSpeedRate") == -65, "Replacing external attributes while buffed uses the new value")
	check(actor.add_buff("119902", -1), "Reducing the final layer removes the source buff")
	check(actor.statuses.is_empty() and actor.attribute("MoveSpeedRate") == -50, "Layer removal restores a negative external value")
	actor.add_buff("119902", 2)
	actor.tick(5.01)
	check(actor.statuses.is_empty() and actor.attribute("MoveSpeedRate") == -50, "Natural source buff expiry reenters the empty fast path")
	check(actor._attribute_stack.is_empty(), "Buff transitions leave no stale recursion guard")

func _recursive_cases() -> void:
	var actor = Combat.new()
	actor.set_external_attributes({"MoveSpeedRate": 10})
	actor._buff_index = {"recursive": {"type": "EBT_NBuffAddCasterUnitAttribToReceiverProperty", "raw_data": {"BuffSettingDataList": [{"Attr_Receiver": "MoveSpeedRate", "Attr_CasterUnit": "MoveSpeedRate", "StartThresholdValue": 0, "AddValue": 5, "MulValue": 1000, "FinalMaxAddValue": -1}]}}}
	actor.statuses.recursive = {"id": "recursive", "layers": 2}
	check(actor.attribute("MoveSpeedRate") == 40, "Self-dependent conversion terminates with its external recursion basis")
	check(actor._attribute_stack.is_empty(), "Self-dependent conversion releases its recursion guard")
	actor._attribute_stack = {"Other": true}
	check(actor.attribute("MoveSpeedRate") == 40 and actor._attribute_stack == {"Other": true}, "Self recursion preserves unrelated active attribute reads")
	actor._attribute_stack.clear()
	var caster = Combat.new()
	caster.set_external_attributes({"MoveSpeedRate": 30})
	caster._attribute_stack = {"Other": true}
	actor.bind_buff_caster("recursive", caster)
	check(actor.attribute("MoveSpeedRate") == 80, "Caster-dependent conversion reads an empty-status caster's external attributes")
	check(actor._attribute_stack.is_empty() and caster._attribute_stack == {"Other": true}, "Nested empty caster reads preserve both actors' recursion guards")
	actor.remove_buff("recursive")
	check(actor.statuses.is_empty() and actor.attribute("MoveSpeedRate") == 10, "Removing a recursive conversion restores the external value")
