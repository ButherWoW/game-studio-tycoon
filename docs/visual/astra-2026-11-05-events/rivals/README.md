# V19 rival studio emblems — nine transparent icons

Nine original symbols for the exact IDs in `src/shared/Config/Rivals.luau`. VISUAL V19 still says8 rivals; current Config contains9, so this complete set includes all9. Filename capitalization follows Config exactly.

| File | Studio | Original emblem |
|---|---|---|
| rival_tinfoilOwl.png | Tinfoil Owl | folded silver owl, amber eyes, cyan brow |
| rival_mangoComet.png | Mango Comet | orange mango comet with green leaf |
| rival_quokkaPixel.png | Quokka Pixel Works | smiling sandy quokka with cyan/purple pixels |
| rival_gloomberry.png | Gloomberry | sleepy blue/plum blueberry |
| rival_brassfern.png | Brassfern Interactive | polished brass fern and emerald stem |
| rival_velvetAnvil.png | Velvet Anvil | plum velvet-topped gold anvil |
| rival_nimbusTurtle.png | Nimbus Turtle | turquoise turtle with white cloud shell |
| rival_okraLantern.png | Okra Lantern | emerald okra-shaped warm glowing lantern |
| rival_bluemoth.png | Bluemoth Games | cobalt/cyan moth with gold crescents |

All runtime images are **256×256 RGBA PNG, genuine transparent backgrounds**, symbol-only with no lettering, watermarks or real brands. Glossy low-poly facets, chunky silhouettes and bold navy#1E1E2E outlines follow the V3 icon family. The icons were generated individually with the **built-in image_gen tool**, not SVG stand-ins or a combined sprite-sheet generation. No CLI/API fallback was used. All nine originals were inspected individually.

`prompts.json` contains each exact prompt, resulting source filename and relative source-copy path. `sources/` preserves the original generated PNGs unchanged, with source hashes in `VALIDATION.json`. One Quokka generation encountered a transient connection error; its standalone retry succeeded. Technical export scales the existing alpha silhouette into a216px content box on the256px transparent canvas to give consistent UI margins. It does not repaint or segment backgrounds. `source/prepare_rivals.py` reproduces the PNG exports, validation and contact sheet from saved originals (Python3/Pillow).

`Rivals_ContactSheet.png` shows all9 at256px with48px samples on light/dark panels. Review labels occur only on that documentation sheet, never on runtime icons. `VALIDATION.json` verifies source PNG/alpha, dimensions, empty corners, output format, margin, filenames and hashes. Subject/style/no-text/no-brand checks are visual review, not a claim of automated OCR or Roblox moderation approval.

Dev1: upload the nine runtime `rival_*.png` files as Images and give IDs to Dev2. Dev2: map IDs to the exact camelCase rival IDs in the industry ranking/toasts. No runtime code, competitor names, balancing or gameplay behavior is changed. Studio/mobile UI integration remains to test. Source Config: https://github.com/ButherWoW/game-studio-tycoon/blob/main/src/shared/Config/Rivals.luau
