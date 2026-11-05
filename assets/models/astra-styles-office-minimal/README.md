# V15 office — Minimal

9 native furniture variants with suffix _Minimal. Exact accepted classic XML snapshot commit `fe8c7a7300ae885931254c375bb6a652a4151a37` is the baseline; original classics are untouched.

| Model | Classic → variant Parts | Width × height × depth |
|---|---:|---|
| OfficeDesk_Minimal | 187 → 188 | 6.0 × 4.87 × 3.83 |
| Cooler_Minimal | 49 → 52 | 1.92 × 3.65 × 1.86 |
| MeetingRoom_Minimal | 82 → 85 | 14.0 × 7.0 × 9.96 |
| FloorDesk_Minimal | 192 → 193 | 5.0 × 4.87 × 3.83 |
| ServerRoom_Minimal | 172 → 175 | 10.0 × 7.8 × 4.0 |
| Lounge_Minimal | 158 → 159 | 8.0 × 4.37 × 8.9205 |
| SkyDesk_Minimal | 70 → 71 | 4.0 × 4.845 × 3.575 |
| SoundStudio_Minimal | 91 → 94 | 10.8 × 7.2 × 8.6 |
| ArtWall_Minimal | 28 → 31 | 13.5 × 7.8 × 0.9 |

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
