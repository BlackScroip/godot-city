# Optional Native Combat AI

The production `DungeonEnemyAI` loads this C++ behavior-tree interpreter when a
matching library is available. Graph preparation, validation, notifications,
blackboard ownership, snapshot schema and restore remain in the existing script.
The complete original GDScript tick implementation remains the fallback.

No tick rate, authored tree, ability, effect, simulation state or RNG contract is
changed. The native runtime uses integer graph links rather than RefCounted node
cycles. Floating-point contraction and fast-math are disabled.

## Build

Run from the repository root:

```sh
sh native/combat_ai/build.sh --platform android
sh native/combat_ai/build.sh --platform macos
```

The script builds debug and release arm64 libraries. Use `--configuration debug`
or `--configuration release` for one variant. Dependencies and intermediates go
to `/private/tmp/city-native-ai`; use `--work` to choose another temporary path.
`--godot`, `--ndk` and `--jobs` override the local tool paths and parallelism.
`CITY_GODOT_CPP_SOURCE` may point at an existing checkout with the exact pin.

Verified toolchain:

- Godot `4.7.2.stable.official.ed1daf0bf`, single precision; API dumped by this binary.
- Official godot-cpp commit `8070599885b6df675fcad033dd032ce44be2b850`.
- Android NDK `28.2.13676358`, arm64-v8a, API 24, static C++ runtime.
- CMake 4.4.4, Ninja 1.13.2; Apple clang 17 for the macOS arm64 validation libraries.
- Dumped extension API SHA-256: `d0e4c08c03b165156dabe6bfb6a906baf0069189f62035341230a246c86d6986`.

Checked Android binaries:

| Variant | SHA-256 |
| --- | --- |
| Debug | `8210e954ba229f280c0d4a53188f0f37154c9c2a331d5efa83faccbc5f8c8aea` |
| Release | `0ee14673b1f8ba9ac097347adf86383d295f19be1cd638b8639c13f65ce35fc2` |

Both are ELF64 AArch64 shared libraries. The release library is approximately
566 KiB; its LOAD segments have 16 KiB alignment. Their only ELF NEEDED entries
are Android's `libc.so`, `libm.so` and `libdl.so`; no `libc++_shared.so` is required.

## Loading And Export

The descriptor is `goDot/addons/combat_ai/runtime/combat_ai.cfg`. Godot 4.7.2
successfully loads this descriptor through `GDExtensionManager.load_extension`.
The `.cfg` suffix intentionally avoids automatic GDExtension discovery and
startup attempts on unsupported platforms.

The enabled `combat_ai` export plugin explicitly adds the matching native
library, descriptor and godot-cpp MIT notice to supported exports. It omits
native runtime files on other platforms or when the matching library is absent.
Only Android arm64 and macOS arm64 are enabled. iOS, Web and other architectures
use the original script. A missing library in the source checkout is checked
before the loader is called. Restart the process after adding/rebuilding a
library because loading is attempted once per process.

`DungeonEnemyAI.backend_name()` returns `native` or `gdscript`; device stress
records should verify this before attributing device timings to native AI.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot \
  --log-file /private/tmp/city-native-production-ai.log \
  --script "$PWD/native/combat_ai/tools/native_ai_probe.gd"
```

The runner uses the actual production class and its normal optional loader. The
reference subclass only overrides `_native_runtime_allowed()` to keep the
original interpreter. Machine-readable results are in
`reports/native-ai-probe.json`.

2026-10-26 validation: 47 graphs, 149,043 checks, zero failures. This includes all
42 shipped source graphs plus shared-child DAG, cycle, missing root, dangling
connection and literal-binding/reconfiguration fixtures. Per graph, 600 traced
and 180 untraced frames compare complete outputs, trace/visited order,
blackboards, node states, clocks, RNG, diagnostics, action notifications,
blackboard overrides, invalid deltas and JSON/frequent restores. Literal
parameter identity is also checked.

The missing-library runner `tools/native_ai_fallback.gd` was executed in an
isolated project containing the production descriptor but no native libraries.
It loaded all 42 graphs and passed 5,130 checks without extension-loading errors.
It also checked the iOS/Web/non-arm64 platform guard. This is a guarded fallback
test, not an iOS device or export test.

Existing production suites passed with the native backend enabled:

| Suite | Checks | Failures |
| --- | ---: | ---: |
| enemy_ai_test | 1,684 | 0 |
| enemy_ai_precompile_test, against raw GDScript reference | 60,653 | 0 |
| monster_combat_test | 5,988 | 0 |
| combat_test | 655 | 0 |
| combat_optimization_test | 235 | 0 |

`combat_test` retains five existing source-gap diagnostics. The native work does
not resolve or suppress those diagnostics.

Desktop headless benchmark: one warm-up and six measured samples per backend,
alternating order, 360 ticks per sample, tracing disabled:

| Roster | Script us/tick | Native us/tick | Native/script |
| --- | ---: | ---: | ---: |
| 23 wolves and source boss 13001 | 826.06 | 405.86 | 0.4913 |
| One AI for each of all 42 source graphs | 1,966.98 | 963.95 | 0.4901 |

These measurements show about 51% less isolated desktop AI CPU time. They are
not Android timings, rendered-frame measurements or evidence of 60 FPS. Device
backend activation, full-scene CPU/render cost and frame pacing must be measured
in the exported Android application.
