# Combat optimization and attack controls

Implemented on 2026-10-25 against the existing working tree, using Godot
4.7.2, Compatibility rendering and 60 Hz physics. Existing unrelated changes
were retained. Android device acceptance is **not complete**: `adb devices -l`
reported no connected devices.

## Controls

- The small button to the left of the skills cycles 普攻, 重击, 关闭.
- Normal mode automatically attacks; heavy mode only requests heavy attacks.
  Insufficient character resources or cooldowns cause it to wait, without
  falling back to normal attacks. Source heavy-to-normal branches are suppressed
  only for automatic heavy actions; manual heavy behavior is preserved.
- Pressing the normal attack button immediately attacks. Holding for 0.35 seconds
  requests heavy at the next legal action window. The held request survives the
  short tap buffer. Release clears an unexecuted request or releases the charge.
- The normal button displays heavy charging/waiting. There are four visible skill
  buttons, explicitly mapped to slots 0-3; heavy retains internal slot 4 and R.
- Manual actions take priority. Dodge/skills disarm the touch hold; pause, focus
  loss and room changes clear inputs. Switching mode releases automatic held input
  without forcibly cancelling an action that has already started.
- `auto_attack_mode` is `normal`, `heavy` or `off`. Legacy `auto_attack=false`
  migrates to `off`, true/missing migrates to `normal`. A valid new mode takes
  precedence. HUD and settings use the same setter.

## Runtime changes

- Save requests coalesce for 250ms before capturing a consistent main-thread
  snapshot. A single background writer handles serialization, validation and
  disk operations on a detached dictionary. New pending requests replace older
  pending snapshots; active writes finish in order. No scene nodes enter the worker.
- Explicit save, background/exit and settlement checkpoints flush necessary
  writes. Temporary-file validation, backup recovery and failure reporting remain.
  Internal `_save()` now queues work; `_save(true)` waits for persistence.
- Projectile visual/state pools share meshes and materials. Reuse resets source,
  target, lifetime, hit history and all motion state, and releases attached visual
  effects before the same mesh is reused. Only idle retained capacity is capped;
  active gameplay projectiles are not dropped.
- Damage labels use a bounded pool and one update loop instead of per-hit nodes
  and tweens. Existing explosion/effect pools and particle/emitter budgets remain.
- Target selection tests nearer weighted candidates first and passes the chosen
  target into execution. Enemy-distance and monster-index bookkeeping no longer
  repeats a full actor scan for each enemy.
- Actor-key lookups are indexed. Enemy projectiles only test the player; only
  homing projectiles reacquire targets. Environment hit definitions are evaluated
  only when environment interaction is enabled.
- Distant idle perception checks are staggered, with immediate refresh for near
  or attacking enemies, movement invalidation and blocked visibility. Path target
  updates are staggered. Core AI/action clocks and movement remain at physics rate.
- AI type decoding and action collision/interrupt event lists are cached, with
  action caches invalidated on configure/restore. These preserve source behavior.
- Enemy packed scenes and per-group effect discovery are cached with bounds.
  Preloading includes active buffs and reachable summons. Loading now also draws
  feedback materials, skinned flash overlays, digits and generic particles in a
  private viewport before gameplay resumes.
- HUD redraws are limited to changed combat visuals. Death/room cleanup releases
  active labels, projectile state and perception caches.
- Existing capsule collision bodies, layer masks and swept actor-hit tests were
  retained and exercised. No physics frequency reduction, offscreen damage cull
  or replacement of collision shapes that would change gameplay was introduced.
- Expiring projectiles now check their final swept segment before recycling;
  travel is clamped to lifetime/distance to prevent that segment exceeding range.

Budgets are configurable in `feel_settings.gd`: 128 retained projectile instances,
96 damage labels, and diagnostic warnings above 96 actors / 512 projectiles.
Warnings do not discard gameplay objects. Existing particle budgets are 2048/128
particles/emitters for full effects and 768/48 for reduced effects.

## Desktop measurements

The initial fixture uses seed 731, 24 enemies including a boss, timed skills,
heavy requests, pickups, periodic saves and eight reinforcements at 15 seconds.
Each below run lasts 20 simulated seconds, on Apple M4 / macOS 26.3, 1600x900
viewport, full effects. No build or other test workload ran concurrently with the
three prewarm-stage measurements. The initial baseline is one run, not a statistical
device baseline. Attack-input changes also change active effect/projectile counts;
these numbers should not be treated as an equal-workload throughput benchmark.

| Metric | Initial baseline | Prewarm 1 | Prewarm 2 | Prewarm 3 |
| --- | ---: | ---: | ---: | ---: |
| Average FPS | 89.03 | 65.20 | 66.49 | 66.42 |
| 1% Low FPS | 18.05 | 26.52 | 31.58 | 32.91 |
| P95 frame ms | 16.70 | 19.57 | 19.53 | 19.41 |
| P99 frame ms | 24.95 | 29.70 | 26.00 | 23.68 |
| Maximum frame ms | 194.07 | 68.56 | 47.42 | 48.54 |
| Frames above 50ms | 7 | 2 | 0 | 0 |
| Frames above 100ms | 3 | 0 | 0 | 0 |
| Maximum save request ms | 14.43 | 4.22 | 4.03 | 4.18 |

The large first-combat stalls improved. Average FPS did **not** improve, and one
run still had a 68.56ms frame. Do not claim the overall performance target
has been met. Engine-tracked static memory peaks were about 917-919MB,
versus 913MB initially; bounded caches intentionally retain some resources.

Raw reports are under `reports/combat-stress-before-desktop.json` and
`reports/combat-stress-warmed-desktop*.json`. Intermediate experiments are kept
separately. `cold` means the first ten combat seconds **after preparation**;
`startup_preparation_ms` separately measures setup/prewarming. `warm` is the
remainder. Physics/process monitors update periodically and can retain a loading
sample initially; actual frame-time percentiles use the monotonic wall clock.
Memory is Godot static allocation tracking, not Android PSS or total GPU memory.

The built-in script Profiler was run with `--profiling --debug`. It identified
world physics, AI tree traversal/reset, projectile processing and effect advancement
as remaining hot paths. Startup function totals include asynchronous preparation
and should not be interpreted as combat self time. Logs are retained in
`reports/combat-script-profiler.log`.

An independent 512-object MultiMesh prototype reduced draw calls from 512 to 1
and transform-update P95 from 0.122ms to 0.068ms, but frame P95 changed from
13.07ms to 13.90ms. Production batching remains disabled: this opaque prototype
does not establish Android gains or transparent-effect/culling correctness.

The extended barrage fixture reached 206 concurrent shots. A subsequent targeted
projectile-indexing optimization changed its full-quality average FPS from 50.76
to 62.78, P95 from 30.15ms to 25.77ms, P99 from 36.01ms to 31.39ms, and >33ms
frames from 25 to 4. Maximum frame time was still 64.84ms. This is a single
20-second comparison, and P95 still misses the target. The preceding reduced
quality run averaged 50.16 FPS with P95 32.13ms; merely lowering particles did
not address the projectile CPU cost. No pre-project baseline exists for this
expanded fixture. The final lifetime-boundary correctness fix was regression
tested after these measurements and is not represented by a fresh timed run.

## Reproduction and artifacts

Run from the `goDot` directory with the installed Godot executable:

```sh
Godot --path . res://scenes/combat_stress.tscn -- --seconds=600 --output=user://combat-stress.json
Godot --path . res://scenes/combat_stress.tscn -- --seconds=600 --barrage --low-effects --output=user://combat-stress-low.json
Godot --path . --profiling --debug res://scenes/combat_stress.tscn -- --seconds=30 --barrage
Godot --headless --path . --script res://tests/combat_optimization_test.gd
Godot --path . --script res://tests/attack_controls_visual_test.gd
Godot --path . --script res://tests/multimesh_probe.gd
```

The extended `--barrage` fixture adds 96 shots every two seconds, explosions and
knockback. It is a separate workload, with no pre-change baseline; do not compare
it directly to the initial fixture. It also exercises pickup-save coalescing.
Samples stay in memory until the end. Reports include average FPS, worst-1%-mean
FPS, P95/P99, peak frame time, 33/50/100ms counts, memory and entity peaks.

- `builds/android/DungeonChasers-combat-debug.apk`: ordinary playable debug build.
- `builds/android/DungeonChasers-performance-release-test.apk`: release engine
  build, local debug certificate, separate `.performance` package, never a store
  release. Launching it runs the extended ten-minute fixture automatically.
- The performance APK writes `user://combat-stress.json` and prints summary,
  phase and device JSON to logcat under `COMBAT_STRESS*`. Private storage may be
  inaccessible on a non-debuggable release build; capture logcat for summaries.
- `reports/attack-controls-*.png`: actual rendered UI checks at desktop and mobile
  landscape sizes. `reports/attack-controls-demo.mp4` is a UI-state slideshow,
  not a gameplay or Android recording.

## Validation boundaries

Passing local checks include the new 235-case input/pool/save suite, 449 heavy
checks, 567 combat assertions, 340 projectile assertions across 321 definitions,
1097 enemy AI assertions, 3887 monster combat checks, 454 lifecycle assertions,
24 save recovery checks, 2 background/menu-quit save checkpoint checks,
134 readiness checks, 110 joystick assertions,
2112 runtime assertions, 62 game-flow checks and 46 altar/reward-flow checks.
All 39 monsters also passed the 40-second physical-world scenario (155 assertions),
and the Boss effect budget suite passed 78 checks. Input-response tests passed
33 assertions.
Rendered control tests passed at 1600x900 and 844x390. Impact physics regression
covers light/heavy/explosion displacement and wall stopping at 30/60/120Hz.
Both final Android APKs passed APK Signature Scheme v2 verification. The
performance package is separate from the playable package and is not debuggable.
Exports report the existing missing-project-icon warning but complete successfully.

Outstanding acceptance gates:

1. Android editor/debug/release comparison on the same actual target device.
2. Three ten-minute before/after runs with recorded device temperature, power
   state and resolution; stable memory/PSS monitoring and low-end device testing.
3. Android target: 60 FPS, P95 <=20ms, P99 <=33.3ms and at least 50% fewer >50ms
   frames. Desktop improvements do not substitute for this gate.
4. Full transparent rendering/overdraw and GPU capture on the target device;
   MultiMesh adoption remains deferred until it shows an actual benefit.

The current changes retain 60Hz physics and gameplay entity counts. Remaining
reinforcement/first-use spikes and the lower desktop average FPS require device
profiling before claiming a complete end-to-end performance win.
