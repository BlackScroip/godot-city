# Migration Status

Checkpoint: 2026-10-23. The user requested an early close-out. **The complete migration plan is not finished.** Original resources remain preserved outside this independent Godot project.

## Implemented And Checked

- Pure GDScript camp/adventure loop: route selection, physical movement, navigation, attacks/dodge/skills, enemy waves, loot selection, settlement, growth and new-profile persistence.
- 198 original GLB assets: 7 characters, 39 enemies, 35 weapons, 117 environments. Structural reports include skins, animations, textures and collider markers. Structural validity does not establish visual parity.
- Original data for 358 loot items, 356 enabled nodes, 11 difficulties, 62 achievement groups, 241 tasks and 630 unlock conditions.
- Achievement-domain replay exercises all 241 tasks/62 groups, preconditions, claim guards and JSON reload through public operations. This does not prove all tasks are attainable in the current live game.
- Offline progression, local shop prices/rewards, NPC dialogue, event/shop/reward interfaces, volume, auto-attack setting, keyboard remapping and independent touch pointers.
- Physical projectile motion, tracking, wall intersection/reflection, target hit budgets and persisted transient state. Summon pickups, static ranges and child summons have world adapters; broad original-prefab/behavior validation remains open.
- Source-bound environment interaction component handles configured doors, treasure, NPCs, destructible objects and trap Buffs, with persisted per-object state and explicit missing-rule diagnostics.
- macOS OpenGL runtime launched successfully on Apple M4. Actual frame capture exposed cutout material and lighting issues; fixes are being revalidated during this checkpoint.
- Unsigned iOS Xcode project and arm64 native Debug compilation pass. Team ID stays empty. No iPhone installation or runtime acceptance has been performed.

## Evidence And Tests

| Area | Report | Meaning |
| --- | --- | --- |
| Assets | `reports/assets-validation.json` | GLB structural coverage |
| Systems | `reports/systems-tests.json` | Domain operations and achievement replays |
| Combat | `reports/combat_test.json` | Focused combat/Buff/phase assertions |
| Campaign | `reports/campaign_test.json` | Route/wave/settlement simulations |
| Runtime | `reports/runtime-tests.json` | Camp, menus, saving, dialogue, run integration, touch events |
| Projectiles | `reports/projectile-tests.json` | 321 original physical definitions plus motion/collision checks |
| Environment | `reports/world_interactions_test.json` | Interaction state tests; see report scope |
| Builds | `reports/builds.json`, `reports/ios-unsigned.json` | Export/compiler status, device verification separately |
| Native evidence | `../Recovery/Reports/godot-native-mapping/achievement-native-ledger.json` | ARM64 static observations and unresolved dispatch semantics |

The four ID ledgers are `reports/assets-conversion.json`, `reports/systems-ledger.json`, `reports/effects-ledger.json` and `reports/achievements-ledger.json`. Detailed enemy/Buff coverage is in `combat_enemy_coverage.json` and `combat_effect_coverage.json`.

## Known Differences And Open Gates

1. Full effects parity remains open. The latest domain audit lists 38 abilities with known semantic gaps and 622 Buff rows needing review/adaptation. The behavioral audit separately lists partial rules, missing world validations and untested Buffs; these counts measure different things and must not be added as a completion percentage.
2. Enemy attack selection, navigation scheduling, seven Boss phase schedulers, some missing elite waves, tracking sensitivity, trajectory interpolation, push-unit scale and rest healing contain documented reconstructions. Serialized AI/config evidence does not establish native runtime equivalence.
3. Unity Shader/particle/Animator behavior, all animation events/property curves, morph curves, every attachment and all 117 environments still need visual/playthrough acceptance. Original effect prefabs are not comprehensively rebuilt.
4. Some environment marker types and UI messages remain diagnosed as unsupported. Portal destinations and all original scripted sequences are not fully restored. Missing campaign data such as island content remains a separate recovery gate.
5. Bounty/chaos content and some permanent-progression branches are incomplete. Partner fusion rules exist in the domain, but all fusion UI success/failure paths and dispatch acceleration rules are not fully verified. Two legacy service currencies still lack natural offline sources.
6. APK native progress dispatch and damage/growth algorithms are not fully decompiled. Cpp2IL declarations are metadata/address carriers, not original method implementations. 119 selected achievement methods have complete linear ARM64 disassembly; that does not prove every control-flow path or callback target.
7. Android/iOS physical touch, safe areas, background transitions, thermal performance and stable 30/60 FPS on target devices remain unverified. The macOS smoke is one scripted room, not a full-run/performance acceptance. No operation recording or complete per-character clear is delivered yet.
8. Android/iOS shipping icons, signing/distribution review and all store submissions remain outside this checkpoint. The debug package and unsigned project must not be represented as production releases.

The project can be continued from the existing per-ID ledgers without repeating extraction. Mark a feature complete only after behavior-level assertions and the relevant runtime/device evidence pass.
