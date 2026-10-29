# Deer effect update performance, 2026-10-29

`authored_effect.gd` updates emitter speed only when pause or playback speed
changes, resetting the cache for configuration and pooled restarts. Shader
updates and burst scheduling now share one emitter traversal. Finished emitters
avoid redundant `emitting = false` writes. Source particle counts, geometry,
materials and event timing are unchanged.

## CPU measurements

Headless Godot 4.7.2, 26 recovered `jiaolu` effect prefabs, 6,000 update frames.
The fixture includes delayed emissions, pauses, playback-rate changes, stopping,
and pooled restarts. All effects advance together for the benchmark; this is a
script workload, not a claim that all 26 appear together during gameplay.

| Quality | Emitters | Before total ms | After total ms | Before ms/frame | After ms/frame | Reduction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Full | 160 | 922.147 | 840.659 | 0.1537 | 0.1401 | 8.8% |
| Reduced | 146 | 833.271 | 774.808 | 0.1389 | 0.1291 | 7.0% |

These are CPU elapsed times inside `advance` (including any recovered model
animation updates), excluding fixture construction,
state serialization, GPU work and device FPS. Shorter runs varied, so the table
uses the longer 6,000-frame samples. It does not establish an overall combat
frame-rate improvement or remove the need for Android profiling.

Both runs used the same final imported resources (including the recovered deer
spirit model). The reports record matching catalog and effect-descriptor SHA-256
hashes, plus the separate implementation hashes. Other team Godot tests were
paused for these sequential measurements.

The per-frame state hashes match before and after in both quality modes. The
trace checks effect age, visibility, emitter start/stop, speed, next looping
burst, shader clock and retained-particle visibility. Particle positions and
rendered pixels are outside this headless comparison.

Raw measurements:

- `reports/deer-effect-cpu-before.json`
- `reports/deer-effect-cpu-after.json`

Reproduce the new implementation and compare its schedule with the saved trace:

```sh
Godot --headless --path goDot --script res://tests/deer_effect_cpu_benchmark.gd -- --frames=6000 --compare=res://reports/deer-effect-cpu-before.json --output=/private/tmp/deer-effect-cpu.json
```

The benchmark accepts `--implementation=/absolute/path/to/authored_effect.gd`
to measure a prior implementation in the same project.

## Regression coverage

- `authored_effect_test.gd`: 4,154 checks passed across 90 effects, including
  delayed bursts, recurring bursts, shared uniforms and continuous-particle tails.
- `chest_smoke_velocity_test.gd`: 380 checks passed.
- `boss_effect_layer_budget_test.gd`: 658 checks passed across protected boss
  effects and both quality budgets.
