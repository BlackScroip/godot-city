extends SceneTree

const AdRewards = preload("res://scripts/domain/ad_rewards.gd")

var catalog = DungeonCatalog.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	check(catalog.load_all(), "Packaged catalog loads")
	_source_contract()
	_unavailable_payments()
	_currency_transaction()
	_rewarded_ad_transaction()
	_purchase_limit()
	_purchase_coin_contract()
	_gold_contract()
	print("MALL_PAYMENT_CONTRACT ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _systems() -> DungeonSystems:
	var systems = DungeonSystems.new(catalog, DungeonProfile.new())
	systems.utc_now = func(): return 172800
	return systems

func _dispose(systems: DungeonSystems) -> void:
	systems.effects = null
	systems.decorations = null

func _source_contract() -> void:
	var systems = _systems()
	var seen: Dictionary = {}
	var payments: Dictionary = {}
	for source in catalog.rows("MallTradeData"):
		var id = DungeonCatalog.row_id(source)
		if seen.has(id): continue
		seen[id] = true
		var row = catalog.find("MallTradeData", id)
		var quote = systems.offer_quote(id)
		check(quote.get("payment", "") == str(row.GoodsPayType), "Quote retains packaged payment type " + str(id))
		check(int(quote.get("price", -1)) == int(row.Price), "Quote retains packaged Price without conversion " + str(id))
		check(not quote.get("offline_conversion", true), "No offer is converted into invented gold " + str(id))
		check(not quote.get("rewards", []).is_empty(), "Unavailable offers still expose their configured reward " + str(id))
		if not row.Enable:
			check(not quote.success and not systems.buy_mall(id).success, "Disabled offer cannot be purchased " + str(id))
			continue
		payments[str(row.GoodsPayType)] = true
		var currency = 101 if row.GoodsPayType == "Gold" else 90001 if row.GoodsPayType == "PurchaseCion" else 90002 if row.GoodsPayType == "FreeCion" else 0
		check(int(quote.currency) == currency, "Only native resource payments expose a spendable currency " + str(id))
		check(int(quote.limit) == int(row.GoodsNum) and int(quote.purchased) == 0, "Quote reflects original purchase cap " + str(id))
		if row.GoodsPayType in ["Money", "Other"]:
			check(quote.iap == row.IAPProductConfigData and quote.payment_price == row.IAPProductConfigData.ServerPrice, "Quote keeps IAP display price and product configuration " + str(id))
	check(payments.size() == 4 and payments.has("Ad") and payments.has("Money") and payments.has("Other") and payments.has("FreeCion"), "Real packaged enabled rows use the four observed payment types")
	_dispose(systems)

func _unavailable_payments() -> void:
	var systems = _systems()
	systems.grant_material(101, 10000000)
	systems.grant_material(90002, 1000000)
	var snapshot = JSON.stringify(systems.profile.data)
	for id in [1001, 1002, 1003, 1004, 2001, 2006, 2014, 2018, 2019, 2020, 30001, 30002, 30003, 30004]:
		var quote = systems.offer_quote(id)
		check(not quote.success and not quote.can_buy and not str(quote.reason).is_empty(), "Nonresource payment has an explicit unavailable reason " + str(id))
		check(not systems.buy_offer(id).success and not systems.buy_mall(id).success, "Direct purchase cannot bypass required payment channel " + str(id))
		check(JSON.stringify(systems.profile.data) == snapshot, "Rejected payment neither spends gold nor grants rewards " + str(id))
	_dispose(systems)

func _currency_transaction() -> void:
	var systems = _systems()
	var snapshot = JSON.stringify(systems.profile.data)
	check(not systems.offer_quote(20001).can_buy, "Unfunded FreeCion quote is immediately disabled")
	check(not systems.buy_mall(20001).success and JSON.stringify(systems.profile.data) == snapshot, "Unfunded purchase is atomic")
	systems.grant_material(90002, 120)
	var quote = systems.offer_quote(20001)
	check(quote.success and quote.can_buy and quote.currency == 90002 and quote.price == 120, "Funded packaged FreeCion offer uses its actual price")
	var reward_before = systems.material(501)
	var changes = [0]
	systems.changed.connect(func(): changes[0] += 1)
	check(systems.buy_mall(20001).success, "Funded FreeCion purchase completes")
	check(systems.material(90002) == 0 and systems.material(501) == reward_before + 10, "Successful purchase deducts its price and grants the exact bundle once")
	check(changes[0] == 1 and systems.stat(str(quote.purchase)) == 1, "Successful transaction emits once and records one purchase")
	snapshot = JSON.stringify(systems.profile.data)
	check(not systems.offer_quote(20001).can_buy and not systems.buy_mall(20001).success, "Quote and repeat execution both recheck the changed balance")
	check(JSON.stringify(systems.profile.data) == snapshot and changes[0] == 1, "Insufficient repeat is atomic without another completion event")
	_dispose(systems)

func _rewarded_ad_transaction() -> void:
	var systems = _systems()
	var rewards = AdRewards.new(systems)
	var context = {"kind": "mall", "id": 1002}
	check(rewards.quote(context).success, "Packaged ad offer has a rewarded-ad entry point")
	check(not systems.buy_mall(1002).success, "Ad offer cannot bypass ad completion through buy_mall")
	var before = systems.material(90002)
	check(rewards.claim(context, "authorized-free-skip", true).success, "Existing legal free-skip path completes an ad offer")
	check(systems.material(90002) == before + 30 and rewards.free_skips() == 2, "Ad reward grants packaged amount and consumes one free skip")
	var quote = systems.offer_quote(1002)
	check(quote.purchased == 1 and quote.remaining == 0 and not quote.can_buy, "General quote immediately reflects the ad purchase cap")
	check(not rewards.quote(context).success, "Ad quote shares the purchased limit")
	var snapshot = JSON.stringify(systems.profile.data)
	check(not rewards.claim(context, "authorized-free-skip", true).success and not rewards.claim(context, "second-receipt", true).success, "Duplicate receipt and over-limit receipt cannot repeat ad reward")
	check(JSON.stringify(systems.profile.data) == snapshot, "Rejected ad repeats preserve resources, skip count and receipts")
	_dispose(systems)

func _purchase_limit() -> void:
	var systems = _systems()
	var original = catalog.find("MallTradeData", 20001)
	var limited = original.duplicate(true)
	limited.GoodsNum = 1
	catalog._indices.MallTradeData["20001"] = limited
	systems.grant_material(90002, 1000)
	var quote = systems.offer_quote(20001)
	check(quote.can_buy and quote.remaining == 1, "Limited resource offer exposes its remaining quantity")
	check(systems.buy_mall(20001).success, "Limited resource offer can complete its first purchase")
	quote = systems.offer_quote(20001)
	check(not quote.can_buy and quote.purchased == 1 and quote.remaining == 0 and quote.reason == "已达购买上限", "Limit exhaustion updates quote before another click")
	var snapshot = JSON.stringify(systems.profile.data)
	check(not systems.buy_offer(20001).success and JSON.stringify(systems.profile.data) == snapshot, "Buy recomputes the purchase limit and cannot reuse a stale quote")
	systems.utc_now = func(): return 259200
	check(systems.offer_quote(20001).remaining == 0, "OneBattle offer does not gain an invented daily reset")
	systems.record("runs")
	check(systems.offer_quote(20001).remaining == 1, "Existing OneBattle boundary updates the purchase key")
	catalog._indices.MallTradeData["20001"] = original
	_dispose(systems)

func _purchase_coin_contract() -> void:
	# The native enum includes PurchaseCion although no current enabled row uses it.
	var systems = _systems()
	var original = catalog.find("MallTradeData", 20001)
	var purchased_coin = original.duplicate(true)
	purchased_coin.GoodsPayType = "PurchaseCion"
	catalog._indices.MallTradeData["20001"] = purchased_coin
	systems.grant_material(101, 1000)
	systems.grant_material(90002, 1000)
	var snapshot = JSON.stringify(systems.profile.data)
	var quote = systems.offer_quote(20001)
	check(quote.payment == "PurchaseCion" and quote.currency == 90001 and quote.price == 120, "PurchaseCion retains native enum, purchased currency and original price")
	check(not quote.can_buy and not systems.buy_mall(20001).success and JSON.stringify(systems.profile.data) == snapshot, "Gold and FreeCion cannot fund a PurchaseCion offer")
	systems.grant_material(90001, 120)
	var gold_before = systems.material(101)
	var free_before = systems.material(90002)
	check(systems.offer_quote(20001).can_buy and systems.buy_mall(20001).success, "Funded PurchaseCion offer can complete")
	check(systems.material(90001) == 0 and systems.material(501) == 10, "PurchaseCion spends its configured amount and grants its bundle")
	check(systems.material(101) == gold_before and systems.material(90002) == free_before, "PurchaseCion never deducts gold or FreeCion")
	catalog._indices.MallTradeData["20001"] = original
	_dispose(systems)

func _gold_contract() -> void:
	# Gold remains a compatibility extension, not a native APK payment enum.
	var systems = _systems()
	var original = catalog.find("MallTradeData", 20001)
	var gold = original.duplicate(true)
	gold.GoodsPayType = "Gold"
	catalog._indices.MallTradeData["20001"] = gold
	systems.grant_material(101, 120)
	var before = systems.material(101)
	var quote = systems.offer_quote(20001)
	check(quote.can_buy and quote.currency == 101 and quote.price == 120, "Gold enum spends only its configured resource")
	check(systems.buy_offer(20001).success and systems.material(101) == before - 120 and systems.material(501) == 10, "Gold transaction completes without premium currency conversion")
	catalog._indices.MallTradeData["20001"] = original
	_dispose(systems)
