# Dungeon Chasers Godot

Independent offline GDScript migration. Engine pinned to **Godot 4.7.2.stable.official.ed1daf0bf**. This is a working migration checkpoint; the full original-game parity and three-device acceptance gates are still open. See [MIGRATION_STATUS.md](MIGRATION_STATUS.md).

## Run

Open `project.godot` in the pinned Godot editor and press Run, or run:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/hanyu/U3D/City/goDot
```

WASD/arrows move, Shift dodges, Space uses the skill, Q uses burst, R holds/releases heavy attack, E interacts, Escape opens settings. Touch uses an independent joystick and four skill buttons; hold normal attack for 0.35 seconds to enter heavy attack. The small left button cycles automatic normal, automatic heavy and off; heavy waits when resources are insufficient. Settings share the same three modes and include volume and keyboard rebinding.

Combat now coalesces background saves, pools projectiles and damage labels, caches repeated AI/media work, and prewarms hit feedback rendering. See [implementation and measured limits](docs/COMBAT_OPTIMIZATION.md) for desktop before/after results, regression checks, stress commands and Android acceptance still pending a connected device.

Touch/combat tuning is centralized in `assets/feel_settings.tres`: radial deadzone, acceleration/braking, 150 ms input buffer, dodge distance/curve and presentation budgets. Settings also expose camera shake and reduced effects. Original APK action events drive restored skill effects, audio and per-hit feedback; see [the implementation and acceptance report](reports/FEEL_IMPLEMENTATION.md) for reconstruction limits.

Combat contacts now share a settled `impact_confirmed` event, local action clocks, category-based feedback and collision-aware knockback. Author overrides live in `scripts/feel_settings.gd`, separately from converted source data. The skill renderer restores recovered particle curves, flipbooks, directional emission and transparent attack silhouettes. See [combat feel delivery](reports/IMPACT_IMPLEMENTATION.md), [before/after video](reports/impact-comparison.mp4) and [APK-guided VFX notes](reports/SKILL_VFX_TUNING.md). Device acceptance and original-runtime visual matching remain open.

Boss and character effects now prepare during room loading, share reusable templates across rooms, and obey global particle/emitter budgets. Attack warnings share their shader. See [combat performance fix and validation](reports/COMBAT_PERFORMANCE_FIX.md) for the stress measurements, graphical boss checks and remaining device validation.

Start from the camp, select a character/weapon, enter an adventure, clear waves, choose loot and continue along the route. Camp menus expose permanent progression and achievements. This project starts a new versioned JSON profile under Godot `user://`; it does not import APK/Unity saves. Temporary validated writes and a backup protect the previous profile.

New adventures enter the first room automatically. During a room, the top-right controls are Difficulty, Character and Settings. Difficulty shows the current adventure without allowing a mid-run change. M opens a read-only chapter map; gates open the actual next-room selection. Death consumes an available revival automatically, otherwise opens settlement. Settlement converts experience to adventure vouchers once before returning to camp. See [APK flow evidence and implementation](reports/GAME_FLOW_IMPLEMENTATION.md).

Dodge starts with two uses. The button shows remaining stock and recharge progress; a remaining use is available during recharge. The APK's last-use delay defaults to one second, then replenishes one use per update until full. This version grants one extra use by default; the source package provides that bonus through progression. See [source evidence and scope](reports/APK_DODGE_CHARGES.md).

Camp ambience binds to the recovered scene's active effect anchors: the spawn circle has cyan runes, flowing light and rising motes; campfires have flames, embers, smoke and local light; leaves, fireflies, steam and waterfall mist run continuously nearby. These are Godot reconstructions using recovered textures. Menu pause and backgrounding freeze them, reduced effects lowers their particle counts and disables local lights, and scene reloads release their owner. The five top-right controls use the original white artwork and reference proportions. The cloud artwork button saves locally in this offline version.

## Conversion And Build

```sh
python3 goDot/tools/convert_unity.py --help
python3 goDot/tools/fetch_templates.py
python3 goDot/tools/build.py all
```

Run these from `/Users/hanyu/U3D/City`. Conversion inputs stay in the existing recovered Unity project. The converter preserves source IDs, bones, skins and animation names and writes collider/semantic sidecars. Geometry uses numeric Unity xyz consistently; do not apply another axis reflection. UV conversion already flips V. OBJ is a repair/interchange format; runtime assets use GLB.

`fetch_templates.py` verifies ranged downloads from the pinned official template ZIP and resumes cached blocks. Android uses the local debug keystore. iOS produces an unsigned arm64 Xcode project with an empty team ID; signing and device installation remain separate. No store submission is included.

## Validation

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/runtime_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/combat_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/campaign_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/systems_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/projectile_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/world_interactions_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/feel_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/feel_physics_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/impact_feedback_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/impact_physics_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/impact_throughput_test.gd -- --baseline=res://reports/impact-throughput-before.json
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/hanyu/U3D/City/goDot --script res://tests/authored_effect_test.gd -- --render-check --all-effects
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/hanyu/U3D/City/goDot --script res://tests/impact_visual_test.gd --fixed-fps 60 -- --label=after
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/hanyu/U3D/City/goDot --script res://tests/feel_visual_test.gd --fixed-fps 60
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/hanyu/U3D/City/goDot --script res://tests/camp_presentation_test.gd --fixed-fps 60
```

Tests write their profiles and reports under `reports/`. A graphical scripted smoke run supports `-- --smoke --capture /absolute/image.png --smoke-output /absolute/reports`. Exported packages require an absolute writable smoke output directory. Reports distinguish config/domain checks, graphical observations and device acceptance.

## Layout

- `scripts/domain/`: independent config, profile, progression, effects, achievements, campaign, combat, dialogue and projectile logic.
- `scripts/`: Godot actors, world physics/navigation, environment interactions, UI, input and atomic saving.
- `assets/`: original converted assets, source data, collision and interaction rules.
- `tools/`: repeatable asset/data conversion and platform packaging.
- `reports/`: test results, per-ID ledgers, runtime logs and evidence limitations.
- `builds/`: generated macOS application, Android debug APK and unsigned iOS project.
