# V12 employee skins — original exact UV artwork

Three independent batches of four: batch1/2 cash tier, batch3 premium tier. Each batch has four shirt/pants PNGs pairs, four native accessory collection RBXMX files, four previews, contact sheet, README and VALIDATION.json.

Clothing artwork is code-native SVG built directly on the classic Roblox R15 585×559 UV map; it is not an AI illustration of a template. Source panels preserve exact UV positions. Official mapping reference: https://create.roblox.com/docs/avatar/classic-clothing . Original shapes/colors only; official template labels/logos are not included in delivered textures.

Preview depth-renders actual PNG panels and native accessory shapes on a canonical segmented block rig using explicit attachment transforms. This is reference QA, not an engine/runtime screenshot. Actual HumanoidDescription scales and attachments require Studio testing, especially seated poses and headwear. Models contain no scripts, external meshes or textures. Neon is used only on premium accessory Parts; no extra lights.

## Reproduce one batch

From this directory, install source/requirements.txt in Python and run npm install --prefix source. Then:

```
python3 source/build_skins.py --batch 1
node source/rasterize.cjs
python3 source/render_validate.py --batch 1
```

Use batch2/3 numbers for the corresponding package. Source is shared across the three PRs and contains all design recipes; each PR delivers exactly four skins. The local optional /private/tmp/gst-render-libs and renderer fallback module path are conveniences; normal installed dependencies take precedence.

Import instructions are in each batch README. Extract Accessory children from each collection and attach using Humanoid:AddAccessory. Do not treat the outer Model as a single Accessory. Review/test uploaded clothing with Shirt/Pants on the game's R15 NPCs before marketplace use.
