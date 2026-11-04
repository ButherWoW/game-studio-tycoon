# V7 third-floor studio — Skyscraper / SkyDesk / SoundStudio / ArtWall

Original native Roblox geometry following `origin/main` docs/VISUAL.md and Config/Upgrades stage4, read 5 November 2026. This is the top floor of one three-storey office, not a skyscraper building. The technical model name Skyscraper is retained for game compatibility.

## Installation

Import the four templates from `models/` into **ServerStorage.Upgrades**, preserving exact names. Pick RBXM or RBXMX, not both. `Sky_Upgrades_Import.rbxm` provides the same templates in a single Upgrades collection; move its four children into existing Upgrades.

All templates have local pivot (0,0,0), centered at the base. Face +Z. Code sets third-floor Y=28 and all Config positions. **Do not bake Y28 into templates.** `Sky_Assembled.rbxm` is a fully populated local layout reference, not an additional upgrade to import alongside the templates. It contains 11 independently named SkyDesk copies and the two facilities at Config coordinates. `layout.json` records placements and reserved volumes.

| Model | Parts | Width × height × depth |
|---|---:|---|
| Skyscraper | 62 | 60 × 14 × 60 |
| SkyDesk | 70 | 4 × 4.775 × 3.575 |
| SoundStudio | 91 | 10.8 × 7.2 × 8.6 |
| ArtWall | 28 | 13.5 × 7.8 × 0.9 |

Full third-floor reference: 951 Parts and five shadowless PointLights (four ceiling fixtures + one recording-studio fixture). Screens and accent strips are Neon geometry with no additional lights. The glass desk, wide monitor, tucked chair and under-desk tower all fit the narrow four-stud width; this deliberately leaves four-stud gaps in Config's first row where centers are eight studs apart.

Skyscraper floor is58×58 at Y0 (thin slab0..0.02); walls end at13 and full60×60 roof occupies13..14. Front opening +Z is24×9; game supplies upper-floor glazing. Lift box X−23..−17, Z21..27, Y0..7 contains no geometry except floor. No lift platform/buttons are supplied. SoundStudio has a6.4-stud opening and clear6-stud forward approach. The original three-piece gallery faces +Z and is freestanding at the exact ArtWall Config placement.

## Checks and previews

`VALIDATION.json` records part budgets, exact oriented primitive bounds, actual PrimaryPart/PivotOffset matrices, XML class allowlist, anchored geometry, no external assets/scripts, one light per fixture with Shadows=false, binary export and placement tests. Peer model bounds, shell intersections, 11 desk aprons of3 studs, horizontal desk gaps of4 studs, lift, front entry, sound-room approach and legacy player/coffee/hits envelopes all pass.

`previews/` contains actual generated geometry, not conceptual image generation. `Sky_Overview_Cutaway.png` hides only the roof, nearest walls and ceiling fixtures to expose the interior; those pieces remain present in both RBXM/RBXMX exports. `Skyscraper_Exterior.png` shows the complete shell. Individual previews and `Sky_Layout_QA.png` support review. The renderer is the copied in-house primitive depth renderer used for previous accepted kits.

No Roblox Studio/runtime playtest was performed here. Tester should import four templates, unlock stage4, verify full stacked building at0/14/28, roof visibility from normal camera, lift travel/controls, NPC positions on11 seats, glass/Neon appearance and mobile FPS. NPC seating is controlled by StaffService; SkyDesk deliberately contains no Seat instance.

## Rebuild

Python3, numpy, Pillow and Rojo are required:

```sh
python3 source/build_sky.py
python3 source/validate_sky.py
```

Rojo path in builder: `/Users/erland/.local/gst-tools/rojo`. No repository checkout or runtime source is changed by these scripts; outputs stay in this kit. All art, controller-free editor graphics and facility silhouettes are original, constructed from native Parts without external meshes, textures or brands.
