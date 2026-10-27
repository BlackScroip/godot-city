# Localization

The game supports these 13 languages. The startup screen and Settings > Account
show language names in their own writing system, so the selector remains usable
when the current interface language is unfamiliar.

| Language | Native name | Locale |
| --- | --- | --- |
| Simplified Chinese | 简体中文 | `zh_CN` |
| Traditional Chinese | 繁體中文 | `zh_TW` |
| English | English | `en` |
| Japanese | 日本語 | `ja` |
| Korean | 한국어 | `ko` |
| Indonesian | Bahasa Indonesia | `id` |
| Thai | ภาษาไทย | `th` |
| Vietnamese | Tiếng Việt | `vi` |
| German | Deutsch | `de` |
| French | Français | `fr` |
| Portuguese | Português | `pt` |
| Spanish | Español | `es` |
| Russian | Русский | `ru` |

## Selecting a Language

Use the selector at the top right of the startup screen, or open Settings >
Account and use the Language row. Changes apply immediately and are remembered across
launches. Changing language does not start a new adventure or reset progress.
The settings page stays in the same section while its translated content refreshes.
The initial language follows the system locale when supported and otherwise
uses English. The saved preference lives in `user://language.cfg`, separately
from the adventure profile.

The startup selector and settings selector both read `DungeonLocale.language_options()`.
Their item metadata stores locale codes. Language names disable automatic
translation, including the popup, and selection does not depend on the displayed
name. The settings selector emits `language` with the locale code as its `id`.

## Adding Interface Text

`DungeonLocale` initializes the Godot translation catalog and owns the current
language. Use `DungeonLocale.set_locale(code)` to change it, and listen to the
`/root/Locale` node's `locale_changed` signal when a view needs to rebuild dynamic
content.

Keep source strings stable. Godot translates plain Label and Button text through
`TranslationServer`. Translate a formatted string before substituting values:

```gdscript
label.text = tr("等级 %d") % level
```

Use `DungeonLocale.text(source)` when the caller cannot use a Node's `tr()`.
Do not call `tr()` in constant initializers. Preserve formatting placeholders,
markup, identifiers, and line breaks in each translation. Catalog IDs and actions
remain language independent.

## Translation Data

The shipped catalogs are JSON under `assets/localization`; the game needs no
translation service or model at runtime. Simplified Chinese is the authored source.
Traditional Chinese is converted with OpenCC `s2twp`. English is generated using
the dedicated Argos Chinese-to-English 1.9 model, then repaired using the reviewed
English dictionary. The other ten languages are generated from that English
baseline using NLLB-200 distilled 600M, with beam size 4. A separate, manually
reviewed dictionary supplies core interface copy and game terminology. Longer descriptions,
dialogue, and less common names are machine translated and still need native
speaker review before a polished commercial release.

`original/` records the APK import and its evidence. Some original entries describe
older mechanics or collide on short Chinese labels, so current-source supplemental
translations take priority. `overrides.json` is merged last. Authored inline
semantic-tag fallback text also takes priority over an old semantic key.
The runtime also indexes corresponding lines and `|`-separated tiers as aliases,
so descriptions remain translated when menus append status lines or select one
building stage. Exact catalog entries retain priority over generated aliases.

`tools/complete_localization.py` collects script literals, player-facing data,
semantic display terms, and settings-guide text into `sources.json`. Its audit
writes `coverage.json` with missing and invalid entries by language. A coverage
pass checks completeness and immutable tokens; it does not establish linguistic
accuracy. `tools/translate_localization_offline.py` can resume local CTranslate2
translation, with protected numbers, formatting placeholders, tags, and line breaks.
Known semantic tags are expanded to the current authored display text before
translation. `tools/refine_english_localization.py` applies reproducible English
repairs from `reviewed/en.json`; selected sources can then be refreshed in the
target languages without regenerating complete catalogs. The numeric audit also
checks explicit signs, decimal values, and percentages. Printf placeholders must
retain their original order.
Model weights and caches stay outside the project.

The 2026-10-27 snapshot contains 8,529 source strings. All thirteen locales cover
every source, with zero missing entries, strict validation failures, source drift,
or differences between reviewed repairs and their shipped supplemental entries.

Use `DungeonLocale.compact_number(value)` for abbreviated large values. It uses
the correct magnitude for each locale's units, including Chinese/Japanese ten
thousands, Korean ten thousands, and Western thousands/millions/billions. Locale
decimal separators are applied without changing the underlying value.

## Layout Checks

The startup selector reserves a fixed area in the upper right. The start button
fits translated text between its arrow artwork. Settings use wrapping labels,
flowing option buttons, a scrollable navigation rail, and vertical rows on narrow
screens. Check all 13 languages at desktop, wide desktop, and `844 x 390` before
shipping. Include German, French, Portuguese, Russian, Thai, and Vietnamese in
font and overflow checks; verify every language selector still shows native names.
The original logo artwork is retained for both Chinese locales. Other languages
show the game's `Dungeon Chasers` brand name in the same frame.

Character, weapon, warehouse, shop, and adventure preparation headings contain
Chinese text in their original image assets. `DungeonStyle.localize_artwork_title`
keeps that artwork in Simplified Chinese and replaces it with a fitted translated
caption for the other twelve locales. New image-based headings need the same
treatment. The character and weapon title frames accommodate longer translations;
translated category buttons and the awakening caption fit their available width.
HUD navigation captions wrap to at most two lines in a fixed area under each
icon, and refit when the language or viewport changes.
Preparation equipment cards reserve space for names, artwork, and rank. Names
fit at most two lines, and the full name is available in the card tooltip.
Awakening summaries wrap within the left column and start with a usable text
width, preventing first-layout height growth from expanding the page.

## Verification

From the repository root, collect current sources and run the strict catalog
audit with the system Python. These commands need no translation model:

```sh
python3 goDot/tools/complete_localization.py
python3 goDot/tools/audit_localization.py
```

`coverage.json` records basic completeness, while `quality_report.json` checks
the effective runtime catalogs for formatting tokens, numbers, percentage signs,
unexpected writing systems, residual Chinese, replacement and control characters,
source drift, and reviewed-repair synchronization. The strict audit exits with a
nonzero status when any check fails. Neither
report substitutes for a native speaker's linguistic review.

Check all actual catalog characters against the bundled fonts with system font
fallback disabled:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /private/tmp/city-localization-fonts-godot.log --path /Users/hanyu/U3D/City/goDot --script res://tools/audit_localization_fonts.gd
```

This writes `assets/localization/font_report.json` and exits with a nonzero status
if a required glyph is missing.

Run the geometry and interaction checks without a display:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --log-file /private/tmp/city-localization-ui-godot.log --path /Users/hanyu/U3D/City/goDot --script res://tests/localization_ui_test.gd
```

Run the same test with `--headless` removed and `-- --render-check` appended to
capture startup, camp HUD, settings, character, weapon, warehouse, shop, and adventure
preparation pages for all 13 languages at `1600 x 900` and `844 x 390`.
The test writes `reports/localization-ui.json` and keeps full screenshot output in
`/private/tmp/localization-ui`. It uses temporary profile and language preference
files and verifies that the user's profile and saved language stay unchanged.
It also checks that translated captions replace baked Chinese headings and fit
on one line. Use a unique `--log-file` for concurrent Godot processes to avoid
competing log rotation. Core behavior and formatting edge cases are checked by
`tests/localization_test.gd` and `tests/localization_edge_test.gd`.

Append `-- --render-check --strict-catalogs` for the final rendered pass. The
strict pass also captures awakening and scans visible text on those pages plus training,
resources, guild and character talents, companions, dispatch, decorations, meals,
buildings, residents, awakening, tokens, amplifications, achievements, tasks, and
the Relic Archive. It rejects residual Chinese in non-Chinese/non-Japanese
interfaces while preserving the native names in language selectors. Use
`--test-locales=en,ko` to limit an investigative run; final verification must
include all thirteen locales.

The final 2026-10-27 verification passed 183 core checks, 1,666 catalog-text
checks, 8 formatting-edge checks, and 38,978 rendered interface checks. The
rendered pass covered all thirteen locales at both viewports, saved 287
screenshots, and verified that the user's save and language preference files
were unchanged. `assets/localization/font_report.json` also reports zero missing
glyphs across all thirteen catalogs with system font fallback disabled.
