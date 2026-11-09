# Pawnshop — oak and forest-green metal kiosk

Original, UV-mapped kiosk replacing the primitive booth. Beveled oak boards, standing-seam painted roof, stone foundation, framed side glazing, shelves, stock cases, a compact till and visible hardware. The title panel stays completely clear for the game’s localized label.

- `Pawnshop.gltf` + `Pawnshop.bin`: model, 11 named mesh nodes / 7 materials, 5,888 triangles.
- Footprint **9.6 × 7.62 studs**, height **6.678 studs**; pivot at center of base, Y=0; front +Z.
- `Counter` and `SignPanel` are separate nodes. Mesh names differ from node names to avoid importer suffix collisions.
- SignPanel: X −3.1…3.1, Y 4.925…5.975, Z 3.27…3.35. Use its +Z surface (Roblox `Enum.NormalId.Back`). No case, coin or icon enters this rectangle.
- `Pawnshop_Front.png`, `Pawnshop_ThreeQuarter.png`, `Pawnshop_Rear.png` are renders of the exported geometry and its UV textures.

## Textures and import

All base-color images are 2048×2048. Shared oak and stone maps live in the sibling `../textures/` folder; preserve that folder when moving this package. Oak UV V follows the board length. Painted-metal base color, normal and ORM maps are original procedural surfaces. The stock atlas reuses four project-owned V36 poster artworks; no third-party logos or mesh assets.

Import the glTF with Roblox Studio’s 3D Importer, retaining hierarchy and named nodes. Inspect SurfaceAppearance on the imported meshes. glTF uses packed ORM (R occlusion, G roughness, B metallic); when assigning Roblox maps manually, use the separate shared roughness/metallic images and `paint_roughness.png` / `paint_metallic.png` for painted metal. Set collision fidelity appropriate for the body, disable collision for small stock/hardware, and add the game label to SignPanel. No scripts or lights are embedded.

## Rebuild

Run `python3 build_kiosk.py` with NumPy, SciPy, Pillow and trimesh available. The source has a local library search path for this workspace. Four original V36 poster images and shared wood/stone textures are required. See VALIDATION.md for limits.
