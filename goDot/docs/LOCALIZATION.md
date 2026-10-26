# Localization

The game supports these 13 languages. The startup screen and Settings > Language
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

Use the selector at the top right of the startup screen, or open Settings and
select the Language section. Changes apply immediately and are remembered across
launches. Changing language does not start a new adventure or reset progress.
The settings page stays in the same section while its translated content refreshes.

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

## Layout Checks

The startup selector reserves a fixed area in the upper right. The start button
fits translated text between its arrow artwork. Settings use wrapping labels,
flowing option buttons, a scrollable navigation rail, and vertical rows on narrow
screens. Check all 13 languages at desktop, wide desktop, and `844 x 390` before
shipping. Include German, French, Portuguese, Russian, Thai, and Vietnamese in
font and overflow checks; verify every language selector still shows native names.
The original logo artwork is retained for both Chinese locales. Other languages
show the game's `Dungeon Chasers` brand name in the same frame.
