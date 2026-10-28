# Map Arrows From The Supplied APK

Implemented October 28, 2026 for `1061664.apk`.

## Evidence And Findings

- APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
- REA archive inspection: `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
  Complete export: `/private/tmp/city-arrow-apk-20261028-rea.json`.
- `reports/route-arrow-apk-native.json` retains 13 APK-verified ARM64 methods,
  method bytes, matching declaration hashes, metadata identity, and the slot
  state jump table. Reproduce with `tools/inspect_route_arrow_native.py`.
- `reports/route-arrow-apk-prefabs.json` retains the packaged transforms, state
  colors, sprite references and verified PNG hashes. Reproduce with
  `tools/inspect_route_connections.py`.

| Question | Static observation | Resolution |
| --- | --- | --- |
| Are crossing branches legal? | `GenerateNodeConnections`, VA `0x2e86c0c`, independently rolls adjacent forward directions at 50 percent. `GenerateRoadMap`, VA `0x2e84838`, adds straight/final-room exits and calls that method. The supplied room screenshot also contains an X crossing. | Answered. Preserve actual reachability and saved routes; do not delete valid crossing branches. |
| Which direction should an arrow indicate? | `CreateARoadMapNode`, VA `0x2f21f64`, populates directional flags from reachable indices. `IsReachable_RightUp/Right/RightDown` test differences 9/10/11; Up/Down use -1/+1. | Answered. Keep occurrence-qualified source/destination edges; derive screen direction from those nodes. |
| Which artwork and orientation? | `ATSlot_RoadMapNode` uses separate straight (220x64) and diagonal (256x200) image rectangles. Downward diagonal images flip the upward images vertically. Available sprites also have separate straight/diagonal references. | Answered. Replace rotated horizontal room arrows with the recovered diagonal state sprites and vertical mirroring. |
| Which paths are dim? | `Slot_RoadMapNode.UpdateUIInfo`, VA `0x2fb9640`, dispatches NoReachable/Passed to gray base lines and Cur to available sprites. Its jump table is at file `0x12f2038`. Packaged `lineColor_Gray` is 90/255 RGB. | Answered. Missed/old base paths use that gray; actual traversed paths and current exits retain their respective bright sprites. |
| Why did the port look tangled? | The previous renderer used `path_*` horizontal art for all room edges and rotated/stretched it. Row spacing expanded independently of card scale, and all unused arrows remained fully bright. | Answered by source inspection and rendered Godot checks. |

REA supplies archive identity/inventory. Capstone and UnityPy provide the focused
local native/resource analysis. Native decompilation providers are unavailable
on this host. The original APK was not executed; these are static observations,
not an Android runtime comparison. Declaration stubs identify methods and fields
and are not original source bodies.

## Port Changes

- Room arrows now use `path_diagonal_unavailable`, `path_diagonal_passed`, or
  `path_diagonal_available` when the destination is on another row. Downward
  arrows mirror vertically without rotating a horizontal arrow.
- Both arrow bounds fit between the nodes' peak selection bounds, including
  badges and glow. Arrow tails and tips stay adjacent to their actual rows.
- Row spacing follows the packaged 220-unit pitch relative to the visible card
  border, with extra clearance for the existing selection animation and vertical
  arrow controls on compact screens.
- Dim routes draw first, then traversed routes, then current choices, so a dim
  crossing cannot paint over the current route's bright outline.
- Existing topology, saved progress, choices, world-map line families and
  vertical-move costs are preserved.

Responsive spacing, full-glow clearance and drawing priority are explicit Godot
adaptations. Native RNG sequence parity is not claimed.

## Verification

- `route_connections_test.gd`: 1,724 rendered checks, covering actual campaign
  progression, all path families, both diagonal directions, duplicate room IDs
  in different columns, saved-topology preservation, and bright crossing pixels.
- `route_selection_polish_test.gd`: 838 headless checks; peak selection frames
  still clear arrows and stay inside the scroll viewport.
- `map_selection_position_test.gd`: 261 checks.
- `route_reference_layout_test.gd`: 115 checks.
- Rendered captures cover 2460x1080, 1600x900 and 844x390. The crossing fixture
  additionally checks 640x900. Desktop and phone progression captures were
  visually inspected after waiting for the entrance animation to finish.
- All recovered connection sprite hashes still match the selected APK. The
  Godot verification logs contain no errors or warnings.

Preview: `reports/route-connections-rooms-progress-2460x1080.png` and
`reports/route-connections-rooms-progress-844x390.png`.
