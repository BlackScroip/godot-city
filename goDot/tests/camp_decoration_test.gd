extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Decorations = preload("res://scripts/domain/camp_decorations.gd")
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog = Catalog.new()
	check(catalog.load_all(), "new APK catalogs load")
	var profile = Profile.new()
	var systems = Systems.new(catalog, profile)
	var decorations = Decorations.new(systems)
	check(decorations.slots().size() == 9 and profile.data.camp_decorations.size() == 9, "all nine native decoration slots have persisted defaults")
	check(decorations.global_status().maximum == 21 and not decorations.available(), "appearance changes require all twenty-one building stages")
	check(decorations.current_id(1) == 1001 and decorations.current_id(999) == 0, "valid slots resolve a default while invalid slots resolve no appearance")
	var slots = decorations.slots()
	check(slots[0].display_id == 1000 and slots[4].display_id == 5001, "unrepaired buildings use ruins; builder develop type zero starts at level one")
	profile.data.buildings["1"] = 1
	check(decorations.slots()[0].display_id == 1001, "repairing a facility exposes its default appearance before customization unlocks")
	var before = JSON.stringify(profile.data)
	check(not decorations.unlock(1002).success and JSON.stringify(profile.data) == before, "city gate rejects purchases atomically")
	for building in catalog.rows("Buildings"):
		profile.data.buildings[str(building.id)] = int(building.max_level)
	check(decorations.available(), "fully built city opens appearance changes")
	check(decorations.status(1001).owned and decorations.status(1001).can_equip, "default appearance is owned without a purchase")
	before = JSON.stringify(profile.data)
	check(not decorations.unlock(1000).success and not decorations.equip(1, 2001).success and not decorations.unlock(999).success and JSON.stringify(profile.data) == before, "ruins, cross-slot selection and unknown IDs cannot mutate state")
	check(not decorations.status(1002).can_unlock and "100" in decorations.status(1002).unlock_reason, "town home preserves the one-hundred-normal-kills condition")
	for enemy in catalog.rows("EnemyData"):
		if str(enemy.get("enemy_rate", "")) == "Normal":
			systems.record("kill:" + str(int(enemy.id)), 100)
			break
	check(decorations.status(1002).can_unlock and decorations.status(1002).price == {"101": 100}, "town home becomes purchasable for exactly one hundred gold")
	var reentry = {"success": false}
	var listener = func(): reentry.success = decorations.unlock(1002).success
	systems.changed.connect(listener)
	check(decorations.unlock(1002).success and reentry.success and systems.material(101) == 0 and profile.data.unlocked_camp_decorations.count(1002) == 1, "unlock records ownership before change listeners can retry and charges once")
	systems.changed.disconnect(listener)
	check(decorations.unlock(1002).success and systems.material(101) == 0, "owned appearances remain idempotent when the wallet is empty")
	check(decorations.equip(1, 1002).success and decorations.current_id(1) == 1002, "purchased appearance can be equipped in its matching slot")
	check(decorations.equip(1, 1002).success and systems.material(101) == 0, "repeated equip never charges")
	for id in [2002, 5002, 6002, 7002, 9002]:
		before = JSON.stringify(profile.data)
		check(not decorations.status(id).can_unlock and "未配置" in decorations.status(id).unlock_reason and not decorations.unlock(id).success and JSON.stringify(profile.data) == before, "source variants without UnlockData remain unavailable: %d" % id)
	before = JSON.stringify(profile.data)
	check(not decorations.equip(4, 4002).success and JSON.stringify(profile.data) == before, "unequipped and unowned town guild cannot bypass purchase")
	systems.record("runs", 5)
	check(not decorations.unlock(4002).success and systems.material(101) == 0, "fulfilled guild condition still requires two hundred gold")
	systems.grant_material(101, 250)
	check(decorations.status(4002).price == {"101": 200} and decorations.unlock(4002).success and systems.material(101) == 50, "town guild consumes its exact configured resource cost")
	check(decorations.equip(4, 4002).success, "town guild selection succeeds after purchase")
	var restored = Profile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "decoration purchase and selection survive JSON save restoration")
	var resumed_systems = Systems.new(catalog, restored)
	var resumed = Decorations.new(resumed_systems)
	check(resumed.current_id(1) == 1002 and resumed.current_id(4) == 4002 and resumed.status(1002).owned, "restored appearance ownership resolves selected prefabs")
	restored.data.run.active = true
	before = JSON.stringify(restored.data)
	check(not resumed.unlock(1002).success and not resumed.equip(1, 1001).success and JSON.stringify(restored.data) == before, "all decoration commands are blocked during an adventure")
	restored.data.run.active = false
	restored.data.camp_decorations["1"] = 2002
	check(resumed.current_id(1) == 1001, "invalid cross-slot saved selection falls back to default")
	restored.data.camp_decorations["1"] = 1000
	check(resumed.current_id(1) == 1001, "saved ruins selection never replaces a repaired default")
	var result = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "New APK decoration gates, slots, costs, ownership, atomicity, duplicate transactions and persisted selections. Static source rules; no original decoration prefab or runtime visual parity claim."}
	var report = FileAccess.open("res://reports/camp-decoration-tests.json", FileAccess.WRITE)
	if report: report.store_string(JSON.stringify(result, "\t"))
	print("CAMP_DECORATION_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
