# Generated artwork

These are newly generated game assets, not recovered original screenshots.
Generation used the built-in imagegen tool. Dynamic text, quantities and level
nodes are rendered by Godot, not baked into the images.

| Asset | Runtime use | Source |
| --- | --- | --- |
| panel-v1.png | Shared nine-slice dark teal/gold panel | exec-5dbb3def-72f9-4556-9dd4-33f1dd80f1b0.png |
| heavy-v1.png | Heavy attack glyph | exec-bf1c302a-a89c-49a1-98e5-bd2b06fe3dd8.png |
| rune-v1.png | Blue camp rune | exec-e3dc277f-e2f1-4b8c-b7e7-5c519cd960bd.png |
| showcase-v1.png | Character/weapon showcase backdrop | exec-78a85b4e-75df-4862-afb3-1befb1d10cbd.png |
| awakening-flame-v1.png | Awakening tree decoration, no configuration ID | exec-fb1f2ee0-e9a3-4437-8885-8659f1b02f7c.png |

Original generator outputs are retained under
`/Users/7700k/.codex/generated_images/01a166a5-39aa-7fa2-b4dd-27c392a11cb3/`.
The first three originals are also retained in `originals/`.
Panel, heavy and rune runtime copies are respectively 1024, 256 and 512 pixels.
All runtime assets reside inside this project and use Godot texture imports.

## Awakening flame prompt (2026-10-23)

Create a single transparent-background game UI decorative flame emblem, 1024x1024. Style reference: a stylized cartoon fantasy mobile RPG awakening screen has a large flat golden-orange outline flame, tall central tongue, two curved side tongues, an elegant inward spiral at the bottom center, pointed shield-like base. Recreate that visual language as a NEW clean reusable asset. Thin amber-gold luminous strokes, restrained orange glow, generous transparent internal negative space and transparent outer margin. Centered symmetrical silhouette, highly readable at 300px. This is decoration behind skill tree nodes, not an ability icon. No letters, no text, no numbers, no level circles, no buttons, no frame, no background scenery, no watermark. Real alpha transparency, no checkerboard.

Generation parameter: `transparent_background=true`.
Reference: user-provided `codex-clipboard-dcf4beff-4ebb-428f-9fa7-b1eab3bfffaf.png`,
visually inspected before writing the prompt. Runtime tint and alpha are applied
by `reference_pages.gd` to keep level nodes legible.

## Earlier prompt records

Exact prompts for the four earlier assets were not available in the resumed
execution record. Their purposes and source filenames are recorded above;
descriptions here must not be treated as exact original prompts.
