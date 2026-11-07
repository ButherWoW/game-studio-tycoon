# Validation — Pawnshop

## Passed offline

- Exported glTF 2.0 JSON and external binary; all external image references resolve.
- 5,888 triangles across 11 mesh nodes, below the 20,000 triangle target.
- Bounds X ±4.8, Z ±3.81; base Y=0; origin centered in X/Z; front +Z.
- All positions and UV values finite; no zero-area triangles.
- Reimport with trimesh preserves total triangle count.
- Counter and SignPanel exist separately; node and mesh names are distinct.
- Sign area is blank, matte forest green. Frame lies outside the text rectangle; stock cases are below or behind it.
- Roof support heights follow its pitch after visual review of the first render.
- Three actual textured-mesh views inspected; this is not a concept illustration.
- No animations, scripts, embedded lights or externally downloaded meshes.

## Still required in Studio

This package has **not** been tested in Roblox Studio. Verify import unit scale, material/normal orientation, named-node preservation, glazing appearance and collisions. Check the localized title at multiple camera distances after the accompanying WorldService label fix. Review touch/click interaction positions against the separate Counter node. Material conversion and label rendering cannot be certified by an offline preview.

Structural joinery intentionally meets/overlaps at posts, counter supports and roof seams. This package does not claim an automatic global nonintersection check. The reserved text face was inspected separately.

Machine-readable bounds and per-node triangle counts: `validation.json`.
