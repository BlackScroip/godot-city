# Dungeon Chasers Godot

Independent offline GDScript migration. Engine pinned to **Godot 4.7.2.stable.official.ed1daf0bf**. This is a working migration checkpoint; the full original-game parity and three-device acceptance gates are still open. See [MIGRATION_STATUS.md](MIGRATION_STATUS.md).

## Run

Open `project.godot` in the pinned Godot editor and press Run, or run:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/hanyu/U3D/City/goDot
```

WASD/arrows move, Shift dodges, Space uses the skill, Q uses burst, R holds/releases heavy attack, E interacts, Escape opens settings. Touch uses an independent joystick and five skill buttons. Settings include volume, automatic attacks and keyboard rebinding.

Touch/combat tuning is centralized in `assets/feel_settings.tres`: radial deadzone, acceleration/braking, 150 ms input buffer, dodge distance/curve and presentation budgets. Settings also expose camera shake and reduced effects. Original APK action events drive restored skill effects, audio and per-hit feedback; see [the implementation and acceptance report](reports/FEEL_IMPLEMENTATION.md) for reconstruction limits.

Combat contacts now share a settled `impact_confirmed` event, local action clocks, category-based feedback and collision-aware knockback. Author overrides live in `scripts/feel_settings.gd`, separately from converted source data. The skill renderer restores recovered particle curves, flipbooks, directional emission and transparent attack silhouettes. See [combat feel delivery](reports/IMPACT_IMPLEMENTATION.md), [before/after video](reports/impact-comparison.mp4) and [APK-guided VFX notes](reports/SKILL_VFX_TUNING.md). Device acceptance and original-runtime visual matching remain open.

Start from the camp, select a character/weapon, enter an adventure, clear waves, choose loot and continue along the route. Camp menus expose permanent progression and achievements. This project starts a new versioned JSON profile under Godot `user://`; it does not import APK/Unity saves. Temporary validated writes and a backup protect the previous profile.

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
