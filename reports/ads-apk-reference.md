# APK advertising reference

Investigated 2026-10-23. Target: `/Users/hanyu/U3D/City/com.teamelo.dungeonchasers.apk`.
SHA-256: `8b6b62e21360f8170fc70d86279e88ab04c7c9c6d0d91f659e76a48bdbdb4ea3` (verified locally).

## Evidence and limits

The existing REA bundle `goDot/reports/apk-feel-rea-evidence.json` matches this hash. Its inventory Evidence ID is `ev_abcc9134d78621f34fad95c09ca5c13a0e7fa21b69aa75a2edba067acdd81a4e`; inspection Evidence ID is `ev_6893c551b1ceeacbc6bbd8090f2a216659f956bcf4d2136b5224207e1eb780bf`. These establish the packaged artifact graph, not advertising behavior. The REA Android/native providers were unavailable in the parent investigation (JADX configuration missing; Ghidra unconfigured).

The following results instead come from ordinary local Cpp2IL static analysis, **not REA Evidence**. Cpp2IL identified Unity `2022.3.56f1c1`, metadata `31.1`, and mapped 158,776 method definitions. Its `callanalyzer` recovered direct native call relationships. Generated method bodies are empty: they are signatures with analysis annotations, not recovered C# implementations. Unknown indirect calls remain. No APK execution, actual ad impression, network response, reward delivery, or remote configuration was observed.

Reproduction (existing local executable, no installation):

```sh
DOTNET_BUNDLE_EXTRACT_BASE_DIR=/private/tmp/city-cpp2il/cache /private/tmp/city-cpp2il/Cpp2IL --game-path /Users/hanyu/U3D/City/com.teamelo.dungeonchasers.apk --use-processor callanalyzer --output-as diffable-cs --output-to /private/tmp/city-ads-calls
```

Sources below are relative to `/private/tmp/city-ads-calls/DiffableCs/Assembly-CSharp/`. They remain locally inspectable; the command regenerates them from the hashed APK.

## Advertising entry points

`Teamelo/ProjectAT/ATGameManager.cs:3906` lists seven direct callers of `ShowRewardADS(string popContent, Action<string> successDel, Action<string> failDel, string adsPointId = null)`:

| Caller | What is supported | Remaining uncertainty |
| --- | --- | --- |
| `MallTradeDataSystem.Buy` | Shop purchase workflow can invoke rewarded advertising. Also present in `GameDataModel_AT.cs:3326`. | Exact eligible goods, quantities, price branch, and placement ID require data/control-flow recovery. |
| `ATPanel_CatMealMenu.<RegisterItem>b__36_2` | Cat meal menu has a rewarded-ad action (`ATPanel_CatMealMenu.cs:454`). Nearby success callback calls `CompletePurchased`, `InitMenu`, `EatMeal`. | Concrete selected meal benefits and callback binding were not recovered. |
| `ATPanel_ExtraChallenge.<RegisterItem>b__30_2` | Extra challenge/commission panel rewarded-ad action. | Exact lambda-to-button binding and reward multiplier operands not recovered. |
| `ATPanel_ExtraChallenge.<RegisterItem>b__30_4` | Second action in the same panel. | Same limit. |
| `ATPanel_ExtraChallenge.<RegisterItem>b__30_6` | Third action in the same panel. | Same limit. |
| `ATPanel_PopMonsterWorkInfoPanel.<Start>b__12_3` | Monster-work popup has a rewarded-ad action. Its panel data has `AdsPopContent`, `AdsDel`, `AdsEnableDel`, `AdsDisableInfo`, and `AdsPointId`. | This is a generic callback entry: individual production/upgrade rewards depend on its callers/data. |
| `Panel_FloatingTest.<>c.<RegisterItem>b__119_47` | Developer test entry. | Do not reproduce it as a player-facing placement. |

The extra-challenge panel explicitly declares `Btn_GetDoubleReward`, `Btn_FinishByAdv`, and `Btn_GetDelegation_Ads` (`ATPanel_ExtraChallenge.cs:167`, `:171`, `:177`). The three ad calls plus these fields strongly support opt-in double rewards, completion by ad, and extra commission acquisition as intended features. This semantic mapping is an inference from the panel structure, not a runtime observation. Success callbacks call `ExtraChallengeSystem.GetExtraChallengeReward` and commission-acquisition logic; exact rewards are data-dependent.

The recovered chain includes `ShowRewardADS` -> confirmation popup and callback -> `ExecuteRewardADS` -> `CSJAdsManager.PlayRewardVideoAd` -> ByteDance `RewardVideoAd.ShowRewardVideoAd`. Relevant sources: `ATGameManager.cs:501-542`, `:1033`, `:3917-3935`; `RFrame/ThirdAds/CSJ/CSJAdsManager.cs:154`. `ATGameManager.EAdsType` contains `ChuanShanJia = 0`. This is a CSJ/Pangle rewarded-video implementation in the reference APK, not evidence that this APK uses TopOn or AdMob for this gameplay chain.

## Limits and lifecycle

- Per-placement daily accounting is present: `RogueConfigData.AdsDailyLimitConfig` is `Dictionary<string,int>`; `RogueStableData.AdsDailyLimitInfoDict` stores `AdsDailyLimitData.DailyUsedCount`. `ShowRewardADS` calls `GetAdsDailyLimitData` and `GetAdsDailyMaxCount`, and `CheckCanShowAds` also uses these methods. Sources: metadata-only export `/private/tmp/city-ads-cpp2il/DiffableCs/Assembly-CSharp/Teamelo/ProjectAT/RogueConfigData.cs:501`, `RogueStableData.cs:39,261`; call export `ATGameManager.cs:2684-2709,3924-3929`. **Exact per-placement maximum values and placement strings remain unknown.**
- `ATGameManager.FREE_SKIP_ADS_DAILY_MAX = 3` is a literal constant. Methods `GetFreeSkipAdsRemainingCount`, `GetFreeSkipAdsUsedCount`, `UseFreeSkipAds`, and stored `FreeSkipAdsDailyData.DailyUsedCount` corroborate a daily free-skip mechanism. **Three is the free-skip allowance, not a maximum number of ads watched.** VIP state and `SkipAdsTicket` are also present; the exact entitlement/consumption branches were not recovered.
- The start panel's `TryInitAdsManagerAfterPrivacyConsent` directly calls `HasPrivacyConsent` and `ATGameManager.InitAdsManager` (`ATPanel_StartGame.cs:1172-1180`). This supports consent-gated initialization intent. The call graph does not prove the branch predicate is enforced in every path.
- CSJ wrapper literal constants: `SDK_INIT_TIMEOUT = 10`, `LOAD_COOLDOWN_SECONDS = 30`, `MAX_BACKOFF_SECONDS = 300` (`CSJAdsManager.cs:260-262`). These concern SDK initialization/load retry. **They are not evidence for a 30-second gameplay/interstitial frequency.** `MinWatchTimeForRewardSec` exists as a mutable static field; its value was not recovered.
- SDK callbacks include `OnRewardArrived(bool isRewardValid, int rewardType, IRewardBundleModel extraInfo)`, `OnVideoComplete`, and close/failure handling. Exact grant ordering cannot be proven from the signature/call annotations; a new integration should grant only on the SDK reward signal and deduplicate the grant as an implementation choice.

## Scope conclusions

Answered: package identity, rewarded-video wrapper, seven recovered direct entry points, daily counter structure, literal three-free-skips constant, SDK retry constants.

Partially answered: semantic reward types in the meal/shop/commission/monster-work flows; privacy initialization gating. These have static support but lack full branch/argument reconstruction.

Initially unresolved: actual ad-point IDs, per-point daily maxima, exact reward quantities, availability by progression, live timing, and remote switches. The configuration follow-up below resolves several of these for the retained local data. The seven direct callers do **not** include death/revive, combat tick, stage-clear, scene transition, or generic periodic interstitial entry. This bounded negative result does not rule out indirect calls, but it does mean automatic level-transition interstitials or revive ads cannot be presented as confirmed reference-APK behavior. Adding those is a product decision, separate from APK parity.

## Follow-up: retained configuration and native reward logic

The parent investigation identified retained tables in `goDot/assets/data`. On 2026-10-23, the bytes of `RogueConfigData.json`, `MonsterWorkData.json`, `CatMealData.json`, and `MallTradeData.json` were hashed and all four matched `manifest.json` exactly. `goDot/tools/prepare_data.mjs:8-20` records their sources as `OfflineUnity/Assets/Systems/Resources/SystemsData/<name>.json`, strips a possible BOM, and serializes parsed JSON. The original `OfflineUnity` directory is no longer present. Thus this verifies integrity against the migration manifest, but is not an independent extraction of those resource bytes from the supplied APK. Do not assign REA Evidence IDs to these tables.

Verified hashes:

| Table | SHA-256 |
| --- | --- |
| RogueConfigData | `685ccc7e9d6f11b312df6d46b56b49e28d2a78317d9acd2495cf2782934d2383` |
| MonsterWorkData | `b08d0e45e030cc1a6f75eaad382dea62301c2dd9e7009d0aa1b991f746797b8e` |
| CatMealData | `4ee6b3c73ab636eb835c205223d23ac9fbf16e0bb0d2f7857171a9f2b7c7e466` |
| MallTradeData | `5378b2428f5e0812050906ba7a5f4ca5da81a0b325f501924e1da9ea4b2d6f98` |

`RogueConfigData.AdsDailyLimitConfig` provides these exact local settings:

| Placement | Daily maximum | Semantic interpretation |
| --- | ---: | --- |
| `ExtraChallenge_GetQuest` | 10 | Acquire commission |
| `ExtraChallenge_FinishQuest` | 10 | Finish commission |
| `ExtraChallenge_GetRewardDouble` | 10 | Double commission reward |
| `MonsterWork_AdSpeedUp` | 10 | Accelerate monster work |
| `CatMeal_FreeOrder` | 100 | Free meal order |

These names corroborate the recovered panel/button structure. They are the retained defaults, not verified live remote settings.

All four `MallTradeData` records with `GoodsPayType = "Ad"` have `Enable=true`, `GoodsNum=1`, and `Price=0`:

| GoodsId | Name | RefreshMode | Raw reward configuration |
| --- | --- | --- | --- |
| 1001 | Random regional materials | `OneBattle` | `DetailsDataType=Rate`, DetailsId 301, Num 3 |
| 1002 | Rainbow crystal support | `OneDay` | `DetailsDataType=Default`, DetailsId 90002, Num 30 |
| 1003 | Random gold support | `OneBattle` | `DetailsDataType=Default`, DetailsId 201, Num 500 |
| 1004 | Daily chest | `OneDay` | `DetailsDataType=Rate`, DetailsId 302, Num 1 |

`Num=500` for goods 1003 is a raw parameter, not proof of exactly 500 coins: its configured description explicitly says a random amount. Similarly, rates/pools 301 and 302 must be resolved through their detail tables. `OneBattle` is the configured refresh mode; its exact reset boundary was not traced here.

### Monster-work acceleration

Address recovery used the same Cpp2IL command with `--use-processor attributeinjector --output-as diffable-cs --output-to /private/tmp/city-ads-addresses`. Focused Capstone 5.0.9 disassembly read `lib/arm64-v8a/libil2cpp.so` directly from the APK ZIP. This is ordinary static native evidence, not a REA provider result.

`EnvUnit_Special_MonsterWork.<>c__DisplayClass11_0.<RegisterItem>b__8` is RVA/file offset `0x305ED9C`, length `0xF8`. It reads current accumulated work progress at `RogueStableData+0x290`, requests `GetAttribute(1900)` (`mov w1,#0x76c` at `0x305EE2C`; call at `0x305EE34`), converts the float to an integer, adds it to existing progress (`add w8,w8,w21` at `0x305EE50`), writes it at `0x305EE54`, saves, and refreshes the UI. Enum value 1900 is `MonsterWorkTimeAccelerate`.

`BattleGlobalSysAttribute_Rogue.GetAttribute` has an explicit 1900 case at `0x2F8FAC8`, jumping to `0x2F8FBA4`, and reads `RogueStableData.MonsterWorkTimeAccelerate` at offset `0x2A4` (`ldr w0,[x0,#0x2a4]`, `0x2F8FBAC`). `GetMonsterWorkAdsPopContent` (file offset `0x305D0E4`) reads the same attribute to construct the message. A separate `b__9` resets both accumulated work and process ID; it must not be mistaken for the acceleration callback.

Follow-up static recovery confirmed the default is **30 minutes**. The `RogueStableData` constructor at file offsets `0x2D2E348` through `0x2D2E354` copies the literal at `0x12587B8` (`1e00000001000000`) into `this+0x2A4`: the first integer is 30. `Update_MonsterWorkCampTime` accumulates elapsed seconds until 60.0 (`0x42700000`) before increasing work progress by one, establishing minutes. `b__4` stores the `<>9__8` action at closure offset `0x38` and then `PanelData.AdsDel` offset `0x70` at file offsets `0x305E1F8` and `0x305E204`, confirming the reward binding. The adjacent initial `MaxCount=1` field does not replace the separate daily ad configuration limit of 10.

Address correction: Cpp2IL's RVA/Offset labels above describe **file offsets** for this export. The ELF code segment virtual addresses are file offsets plus `0x4000`; literal mapping must use the ELF segments. These are static observations, not runtime ad delivery. The migration applies 1800 seconds to the selected UTC dispatch order and clamps at the current time. This adapts the original shared work-progress model to the existing Godot dispatch system; future attribute modifiers still need explicit mapping.

### Cat-meal free order

The ordinary meal button callback `<RegisterItem>b__36_1` calls `CatMealDataSystem.BuyMeal`. The rewarded path `<RegisterItem>b__36_2` calls `ShowRewardADS`, while its nearby string callback `<RegisterItem>b__36_5` calls `CompletePurchased`, clears the selection array, reinitializes the menu, and calls `EatMeal`. Research uses a separate callback `<RegisterItem>b__36_7` calling `CatMealDataSystem.Research` (`ATPanel_CatMealMenu.cs:435-480` in the call export).

Together with the placement name `CatMeal_FreeOrder`, this strongly supports granting the selected meal order without the normal purchase step, rather than unlocking/researching meals or doubling the meal's effect. It does not prove every material/currency mutation inside `CompletePurchased`; those internals and the delegate constructor arguments were not fully decompiled. A migration should retain existing meal selection, availability and buff application, and replace only the purchase gate for this placement.
