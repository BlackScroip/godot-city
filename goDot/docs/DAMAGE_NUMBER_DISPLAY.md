# Damage, Critical Hits and Dodge Captions

The confirmed hit now carries `resolved_critical` and its damage element into
the pooled display. Numbers use the original APK's colored TMP sprite glyphs;
critical hits prepend its `bgcrit` sprite. Received damage uses the `hurt` set.
Existing full/abbreviated/hidden settings still work, including pooled reuse.

Successful player dodges display localized text. Manual dodge collision immunity
and combat automatic-dodge rejection both reach the presentation; block rejection
does not say dodge. A short per-player cooldown suppresses overlapping captions.

## Source Evidence

- Target: `1061664.apk`, SHA-256
  `ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505`.
- REA package inventory evidence:
  `ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323`.
  Complete retained export: `/private/tmp/city-damage-apk-evidence.json`.
- `tools/recover_damage_numbers.py` reads the APK manifest and dependencies of
  `PopEffect_Damage`, then extracts TMP glyph rectangles and original pixels.
  It writes `assets/ui/damage_numbers/glyphs.json` with target hash and metrics.
- `PopEffect_NumText.Init`, file `0x30f3dc4`, reads `IsCrti` at field `0x1c`
  and concatenates its selected prefix with `GetSpriteText_Damage` output.
  Its serialized example includes `<sprite name="bgcrit">`; the glyph's scale
  is 1.7. `reports/damage-number-apk-native.json` retains bounded disassembly.
- The damage prefab's TextMeshPro font size is **20**. Native damage animation
  uses scale `2.1 * 1.5 * 0.7 = 2.205`, a 0.1-second scale transition,
  0.5-second movement, 0.05-second fade-in and fade after 0.8 seconds for 0.2 seconds.
- `reports/dodge-tip-apk-prefab.json`: `PopEffect_TipsText` uses **32** point
  text and references TMP font asset path ID `-4280675585639441827`.
  `assets/ui/damage_numbers/source_font.json` identifies that asset as
  **Alibaba PuHuiTi 3.0 / 95 ExtraBold**. The display reuses the matching APK
  font already recovered at `assets/ui/boss_intro/font_a8fb15c8685836d5.ttf`.
- `reports/dodge-tip-apk-native.json` retains `RoleUnit.ProcessDamageOrHeal`
  and `PopEffect_TipsText` methods. These are static disassembly observations,
  not Android runtime captures.
- Manual dodge at file `0x3162440` selects throttle key `Dodge`, resolves
  `keyword_Dodge` via literal slot `0x65cf900`, and writes RGBA `(0,1,0,1)`
  from VA `0x128c9b0`. Automatic dodge resolves `keyword_AutoDodge` via slot
  `0x65dbd30` and uses the same green. The APK localization values are
  `闪避` and `自动闪避`. The throttle literal is 0.3 seconds. Tips animation
  scales to 1.5 in 0.04 seconds, fades in over 0.1, and fades out at 0.65
  over 0.3 seconds with the default duration multiplier.

## Adapter Boundaries

The presentation projects source UI sizes into the existing 3D scene against a
1080-high reference, recalculating scale so camera zoom cannot inflate the text.
Movement paths, separation lanes and punctuation fallback are Godot adaptations.
Full Unity TMP shader and animator parity have not been established. Chinese text uses the source font;
the existing localization system supplies translated captions.

Damage formulas and HP loss remain the existing game's calculations. This change
matches the display resources and forwards the final result; it does not claim
that the reconstructed combat formulas are identical to the APK.

## Verification

- `damage_number_display_test.gd`: actual critical-hit events, elemental glyphs,
  pool reset, number separation, fade lifecycle, camera zoom, manual/automatic
  dodge and block distinction. Desktop/mobile screenshots use the real renderer.
- Existing `settings_runtime_test.gd`, `combat_optimization_test.gd` and
  `dodge_charges_test.gd` cover settings, pool budget and dodge behavior.
