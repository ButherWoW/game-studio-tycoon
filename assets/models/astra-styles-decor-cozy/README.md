# V15 decor — Cozy

12 native furniture variants with suffix _Cozy. Exact accepted classic XML snapshot commit `fe8c7a7300ae885931254c375bb6a652a4151a37` is the baseline; original classics are untouched.

| Model | Classic → variant Parts | Width × height × depth |
|---|---:|---|
| Plant_Cozy | 31 → 35 | 2.4668 × 4.2405 × 2.112 |
| Rug_Cozy | 70 → 73 | 21.0 × 0.16 × 23.0 |
| Sofa_Cozy | 281 → 282 | 8.83 × 3.07 × 3.2455 |
| CoffeeTable_Cozy | 61 → 65 | 5.8 × 3.1892 × 2.568 |
| PendantLamp_Cozy | 10 → 12 | 2.35 × 3.05 × 2.39 |
| WallBench_Cozy | 26 → 30 | 5.8 × 1.725 × 1.763 |
| BeanBags_Cozy | 15 → 18 | 7.8 × 2.41 × 2.65 |
| Bookshelf_Cozy | 57 → 61 | 5.8 × 5.0 × 1.44 |
| MiniFridge_Cozy | 42 → 43 | 2.4 × 4.0 × 2.5055 |
| NeonSign_Cozy | 18 → 19 | 5.7 × 2.37 × 0.26 |
| Aquarium_Cozy | 45 → 49 | 5.9 × 4.96 × 2.023 |
| ArcadeMachine_Cozy | 34 → 35 | 2.86 × 6.0 × 2.5455 |

Import one format per model into ServerStorage.Upgrades. Both RBXM and RBXMX are provided. Game style-switch code must select exact suffix names; no gameplay code is included. Pivots, original Part names/classes/sizes/transforms, PcSeat Seat instances, BlueSeat*/SeatCushion, shelf boards, monitor and desktop heights are preserved. NeonSign and PendantLamp retain their original wall/ceiling pivot exceptions. Original artwork, canvas/background panels, screen miniatures, server status colors, hot/cold tap levers and colored control keys retain both classic Color and Material. Only frames, bodies and new trim take the selected style. Each native light remains in its original location with Shadows=false; no new lights.

Style uses materials and new physical geometry: Neon adds cyan/violet luminous edge rails/status inlays on dark metal; Cozy adds warm wood, textile bindings and soft end pads; Minimal adds pale oak inset panels with rounded white caps. Detail count adapts to each base object's20% budget. Complete-base and new/new OBB SAT resolves placement on exposed surfaces; monitors use top bezel caps above the UI, not screen-covering overlays. Some complex silhouettes use a single safe exterior binding instead of multiple overlapping patches. These are exterior trim Parts beside existing surfaces; they have no solid overlap with the base or each other and are noncolliding.

VALIDATION.json checks all original transforms/functionality, bounds within±0.2stud, exact baseY, unchanged pivot, native class allowlist, lighting and counts. Every new/base and new/new oriented-bounds pair is tested with SAT (0.0001stud numerical tolerance); per-model pair counts and zero-overlap results are recorded. Classic_vs_Style.png compares actual exported geometry with classic in the same camera; individual variant renders are in previews/. Accepted XML/source snapshots and standalone generator/renderer are included in baseline/ and source/. No scripts, external meshes, textures or brands.

No Studio/runtime test performed. Verify actual Humanoid seating, style swapping, inherited interactions and lighting/FPS on phone. This kit intentionally preserves any preexisting classic geometry quirks rather than moving working parts to conceal them.

## Rebuild this independent batch

```sh
python3 source/build_styles.py
python3 source/validate_render_styles.py
```

Python3, numpy, Pillow and Rojo are needed. Generator uses `/Users/erland/.local/gst-tools/rojo`; edit the executable path for another machine. All outputs stay in this batch.
