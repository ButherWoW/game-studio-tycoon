# Premium interior finish — Sakura

Pale wood floor panels, muted pink inlays and lower wall bands, ivory shoji paper panels in wood frames and original geometric cherry blossoms.

Four independently importable native shell templates, with suffix `_Sakura`. These are premium asset themes intended for a separate Robux interior-finish category; this kit invents no prices, products or entitlement logic. It changes architecture (floors, walls, window frames, skirting, beams and fixture housings), not the selected furniture style.

| Model | Parts | Width × height × depth |
|---|---:|---|
| GarageWalls_Sakura | 541 | 60.2 × 18.47651 × 60.0 |
| Office_Sakura | 293 | 60.0 × 13.0 × 60.0 |
| Floor_Sakura | 294 | 60.0 × 13.0 × 60.0 |
| Skyscraper_Sakura | 238 | 60.0 × 14.0 × 60.0 |

## Floors and architecture

Every floor is an exact169-box partition, not a second decal plane. Alternating panel/inlay intervals fill58×58 exactly (garage60×60 exception) with no uncovered or double-covered compressed-grid cells. All169 tiles are contained in the original slab volume. Floor localY remains0...02 for Office/Floor/Skyscraper; garage keeps its accepted−.24...0 slab. The existing0.02 contact at furniture feet is inherited from the accepted source floor and is not increased. `manifest.json` and `VALIDATION.json` list every `floorPartNames`, `floorXZ`, `floorY` and area proof.

Classic originals remain unchanged. The premium Office removes the old plank overlays, uses58×58 floor, and receives a new59×2 soffit inY9..11 plus side panels to form the required24×9 front opening; the accepted upper header/beam joints stay untouched. Floor/Skyscraper retain their24×9 openings. The lift box X−23..−17, Z21..27, Y0..7 is empty above the floor. Full model pivot and overall shell bounds match the classic baseline exactly. Garage retains its actual accepted open facade, rafters up to18.23651 and four hanging fixtures; no roof is added. Office/Floor have no continuous ceiling slab. Only Skyscraper keeps its roof at13..14.

New wall accents, entry panels and soffit have **zero OBB SAT overlaps** with actual base shell solids, current stage furniture or one another. A second conservative precheck expands each stage furniture model's full AABB by0.2stud on every side, covering the accepted V15 furniture-style bounds; it also passes with zero overlaps. These tests exclude floor support contact and do not rewrite old structural joints. All12 shell models stay below600 Parts; existing fixture counts/positions are retained, at mostone PointLight per fixture, all Shadows=false. No scripts, external meshes, Decals or Texture assets. Native Roblox Material.Marble/WoodPlanks are built-in materials, not external texture references.

## Import and runtime integration

Import either RBXM or RBXMX copies into ServerStorage.Upgrades, preserving exact names. Do not import both formats. `GarageWalls_Sakura` is the garage shell template; the integrating code should handle its Garage/GarageWalls alias. Keep local pivotY0 and normal game stage positioning. Do not bake floor heights14/28 into these templates.

Use a **separate** profile/selection field such as `interiorFinish`, distinct from furniture.selected, so a premium shell finish does not reset furniture styling. `manifest.json` includes ceilingColor=`FFF1E8` and ceilingMaterial=`SmoothPlastic`. Runtime OfficeFloors.FloorSlab topY−.01 is below the floor art; its underside is the first/second-floor ceiling, so Dev2 should apply those ceiling fields to that code-created slab. Do not add full model ceilings to Office/Floor. INTEGRATION.md in this kit contains the developer handoff.

## Previews and validation

`previews/*_Furnished.png` use the actual accepted stage furniture at Config positions. Near side/front/roof, front soffit and inherited overhead beams, suspensions and ceiling-light fixture geometry are camera cutaways only; garage rafters/eave beams are also hidden in preview. All exported models remain complete and contain these parts. `ShopCard_512.png` is a512×512 text-free close interior shop preview; Office_Detail.png uses the same rear-wall view and ShopCard_FullRoom_QA_512.png retains an overall review view. These are local software renders, not ImageGen. The renderer shows actual geometry and base colors; **Roblox's built-in Marble/WoodPlanks material grain/shader is not reproduced locally** and must be reviewed in Studio, together with Glass/Neon and actual game lighting.

`VALIDATION.json` records coverage, shell bounds, pivot, native class allowlist, lift/entry/roof limits, source light counts, SAT pairs and the0.2 furniture-style envelope. No Studio/runtime/mobile test performed. Verify theme swapping, upper-floor glass, elevator, purchased furniture and phone FPS in the game. Source snapshot commit: `48abb8b0e3b445aa013d9da5716553afd488ee36`. Exact accepted XML snapshots and source recipe copies are included under baseline/.

Rebuild this independent theme with Python3/numpy/Pillow and Rojo:

```sh
python3 source/build_themes.py
python3 source/validate_render.py
```

Rojo is resolved from GST_ROJO, then PATH, with the original local path as fallback. No game code or classic assets are modified by rebuilding.

Independent floor check: `python3 source/check_floor_coverage.py` checks all four templates without the renderer. FLOOR_COVERAGE_INDEPENDENT.json records full coverage, zero gaps and zero overlaps. Only import models/ into Studio; baseline/ is a source/QA reference. Furniture shown in previews is not replaced by this finish.


## Мебель в тон отделке

Добавлены29вариантов классической мебели. Финальные шаблоны находятся в models/, подробные проверки, исходники и превью — в [furniture/README.md](furniture/README.md). Прежние четыре оболочки сохранены без изменений. Код #222 выбирает эти варианты при стиле мебели «Классика» и соответствующей отделке; купленные Neon/Cozy/Minimal имеют приоритет. Новые товары/цены/права собственности этой пачкой не создаются.
