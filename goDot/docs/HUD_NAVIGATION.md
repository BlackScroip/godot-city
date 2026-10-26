# HUD Navigation And Resource Feedback

Implemented against the supplied `1061664.apk` on 2026-10-26. This covers the
interaction prompt, upper-left resource feedback, and upper-right entry flows.
Skill input/image scaling is documented in [SKILL_CONTROLS.md](SKILL_CONTROLS.md).

## Evidence

The APK SHA-256 is
`ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
Its ARM64 `libil2cpp.so` SHA-256 is
`86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944`.

REA package inventory and inspection are retained as
`ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c`
and `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
The complete local ledger is `reports/hud-navigation-rea-evidence.json`.
Focused Unity prefab, configuration, localization, and ARM64 instruction
evidence is in `reports/hud-navigation-apk-evidence.md` and its JSON sidecar.
That analysis retains 102 method ranges and distinguishes observations,
inferences, and unknowns. Empty Cpp2IL bodies serve only as an address index.
The original APK was not executed for this investigation.

## Resource Counters

Initial synchronized totals stay hidden. Gold, magic, mineral, free currency,
and token-upgrade resources reveal their own row after either a gain or an
expense. Each change restarts the five-second lifetime, with a half-second
fade in and immediate deactivation when it expires. Closing another panel
does not resurrect expired rows.

Signed changes accumulate for four seconds; a sign reversal resets the
accumulator. Their text holds for two seconds, then fades for two seconds.
The changed total starts at scale 1.8 and yellow, returning to scale 1 over
0.62 seconds and white over 1.5 seconds. The timing and endpoints come from
the native instructions; interpolation is an authored linear reconstruction.
Gameplay gain/spend events preserve feedback even when spending and a refund
occur within the same frame.

Search points use a separate string path, displaying current/maximum without
numeric delta effects. The inspected class sets its private first-display
flag true and contains no retained method that clears it. Accordingly, this
implementation updates the text without inventing an automatic popup.
Unexamined external writers/reflection remain an evidence limit. Disabled
auto-reveal currency/resource types are not added as permanent camp counters.

The existing camp overview button moves below visible resource rows. This is
an authored layout accommodation for this reconstruction's extra shortcut.

## Upper-Right Entries

Ordering follows the source's sibling order, with 25 logical units between
90-unit buttons and 80-unit artwork. The final simplified Chinese label for
GoComment is `分享评价`; its cached prefab label `评论` is not the final text.
The gift and meal-buff artwork are extracted through the prefab's sprite
references, with hashes in `reports/hud-navigation-art-source.json`.

| State | Entries |
| --- | --- |
| Camp, guide complete | Mall, character, settings |
| Camp, at least one difficulty victory | Adds quick start, unread review and unread cloud prompts |
| Adventure, guide complete | Difficulty, character, settings |
| Adventure with purchased meals | Adds purchased meal effects |
| Dialogue | Suppresses the top entries |

Native guide completion means index >=10; victory means any positive
per-difficulty victory count. The reconstruction also accepts its historical
aggregate `wins` field. Saves without a guide index default to 10 because this
project enters the ordinary camp without the source tutorial. This is a save
migration choice. The native shared visibility gate's exact singleton class
is unresolved; mapping it to this project's dialogue state is an inference.
Debug-only native attribute/damage entries are excluded from the normal HUD.

Quick start acknowledges its red dot, saves, and opens selectable adventure
preparation. It remains available afterwards. Adventure difficulty opens the
same information in read-only mode. The meal entry displays actual purchased
effects at their current ranks, with no research/purchase actions. Character
and weapon operations validate ownership and reject camp changes during a run.
Settings uses its gear artwork in both camp and adventure.
Unread detection uses marker-key absence, matching the native dictionary check;
an existing zero-valued marker does not recreate an unread prompt.

Review opens confirmation and temporarily clears its red dot without marking
the persistent flag. Confirmation launches the exact packaged TapTap URL,
grants resource 90002 x200, saves, and hides the entry. URL-launch failures
remain retryable without consuming the reward. Reward-once and launch-result
checks are authored failure/repeat handling: the native OpenURL returns void
and its reward call precedes the read-marker test. Tests replace the URL
opener, so they never launch the user's browser or submit a review.
Feedback reports its unconfigured support channel; a live customer-service
integration is not implemented.

Cloud uses the original first-use prompt. Opening/canceling preserves both
the red dot and unread flag. The source writes that flag only after successful
account-service initialization. This project has no cloud SDK or account
backend, so confirmation reports unavailable and offers retry/close; it never
pretends that local saving is cloud saving. Actual authentication, upload,
download and conflict resolution remain unimplemented service dependencies.

Mall keeps original enabled offers and payment types. Direct currency trades
use the actual wallet and recheck balance/quota at purchase. Rewarded ads use
the ad completion path. Cash and unsupported payments are explicitly blocked
without platform payment/receipt services. No cash-to-gold conversion or free
cash-only recruitment is allowed. See `reports/mall-payment-contract.md`.

## Interaction Placement

The contextual command now sits 56 logical units farther left and 52 higher
than its previous position. It shares the skill cluster's anchor and safe-area
shift, is clamped to the viewport, and preserves the original frame aspect.
Geometry checks include padded touch targets for all four skills and the
automatic-attack switch, not just their visible images.

## Verification

All checks below pass on the final source used for this HUD change:

- `hud_navigation_test.gd`: resources, signed deltas, expiry, dynamic entries,
  legacy victories, dialogue, six viewport sizes and simulated safe insets.
- `hud_actions_flow_test.gd`: actual main/menus/save store, quick start,
  cloud cancel/retry, review launch failure/success/repeated confirmation,
  store, character, settings, read-only difficulty and purchased-meal effects.
- `pickup_world_visual_test.gd`: 133 checks in an actual room, including
  physical clicks and nonblank image-region checks at 1600x900, 844x390,
  and 2460x1080.
- `skill_controls_live_test.gd`: 59 checks with main and physics running.
  `skill_controls_visual_test.gd`: rendered idle/pressed/rebound/charging/tap
  frames at those three sizes; icon pixels change while outer frames stay fixed.
- `systems_test.gd`: 4,997 assertions; `mall_payment_contract_test.gd`: 301;
  `navigation_menu_rules_test.gd`: 195; rewarded-ad tests pass.
- Existing camp, map preview, difficulty preparation, navigation and character
  detail regressions pass after adapting their obsolete fixed-menu assumptions.

Graphical captures are under `reports/hud-camp-*.png`,
`reports/pickup-world-*.png` and `reports/skill-controls-*.png`.
These are Godot desktop/phone-size viewport observations, not original APK
execution or iOS device acceptance.

The final iOS export is `builds/ios/hud-navigation-final.pck`, SHA-256
`7ec2c34a4135b9c97978b697489bf4ea3061e2c4b4b7bdb76676ca0ecce5cc69`.
The canonical iOS packs and the pack inside the built application have the same
hash. Xcode 26.5 / iPhoneOS 26.5 builds the existing unsigned workspace with
`CODE_SIGNING_ALLOWED=NO`, producing an arm64 application under
`builds/ios/unsigned/DerivedData/Build/Products/Debug-iphoneos/`.
The official macOS release template also starts this pack and loads the actual
camp, character and weapon, and writes its temporary save successfully.
The smoke retains a camp `CatMeal_Shop` marker-binding diagnostic and reports
13 ObjectDB instances at process shutdown; it is not a full camp parity gate.
This is package-loading coverage and does not exercise iOS APIs.
Device signing/install and real cloud, payment and
account-provider acceptance remain open.
