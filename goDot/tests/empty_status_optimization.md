# Empty Status Substeps

The production change is confined to the status substep block in
`scripts/domain/combat.gd::_tick_segment`. When `delta > 0.000001`, statuses are
empty and condition recursion depth is at most sixteen, it clamps health once.
The original empty substeps only clamp the same health limit and dispatch a
tick notification with no listeners, counters, RNG or emitted events. All
nonempty status updates retain their original 0.01-second substeps and order.
The epsilon and recursion guards preserve zero-delta behavior and diagnostics.
Action-end notifications still run before the branch, and queued actions still
run after it, so newly added or expired buffs retain their original timing.

`fixtures/status_substeps_reference.gd` independently retains the original full
segment interpreter. It was verified to match the production method exactly
apart from the optimized status block. The reference and production paths share
the same native AI, enemy interrupt backend and source catalog.

## Validation

Run from the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --log-file /private/tmp/city-empty-status-test.log --script res://tests/empty_status_optimization_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --log-file /private/tmp/city-empty-status-bench.log --script res://tests/empty_status_benchmark.gd
```

The differential suite passed 92,779 checks over all sixty enemies, 895 enemy
and action combinations and eight characters at mixed 30/60/120Hz. It compares
full snapshots, pending timeline events, AI/RNG state, emitted events, impact
timers, skill energy/cooldowns and JSON restore. Event source references must
point to their own combat instance before normalization to its actor key. The
catalog is checked for mutation.

The reusable boundary fixture has 338 assertions: 324 health/epsilon/recursion
checks plus fourteen death, frozen/impact/stagger, buff-expiry, queued-buff and
action-end-listener state/event checks. It runs in both the suite and benchmark.

Existing regressions passed: enemy AI 1684, monster combat 5988, damage 24,
lifecycle 685, monster skills 40, combat 655, optimization 235, heavy 449, October
timing 4666, source-heavy 248, empty-attribute 60 and interrupt differential 116137.
The optimization suite requires access to its temporary Godot `user://` saves.

## Desktop Benchmark

Godot 4.7.2 stable, macOS. Twenty-four source enemies (one 13001 boss and
twenty-three 11001 wolves); seven alternating samples, 120 warmup ticks and 600
timed 60Hz ticks. Only the outer AI-plus-combat workload is timed; configuration
and snapshot comparisons are outside it. All seven final snapshots match;
345 checks, including 338 boundary checks, passed.

Latest median: 962.130us to 861.647us per roster tick (ratio 0.89556). Raw measured
durations in microseconds for 600 ticks, in sample order:

```json
{
  "baseline": [556367, 602095, 584381, 577278, 551135, 638797, 553221],
  "optimized": [500499, 504030, 538938, 516988, 528782, 588333, 502033]
}
```

An earlier isolated comparison measured 918.873us to 852.483us (-7.23%). The latest
run has visible timing variability; these results support a CPU reduction, not
a precise Android prediction. A separate coarse world-only investigation found
directional 2-5% gains with system-load drift. It is not an equality proof:
repeated baseline physical-world runs themselves produce different final state
digests. Behavioral evidence comes from the stepwise logic suite above.

Machine-readable outputs are generated in `reports/empty-status-optimization.json`
and `reports/empty-status-benchmark.json`; that existing output directory is
ignored by Git. No rendering quality, APK action, animation, damage, cooldown or
active-status update frequency is changed. Android FPS remains for device tests.
