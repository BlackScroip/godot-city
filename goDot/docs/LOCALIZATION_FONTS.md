# Localization Font Sources And Coverage

Audit date: 2026-10-27. These are static font-table observations plus an actual
Godot 4.7.2 font loading and glyph coverage check. No system font was copied.

## Existing Fonts

`assets/fonts/default.otf` is the existing Alibaba PuHuiTi asset copied by
`tools/convert_unity.py` from
`RecoveredUnity/ExportedProject/Assets/_00001_Media/FontNotBuild/AlibabaPuHuiTi-3-95-ExtraBold.otf`.
Its Unicode cmap contains 29,197 nonzero glyph mappings, including Chinese,
Japanese kana, Latin and Cyrillic. It has no Thai or modern Hangul syllables and
lacks 88 of the 90 Vietnamese precomposed characters in U+1EA0 through U+1EF9
(only U+1EF2 and U+1EF3 are present).

`assets/fonts/default.ttf` is the existing, subsetted `msyh.ttf` asset imported
by the same converter from
`_00010_Plugins/_002_Tools/UGUICircularScrollView/Fonts/msyh.ttf`.
It contains 3,625 nonzero Unicode cmap mappings and also lacks Thai, Hangul,
Vietnamese accented characters, and some Chinese and Japanese characters.
It cannot supply the requested thirteen-language coverage by itself.

Existing font hashes:

| File | SHA-256 |
| --- | --- |
| default.otf | a8fb15c8685836d5041a4c47f2917fd57117182aff01350ea0335b216cc7993e |
| default.ttf | 877827373adde63afc3df474a35a1f81837e57dc9bf1ff3ec3e407c350ae97d8 |

## Added Fonts

`assets/fonts/NotoSansKR.ttf` was copied byte for byte from the already cached
`/Users/hanyu/tank-game/assets/fonts/NotoSansKR.ttf`, together with that asset's
`NotoSansKR-OFL.txt`. The embedded copyright and license records agree with the
included SIL Open Font License 1.1: copyright 2014-2021 Adobe, Reserved Font Name
`Source`. The embedded family is `Noto Sans KR Thin`, version
`2.004-H2;hotconv 1.0.118;makeotfexe 2.5.65603`.

This is an unmodified variable font with a `wght` axis from 100 to 900 and a
default weight of 100. Use a Godot `FontVariation` with `wght` set to 400 or 500
when adding it as a fallback. It contains 23,174 nonzero Unicode cmap mappings,
including all 11,172 modern Hangul syllables U+AC00 through U+D7A3 and every
Vietnamese precomposed character U+1EA0 through U+1EF9.

`assets/fonts/NotoSansThai.ttf` is the unmodified official Google Fonts file
`ofl/notosansthai/NotoSansThai[wdth,wght].ttf`, version 2.002. It and its matching
OFL were obtained through the official repository's GitHub blob API. Both blobs
were checked against their Git SHA-1 identities after download:

| Asset | Official Source | Git Blob SHA-1 |
| --- | --- | --- |
| NotoSansThai.ttf | https://github.com/google/fonts/blob/main/ofl/notosansthai/NotoSansThai%5Bwdth,wght%5D.ttf | 34b48ab6f74867dbfce19410a2f452abef34e3ff |
| NotoSansThai-OFL.txt | https://github.com/google/fonts/blob/main/ofl/notosansthai/OFL.txt | 7fa8dcb08ce4d2667b683ac4a8e79166e44e5277 |

The Thai font has 426 nonzero Unicode cmap mappings and covers all assigned Thai
letters, combining marks, digits and punctuation in U+0E01 through U+0E5B. Its
embedded copyright is `Copyright 2022 The Noto Project Authors` and it uses SIL
Open Font License 1.1. The full license travels with the font at
`assets/fonts/NotoSansThai-OFL.txt`.

Added asset hashes:

| File | SHA-256 |
| --- | --- |
| NotoSansKR.ttf | 194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252 |
| NotoSansKR-OFL.txt | 1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9 |
| NotoSansThai.ttf | 5a1c559bb539583c8a1fd99d1c5b9491e5e14478c9cd2bd0970d5c3096cc9ef8 |
| NotoSansThai-OFL.txt | 2e98fd23a52d253db8612cd5942c8f2ff4111b21d2367050fdca91d8ccc374a0 |

## Verification

The sfnt `cmap` format 4 and 12 tables were decoded directly for the observations
above. The final catalog check uses `tools/audit_localization_fonts.gd` to load
the actual bytes of `default.otf`, `NotoSansKR.ttf`, and `NotoSansThai.ttf` in
Godot. Every `FontFile` has `allow_system_fallback = false`. The Korean font is
wrapped in `FontVariation` with `wght = 400` and added to `default.otf` together
with the Thai font.

All thirteen effective catalogs were checked against the current 8,529 sources,
using the runtime order of original catalog, supplemental catalog, then manual
overrides. Simplified Chinese uses the source text. Recovered keyed catalogs
and every override were also included. Markup, line breaks, and known zero-width
formatting characters were excluded from glyph collection. Every collected
display character has a bundled font glyph:

| Catalog | Distinct Display Codepoints | Missing |
| --- | ---: | ---: |
| zh_CN | 2,395 | 0 |
| zh_TW | 2,452 | 0 |
| en | 108 | 0 |
| ja | 1,995 | 0 |
| ko | 1,113 | 0 |
| id | 96 | 0 |
| th | 161 | 0 |
| vi | 176 | 0 |
| de | 104 | 0 |
| fr | 112 | 0 |
| pt | 113 | 0 |
| es | 106 | 0 |
| ru | 153 | 0 |

The check exited with `ALL_CATALOG_FONT_FAILURES={}` and wrote
`assets/localization/font_report.json`. The separate strict catalog audit also
rejects replacement characters U+FFFD and U+2047, unexpected control characters,
and inappropriate writing systems, which glyph availability alone cannot
detect.

With Godot on `PATH`, reproduce both reports from the `goDot` directory:

```sh
python3 tools/audit_localization.py
godot --headless --path . --script res://tools/audit_localization_fonts.gd
```

All seven presets in `export_presets.cfg` include `assets/fonts/*-OFL.txt`, so
both added font licenses ship with exported builds.

The supplemental catalogs have been generated and checked, with manual review
of core text and targeted repairs. Most long-tail text uses offline machine
translation. Font and structural checks do not constitute a complete native
linguistic review of every translation.
