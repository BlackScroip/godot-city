# Skill Controls

Updated on 2026-10-26 in the HUD, touch button, input controller and world dispatch.

## APK Reference

Target: `1061664.apk`, SHA-256
`ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.

REA inventory Evidence:
`ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c`.
Inspection Evidence:
`ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
Graph manifest:
`agm_1151b3c3400a935ccfe9a66a328f2ad73d0dd089d1575602405843ee447bce20`.

The YooAsset manifest resolves `Panel_BattlePlayerCtrl` to
`assets/yoo/DefaultPackage/c77908234c52fdfb5f6694d3dc60f5dd.bundle`.
`tools/inspect_skill_controls.py` reads its Unity RectTransforms directly and
records bundle hashes, object IDs, hierarchy paths, anchors and local scales in
`reports/skill-controls-apk-reference.json`.

| Control | Observed local size after scale | Godot diameter |
| --- | ---: | ---: |
| Normal attack | 270 | 192 |
| Dodge | 165 | 120 |
| Active skill 1 | 180 | 128 |
| Active skill 2 | 150 | 112 |
| Auto attack | 90 | 72 |

Observed: the serialized prefab uses a large primary attack, smaller surrounding
skills, and a small auto-attack control anchored near the lower right corner.
These local sizes exclude Canvas scaling and runtime layout preferences.

Current native dispatch and prefab bindings were independently checked against
the matching APK's ARM64 library. See
[the native evidence report](../reports/skill-controls-native-evidence.md) and
`tools/inspect_skill_controls_native.py`. The retained JSON contains exact
instruction bytes, ELF offsets, constant values and delegate-token bindings.
Cpp2IL declarations were used only as an address/type index, not as method bodies.

Observed native behavior: the four skill slots scale only `Image_SkillIcon`
to 0.9 on down and restore 1 on up. These callbacks assign scale immediately.
The animated transitions and expanded Godot spacing below are authored UX
enhancements; they are not claimed to be observed APK animation timing.

## Behavior

- The cluster occupies 520 x 392 logical units with 24-unit right/bottom margins.
  Attack, dodge and active skill one are larger, with distinct auxiliary sizes
  and wider gaps. Native mobile safe-area right/bottom insets are converted
  into viewport coordinates before placement.
- Only the centered artwork contracts to 90% in 65 ms and returns with a small
  overshoot over 180 ms. Same-frame down/up completes its compression before
  returning, so quick taps remain visible without delaying gameplay release.
- The frame, SP fill, cooldown/recharge, stock text, ready orbit and circular
  input target keep their original size and center throughout feedback.
- The auto-attack control retains a minimum effective diameter of 48 viewport
  pixels at the tested sizes. Its caption stays outside the icon.
- Normal attack down captures a gesture without starting a normal action.
  Short up requests normal attack. At 0.3 seconds the gesture becomes long,
  repeatedly requesting heavy each input tick; long up stops heavy, including
  when all heavy requests were unavailable. It never falls back to a normal tap.
- Active one and two and dodge request their actions on down. Active one gets
  `InputSkill1_LongPress` only after 0.3 seconds and clears it on up. Active two
  does not invent an `InputSkill2_LongPress` flag, and neither skill down writes
  `InputAttack`. Successful action entry consumes the skill request flag.
- Auto mode cycles `off -> normal -> heavy -> off` on an inside click release.
  Holding, outside release and cancellation do not switch modes. A manual attack
  hold suspends auto execution; auto tap has a 0.25-second minimum interval.
- Gesture/auto clocks use frame input time rather than battle slow-motion time.
  Gameplay still uses the existing action/resource/cooldown admission and input
  buffer. Per-character actions and held-skill responses use existing source data.
- Separate touch IDs, outside skill release, charging and cooldown remain
  available. Cancellation has its own signal before up, preventing menu, focus,
  disable or resize cancellation from turning into a short attack. Canceling one
  button preserves another finger's queued skill. Dodge preserves captured touches.
- Fixed a live-game regression: `main._process()` refreshed adventure mode every
  frame and the setter always relaid out the HUD, resetting every held pointer
  and feedback animation. Unchanged mode updates now return early; layout resets
  skills only when their final geometry actually changes.
- Full cooldowns draw a circle rather than a closed fan with duplicate endpoint
  vertices, avoiding the polygon triangulation error found during rendering QA.

## Verification

| Check | Result |
| --- | --- |
| `tests/skill_controls_test.gd` | 403 assertions passed |
| `tests/skill_button_logic_test.gd` | 365 checks passed, seven characters at 30/60/120 Hz and auto cadence |
| `tests/skill_controls_live_test.gd` | 59 checks passed, live main/world processing in camp and adventure |
| `tests/combat_optimization_test.gd` | 256 checks passed |
| `tests/heavy_attack_test.gd` | 449 checks passed |
| `tests/attack_motion_test.gd` | 9,370 assertions passed |
| `tests/skill_ready_test.gd` | 134 assertions passed |
| `tests/joystick_test.gd` | 110 assertions passed |
| `tests/skill_controls_visual_test.gd` | 15 captures, no failures; main update enabled |

Layout/input checks cover 640 x 360, 844 x 390, 1280 x 720, 1600 x 900,
2460 x 1080 and 1200 x 900. The smallest measured gap between circular input
targets remains positive at every tested size. Rendering on Apple M4 covers idle,
simultaneous press, release overshoot, quick taps and charging/cooldown at
844 x 390, 1600 x 900 and 2460 x 1080. Pixel checks confirm visible art changes
with unchanged outer-frame pixels. Screenshots and JSON results are under
`reports/skill-controls-*` and `reports/skill-button-logic.json`.

The visual fixture freezes world motion and steps icon feedback for repeatable
captures, but leaves the main HUD update enabled. The separate live test leaves
both normal main processing and world physics enabled, exercising real held
touches through the 0.3-second threshold, independent dodge, auto mode clicks and
modal cancellation. This closes the prior fixture's coverage gap.

The updated iOS resource pack was exported to
`builds/ios/skill-controls-20261026.pck` and synchronized into the existing iOS
projects. The unsigned Debug device build passed with Xcode 26.5 (17F42), the
iPhoneOS 26.5 SDK and `CODE_SIGNING_ALLOWED=NO`. Its executable is arm64, and
`builds/ios/unsigned/DerivedData/Build/Products/Debug-iphoneos/DungeonChasers.app/DungeonChasers.pck`
matches both the exported pack and the Xcode source resource with SHA-256
`c8a74d7df4b6cc5209ac4ff18d313fc890122fc4a30805854586ac19086fea5c`.
Build output retains existing native-ad SDK and deployment-target warnings.

These are desktop rendering and automated game tests, not iOS device acceptance
or observed execution of the original APK. Exact device ergonomics and exhaustive
downstream action-graph equivalence remain unverified.

Run the focused checks with the project's pinned Godot:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --script res://tests/skill_controls_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --script res://tests/skill_button_logic_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --script res://tests/skill_controls_live_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --path goDot --script res://tests/skill_controls_visual_test.gd
```

The APK inspector requires the existing UnityPy analysis environment:

```sh
PYTHONPATH=/private/tmp/city-charge-pydeps:/private/tmp/city-native-pydeps python3 goDot/tools/inspect_skill_controls.py --apk 1061664.apk --output goDot/reports/skill-controls-apk-reference.json --rea-inventory-evidence ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c
```
