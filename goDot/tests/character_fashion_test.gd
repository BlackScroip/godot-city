extends SceneTree

const Fashion = preload("res://scripts/domain/character_fashion.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Source catalog loads")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	var fashion = Fashion.new(systems)
	check(fashion._rows.size() == 45, "The exact APK fashion table has 45 records")
	check(profile.validate(), "Existing saves require no new mandatory fields")
	check(systems.character_fashion_owned().size() == 8, "Eight source default fashions need no purchase")
	check(systems.character_fashion_equipped()["1"] == 1001, "Old profiles resolve the correct default appearance")
	var quote = systems.character_fashion_status(1002, 1)
	check(quote.price == {"502": 10} and not quote.owned and not quote.can_unlock, "Material price and affordability come from the source record")
	var before = profile.data.duplicate(true)
	check(not systems.unlock_character_fashion(1002, 1).success and profile.data == before, "Insufficient materials cannot mutate ownership or balances")
	systems.grant_material(502, 20)
	check(systems.unlock_character_fashion(1002, 1).success, "A source material fashion can be purchased")
	check(systems.material(502) == 10 and 1002 in systems.character_fashion_owned(), "Purchase spends exactly the source quantity and grants ownership")
	check(systems.attributes(1).BaseAtk == 10 and systems.attributes(1).BaseHp == 5, "Source ownership bonuses reach the actual character attributes")
	check(systems.equip_character_fashion(1002, 1).success and systems.character_fashion_equipped()["1"] == 1002, "Owned fashion is remembered for its character")
	check(systems.equip_character_fashion(1001, 1).success and systems.attributes(1).BaseAtk == 10, "Returning to default appearance retains owned-fashion bonuses")
	check(not systems.unlock_character_fashion(1002, 1).success and systems.material(502) == 10, "Duplicate purchases cannot consume materials twice")
	before = profile.data.duplicate(true)
	check(not systems.equip_character_fashion(1002, 2).success and profile.data == before, "A forged character id cannot equip another character's fashion")
	check(not systems.unlock_character_fashion(2002, 2).success and profile.data == before, "Locked characters cannot buy fashions")
	check(not systems.unlock_character_fashion(999999, 1).success and profile.data == before, "Unknown fashion ids cannot mutate the profile")
	profile.data.character_levels["7"] = 1
	check(not systems.unlock_character_fashion(7201, 7).success, "Cash fashion cannot be bought with a local material operation")
	quote = systems.character_fashion_status(7202, 7)
	check(quote.grant_owner_id == 7201 and not quote.can_unlock, "Empty-price variants remain dependent on the paid core fashion")
	check(not systems.unlock_character_fashion(7202, 7).success and not quote.owned, "An attached variant is not a free purchase")
	# A retained entitlement fixture exercises derived ownership without invoking payment.
	profile.data.fashion_owned.append(7201)
	check([7201, 7202, 7203, 7204, 7205].all(func(id): return id in systems.character_fashion_owned()), "Core ownership derives all four source auto-granted variants")
	check(systems.attributes(7).BaseAtk == 10 and systems.attributes(7).CriticalRate == 50, "Auto-granted variants do not duplicate the core's numeric bonus")
	check(fashion.equipped_buffs(7).is_empty(), "Owned but unequipped special fashion grants no combat buff")
	check(systems.equip_character_fashion(7202, 7).success and fashion.equipped_buffs(7) == [26081701, 26081702], "Only the equipped source fashion grants its authored combat buffs")
	var restored = DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "Fashion ownership and equipment round-trip through JSON saves")
	check(typeof(restored.data.fashion_owned[0]) == TYPE_INT and typeof(restored.data.fashion_equipped["7"]) == TYPE_INT, "Restored fashion ids are normalized to integers")
	var malformed = profile.data.duplicate(true)
	malformed.fashion_equipped["7"] = "7201"
	check(not restored.restore(malformed), "Malformed equipment values are rejected during restore")
	malformed = profile.data.duplicate(true)
	malformed.fashion_owned = ["7201"]
	check(not restored.restore(malformed), "Malformed ownership ids are rejected during restore")
	profile.data.fashion_equipped["1"] = 999999
	check(fashion.selected_id(1) == 1001, "Unavailable saved fashion falls back to the source default")
	profile.data.run.active = true
	before = profile.data.duplicate(true)
	check(not systems.unlock_character_fashion(1003, 1).success and profile.data == before, "Level context cannot purchase permanent fashion")
	check(not systems.equip_character_fashion(1002, 1).success and profile.data == before, "Level context cannot change permanent fashion equipment")
	systems.effects = null
	systems.decorations = null
	var result = {"checks": checks, "failures": failures}
	var file = FileAccess.open("res://reports/character-fashion-tests-20261027.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("CHARACTER_FASHION_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
