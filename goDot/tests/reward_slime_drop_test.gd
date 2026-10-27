extends SceneTree

const Rewards = preload("res://scripts/domain/loot_rewards.gd")
var checks := 0
var failures: Array[String] = []
var world: DungeonWorld

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func total(id: int) -> int:
	var amount := 0
	for row in world.ground_loot.entries:
		if int(row.id) == id and row.material: amount += int(row.amount)
	return amount

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Reward slime catalog loads")
	var systems := DungeonSystems.new(catalog, DungeonProfile.new())
	check(systems.begin_run(1729, 1, 100).success, "Reward slime fixture starts")
	var rewards := Rewards.new(systems, func(_limit): return 1000)
	for enemy_id in [90001, 90002, 90003]:
		var id: int = {90001: 101, 90002: 102, 90003: 90002}[enemy_id]
		var attribute: String = {90001: "DropGoldFactor", 90002: "DropMagicPointFactor", 90003: "DropFreeCoinFactor"}[enemy_id]
		for event in ["hit", "dead"]:
			var base: int = ({90001: 5, 90002: 10, 90003: 1} if event == "hit" else {90001: 80, 90002: 160, 90003: 16})[enemy_id]
			var drops: Array = rewards.reward_slime(enemy_id, event, {})
			check(drops == [{"id": id, "amount": base, "material": true}], "Slime%d %s has native baseline despite DropChance zero" % [enemy_id, event])
			var boosted: Array = rewards.reward_slime(enemy_id, event, {attribute: 1000, "DropGoldMonsterFactor": 100000})
			check(boosted.size() == 1 and int(boosted[0].amount) == int(base * (1.5 if enemy_id == 90002 else 2.0)), "Slime modifier uses the dedicated branch without monster gold factor")
		check(rewards.reward_slime(enemy_id, "hit", {attribute: -2000}).is_empty(), "Nonpositive slime quantity is suppressed")
	check(rewards.reward_slime(11001, "dead", {}).is_empty(), "Ordinary enemy cannot emit special slime rewards")
	check(rewards.reward_slime(90001, "unknown", {}).is_empty(), "Unknown slime event cannot emit rewards")
	var original: float = float(catalog.config.DefaultRewardSlimeDropResPoolData.GoldData.DropBase)
	catalog.config.DefaultRewardSlimeDropResPoolData.GoldData.DropBase = 39
	check(rewards.reward_slime(90001, "hit", {"DropGoldFactor": 1000})[0].amount == 2, "Slime truncates base times event factor before attribute multiplier")
	catalog.config.DefaultRewardSlimeDropResPoolData.GoldData.DropBase = original
	world = DungeonWorld.new()
	root.add_child(world)
	world.systems = systems
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.audio_enabled = false
	world.presentation.set_process(false)
	var notices: Array = []
	world.world_message.connect(func(name, _payload): notices.append(name))
	for enemy_id in [90001, 90002, 90003]:
		var actor := DungeonActor.new()
		actor.actor_id = enemy_id
		actor.combat = DungeonCombat.new()
		check(actor.combat.configure_enemy(enemy_id, 193).success, "Slime configures for world dispatch")
		actor.combat.actor_key = "slime:" + str(enemy_id)
		world.add_child(actor)
		world.actors.append(actor)
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.combat.begin_enemy_spawn()
		actor.combat.drain_events()
		var id: int = {90001: 101, 90002: 102, 90003: 90002}[enemy_id]
		var initial := total(id)
		var context := {"target_available": true, "distance": 3.0, "line_blocked": false, "battle_time": 0.0, "monster_index": 0, "target_buffs": []}
		for ratio in [1.0, 0.79, 0.59, 0.39, 0.19, 0.1]:
			actor.combat.health = actor.combat.max_health * ratio
			for tick in 5:
				actor.combat.tick_enemy_ai(0.1, context)
				for event in actor.combat.drain_events(): world._consume(actor, event)
		var per_hit: int = {90001: 5, 90002: 10, 90003: 1}[enemy_id]
		check(total(id) - initial == per_hit * 3, "Actual slime AI emits exactly three threshold resource rewards")
		actor.combat.health = 0
		world._die(actor)
		var death_amount: int = {90001: 80, 90002: 160, 90003: 16}[enemy_id]
		# Ordinary death can add the same material independently of the slime message.
		check(total(id) - initial >= per_hit * 3 + death_amount, "Authored death action emits its independent slime resource reward")
		check(actor.dead and world.defeated_count == (enemy_id - 90000), "Slime still follows ordinary death accounting")
		var after := total(id)
		world._die(actor)
		check(total(id) == after, "Repeated death dispatch cannot repeat slime reward")
	check(notices.is_empty(), "Internal slime reward messages do not become player notices")
	systems.decorations = null
	world.queue_free()
	await process_frame
	print("REWARD_SLIME_DROP_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
