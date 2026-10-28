# Combat performance and source hit feedback

Implemented on 2026-10-28. This is a scoped optimization of the existing Godot
combat, with source-authored model-shake feedback restored. It does not establish
complete Unity runtime equivalence or eliminate every measured frame spike.

## APK evidence

- Supplied APK: `../../1061664.apk` relative to this document, SHA-256
  `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
- REA inspection: `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
- REA inventory: `ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c`.
- Artifact manifest: `agm_1151b3c3400a935ccfe9a66a328f2ad73d0dd089d1575602405843ee447bce20`.
- Its verified `lib/arm64-v8a/libil2cpp.so` member hashes to
  `86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944`.
  All 39 retained method ranges in `reports/hit-feedback-native-static.json`
  and all 28 in `reports/combat-timing-native-static.json` were rehashed against
  a matching extracted library; all match.
- Full REA export: `/private/tmp/city-combat-apk-20261028-evidence.json`.
  Inspection was completed once and exported after its complete graph exceeded
  the MCP transport budget. The archive graph is not runtime observation.

The source `hit-model-shake` finding establishes intensity 0.05, five samples,
strict elapsed >0.02, and one X/Z sample per render update. Unity's integer
`Random.Range(-1, 1)` gives -1 or 0. The sixth interval restores the model.
Relevant virtual addresses: StartShake `0x3181348`, UpdateShake `0x3180734`,
ResetShake `0x3181374`, URoleUnit.Update `0x31805e4`. The inspected timer receives
Unity delta; all possible Unity global time-scale callers remain unaudited.

## Changes

- Cache immutable serialized feedback and raw definitions in a 2,048-entry FIFO.
  Internal readers share recursively read-only values. Existing mutable APIs
  return deep copies; mutable dictionary inputs are evaluated afresh. This
  preserves runtime modifiers and prevents cache contamination between actors.
- Reuse the already normalized hit feedback for source presentation.
- Reserve the existing particle/emitter budget before acquiring an authored
  effect. A recycled instance can serve the incoming cast, and a denied cast
  no longer clones an unused particle hierarchy and materials.
- Skip updating the fallback quad material while that quad is hidden behind
  an authored effect. Visible effects keep their existing opacity updates.
- Apply the source model-shake flag on accepted source hits. A dedicated visual
  parent and local RNG leave body transforms, collisions, damage, action clocks,
  animation transforms and gameplay random draws intact. Pause, death, impact
  cleanup and visual replacement clear the offset. Existing source hit stop,
  named effects, scale, audio and camera parameters remain intact.
- Add explicit stress-test focus and FPS options plus a combat-activity gate.
  A paused window can no longer produce a successful combat benchmark with
  zero impacts. Test options do not write the player's saved settings.

No effect density, particle budget, resolution, physics frequency or character
attack parameters were reduced by these changes. The existing generic normal
attack feedback remains; native material flash, full force/controller behavior
and pixel-identical camera motion are not claimed by this change.

## Focused validation

`hit_feedback_cache_test.gd` passes 38,018 assertions across 18,994 packaged
definitions, including 1,346 with feedback. It checks content parity, nested
ownership, dynamic edits, invalid shapes, bounded eviction and live references.

In three warm, same-process CPU measurements, 24 real payloads repeated 100
times each produced these medians:

| Operation, 2,400 calls | Original ms | Optimized ms |
| --- | ---: | ---: |
| Feedback normalization / internal cached read | 179.117 | 16.662 |
| Raw JSON parse / cached private deep copy | 158.421 | 57.771 |

These are function costs, not a frame-rate improvement percentage.
Raw output: `reports/hit-feedback-cache-tests.json`.

`effect_pool_pressure_test.gd` passes 412 assertions. The new rejection case
fails against the original allocation order and passes after the change.
Full quality retains 42 active effects, 1,344 particles and 126 emitters while
using 42 distinct instances instead of 43. Reduced quality retains 16 effects,
512 particles and 48 emitters while using 16 instead of 17. Steady median spawn
cost is essentially unchanged (23 to 24 microseconds); this change removes an
unnecessary allocation at the boundary rather than claiming a steady speedup.

Source model-shake tests pass 27 assertions, source feedback helper tests 248,
world integration 377, and heavy presentation 216. The Boss effect budget suite
passes 108 checks. Combat, October source timing, projectile, impact, source hit
stop, root motion, animation and player transfer regressions also pass. The
motion suites cover 30/60/120Hz and unchanged action displacement.
The combat/input/pool/save regression passes 256 checks after rerunning with
permission to write its temporary `user://` saves. Its initial sandboxed save
failure is not counted as a production regression.

Rendered axe-heavy verification shows 15 impacts, 32 effects, five spin contact
frames, and no missing effect resources. Screenshot:
`reports/impact-combat-20261028-heavy-axe-95.png`.
The sword-heavy case also passes with fixed 60 FPS rendering: 27 impacts,
30 effects and no missing resources. Screenshot:
`reports/impact-combat-final-20261028-heavy-sword-55.png`. A first non-fixed
rendered attempt produced zero contacts and was rejected; the headless and
fixed-rate reruns both establish the expected contacts. The first attempt's
cause was not independently isolated, so it is not evidence of visual parity.

## Whole-frame limits

One valid 25-second before/after source-crowd run used Apple M4, Godot 4.7.2,
Compatibility rendering, full effects, 1280x720 window, 1600x900 viewport,
60Hz physics and a 45 FPS cap. Both runs confirm 558 impacts and 56 player casts.
The initial attempt while the window was paused is excluded.

| Metric | Before | After |
| --- | ---: | ---: |
| P95 frame ms | 31.922 | 30.487 |
| P99 frame ms | 39.892 | 39.215 |
| Maximum frame ms | 231.283 | 125.441 |
| Frames above 50ms | 2 | 6 |
| Mean event dispatch ms | 0.07145 | 0.06165 |
| Mean world tick ms | 4.06123 | 4.14060 |

These mixed results do not establish an overall stutter win. First-use rendering
and eight-enemy reinforcement spikes remain. This is one debug desktop sample,
with no thermal controls or exact rendered-workload equivalence; model shake and
render scheduling can alter visible effect overlap. Raw files are
`reports/city-combat-active-before-20261028.json` and
`reports/city-combat-after-20261028.json`.

ADB found only `emulator-5554` (TapTapEmulator), not a physical Android device.
Android/iOS frame pacing, GPU cost and perceptual parity with the original APK
remain unverified. No APK was installed or published by this task.

## Reproduction

From this project directory, use the installed Godot executable:

```sh
Godot --headless --path . --script res://tests/hit_feedback_cache_test.gd -- --benchmark
Godot --headless --path . --script res://tests/effect_pool_pressure_test.gd
Godot --headless --path . --script res://tests/source_model_shake_test.gd
Godot --path . res://scenes/combat_stress.tscn -- --seconds=25 --no-barrage --ignore-focus --fps=45 --profile-cpu --output=/private/tmp/combat-measurement.json
```
