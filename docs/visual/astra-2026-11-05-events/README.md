# V19 — company events, rivals, contracts and bailiff

The actual `origin/main` config contains **22 company events and9 rival studios**, despite the VISUAL.md summary mentioning20 and8. This package follows the config IDs exactly; `CONFIG_IDS.json` records the verified lists.

| Batch | Final raster icons | Subject |
|---|---:|---|
| events-1 |11| angel through flood, in config order |
| events-2 |11| audit through bankrupt, in config order |
| rivals |9| all invented studios in Rivals.luau, preserving exact ID case |
| contracts-bailiff |4| bailiff, contract, publisher, franchise |
| Total |35|256×256 PNG with genuine alpha |

All35 illustrations are generated separately with built-in image_gen, then resized to256×256 using sips. No SVG/icon placeholders replace generated raster art. The same thick dark outline, blue/gold cartoon palette and large toy-like shapes connect the sets. Per-file metadata records the exact generation prompt, generated source location and final destination. Any corrective edit also records its reference and exact edit prompt. No text, real brands or studio names are rendered; rivalry symbols are original pictograms of the invented names.

The bailiff's585×559 shirt and pants use the accepted code-native SVG UV system, with editable artwork and a real UV-rendered512×512 preview. This deterministic clothing workflow is separate from the35 raster icon calls. The folder/tablet appears as a plain item in the jacket pocket; no frightening legal imagery or real authority insignia.

Each batch contains final assets under V19/, metadata/, README, VALIDATION and a contact sheet. `source/validate_assets.py --partial` validates delivered images during generation; run it without `--partial` after all35 are complete. It checks exact IDs, dimensions, real alpha, clear image corners, unclipped silhouette bounds and prompt metadata. Final visual review uses the actual native-size contact sheets. Upload/moderation results and48pixel in-game readability still need Studio review.

Clothing rebuild: `python3 source/build_bailiff.py`, `node source/rasterize_clothing.cjs`, `python3 source/render_bailiff.py`. Requires Pillow/numpy and the resvg package in source/package.json. The artwork and icons are original; no third-party brands, artwork, external meshes, gameplay code or Git changes are included.
