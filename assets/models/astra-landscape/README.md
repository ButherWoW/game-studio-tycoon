# Modular landscape/street props — batch7

Six original native Roblox models: RockSmall, RockMedium, RockLarge, Hedge, FenceSection, StreetBench. Each is provided as RBXM and RBXMX with exact technical name. These standalone modular props are not an automatic Park placement update.

| Model | Parts | Width × height × depth |
|---|---:|---|
| RockSmall | 3 | see VALIDATION.json |
| RockMedium | 3 | see VALIDATION.json |
| RockLarge | 3 | see VALIDATION.json |
| Hedge | 9 | 7.55 × 2.64 × 1.8 |
| FenceSection | 10 | 5.98 × 3.12 × 0.38 |
| StreetBench | 14 | 5.8 × 2.77 × 1.715 |

Every model stays below15 real Parts. Three rock sizes share an layered boulder silhouette made of native ellipsoids; no mesh asset is needed. Hedge length7.55 fits the requested6–8 range. Fence is a modular~6-stud section. Bench uses warm wood and muted green supports, facing+Z, without laptop or Seat (ParkBench is a different gameplay model).

Pivot is footprint center at baseY0. Every Part is anchored, geometry uses Model/Part classes only, no scripts/meshes/textures/external assets or lights. Import one format per model. Placement in the park, collisions with paths/spawn artifacts and bench seat behavior remain the integrating developer's responsibility.

Rebuild with Python3 and Rojo at `/Users/erland/.local/gst-tools/rojo`:

```sh
python3 source/build_landscape.py
python3 source/validate_landscape.py
```

numpy and Pillow render previews from the actual generated primitives. `VALIDATION.json` checks part budget, native class allowlist, base/center, hedge/fence limits and binary export header. The source copies the existing in-house geometry/renderer helpers. `previews/Landscape_ContactSheet.png` and six individual renders show the exported geometry. Studio/runtime playtest is still required.
