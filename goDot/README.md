# Dungeon Chasers Godot

Independent offline GDScript migration. Engine pinned to **Godot 4.7.2.stable.official.ed1daf0bf**. This is a working migration checkpoint; the full original-game parity and three-device acceptance gates are still open. See [MIGRATION_STATUS.md](MIGRATION_STATUS.md).

The 2026-10-27 camp update adds independent bounties, per-character token sockets and presets, five-copy amplifier composition, immediate golden-apple credit, relationship dialogue, visitors and adventure history. See [the camp implementation matrix, tests and screenshots](reports/CAMP_COMPLETION_20261027.md). Original APK runtime comparison and Unity RNG sequence equivalence remain unverified.

## Run

Open `project.godot` in the pinned Godot editor and press Run, or run:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/hanyu/U3D/City/goDot
```

WASD/arrows move, Shift dodges, Space uses the skill, Q uses burst, R holds/releases heavy attack, E interacts, Escape opens settings. Touch uses an independent joystick and four skill buttons: a short attack release requests normal attack; holding for 0.3 seconds repeatedly requests heavy attack. Active skill one has its own delayed hold flag. Skill images contract inside stable frames, and the more spacious cluster respects mobile safe edges. Clicking the small left button cycles automatic normal, automatic heavy and off; heavy waits when resources are insufficient. See [APK evidence, behavior and verification](docs/SKILL_CONTROLS.md). Settings share the same three modes and include volume and keyboard rebinding.

Combat now coalesces background saves, pools projectiles and damage labels, caches repeated AI/media work, and prewarms hit feedback rendering. See [implementation and measured limits](docs/COMBAT_OPTIMIZATION.md) for desktop before/after results, regression checks, stress commands and Android acceptance still pending a connected device.

Touch/combat tuning is centralized in `assets/feel_settings.tres`: radial deadzone, acceleration/braking, 150 ms input buffer, dodge distance/curve and presentation budgets. Settings also expose camera shake and reduced effects. Original APK action events drive restored skill effects, audio and per-hit feedback; see [the implementation and acceptance report](reports/FEEL_IMPLEMENTATION.md) for reconstruction limits.

Combat contacts now share a settled `impact_confirmed` event, local action clocks, category-based feedback and collision-aware knockback. Author overrides live in `scripts/feel_settings.gd`, separately from converted source data. The skill renderer restores recovered particle curves, flipbooks, directional emission and transparent attack silhouettes. See [combat feel delivery](reports/IMPACT_IMPLEMENTATION.md), [before/after video](reports/impact-comparison.mp4) and [APK-guided VFX notes](reports/SKILL_VFX_TUNING.md). Device acceptance and original-runtime visual matching remain open.

Boss and character effects now prepare during room loading, share reusable templates across rooms, and obey global particle/emitter budgets. Attack warnings share their shader. See [combat performance fix and validation](reports/COMBAT_PERFORMANCE_FIX.md) for the stress measurements, graphical boss checks and remaining device validation.

Start from the camp, select a character/weapon, enter an adventure, clear waves, choose loot and continue along the route. Camp menus expose permanent progression and achievements. This project starts a new versioned JSON profile under Godot `user://`; it does not import APK/Unity saves. Temporary validated writes and a backup protect the previous profile.

The camp portal and adventure button open preparation with character, weapon, difficulty and reward information. Confirming opens the world region map; selecting a region enters its entrance room. Completing a region returns to the world map for the next module. Island and lava require difficulty 10; closed unknown regions stay unavailable. During a room, Difficulty shows the current adventure without allowing a mid-run change. M opens the chapter map; gates open the next selection. Death consumes an available revival automatically, otherwise opens settlement. Settlement converts experience to adventure vouchers once before returning to camp. See [new APK map evidence](reports/APK_WORLD_MAP_NATIVE.md), [difficulty rules](reports/APK_ADVENTURE_DIFFICULTY.md), and [trial rules](reports/APK_CHEST_TRIAL.md).

The completed portal/map/drop integration against `1061664.apk`, its verification results, screenshots and remaining source gaps are collected in [the adventure implementation report](reports/NEW_APK_ADVENTURE_IMPLEMENTATION.md).

The room merchant now supports purchases, dynamic prices, refresh, investment and sealing. Ground pickups use 439 recovered item/material sprites and a dismissible description. Gold and shop orbs split, scatter with two jumps, then accelerate toward the player and collect automatically, preserving values and flight state across saves. The source exit indicator and vertical ultimate SP fill are connected, with JP kept separate and skill resources preserved across rooms and saves. See [the four-feature implementation and verification report](reports/LEVEL_FEATURES_IMPLEMENTATION_20261026.md) for source evidence, desktop/phone captures and Android acceptance limits.

Monster interruption follows the APK's per-monster tenacity, current-action stability and authored hit-action gates. Monster drops use the APK's Normal/Elite/Boss low-pool rolls and independent resource branches, including reward slime messages. Chest probabilities, room qualities and bonus rewards follow the byte-verified source branches. See [the drop-rate audit](reports/APK_DROP_RATE_AUDIT_20261027.md) for corrections, verification and remaining challenge/account-specific gaps, and [the monster rules correction](reports/MONSTER_RULES_CORRECTION_20261026.md) for interruption and motion findings.

Boss, ordinary and elite health displays now use recovered `1061664.apk` artwork, source per-frame trailing fills, separate armor/shield bindings and active Boss HP-lock animations. See [health display evidence and verification](docs/ENEMY_HEALTH_DISPLAY.md) for the implementation, reproducible tests and runtime comparison limits.

Boss entrances now execute their authored gameplay actions, including phase HP locks. Shared HP settlement covers damage, healing, DOT and HP costs; finite locks preserve remaining uses and deferred triggers through saves. Dragon recovery and lava-dragon shield decay follow the recovered configurations. See [Boss skills and HP lock implementation](reports/BOSS_SKILLS_HEALTH_LOCK_IMPLEMENTATION_20261026.md) for native evidence, verified phase chains, rendered skill checks and source gaps.

Boss entrance cutscenes now use the current APK's embedded Show banner, recovered animation curves, sprites, matching font and audio. Player controls lock while the real Boss action continues; the saved skip toggle selects 3x speed, and the banner completes its independent tail after controls return. See [Boss entrance implementation and validation](reports/BOSS_INTRO_IMPLEMENTATION_20261027.md) for exact timing, desktop/mobile captures, test results and the unpackaged tiger-model limit.

The current-APK Boss and spirit pass refreshes all 208 Boss actions and 33 spirit abilities, with delayed/persistent attack entities, complete summon dispatch, source modifiers and recovered effect lifecycles. See [Boss and spirit implementation and verification](reports/BOSS_SPIRIT_IMPLEMENTATION_20261027.md) for the current data, test ledgers, rendered captures and explicit missing-source limits; this supersedes older combat values quoted in earlier reports.

Combat rooms wait for the authored entry trigger before closing arena barriers and spawning enemies. Enemies arrive 0.2 seconds apart; waves have a 2-second minimum guard and a 1-second gap. Final clearance releases barriers/rewards and unlocks the exit in separate timed stages. Protection rooms additionally require activating the placed target. Shop, rest and event activities are optional; curse rooms require a successful reward choice. These phases survive saves and pause with gameplay. Locked exits keep their stone geometry, while recovered airwall materials and exit effects reflect gate state. See [timing and gate evidence](reports/APK_ROOM_TIMING_GATES.md), [implementation checks](reports/ROOM_GATE_IMPLEMENTATION.md), and [door presentation limits](reports/APK_DOOR_PRESENTATION.md).

The 2026-10-27 room pass checks all 514 active nodes against the supplied APK and implements source-bound springs, 71 adventure events, old-day and sacrificial altars, two-slot partner selection/combat and reusable adventure meal shops. Sacrifice prices, locking and conditional free refresh, pending-choice continuation, spring rewards, event costs/progression and partner SP/cooldowns use packaged/native evidence. See [implementation, evidence and desktop/phone verification](reports/APK_ROOM_ACTIVITIES_IMPLEMENTATION_20261027.md). Original APK runtime and physical-device equivalence remain unverified.

Dodge starts with two uses. The button shows remaining stock and recharge progress; a remaining use is available during recharge. The APK's last-use delay defaults to one second, then replenishes one use per update until full. This version grants one extra use by default; the source package provides that bonus through progression. See [source evidence and scope](reports/APK_DODGE_CHARGES.md).

Camp ambience binds to the recovered scene's active effect anchors: the spawn circle has cyan runes, flowing light and rising motes; campfires have flames, embers, smoke and local light; leaves, fireflies, steam and waterfall mist run continuously nearby. These are Godot reconstructions using recovered textures. Menu pause and backgrounding freeze them, reduced effects lowers their particle counts and disables local lights, and scene reloads release their owner. Top-right entries now follow the APK's guide, victory, run, purchased-meal and unread conditions. Resource counters appear temporarily after signed changes. Cloud opens its original confirmation and reports the missing account service; local saving remains a separate settings action. See [HUD rules, actions and verification](docs/HUD_NAVIGATION.md).

Camp now connects construction, guild support, commissions, NPC dialogue, permanent resources and timed partner work. Construction has seven three-stage rows, validates prerequisites and costs, updates original building geometry/collision/navigation, and focuses the completed facility. The camera uses recovered perspective parameters and supports facility tap navigation. The commission board, guild tree, dialogue portraits and proximity prompts use recovered APK artwork with the supplied screenshots as layout references. See [camp implementation and verification](reports/CAMP_SYSTEMS_IMPLEMENTATION.md) and [camera/geometry evidence](reports/CAMP_CAMERA_IMPLEMENTATION.md).

The 2026-10-25 audit against the supplied `1061664.apk` corrects dispatch claim-time charges and daily limits, meal research/purchase/recook, global awakening, commission conditions, and camp decoration purchases and scene restoration. Settlement keeps already collected gold/materials and grants converted adventure vouchers once. See [new APK camp and economy audit](reports/NEW_APK_CAMP_ECONOMY_AUDIT.md) for source evidence, regression results and remaining limits.

The 2026-10-26 camp pass adds source-volume proximity checks, overlapping facility selection, the real work marker, guarded recruitment/awakening and persistent per-character weapons. The unlocked smith training area restores three original scarecrows with isolated combat, live damage statistics and safe exit. Shop and character pages now use dedicated layouts with recovered artwork, working domain actions and phone landscape checks. See [implementation, evidence and validation](reports/CAMP_SHOP_CHARACTER_IMPLEMENTATION_20261026.md); live payments and original-runtime/device acceptance remain open.

The 2026-10-27 role-page pass reconstructs the APK character, weapon, backpack and warehouse views, including the original fire-ring artwork, source weapon models, character and weapon selectors, and persistent fashion ownership/equipment. Camp shows three categories; levels add the run backpack and unlock monster partners at institute level three. See [source rules, page captures and verification](reports/ROLE_PAGES_IMPLEMENTATION_20261027.md).

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
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/enemy_hit_reaction_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/hanyu/U3D/City/goDot --script res://tests/new_apk_drop_rules_test.gd
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
