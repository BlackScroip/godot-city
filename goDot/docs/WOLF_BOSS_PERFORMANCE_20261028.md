# Wolf combat performance, 2026-10-28

The wolf's dense effects now prepare concurrent particle instances during room
preparation. Preparation uses the existing per-step time budget. The bounded
inactive pool can retain 119 instances instead of 72 for wolf encounters; active
effect, emitter and particle budgets are unchanged. Read-only projectile and hit
updates reuse parsed source definitions; mutable callers still receive deep copies.

APK effect assets, requested emissions, damage and action timing are preserved.

## CPU burst measurements

Headless Godot, full quality, first burst after preparation:

| Effect | Requested | Before (ms) | After (ms) | Runtime clones before / after |
| --- | ---: | ---: | ---: | ---: |
| Roar fireball | 50 | 20.094 | 2.301 | 31 / 0 |
| Fireball explosion | 8 | 8.514 | 0.585 | 7 / 0 |
| Roar eruption | 4 | 7.027 | 0.350 | 4 / 0 |
| Flying slash | 4 | 2.907 | 0.231 | 3 / 0 |

Reduced-quality fireballs: 7.828 ms to 1.591 ms. All eight full/reduced
burst cases emitted the requested effects without runtime instance construction.
These measurements cover CPU allocation cost, not GPU time or device FPS.
The tradeoff is additional bounded cached instances and room preparation work.

## Verification

- `wolf_skill_execution_test.gd`: 86 checks passed.
- `wolf_boss_apk_effects_test.gd`: 61 checks passed.
- `boss_skill_entities_test.gd`: 35 checks passed.
- `combat_performance_test.gd`: passed across the tested bosses and both qualities.
- Rendered `roar-gated` at 960x540 full quality: passed, 16 captured frames;
  effect-hidden comparisons detect source effects on screen.
- All 24 wolf scenario traces match before/after for action transitions, effect
  records/counts, events, impacts, peak populations and missing effects.
- The full visual suite remains 22/24: existing forward rectangle warning failures
  in `attack2-normal` and `attack3-gated` are unchanged and remain unresolved.

Raw measurements: `reports/wolf-combat-performance-{before,after}.json`.
Scenario comparison: `reports/wolf-boss-performance-{before,after}-960x540-full.json`.
