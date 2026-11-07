# Flowerbed
Original UV-mapped glTF 2.0 park planting, 3.800 × 1.360 × 3.800 studs, Y-up, center-base pivot. Root: Flowerbed. Front: +Z.

12,604 triangles across seven material-batched mesh nodes. Beveled sandstone edging, soil, eight daisies, five coral tulips, and four lavender clumps with three stems each. Curved petal/leaf surfaces are actual geometry. Texture UV V follows the length of broad leaves and flower petals. Botanical material is double-sided for thin leaves/petals.

`Flowerbed.gltf` references `Flowerbed.bin` and shared `../textures` PBR maps. Keep directory structure intact. Import glTF through Roblox Studio 3D Importer. Base colors, normal maps and ORM maps are separate linked image files. Roblox may require roughness and metalness channels assigned as separate SurfaceAppearance textures.

Rebuild with `python3 build_flowerbed.py` using numpy, trimesh and Pillow. Source includes deterministic random seed. `validation.json` reports actual exported bounds and counts. `Flowerbed_provisional_untextured_preview.png` is a deterministic shaded rendering of the actual mesh, without texture mapping; it is not concept art.

`Flowerbed_textured_preview.png` renders the actual exported mesh with linked 2048px basecolor images and material tints. Run `python3 render_and_validate.py` after shared textures exist to regenerate that preview and texture/UV/reimport validation. The renderer uses the sibling rocks-bush build script. Texture files were verified present and 2048×2048. All seven reimported meshes have finite UVs and zero degenerate triangles.
