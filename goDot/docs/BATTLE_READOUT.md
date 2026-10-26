# APK-Guided Battle Readout

Implemented on 2026-10-26 against the supplied `1061664.apk`.

## Evidence

- APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
- ARM64 `libil2cpp.so` SHA-256: `86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944`.
- REA archive inspection: `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
- [Native instruction record](../reports/battle-readout-apk-native.json): APK-verified library bytes, method addresses, decoded ARM64 instructions and metadata hashes. This is ordinary-shell static disassembly, separate from the REA archive Evidence.
- [Prefab and sprite record](../reports/battle-readout-apk-prefab.json): `Panel_BattlePlayerCtrl` / `Mode_InBattle` / `Box_HitCount`, serialized rectangles, animation settings, source bundle hashes and recovered PNG hashes.

The APK was inspected statically. The runtime observations below describe this Godot project.

## Observed Rules

| Source | Static observation |
| --- | --- |
| `BattleGlobalSysAtrribute_Common` constructor, VA `0x30898ac` | Default combo keep time is 2000 ms. |
| `BattleManager.ChangeHitCount`, VA `0x3090c94` | Adds hits and renews the countdown for positive additions. The native game reads its effective duration from a Rogue attribute. |
| `BattleManager.UpdateHitCount`, VA `0x3090dc4` | Decrements the live combo timer and clears it at zero. |
| `BattleManager.ClearHitCount`, VA `0x3090f04` | Clears hit count, remaining time and damage accumulated during the combo. |
| `Panel_PlayerBattleCtrl.UpdateHitCountInfoBox`, VA `0x30ed93c` | Shows the box only for positive hits and positive remaining-time ratio; otherwise requests hide. |
| Same method, VA `0x30ed97c` | Stage is `min(hit_count / 10, 3)`: Nice, Good, Great, Excellent. |
| `Box_HitCount.SetTotalDamage`, VA `0x3100370` | Uses the current combo's damage and start time, with a minimum one-second divisor; DPS updates every 0.2 seconds. |
| `Box_HitCount.ShowBox`, VA `0x30fff18` | Cancels an existing canvas tween before revealing the box. |
| Root `Box_HitCount` prefab tween | Fades the entire group to zero alpha over 0.3 seconds. Its children include hits, total damage and DPS. |
| `Panel_PlayerBattleCtrl.UpdateHitCountInfoBox(float)`, VA `0x30eb314` | A separate three-second timeout hides the box if update delivery stops. |

## Project Behavior

- Room entry starts with the statistics hidden. Only accepted positive player damage to an enemy starts or renews the live combo.
- Hits, damage and DPS describe the current combo. The existing cumulative room counters and adventure settlement damage remain separate.
- Two seconds without a valid hit clears the live combo. The last displayed figures survive during the 0.3-second fade, avoiding a visible zero flash.
- A hit during fading reveals the group immediately and starts a new combo, including a new DPS clock.
- The timer continues after the final enemy dies. Pauses, modal pages and application backgrounding freeze it; it follows the world's simulation speed.
- Live combos retain their countdown through checkpoints. Old saves containing cumulative counters alone do not manufacture a live combo.
- The recovered four-stage progress, HITS tail and rating artwork replace the permanent separator. The source number pulse uses a 0.1-second, 1.39-scale return.
- All readout controls ignore pointer input. Boss and enemy health displays retain independent visibility.
- Numeric text fits fixed widths. Progress textures use stretchable fixed bounds so their original 256-pixel width cannot enlarge the panel.

The current adapter implements the native default two-second duration. Native Rogue modifiers that alter combo duration, its custom sprite-font digits, stage-entry motion and optional short-number formatting are not reconstructed here. Godot layout and digit colors are presentation choices. The readout receives an update every active main-loop frame, so it does not add the native message-delivery watchdog.

## Verification

| Suite | Checks | Result |
| --- | ---: | --- |
| `battle_readout_visibility_test.gd` | 110 | Passed: timer boundaries, fade interruption, save compatibility, stage artwork, numeric fitting, pause and independent boss health. |
| `battle_readout_flow_test.gd`, graphical | 24 | Passed: actual game impact callback, post-combat countdown, backgrounding, simulation speed, settlement counters and rendered visibility. |
| `battle_presentation_test.gd`, headless | 41 | Passed: existing battle tally and boss presentation checks. |
| `enemy_health_display_test.gd`, headless | 33 | Passed: existing enemy health behavior. |

Graphical captures cover 1600x900, 844x390 and 2460x1080. For each size, pixel comparisons confirm that an active readout is nonblank and that the fully hidden readout leaves no pixels compared with its idle frame. Manual screenshot review also checks placement and progress width.

- [Desktop active](../reports/battle-readout-1600x900-active.png)
- [Phone active](../reports/battle-readout-844x390-active.png)
- [Phone fading](../reports/battle-readout-844x390-fading.png)
- [Phone hidden](../reports/battle-readout-844x390-hidden.png)
- [Graphical results](../reports/battle-readout-flow.json)
- [State results](../reports/battle-readout-visibility.json)

Original APK runtime matching and physical Android-device verification remain unobserved.
