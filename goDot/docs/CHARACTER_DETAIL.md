# Character Detail Pages

The character, weapon, weapon selection and inventory/storage back buttons use
`presentation/role_navigation.gd`: the same recovered arrow, 120 x 100 control
at (20, 14), scaled from the 2048 x 900 source canvas.

Character details open three separate views:

- Attributes: a translucent full-screen, scrollable table with all 52 recovered
  source rows, category separators, original icons and help text. Camp previews
  use progression/equipment attributes; adventure views use live combat values.
  Maximum HP, final attack/defense, critical values and movement/attack speed
  are resolved from the existing combat implementation. Charge and percentage
  formatting follow the recovered native table. Default/maximum hints are
  tooltips, not substituted runtime values.
- Fashion: source color swatches, locked/equipped states, artwork, suit card,
  owned-stat effects and source-priced unlock/equip commands. Preview does not
  equip or spend. Returning restores the equipped appearance. Alternate 3D is
  disabled where a matching model has not been recovered.
- Upgrade: base-stat current/next comparison, actual held/required materials,
  cancel and confirm. Opening/canceling never mutates progression. Confirmation
  revalidates level, cost, affordability and camp availability, then dispatches
  the existing atomic upgrade transaction once. Insufficient materials and
  maximum level remain inspectable with confirmation disabled.

Evidence and limitations: `reports/CHARACTER_DETAIL_APK_20261027.md`. This change
uses static APK resources/native evidence and tests the Godot reconstruction;
it does not claim an original-APK runtime comparison or replace existing combat
rules with newly inferred formulas.

Validation scripts: `character_page_test.gd`, `character_detail_test.gd`,
`character_upgrade_test.gd`, `character_fashion_test.gd`, `weapon_page_test.gd`,
`inventory_page_test.gd`, and `role_pages_integration_test.gd` under `tests/`.
Rendered snapshots under `reports/character-{attributes,fashion,upgrade-page}-*`
cover desktop and phone landscape dimensions.
