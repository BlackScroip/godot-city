# Monster Knockback

Implementation and verification date: 2026-10-28.

The previous monster path selected `hit_1` / `hit_2` but never moved the actor.
`EnemyHitReaction` now retains the source force and timers; `DungeonActor` adds
the resulting displacement to authored movement before `move_and_slide()`.
Visual impact settings do not disable this gameplay movement.

## Source Identity

- Artifact: `1061664.apk` in the repository root.
- APK SHA-256: `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
- ARM64 library SHA-256: `86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944`.
- REA inventory: `ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c`.
- REA artifact inspection: `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.

`reports/monster-knockback-apk-rea-evidence-20261028.json` retains the archive
evidence. `reports/monster-knockback-native-20261028.json` retains native method
bytes, disassembly, metadata identities, constants, and the finding ledger.
`reports/monster-knockback-clock-boundaries-20261028.json` adds the native
action-clock and speed-event boundaries, with a statically derived frame trace.
The extractor verifies the selected APK members and revalidates all 60 methods
in `hit-feedback-native-static.json` and `monster-hit-rules-native-static.json`.
Metadata method stubs identify ranges; executable behavior comes from ARM64
instructions and packaged action data.

## Recovered Rules

| Question | Result | Evidence |
| --- | --- | --- |
| When does a monster move? | Accepted `EHT_HitAction` feedback must break tenacity or reach an already weak monster. Authored action stability still applies. | `HitAction.OnHitFeedback`, existing monster hit-rule report |
| Is an attacking monster always immune? | No. Wolf 11001 has threshold 100 in idle/run and 150 during attack because `StableValue=50`. | `monster_hit_rules.json`, authored interrupts |
| What selects direction? | Modes 0/1/2/3 select attacker forward, attacker-to-target, stored hit direction, and stored hit-point-to-target. Modes 2/3 fall back only for a near-zero stored 3D vector. | `HitAction.OnHitFeedback`, VA `0x2fec5ac` |
| What produces hit geometry? | Frame entities retain their start position; physical entities use their current position and forward direction. | `FrameEntity.SetHitPointPosAndDir`, VA `0x2fe3458`; `PhysicalEntity.SetHitPointPosAndDir`, VA `0x2fe96cc` |
| What controls displacement? | Signed force, current weight, and pre-decrement remaining time; the source uses explicit Euler sampling. | `ActionStatus.SetHitAndUpMove`, VA `0x2fd5c00`; `ProcessHitAndUpMove`, VA `0x2fd62e4` |
| What survives action changes? | Force and timers survive ordinary action starts and resets. Death clears the reconstruction's pending force. | `ActionStatus.Reset`, `OnActionStart`, `ResetForce`; local lifecycle tests |

Effective signed force is `sign(power) * max(abs(power) - resistance, 0)`.
Weight includes the current action's `WeightAddValue`; zero weight becomes 100.
The implementation preserves single-precision intermediate results at the
source arithmetic steps.

For `r = abs(force) / weight`, a low reaction starts when `r >= float32(0.1)`:

```text
duration = (log2(1 + r) + 1) * float32(0.1)
velocity = 2 * (force / current_weight) * remaining / duration^2
displacement = velocity * effective_delta
remaining -= effective_delta
```

Velocity is sampled before decrementing the timer, including a final step that
overshoots zero. Remaining time at or below `float32(0.05)` resets the movement.
Consequently, different tick rates can yield different total travel. There is
no replacement fixed-distance easing curve.

Every admitted weak hit replaces the force. A hit below the start threshold
retains an existing timer. `UpperPower >= weight` clears horizontal timers and
requests the authored high reaction; this branch adds no synthetic vertical
impulse. Facing uses the negative normalized direction regardless of force sign.

For target center `C`, entity origin `E`, and target radius `R`, the stored hit
point is `C + flat(normalize3D(E - C)) * R * float32(0.9)`. Frame hit direction is
`C - E`; physical hit direction is current projectile forward. Continuous frame
contacts preserve `E` even when the attacker moves.

## Integration

- `scripts/domain/enemy_hit_reaction.gd`: admission, directions, force, timers,
  pending facing, motion clock, and JSON state restoration.
- `scripts/domain/combat.gd`: captures the movement step from the unpaused
  combat clock before advancing ordinary action motion.
- `scripts/actor.gd`: consumes facing and displacement, combines action motion,
  applies battle scale through the existing collision movement, clears on death.
- `scripts/world.gd`: constructs target-specific frame/projectile geometry and
  keeps generic presentation knockback from adding a second force to monsters.

The motion clock retains independent integer milliseconds for each action.
It quantizes using the previous speed scale, clips at the action end, enters
due speed events, and ages every active event by the whole current step.
An event exits only after its elapsed time exceeds its duration; exits reset
the rate to one. Movement divides by the resulting scale. Owner pause and
battle scale affect motion. JSON snapshots retain this clock, active events,
force, and timers; the cached per-tick step is rebuilt after restoration.

Player movement remains outside the monster force path. The equipped default
swordsman prefab retains a source placement offset of -0.985 metres on X;
`DungeonActor._align_player_prefab_origin()` removes horizontal placement on
the player prefab before attaching it. This keeps the visible model centred
on its body when turning, while preserving animated height and authored motion.

## Verification

`tests/enemy_knockback_test.gd` covers idle/run/attack admission, protection,
all four direction modes, signed force and resistance, current action weight,
weak-hit replacement, timer cutoff, local clocks, JSON restoration, real frame
and projectile contacts, additive action movement, battle scale, freeze, death,
and physical wall collision at 30/60/120 Hz.

For force 50 and weight 100, the tested Godot world travels approximately
0.572727 / 0.492634 / 0.474804 units at 30 / 60 / 120 Hz. A wall placed 0.2 units
beyond the actor collider stops travel at approximately 0.19906 units.

Run the focused test from the project directory:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/enemy_knockback_test.gd
```

Related regression scripts are `enemy_hit_reaction_test`,
`source_heavy_world_test`, `source_hit_stop_test`, `attack_motion_test`,
`enemy_interrupt_precompile_test`, `monster_lifecycle_test`,
`impact_feedback_test`, and `projectile_test`. Their JSON reports retain the
assertion counts and failures.

## Verification Boundary

The rules above are static APK observations and tests of the Godot
reconstruction. No original APK playthrough or frame-by-frame runtime
comparison was performed. Godot retains its existing collider dimensions and
collision solver; Unity collision results are not claimed bit-identical.
The existing action engine uses a floating-point cursor, so quantizing the
knockback clock does not make the entire action engine match native integer
timing. Tests explicitly distinguish native force arithmetic from the local
world and collision integration.
Speed-event conditions currently run before the ordinary combat payloads in
the same segment. Same-frame condition/buff ordering and action transitions
therefore remain part of the existing floating-point action engine boundary.
