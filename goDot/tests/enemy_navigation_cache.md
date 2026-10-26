# Enemy Navigation Window Cache

Date: 2026-10-26. Godot 4.7.2 stable.

`enemy_navigation_requested()` previously scanned the full authored event list
on every enemy tick. It now retains only the active immutable definition's
enabled navigation start/end pairs in a `PackedFloat64Array`, plus the action
name fallback. It still reads health, enemy availability, action time, feel
speed and current action/definition identity on every call. Direct assignments
to `current_action` work. Changing the definition dictionary invalidates the
cache; configure/reset clears it. In-place mutation of cached catalog records
is outside the existing immutable-catalog contract.

The original method is retained independently in
`fixtures/navigation_reference.gd`. `enemy_navigation_cache_test.gd` compares
production against it. Coverage includes all 60 source enemies, 895 enemy/action
pairs, 51 enabled navigation windows, exact start/end and epsilon probes,
negative/zero durations, float64 precision cases, name fallbacks, speed and
health changes, empty enemies, definition replacement/removal/reintroduction,
enemy/player reconfiguration, mixed 30/60/120Hz AI/combat, JSON restoration,
full snapshots and emitted events. NaN/infinite query inputs are compared as
booleans; snapshot equality is checked after returning to a finite elapsed time.

Run from the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --log-file /private/tmp/city-navigation-cache-test.log --script res://tests/enemy_navigation_cache_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path goDot --log-file /private/tmp/city-navigation-cache-benchmark.log --script res://tests/enemy_navigation_cache_benchmark.gd
```

Reports: `reports/enemy-navigation-cache.json` and
`reports/enemy-navigation-cache-benchmark.json`. The latest differential rerun
passed 114,298 checks at 2026-10-26T06:51:03Z with stable production source SHA256
`28117fe47e49167cf23b89a88c8413191c9a31986f172ab6729f2bfe5c2e0ff5`.
Both reports retain UTC execution time and the combat source SHA256 before/after
the run. Reference and production share the current base class, including
concurrent workspace skill/charge changes; the reference overrides only navigation.

Production passed 114,298 checks at 2026-10-26T06:40:36Z. The benchmark started
at 2026-10-26T06:45:08Z, after other Godot tests ended. Both runs retained the
same combat SHA256 before/after:
`c075f4d790b0f304dacb42e750394ab74f247161af8e466976f8f081b2036ee5`.
Seven alternating-order desktop samples produced these medians, with
configure/catalog loading outside the measured scopes:

| CPU scope | Reference | Cached | Ratio |
| --- | ---: | ---: | ---: |
| Warm idle navigation, 24-actor roster | 50.065 us | 15.011 us | 0.300 |
| First query across 895 actions, per action | 7.781 us | 7.835 us | 1.007 |
| Authored AI + navigation + combat, 24 actors/tick | 885.543 us | 834.438 us | 0.942 |

Every benchmark sample retained equal final snapshots and query checksums.
First-action compilation adds a small cold cost. A separate instrumented
reference run measured 14,400 calls, 60.052 us per roster tick and 6.76% of its
combined scope inside navigation; nested clocks/dispatch affect this diagnostic
and it is not a precise uninstrumented share.

These are desktop headless CPU measurements. The combined scope excludes world
movement, collision, animation, presentation and rendering. Its 5.8% reduction
does not establish Android FPS, sustained 60 FPS or the cause of the observed
source-crowd slowdown. An earlier isolated prototype measured a 4.7% combined
reduction, indicating normal timing variability. The reports retain raw samples
for reproducibility.
