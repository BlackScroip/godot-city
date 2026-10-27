# Construction UI

Implemented against the supplied `1061664.apk` on 2026-10-27.

## Behavior

- Drag the construction list with a mouse or touch, use the wheel, or drag the scrollbar. Dragging from a building does not activate it. Scrolling clamps at the ends and stops immediately on release, matching the prefab's disabled inertia.
- Only the selected stage displays the two original inward-facing arrows. Their zero-slope keys repeat at 0, 0.5 and 1 second; the 220-unit source slot is adapted to the page's 140-unit artwork.
- The panel slides upward and fades in over 1/3 second. Wood moves and fades over 4/15 second; wood and hammer replay the recovered quaternion rotation samples, including their rebound. Hammer uses its original off-center pivot. Pointer input unlocks at 0.5 second. Closing fades for 0.3 second. Timing respects the existing UI speed setting.
- The question mark opens GuideData article 101 using its original title, heading, image and text. The modal uses the recovered dark gold-edged panel, white image frame, divider, close artwork and one gold page dot. Both close buttons and Escape dismiss the guide first.
- Closing help preserves the selected stage, details and list position. Same-page reconstruction restores the stage and scroll position. Existing construction transactions and the return to the actual camp facility continue through the established domain flow.

## Evidence

APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.

REA archive observation: `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`. The complete retained record is exported in `../../reports/construction-apk-rea-evidence-20261027.json`.

`../assets/ui/camp/construction/source.json` records the content hashes, Unity object IDs, bundle members, original prefab fields, animation curves, source image comparisons, decoration transforms and guide validation. The page uses its own map of 84 sprites recovered from this APK. GuideData 101 and its existing guide PNG match the supplied APK exactly.

Recovery command, with UnityPy, Pillow and Capstone available in the Python environment:

```sh
python3 goDot/tools/recover_construction_ui.py --apk 1061664.apk
```

The archive inventory and Unity data are static observations. The original Android application was not executed. Runtime validation below exercises the Godot implementation; layout adaptation and mouse support are implementation choices.

## Verification

- `building_interaction_test.gd`: 90 checks passed with rendering enabled, including real mouse/touch/wheel input, drag cancellation, source animation sample values, input blocking, stage selection, list bounds, refresh restoration and Escape routing.
- Captured and visually inspected the list, help and bottom of the list at 1600x900, 844x390 and 2460x1080, plus entrance animation frames. Images are in `../reports/construction-*.png`; the result is `../reports/construction-interaction-test.json`.
- `camp_flow_test.gd`: 70 checks passed, including construction costs, persistence and camera focus after successful construction.
- `settings_flow_test.gd`: 144 checks passed, including existing guide and Escape behavior.
