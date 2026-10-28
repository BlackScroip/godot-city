# Settings Motion And APK Reference

Updated 2026-10-28.

## Implemented

- Vertical pointer drag with inertia; smooth wheel and trackpad scrolling.
- A 10-pixel gesture threshold cancels pending button clicks once dragging starts.
- Slider input waits for horizontal intent or a tap, so vertical scrolling does not save accidental values.
- Each settings category remembers its scroll position. Clicking its active tab preserves the controls.
- Each segment group draws one animated selection background, reusing the source texture. Rapid changes redirect the running transition.
- Selection movement takes 0.3 seconds at normal UI speed, with the existing double-speed setting applied.
- Auto attack updates the current page instead of reconstructing it.
- Dialogs suspend background scrolling. Scrollbars and keyboard focus remain available.
- Segment widths, sidebar icons/text and footer buttons fit narrow landscape screens and translated labels.

## Evidence

APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.

The supplied APK was reopened with REA and matched the existing archive record,
Evidence `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
The settings bundle SHA-256 was recalculated as
`d47ec4770e365d15a9c91d71e35e3915467d8e576d0b4071756f77745f59b3dd`.

`assets/ui/settings/option/prefab-layout.json` records an independent active slot
of 200 by 62.3225 units over a 600 by 54.43-unit track. The implementation uses
the original active/track sprites and their relative heights.

`reports/settings-motion-source.json` retains three bounded ARM64 method listings,
the matched native-library digest, ELF address mapping, and the duration constant.
`ATPanel_Option.MoveActiveSlotTo`, file offset `0x2ef0410`, loads the float at
virtual/file address `0x12882b4` into `s3`, then tail-calls `DOLocalMove`.
The mapped declaration identifies `s3` as duration; the stored value is
`0.30000001192092896` seconds.

These are local static observations linked to existing REA evidence, not new
REA-native Evidence records or observations of the original APK executing.
The original global easing curve, ScrollRect inertia and elasticity remain
unrecovered. Cubic-out easing, 0.135 exponential inertia decay, bounded edges,
gesture arbitration and UI-speed integration are implementation choices.

Reproduce the bounded native inspection with `tools/inspect_settings_motion.py`,
passing `--apk`, the matching extracted `--native` library, matching Cpp2IL
`--stubs`, and a new `--output` path. It uses the standard Python library and r2.

## Verification

- `tests/settings_motion_test.gd`: 387 checks passed with macOS rendering.
- `tests/settings_flow_test.gd`: 144 checks passed headlessly.
- Actual viewport input injection covers clicks, cancelled clicks, continuous
  slider changes, inertia, wheels, trackpad gestures, direct touch drags,
  failed persistence, rapid selection and double UI speed.
- Layout checks cover 1600x900, 844x390, 1280x900 and 2460x1080, plus English
  row, segment and sidebar text at 1280x900.
- Screenshots are retained under `reports/settings-motion/`; the focused
  machine-readable result is `reports/settings-motion-test.json`.
- Original APK runtime comparison and physical-device touch feel were not tested.

All requested implementation areas are handled. Exact original easing and scroll
parameters remain a partial reverse-engineering result, as noted above.
