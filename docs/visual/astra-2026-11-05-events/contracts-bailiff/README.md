# V19 / contracts-bailiff

Expected 4 icons; current status PASS. All final raster icons are256×256 PNG with genuine transparency, thick dark#1E1E2E outlines, blue#3D7BFF and gold#FFC93C, plus a few subject accents. Built-in image_gen was called separately for every illustration; no SVG stand-ins were used for icons. Exact prompts, generated-source paths and final filenames are saved per asset in metadata/. PNGs are resized through sips and retain RGBA alpha. Contact sheet shows final256assets at native size.

Filenames correspond to the actual origin/main config IDs. CONFIG_IDS.json records the discrepancy: VISUAL says20events/8rivals while CompanyEvents has22 and Rivals has9. All actual IDs are delivered across the four batches. Rival names are recorded in metadata for integration; only original pictograms are rendered, without studio names or real brands.

Upload PNGs to Roblox and connect the resulting IDs in the existing UI. No gameplay code or Git state changed. Validate small-screen readability and moderation/upload results in Studio before release.

The contracts-bailiff batch additionally includes original585×559 shirt/pants SVG artwork and PNGs using the accepted classic-clothing UV system. Clothing is authored deterministically because exact UV geometry matters; its raster icons use image_gen like every other V19 icon.

Standalone validation from the package root: `python3 source/validate_assets.py --batch contracts-bailiff`.
