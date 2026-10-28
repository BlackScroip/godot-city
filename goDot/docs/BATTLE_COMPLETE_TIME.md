# Battle Completion Time

The room completion HUD now freezes the existing `world.elapsed` combat clock at
completion. This is separate from the full adventure elapsed time already shown
in the settlement page. Only completed Boss rooms show the combat banner; ordinary
combat and noncombat rooms do not. Loading a
room, returning to camp, or opening a modal clears it; resuming an already cleared
room does not replay it. The running-timer setting does not suppress the result.

## APK Evidence

- APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
- REA inventory: `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
- Static Unity prefab: `Panel_BattlePlayerCtrl/BattleSysWnd/Container_BannerEffect/Banner_Win/Anim_BattleWin/BattleWinBanner_Title`.
- TextMeshPro font size and base size are **64**, autosizing is disabled, character
  spacing is zero, font is **Alibaba PuHuiTi 3.0 / 95 ExtraBold**, and color is
  `#ffebaf`. The adapter reuses the corresponding recovered boss-intro font.
- Banner size is `1310 x 320`; the text rectangle is `1310 x 180`, offset 90 down
  from the banner top. The banner root has a 12-unit downward offset. Scaling
  follows the existing 1920 x 1080 reference-canvas adapter.
- `victory_background.png` is the APK sprite `胜利底框`, PNG SHA-256
  `2c73d96be799d99b1b2f1b0fa4fff7bd18a28bdc4a7eb6f9567fee24c9911bb1`.
- `SetBossBattleWinBannerDisplay` coroutine `MoveNext`, file offset `0x30f9568`,
  writes the initial banner context, waits **1.8 seconds**, then writes nonempty
  `bossBattleTime` into the same title field. The float literal at VA `0x1287d00`
  is `1.7999999523162842`.
- Original localized key `Keyword_KillBossTimeUse` is `讨伐用时`.

The native image and metadata used for disassembly were hash-matched against the
supplied APK using `tools/inspect_settlement_native.py`. Full local inspection
outputs are `/private/tmp/city-battle-end-time-native.json`,
`/private/tmp/city-battle-end-time-native.txt`, and
`/private/tmp/city-battle-end-prefab.json`.

## Boundaries

This is static evidence, not observation of the Android app running. The result
is limited to Boss room completion; the recovered native coroutine specifically
gates its timed title branch on a boss battle. The
`MM:SS.cc` formatting and four-second dismissal are adapter choices, not claims
of recovered APK behavior. Full original animator curves, rank badge and light
effects are outside this change. Font size, font family, text slot, background
sprite and the 1.8-second title replacement follow the recovered source.

## Verification

- `tests/battle_complete_test.gd`: formatting, invalid inputs, frozen time,
  native title delay and font size, duplicate completion, dismissal, modal
  cleanup, timer-setting independence, desktop/mobile layout and rendered PNGs.
- `tests/room_gate_flow_test.gd`: ordinary final-wave completion does not publish
  Boss statistics; Boss completion publishes frozen time, and checkpoint restore
  does not replay the banner.
