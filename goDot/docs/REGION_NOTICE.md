# Region Entry Notice

The HUD now presents the current area's name after a new room finishes loading
and the player's arrival transfer completes. New rooms get a fresh animation;
opening maps, restoring a saved room, practice fixtures and returning to camp do
not replay it. Menus and camp cancel an active notice. Ordinary toasts remain
independent, move below an active banner, and return to their usual position
when it ends. The notice does not capture input.

## APK Evidence

The selected artifact is `1061664.apk`, SHA-256
`ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
REA inventory Evidence:
`ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
The full inventory is retained in `reports/region-notice-rea-evidence.json`.

Static Unity observations in `reports/region-notice-apk-evidence.json`:

- `Panel_BattlePlayerCtrl/BattleSysWnd/Container_BannerEffect/Banner_GameStart`
  contains the animated image and `RegionTitle`. Its serialized sample text is
  the forest name, with a white 42-point centered label.
- The `RegionStart` clip lasts 2.666666746 seconds and supplies 24 sprite pointer
  entries, background and text activation, and cubic alpha curves. The port
  reads the recovered keys and sprites directly, including the initial flash
  and final fade.
- The image has preserve-aspect enabled. Its top-aligned rectangle is 341 units
  tall; the containing banner adds a 43-unit downward offset. Layout uses a
  1920 x 1080 reference with proportional scaling as a port layout choice.
- Local Capstone analysis of the APK-matched ARM64 image finds
  `SetBannerDisplay` at file offset `0x30effc4`, mapped VA `0x30f3fc4`. The
  `GameStart` branch compares banner type with 5, starts the banner animator,
  and assigns the supplied context to `Text_RegionTitle` at field `0x170`.

These are static observations, not a recording of APK execution. The Godot
entry timing, area-name lookup, resume suppression and menu cancellation are
port integration choices. Source sound activation is retained in the evidence;
this addition uses the existing room-entry audio.

## Validation

`tests/region_notice_test.gd` exercises actual forest and island entry, same-area
room changes, loading/arrival ordering, independent toasts, expiry, save resume,
menus and camp. Running without `--headless` also captures flash, title and
hidden states at 1600 x 900, 844 x 390 and 2460 x 1080 and checks rendered gold
pixels and viewport bounds.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/region_notice_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/hanyu/U3D/City/goDot --script res://tests/region_notice_test.gd
```
