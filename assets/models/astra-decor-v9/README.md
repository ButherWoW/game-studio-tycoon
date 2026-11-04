# Studio decor V9 — six native Roblox models

Original geometry following current `docs/VISUAL.md` V9 and `src/shared/Config/Decor.luau` (5 November 2026). Only the six newly requested assets are included.

## Import

Insert the individual files in `models/` into **ServerStorage.Upgrades**, keeping exact model names. Choose either `.rbxm` or `.rbxmx`; do not import both copies. The game uses Config/Decor slots, rotations, floor offsets and the Y=8 wall-sign height. Do not bake those world positions into these templates.

Models face +Z. Furniture pivot is center of the footprint at Y=0; NeonSign pivot is backing-panel center. PrimaryPart uses a PivotOffset, with no invisible helper parts. All geometry is anchored; no scripts, meshes, textures, asset references or text. These are decor models, not functional seats or gameplay machines. Collidable case bodies coexist with noncolliding detail Parts.

| Model | Parts | Width × depth × height, studs |
|---|---:|---|
| BeanBags | 15 | 7.8 × 2.65 × 2.41 |
| Bookshelf | 57 | 5.8 × 1.44 × 5 |
| MiniFridge | 42 | 2.4 × 2.46 × 4 |
| NeonSign | 18 | 5.7 × 0.26 × 2.3 |
| Aquarium | 45 | 5.9 × 1.9825 × 4.96 |
| ArcadeMachine | 34 | 2.86 × 2.5 × 6 |

MiniFridge, NeonSign, Aquarium and ArcadeMachine each contain one low-brightness PointLight with Shadows=false. The other two have no lights. Original controller silhouette and geometric arcade screen use no brands.

## Reproduce

Python 3, numpy and Pillow are required for previews. Set `ROJO` below by editing the local executable path in `source/build_decor.py` if necessary.

```sh
python3 source/build_decor.py
python3 source/validate_render.py
```

Builder uses Rojo at `/Users/erland/.local/gst-tools/rojo`. Included `geometry.py` and `render_geometry.py` are self-contained copied helpers from the existing Park kit; previews render actual generated native Part geometry, including glass. The optional `/private/tmp/gst-render-libs` import path allows installed render dependencies; regular Python-installed numpy/Pillow also work.

`VALIDATION.json` records per-model measurements and structural checks. Checks cover exact oriented primitive bounds, V9 part/dimension caps, base height, XML classes, anchored geometry, actual PrimaryPart + PivotOffset matrix, one shadowless light on each lit object and binary file header. Rojo successfully built all six binary models. Visual review of the contact sheet completed. Final Studio import and in-game placement/mobile playtest remain for the tester; this kit does not claim a Roblox runtime test.

Preview: `previews/V9_ContactSheet.png`, plus six individual renders.
