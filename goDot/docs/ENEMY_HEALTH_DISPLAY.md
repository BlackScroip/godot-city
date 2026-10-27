# Enemy and Boss Health Display

Implemented against the supplied `1061664.apk` on 2026-10-27. This is a Godot
runtime implementation reconstructed from matching APK code and Unity assets.
The APK itself was not executed or captured during this task.

## Source Identity and Evidence

- APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
- ARM64 `libil2cpp.so` SHA-256: `86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944`.
- Metadata SHA-256: `d4fb0878468562c03cd359fee2b8ed4ca31d569da8b9a6f7799d9bd3d7e7e15e`.
- REA inspection: `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
- REA inventory: `ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c`.
- REA manifest: `agm_1151b3c3400a935ccfe9a66a328f2ad73d0dd089d1575602405843ee447bce20`.

[Prefab evidence](../reports/enemy-health-display-apk-prefab.json) records bundle
digests, object IDs, source rectangles, colors, borders and lock AnimationClips.
Fifteen sprites were extracted directly from the APK, rather than approximated
with replacement graphics. Both imported enemy tables were compared as parsed
JSON against this APK and matched, including the numerical table's outer wrapper.

[Native evidence](../reports/enemy-health-display-apk-native.json) contains
matching native/metadata identity checks, 55 selected methods, raw ARM64
instructions, method hashes, recovered literals, observations and bounded
negative searches. The `apk-health-native-*` IDs below are local raw-instruction
anchors in that report, separate from REA's inventory Evidence IDs.
The complete exported [REA evidence bundle](../reports/enemy-health-display-apk-rea.json)
is retained alongside these generated reports; the archive session was closed.

## Implemented Contracts

| Question | Source observation and boundary | Implementation |
| --- | --- | --- |
| HP and trailing fill | `HpStateBar.Update`, `apk-health-native-0x2d0e74c`: follow moves 10% toward current each rendered frame, including healing. | Shared `health_state_bar.gd`; current changes immediately, paused updates retain trail. |
| Excess fill | `HpStateBar.Init`, `apk-health-native-0x2d0d1ec`: ratio clamps to 0..2, base to 0..1 and excess to 0..1. | Separate base and excess layers using recovered artwork where present. |
| Ordinary and elite bars | `apk-health-native-0x30f5ac8`: HP ratio and `CurArmor / MaxHp`; elite icon enabled only for Elite. | Separate actor-instance bars projected above model impact bounds; outer bar reads armor. |
| Floating captions | `apk-health-native-0x315e7e0`, `apk-health-native-0x30c7114`: localized enhancement names, spaces and enemy name; empty when unenhanced. | Real enhancement state supplies fitted captions; no invented numeric elite HP caption. |
| Death visibility | `apk-health-native-0x2d0d080`: alpha moves 20% toward its target each invocation; deleted units remove boxes. | Existing dead-unit bars retain projection and fade toward zero each frame; removal and room cleanup release them. |
| Boss selection | `apk-health-native-0x30eb75c`: first living Boss of the current wave. | First displayable Boss; dead, zero-HP and hidden units are skipped. New targets reset old trailing/lock state. |
| Boss numbers | `apk-health-native-0x2d0de10`: raw current/max use `f0`, joined by `/`. | Rounded text without spaces; underlying range keeps actual fractional combat values. |
| Boss shields | `apk-health-native-0x2d0df50`: truncated integer shield / max HP, two layers; ratios in inclusive 0.01..0.05 become 0.05. | Actual shield state, both source layers and shield number; depletion clears them. |
| Boss HP lock | `apk-health-native-0x2d0dd10`: transition on active HP-lock state, with open/close clips. | Triggered lock statuses drive recovered artwork and Hermite animation curves; installing an untriggered buff shows no lock. |
| Special-state/level APIs | No direct B/BL callers found across executable sections. Indirect/reflection paths remain unknown. | Special bar API retained and normally hidden; no invented gameplay source or level display. |

## Runtime Files

- `scripts/presentation/health_state_bar.gd`: common source graphics, ranges, follow and hit punch.
- `scripts/presentation/enemy_health_bar.gd`: normal/elite layout and armor/caption binding.
- `scripts/presentation/enemy_health_overlay.gd`: projection, instance lifecycle and death fade.
- `scripts/presentation/boss_health_bar.gd`: Boss name, HP, shield layers and lock animation.
- `scripts/presentation/battle_readout.gd`: shared HUD integration, preserving its public range/label aliases.
- `scripts/domain/combat.gd`: read-only display accessors for enhancement names and activated HP locks.
- `scripts/main.gd`: living Boss selection for the readout and introduction flow.

Existing combat damage, armor, shield and HP-lock calculations remain the source
of displayed values. The display accessors add no independent damage calculation.

## Rendering Corrections

The source Boss `HpStateBar/Bar` contains a Unity UI Mask. Its absence in the
initial migration allowed rectangular HP and follow fills to protrude past the
angled frame. The Godot bar now clips those layers to the recovered background
silhouette, using a binary alpha stencil so the mask does not dim their colors.
The background and frame sprites also restore their original transparent sprite
rectangles before slicing; the extracted PNGs contain only tightly cropped pixels.
The recovery report and `styles.json` retain both the source rectangles and crop
offsets, while all 15 PNG payloads remain identical to their recovered sources.

The lock plate is a sliced source image with left/right borders of 31/27 pixels.
It now uses a `NinePatchRect` rather than stretching the whole sprite. Its height
fits the visible HP frame and each end is inset by 10 HUD units before animation
to align with the inner fill. The padlock occupies the left end, and centered HP
numbers render above the plate with space reserved for the icon. The recovered
open/close curves are retained. These dimensions and icon placement adapt the
source artwork to the shared Godot HUD; they are not measured APK runtime layout.

## Verification

Run the focused presentation tests with the pinned Godot executable:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/enemy_health_display_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/boss_health_display_test.gd
```

Omit `--headless` to render the real room and write PNGs at 1600x900, 2460x1080
and 844x390. Reports are generated under `reports/`, which the repository ignores.

The tests use settled combat damage, real enhancement state, repeated lava-dragon
shield buffs, a triggered lock fixture, target switching, pause and healing,
60/120-frame interpolation, death fade, room cleanup and text fitting.
The finite-lock fixture also verifies that the last trigger remains active with
zero remaining uses until the next frame removes its buff; a paused tick does
not remove it.

Final results on Godot 4.7.2:

| Check | Passed |
| --- | ---: |
| Monster display, headless / graphical | 84 / 84 |
| Boss display, headless / graphical | 104 / 107 |
| Boss fill bounds, graphical | 39 |
| Existing enemy health rules | 13,268 |
| Existing Boss HP-lock rules | 37 |
| Existing enemy enhancements | 55 |
| Existing battle readout visibility | 110 |
| Existing battle presentation | 42 |

The main script also passes `--check-only`, all 15 recovered PNG hashes match
the extraction report, and the focused diff passes whitespace checks. The
graphical tests and manual image review cover 1600x900, 2460x1080 and 844x390.
Room geometry and source sprites render; the Boss test also checks sampled
framebuffer color diversity, screen bounds, sliced lock borders, text layering
and icon/text separation at six opening-animation samples.

`tests/boss_health_bounds_test.gd` requires the graphical renderer. It compares
colored HP/follow pixels against an empty bar at the same transform across six
HP values and three hit-punch samples. All 18 cases have zero overflowing pixels
after the correction; the full-HP baseline previously had 83. The test also checks
that the stencil preserves opaque red fill. See the [bounds report](../reports/boss-health-bounds-test.json).

Mobile screenshot examples:

- [Normal/elite bars and enhancement caption](../reports/enemy-health-844x390.png).
- [Boss base HP and numbers](../reports/boss-health-display-unlocked-844x390.png).
- [Boss lock and shield layers](../reports/boss-health-display-844x390.png).

Detailed results: [monster display](../reports/enemy-health-display-test.json)
and [Boss display](../reports/boss-health-display-test.json). During verification,
three explicit touch-layout types and one effect-call indentation were repaired
in concurrently modified HUD/presentation files to restore compilation.

## Reconstruction Limits

The source DOTween punch is approximated with a damped scale oscillation using
the recovered strength 0.15, duration 0.12s, vibrato 8 and three-per-second limit.
This does not claim identical DOTween sample positions. Screen geometry adapts
the recovered components to the project's shared Godot canvas and actor bounds;
it is not a pixel comparison against a running APK.

The source lock indicator reads `RoleUnit.mIsLockHpActive`; this migration derives
it from activated, live lock statuses. Ordinary single-lock behavior is covered;
the Godot `lock_count` is cumulative activations, while `lock_remaining` holds
remaining uses. Native reset ordering for overlapping lock statuses remains unverified. Original
Android runtime timing and device acceptance remain open. Zero/NaN maximum-HP
edge behavior is guarded by the migration rather than copied from unchecked
native division.

## Reproduction

`tools/recover_enemy_health_display.py` recovers the sprites and prefab report
using UnityPy. `tools/inspect_enemy_health_display_native.py` regenerates bounded
native evidence using Capstone plus the matching existing address stubs. Both
tools take explicit APK/output paths; native recovery rejects a different APK
digest. Consult each tool's `--help` for its inputs.
