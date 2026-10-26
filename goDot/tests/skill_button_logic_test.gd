extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Intent = preload("res://scripts/player_intent.gd")
var checks := 0
var failures: Array[String] = []

class AutoDispatchWorld extends DungeonWorld:
	var commands: Array[int] = []
	var fixture_target: DungeonActor
	func _attack_target(_slot: int) -> DungeonActor:
		return fixture_target
	func _execute_player(slot: int, _automatic := false, _selected_target: DungeonActor = null) -> bool:
		commands.append(slot)
		return true

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func fighter(character: int) -> RefCounted:
	var combat = Combat.new()
	combat.configure(null, null, character)
	for slot in 5: combat.energy[slot] = combat.skill_capacity(slot)
	var resource = str(combat.fighter.get("jp", ""))
	if not resource.is_empty(): combat.add_buff(resource, 300)
	return combat

func run() -> void:
	for hz in [30, 60, 120]:
		for character in range(1, 8):
			var label = "%d at %d Hz" % [character, hz]
			var combat = fighter(character)
			var intent = Intent.new()
			intent.attack_button(combat, true)
			for frame in int(hz * 0.2): intent.advance_hold(combat, 1.0 / hz)
			check(intent.take_ready(combat, 0) == -1 and combat._cast_sequence == 0, "Down waits for tap/hold classification " + label)
			intent.attack_button(combat, false)
			var slot = intent.take_ready(combat, 0)
			check(slot == 0 and combat.request_attack(slot).success, "Short up starts a real normal action " + label)
			intent.attack_button(combat, false)
			check(intent.take_ready(combat, 0) == -1, "Duplicate up cannot queue another normal " + label)
			combat = fighter(character)
			intent = Intent.new()
			intent.attack_button(combat, true)
			intent.advance_hold(combat, 0.29)
			check(intent.take_ready(combat, 0) == -1, "Heavy stays absent before 0.3 seconds " + label)
			intent.advance_hold(combat, 0.01)
			check(intent.hold_consumed and intent.take_ready(combat, 0) == 4, "0.3-second hold requests heavy without a leading normal " + label)
			intent.attack_button(combat, false)
			check(intent.take_ready(combat, 0) == -1 and not combat.custom_properties.InputAttack_LongPress, "Long up stops heavy without a trailing normal " + label)
			combat = fighter(character)
			intent = Intent.new()
			combat.cooldowns[4] = 2.0
			intent.attack_button(combat, true)
			intent.advance_hold(combat, 0.31)
			check(intent.hold_consumed and intent.pending.is_empty(), "Unavailable heavy still classifies the gesture as long " + label)
			combat.cooldowns[4] = 0.0
			intent.advance_hold(combat, 1.0 / hz)
			check(intent.take_ready(combat, 0) == 4, "Held heavy retries after becoming available " + label)
			intent.cancel_button(combat, 0)
			intent.attack_button(combat, false)
			check(not intent.manual_attack_active() and intent.pending.is_empty(), "Cancellation cannot become a short tap " + label)
			combat = fighter(character)
			intent = Intent.new()
			intent.request(combat, 2, true)
			check(not combat.custom_properties.get("InputSkill1_LongPress", false) and not combat.custom_properties.InputAttack, "Skill one down does not invent attack/long input " + label)
			var active_slot = intent.take_ready(combat, 0)
			check(active_slot == 2 and combat.request_attack(active_slot).success and not combat.custom_properties.InputSkill, "Actual active action consumes its one-shot request " + label)
			intent.advance_hold(combat, 0.29)
			check(not combat.custom_properties.get("InputSkill1_LongPress", false), "Skill one has no early hold flag " + label)
			intent.advance_hold(combat, 0.01)
			check(combat.custom_properties.InputSkill1_LongPress, "Skill one long callback starts at 0.3 seconds " + label)
			intent.request(combat, 2, false)
			check(not combat.custom_properties.InputSkill1_LongPress and not intent.skill_one_held, "Skill one up clears its long flag " + label)
			combat = fighter(character)
			intent = Intent.new()
			intent.request(combat, 3, true)
			intent.advance_hold(combat, 0.5)
			check(not combat.custom_properties.get("InputSkill2_LongPress", false) and not combat.custom_properties.InputAttack, "Skill two has only its down command " + label)
			combat = fighter(character)
			intent = Intent.new()
			combat.energy[3] = 0.0
			check(not intent.request(combat, 3, true).success and not combat.custom_properties.InputSkill, "Unavailable active skill cannot leave an action-switch input " + label)
			combat = fighter(character)
			intent = Intent.new()
			intent.attack_button(combat, true)
			intent.request(combat, 2, true)
			intent.cancel_button(combat, 0)
			check(combat.custom_properties.InputSkill and intent.take_ready(combat, 0) == 2, "Canceling attack preserves another finger's active request " + label)
	check_auto_dispatch()
	var report = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "characters": 7, "rates": [30, 60, 120]}
	FileAccess.open("res://reports/skill-button-logic.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SKILL_BUTTON_LOGIC ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func check_auto_dispatch() -> void:
	# Keep the real input policy and stub action execution to expose its cadence.
	var world = AutoDispatchWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.player = DungeonActor.new()
	world.player.combat = fighter(1)
	var target = DungeonActor.new()
	world.fixture_target = target
	world.fighting = true
	world.set_attack_mode("off")
	world.set_attack_mode("normal")
	world._tick_player_input(0.24)
	check(world.commands.is_empty(), "Auto tap waits for its initial 0.25-second interval")
	world._tick_player_input(0.01)
	check(world.commands == [0], "Auto tap dispatches at 0.25 seconds")
	world.use_skill(0, true)
	world._tick_player_input(0.2)
	world.cancel_skill(0)
	world._tick_player_input(0.24)
	check(world.commands == [0], "Manual takeover freezes the auto tap timer")
	world._tick_player_input(0.01)
	check(world.commands == [0, 0], "Auto tap resumes its timer after manual takeover")
	world.fixture_target = null
	world._tick_player_input(1.0)
	world.fixture_target = target
	world._tick_player_input(0.24)
	check(world.commands == [0, 0], "No target freezes auto tap time")
	world._tick_player_input(0.01)
	check(world.commands == [0, 0, 0], "Returning target resumes eligible auto tap time")
	world.set_attack_mode("heavy")
	world._tick_player_input(0.01)
	world._tick_player_input(0.01)
	check(world.commands == [0, 0, 0, 4, 4], "Auto hold requests heavy on each eligible tick")
	world.set_attack_mode("off")
	world._tick_player_input(1.0)
	check(world.commands.size() == 5, "Off mode dispatches no attack")
	world.player.free()
	target.free()
	world.free()
