# Deer King skills, 2026-10-29

Target: enemy 33001, `ActGroup_jiaolu`, from `1061664.apk` SHA-256
`ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.

## Evidence

REA `inspect-artifact` regenerated archive identity and inventory:
`ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`
and `ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c`.
The complete local output is `/private/tmp/deer-rea-artifact.json`.

`tools/audit_deer_skill_source.py` separately reads Unity objects from the APK.
Its report, `reports/deer-skill-source-audit.json`, checks 26 actions, 44 source
records, 62 media references, six buffs, 11 summons and 10 damage IDs. These
are static source checks, not observations of APK execution. REA archive
evidence does not establish the contents of individual Unity objects.

The phantom prefab contains one SkinnedMeshRenderer and one Animator. The old
presentation descriptor contained eight particle layers but omitted the skinned
deer. `tools/recover_deer_skill_model.py` restores its mesh, skin, five skeletal
clips, controller default, source root transform, material textures, rim and
dissolve settings, and the 4.333-second material animation. The source renderer
has `m_CastShadows=0`; the runtime now honors that setting instead of casting
opaque shadows beneath translucent phantoms.

Recovery retains 35 unsupported Animator root-motion bindings in the report.
Projectile movement remains owned by the imported combat motion definitions.
No claim of original-engine shader or pixel equivalence is made.

## Runtime

- Deer warnings use the recovered prefabs. The automatic procedural warning
  fallback is disabled for this enemy, as it already was for the wolf.
- Source transforms, playback speeds, full particle lifetimes and explicit
  action-switch destruction flags are retained. In particular, the roar's
  2,233ms conversion effect survives the following action when its source flag
  requests that behavior.
- Phantom projectiles hide the generic projectile mesh and follow each
  projectile's travel direction, including independent directions in a volley.
- Repeated warnings, ice spikes, phantom deer, ice-ball explosions and hit
  effects are instantiated during preparation. Counts are bounded by the
  existing particle/emitter budgets; retained capacity is released on room exit.
- Preparation renders skinned model material variants as well as particle
  variants in the existing offscreen warmup viewport.
- Deer action-event silhouettes have priority over their own simultaneous
  field bursts, so reduced-quality mode does not evict the charge effect in
  the very frame it begins. Hard rendering budgets remain in force.
- The common effect updater caches unchanged playback speed and combines
  emitter traversal with burst scheduling. See `DEER_EFFECT_PERFORMANCE_20261029.md`.

## Verification

`tests/deer_boss_skill_visual_test.gd` enumerates all 14 combat/pose actions,
their buff-gate combinations and an explicit roar/action-switch scenario:
27 cases per quality mode. It checks source effects and summons, missing
anchors, template and instance allocations, hard budgets, skinned model
presence, animation progression, shadow settings and projectile orientation.
Rendered runs additionally compare screenshots with selected effects hidden.

Final full/reduced runs passed all 54 cases with zero in-cast template builds,
zero in-cast instance allocations and no missing effects or anchors. Rendered
acceptance passed at 1280x720 (EX charge), 720x1280 (ice-ball volley), and
960x540 (skinned phantom charge). The boss entity regression passed 35 checks,
wolf source-effect regression 107 checks, and the existing light-spirit sword
regression 101 checks. Runtime descriptor validation matched all 3,970 records.

Reports and images are generated under `reports/deer-boss-*`. The fixtures
disable AI selection and step actual world event/entity/projectile/summon
paths. Their CPU samples are not Android frame-rate measurements. No Android
device profiling or original APK runtime comparison was performed in this task.

```sh
Godot --headless --fixed-fps 600 --path goDot --script res://tests/deer_boss_skill_visual_test.gd -- --quality=full --label=verify
Godot --headless --fixed-fps 600 --path goDot --script res://tests/deer_boss_skill_visual_test.gd -- --quality=low --label=verify
Godot --path goDot --script res://tests/deer_boss_skill_visual_test.gd -- --case=attack3-normal --label=phantom --viewport=1280x720
```
