# Map Selection Polish

Implemented on 2026-10-28 against the supplied `1061664.apk` and two map screenshots.

## Result

- Both route maps use the APK's blue magic-essence icon, green search-point icon,
  currency bar, back button, confirmation button, and checkbox artwork. Atlas
  regions remove unequal transparent padding before sizing the resource icons.
- The selected title, icon, and description are centered above the map. The
  confirmation button stays centered independently of the automatic-route toggle.
  Compact layouts preserve room for the map and keep the controls inside the screen.
- The room selection texture's bright stroke aligns with the inner card at its
  contracted size. The peak is 1.055 times that outline. Drawing bounds include
  the full glow and reward badges; arrows stop outside those bounds. Vertical
  arrows remain at least 14 pixels tall in the tested compact layouts.
- World-map selections now breathe. Initial framing, selection, keyboard focus,
  and resizing account for the complete peak frame, including at either scroll edge.
- Entry retains staggered node appearance and adds a small settling rebound.
  Reward badges fade in after the card. Selection follows a one-second cycle;
  title changes and the first confirmation button appearance fade in.
- Confirmation moves the current character portrait to the destination over one
  second before the existing room-loading flow. Input remains locked during this
  interval, repeated confirmation cannot restart it, and the main scene owns the
  timer so a freed page cannot leave the transition waiting on its tween.
- Reachable boss rooms have a bounded red glow and moving flow/streamer textures.
  The effect uses shader time and does not add a CPU update loop.

## Evidence

APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.

REA archive inspection:
`ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
The complete session was exported to
`/private/tmp/city-route-polish-apk-20261028-evidence.json`; matching retained
archive evidence also exists in `../reports/map-selection-position-rea-evidence.json`.

Focused Unity extraction is separate static evidence, reproduced by
`../tools/inspect_route_chrome.py`. Exact sprite identities, bundle hashes,
material parameters, and authored animation keys are in
`../assets/ui/route/chrome/provenance.json`. Complete source trees and curves are
in `../reports/route-chrome-apk-source.json` and
`../reports/route-chrome-apk-source-curves.json`.

Observed package curves include the one-second selection and portrait-movement
cycles, the 0.333/0.35/0.45-second card settling keys, and the 0.833-to-1-second
badge fade. The original selection peak is anisotropic (1.1, 1.2); reducing it,
adapting travel to responsive node coordinates, and bounding boss effects are
intentional Godot changes. Original APK playback was not observed. Its boss
prefab has zero root scale, so its eventual runtime size remains unknown.

## Verification

All requested implementation areas above are complete. Original Android runtime
timing/particle activation remains outside the static-evidence boundary.

- `route_selection_polish_test.gd`: 838 headless checks; 840 with rendering,
  including actual changed red pixels for boss glow and moving shader layers.
  Covers 2460x1080, 1600x900, 844x390, and 640x900; first/middle/last selections,
  keyboard focus, resize, locked regions, arrow clearance, icon initialization,
  rapid switching, portrait travel, and actual campaign world-map captures.
- `route_animation_test.gd`: 469 rendered checks, including badge staging and
  rebound completion on desktop and mobile layouts.
- `route_connections_test.gd`: 668 checks.
- `world_map_layout_test.gd`: 201 checks.
- `route_reference_layout_test.gd`: 115 checks.
- `map_selection_position_test.gd`: 261 checks.
- `route_presentation_test.gd`: 248 checks through the main-scene entry flow.
- `map_preview_test.gd`: 49 checks.
- Recovered PNGs were decoded and checked against all 15 recorded SHA-256 hashes.

Actual map previews:
`../reports/route-selection-polish-world-reference-2460x1080.png`,
`../reports/route-selection-polish-world-reference-844x390.png`,
`../reports/route-animation-2460x1080.png`, and
`../reports/route-animation-844x390.png`.

Final test logs are under `/private/tmp/city-route-polish-*`.
