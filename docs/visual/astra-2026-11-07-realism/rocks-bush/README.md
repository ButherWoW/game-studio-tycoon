# Original realistic park rocks and bush

All geometry is newly authored by the reproducible build script; no native Roblox Ball parts are used. The three rocks have distinct irregular rounded eroded silhouettes, closed surfaces, and UV mapping. Bush has 544 individually modeled curved and folded broad leaves plus 35 tapered twig segments. Leaf blades use real silhouette geometry rather than alpha rectangles or spheres.

Run from any directory:

    PYTHONPATH=/private/tmp/gst-realism-libs python3 -B build_assets.py --stone ../textures/stone_basecolor.png --leaf ../textures/broadleaf_basecolor.png

Use absolute texture paths if running outside this directory. Dependencies: numpy, trimesh, Pillow. Companion `_normal.png` and `_orm.png` files are picked up automatically. ORM is occlusion / roughness / metallic; metallic-roughness uses G/B. Leaf images run vertically from UV base at (0.5,0) to tip at (0.5,1). Twig bark is generated deterministically at 2048px by the script.

Each asset folder contains importable glTF 2.0, its geometry buffer, and external texture images. Keep all sibling files together during import. Coordinates are Y-up, in Roblox studs, centered horizontally, with the lowest vertex on Y=0. Source primitive envelopes were inspected; replacements retain approximately the original overall visual sizes.

RockSmall: 1.5 × 0.9 × 1.1 studs. RockMedium: 2.5 × 1.5 × 1.85. RockLarge: 4.1 × 2.45 × 3. Bush: 3.1 × 1.7 × 2.0. Each rock has 3,248 triangles. Bush has 13,476 triangles across foliage and twigs. Foliage and twigs are intentionally open double-sided surfaces; rocks are closed after duplicated UV seam vertices are welded.

The previews are CPU rasterizations of the actual exported geometry, UVs, and base color images, with simple diffuse lighting. They are not concept images or a substitute for checking the imported asset in Roblox. `validation.json` records triangle counts, UV bounds, degenerate faces, seam-weld closure, bounds, and signed volume.

Roblox importer must preserve UVs/material images; after upload, verify SurfaceAppearance maps and set collision/query behavior to match your placement system. No scripts are embedded.
