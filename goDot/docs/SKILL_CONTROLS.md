# Skill Controls

Implemented on 2026-10-26 in `scripts/hud.gd` and `scripts/touch_button.gd`.

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
| Normal attack | 270 | 168 |
| Dodge | 165 | 112 |
| Active skill 1 | 180 | 112 |
| Active skill 2 | 150 | 112 |
| Auto attack | 90 | 64 |

Observed: the serialized prefab uses a large primary attack, smaller surrounding
skills, and a small auto-attack control anchored near the lower right corner.
These local sizes exclude Canvas scaling and runtime layout preferences.

Design choices: equal auxiliary diameters, new spacing, edge margins and click
animation curves are authored for this Godot implementation. Static inspection
does not establish the original APK's click animation or its timing. Original
runtime visual equivalence remains unverified. Existing recovered artwork is used.

## Behavior

- The cluster occupies 400 x 344 logical units with 24-unit right/bottom margins.
  Circular targets are separated, including the auto-attack target's padding.
- Artwork contracts to 88% in 65 ms and returns with a small overshoot over
  180 ms. A press immediately contracts to at most 96%, so even a tap released
  before the next frame has visible feedback.
- Drawing and the ready orbit share the same visual transform. The Control's
  layout rectangle, center and circular input target remain fixed.
- The auto-attack control retains a minimum effective diameter of 48 viewport
  pixels at the tested sizes. Its caption stays outside the icon.
- Separate touch IDs, outside release, charging and cooldown state remain
  available. Cancellation, hiding, focus loss, disabling, window exit and layout
  changes reset the held state and visual transform.
- Full cooldowns draw a circle rather than a closed fan with duplicate endpoint
  vertices, avoiding the polygon triangulation error found during rendering QA.

## Verification

| Check | Result |
| --- | --- |
| `tests/skill_controls_test.gd` | 353 assertions passed |
| `tests/skill_ready_test.gd` | 134 assertions passed |
| `tests/joystick_test.gd` | 110 assertions passed |
| `tests/skill_controls_visual_test.gd` | 12 captures, no failures or engine errors |

Layout/input checks cover 640 x 360, 844 x 390, 1280 x 720, 1600 x 900,
2460 x 1080 and 1200 x 900. The smallest measured gap between circular input
targets is 9.61 pixels at 640 x 360. Rendering on Apple M4 covers idle, simultaneous
press, release overshoot and charging/cooldown states at 844 x 390, 1600 x 900 and
2460 x 1080. Screenshots and JSON results are under `reports/skill-controls-*`.

An additional `tests/feel_test.gd` run passed 159 of 180 assertions. Its 21
failures are the three burst-start/animation/presentation assertions for each
of seven characters: that test requests slot 3 immediately after configuration,
when its energy is 0 and its cost is 100. An independent combat-only probe,
without a HUD or touch button, reproduced all seven insufficient-energy results;
all seven requests succeeded after filling energy. This test precondition and
the reported missing voice reference `audio_voice_zhangnv_battle_3` are recorded
separately from the passing UI checks.

Run the focused checks with the project's pinned Godot:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --script res://tests/skill_controls_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --path goDot --script res://tests/skill_controls_visual_test.gd
```

The APK inspector requires the existing UnityPy analysis environment:

```sh
PYTHONPATH=/private/tmp/city-charge-pydeps:/private/tmp/city-native-pydeps python3 goDot/tools/inspect_skill_controls.py --apk 1061664.apk --output goDot/reports/skill-controls-apk-reference.json --rea-inventory-evidence ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c
```
