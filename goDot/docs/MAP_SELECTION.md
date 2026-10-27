# Map Selection And Horizontal Positioning

Implemented on 2026-10-26 against the supplied `1061664.apk`.

## Evidence

- APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
- REA archive inspection: `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
- Complete retained inventory: `../reports/map-selection-position-rea-evidence.json`.
- APK-verified native bytes and decoded instructions: `../reports/map-selection-position-apk-native.json`.
- Named disassembly: `../reports/map-selection-position-native.txt`.
- APK prefab pivot, spacing and viewport evidence: `../reports/map-scroll-layout-apk.json`,
  reproducible with `tools/inspect_map_scroll_layout.py`.

The native helper verifies the local ARM64 library against the actual APK member,
retains its method bytes and declaration hashes, and records the packaged metadata
hash. REA supplies package identity/inventory; the focused instruction decoding is
a separate local Capstone analysis. Recovered Cpp2IL declarations identify methods
and offsets; their empty bodies are not original source. Attached artifact text
was treated as evidence, not instructions.

## Observed Rules

| Question | Static evidence | Result |
| --- | --- | --- |
| Initial selection | `ATPanel_RoadMapSelect.InitSelf`, file `0x2f1dca8`, VA `0x2f21ca8`; region `InitSelf`, file `0x2f03d74`, VA `0x2f07d74` | Both panels clear selection and initially hide confirmation. Small-map initialization does not preselect an available room. |
| Selecting a room | Road-map click callback, file `0x2f20534`, VA `0x2f24534` | Records the actual `RoadMapNodeData` object, updates its highlight/details, and enables confirmation. Ordinary clicks do not enter a room directly. |
| Selecting a region | `OnSlotClick`, file `0x2f07688`, VA `0x2f0b688` | Only current-module/data-ready slots can be selected in normal mode. Openness and unlock conditions separately control confirmation. |
| Region confirmation | `OnConfirm`, file `0x2f080e0`, VA `0x2f0c0e0` | Rechecks eligibility before the existing high-risk confirmation/entry flow. |
| Small-map position | `ScrollToTargetPosition`, file `0x2f1e49c`, VA `0x2f2249c`, plus the packaged slot pivot | Aligns the active node's right edge with the viewport center, independently of the selected candidate. |
| World-map position | `ScrollToCurrentModule`, file `0x2f06024`, VA `0x2f0a024` | Centers the current module, including the next pending module after a region is complete. |
| Automatic entry | `StartRegionRouteRun`, file `0x2e7fa08`, VA `0x2e83a08`; `AdvanceRegionRoute`, file `0x2e5cbcc`, VA `0x2e60bcc` | A normal new run still opens its first world selection. Subsequent single-choice modules may auto-enter. |

Small-map pixel-equivalent formula:

```text
scroll_x = clamp(active_node_right_x - viewport_width / 2,
                 0, max(0, content_width - viewport_width))
```

The native calculation adds half the slot width to `anchoredPosition.x`
(`0x2f22554`-`0x2f2256c`). Both the panel's referenced slot and the standalone
`ATSlot_RoadMapNode` have `m_Pivot.x = 0.5` and width 100, so that anchored position
is the center and the sum is the right edge. The packaged first-node X is 400
and column spacing is 510. `RoadMapData.GetActivatingNode` (VA `0x2d878b0`)
resolves the last activated occurrence rather than a newly selected candidate.
The earlier center-based Godot formula omitted this half-width offset; the
follow-up correction restores the APK's forward space when opening selection
after completing a room.

World-map source center is `map_margin + column_space * (module_index + 1)`.
The Godot layout uses the current module's actual node center, accounting for its
entrance column and control dimensions. Both formulas clamp at the map edges.

## Implementation

- Both map panels open without a candidate selected. Selecting a node alone does
  not advance progress or spend a shift charge. Repeated confirmation dispatches
  at most once from the current page.
- Current locked/unopened region slots show their details in the map and disable
  confirmation. Future/passed columns cannot replace the selected candidate.
  Read-only previews reject selection and confirmation.
- Room commands preserve `node_id` plus `layer_index` through selection, resource
  loading, campaign entry and shift billing. A shared `route_choice` resolver
  prevents a repeated configuration ID in the forward and vertical columns from
  selecting the wrong occurrence. Legacy unqualified calls prefer forward entry.
- The initial world map remains visible with automatic routing enabled; later
  single-choice modules retain automatic entry.
- New pages center the world module or the room anchor's right edge. On small-map
  selection pages, narrower viewports scroll farther only when needed to keep
  the next reachable column and its selection-frame padding fully visible.
  Resizing retains focus when the user has not scrolled, and preserves the
  browsed column after manual
  scrolling. Selected details and map captions fit above the horizontal scrollbar.

Resize preservation, the narrow-viewport visibility guard, duplicate-submit
protection and the compact inline detail label are Godot implementation choices.
Static evidence does not establish Unity window-resize behavior or pixel-identical
UI appearance. The duplicate-ID fixture
uses a legal repeated configuration in two reachable occurrences; no claim is
made that the APK itself has this reconstruction bug.

## Verification

`tests/map_selection_position_test.gd` covers 207 checks, including initial and
locked selection, single confirmation, duplicate occurrence identity, actual
main-controller shift charging, automatic initial/later region behavior, current
focus, manual-scroll resizing, and end-of-map clamping. It also completes six
consecutive actual campaign rooms and checks every next selectable node including
its selection glow at 1600x900, 1280x720, 2460x1080, 844x390, 1000x900 and 640x900.
The earlier formula fails the APK alignment and narrow-window visibility checks.
The corrected suite passes headless and graphically; graphical verification
records the same geometry and saves `map-next-room-*.png` captures.

The follow-up world-layout suite passes 201 checks and preview passes 49 checks.
The full-scene route suite reaches all 248 assertions, but its latest startup
also reports a missing `DungeonWorld.apply_settings` hook while the separate
settings changes are in progress (`/private/tmp/city-map-next-room-integration-final.log`).
That run does not establish a clean startup of all concurrent workspace changes.

Existing campaign, route rules, world rules, preview, world layout, room layout,
connection, animation and full route-presentation regressions also passed.
Real-map and focused-position PNG captures were visually inspected on desktop
and landscape phone sizes. Results/captures are under `../reports/` and logs under
`/private/tmp/city-map-*`.

Reproduce the focused suite:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /private/tmp/city-map-selection.log --path /Users/hanyu/U3D/City/goDot --script res://tests/map_selection_position_test.gd
```

All requested selection and horizontal-position questions are answered within
static APK and Godot test coverage. The original APK was not executed on Android;
touch feel, original animation timing and runtime pixel parity remain unverified.
