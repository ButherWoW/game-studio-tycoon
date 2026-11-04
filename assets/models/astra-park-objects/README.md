# Park interactive objects / V7 batch 2

Four original low-poly models built from native Roblox Parts and one Seat. No scripts, external meshes, image textures, text or brands. Created with the included Python geometry generator; binary conversion through Rojo. Previews render the actual exported geometry rather than image-generated concepts.

| Model | Width × height × depth, studs | Parts | Details |
|---|---|---:|---|
| ParkBench | 5.45 × 3.88 × 2.90 | 27 | Wooden bench, table, open laptop; Seat `PcSeat` with `Public=true`; seated player faces −Z, screen faces +Z |
| JobBoard | 6.90 × 6.895 × 0.90 | 28 | Abstract task sheets and pins, front +Z; `Board` is the prompt target |
| Pawnshop | 9.70 × 6.575 × 7.70 | 39 | Open-front trading kiosk, cartridges, pictogram sign; front +Z, `Counter` target; one shadowless light |
| Fountain | 10.80 × 4.90 × 10.80 | 64 | Separate two-tier fountain with open basin and stylized water drops |

Every individual model has its pivot at the center of its footprint, Y=0; lowest geometry at Y=0. All native parts anchored. Structural pieces collide, decorative details do not; Seat retains touch/query for sitting. PointLight Shadows=false. Each model is below 250 Parts.

## Import

Use `models/*.rbxm` (binary) or `models/*.rbxmx` (XML) as templates in `ServerStorage.Upgrades`. Preserve exact model names. Preserve `PcSeat`, its boolean Public attribute, `Board`, and `Counter`. The current ModelFactory template-cloning path must select these templates rather than append fallback geometry. No gameplay changes are included.

`Park_Objects_Layout.rbxm/.rbxmx` is **preview/QA only**: it includes a copy of the existing Park landscape and six benches plus one board, kiosk and fountain. Do not import it on top of an existing Park. Individual models do not include landscape.

## Coordinates and integration findings

Verified against `origin/main` VISUAL.md, StartPark config and WorldService. Six benches retain radius28 at angles30,90,150,210,270,330; local −Z faces spawn. The assembled layout uses **approvedProposedLayout**, with no intersections against existing landscape, paths or other interactive models. `layout.json` and `VALIDATION.json` retain both the proposed placement and the current config findings.

| Object | Current game config | Proposed layout to implement in Dev2 | Yaw |
|---|---|---|---:|
| JobBoard | (0,0,12) | **(0,0,17)**, angle90/radius17 | 180° |
| Pawnshop | (0,0,−12) | **(−9.148114,0,−43.038494)**, angle258/radius44 | 12° |

**Required integration change:** currentConfig positions overlap GardenWalk (15 board/path Part pairs and26 kiosk/path pairs (including rounded path joins)). These old positions are recorded as findings only; they are **not** the delivered assembled scene. Keep the board near the plaza at radius17 and move the full-sized pawn kiosk into the open lawn beside the promenade at angle258/radius44. The kiosk could not fit near its old position while retaining the existing paths, trees and bench approaches. Its new front faces spawn; its entry apron meets the walkable promenade.

The proposed scene passes actual native Part footprint checks against path segments and rounded joins, landscape geometry and all other interactive objects. It also reserves unobstructed **6stud-deep ×6stud-wide front approaches** for board/kiosk and **3stud-deep ×5.45stud-wide front approaches** for every bench; none intersects another object, landscape prop or the central16×16 plaza. Access aprons may meet walkable paths intentionally. No game code was changed: Dev2 must update placement before using this proposed layout.

Fountain is intentionally separate from the central plaza, at **(43.466662,0,11.646857)**, angle15/radius45. At that placement it clears the existing promenade and trees. This is a proposed placement, not an existing WorldService placement: Dev2 must instantiate Fountain there before StartParkService collects obstacles. Do not move it into the open 16×16 spawn plaza. Keep its model name `Fountain` so the service's recursive lookup registers it. Preserve existing Park/LandscapeObstacles integration; do not register the entire landscape as one obstacle.

The entire 16×16 central plaza remains free. Y=0 placements follow current WorldService; Park meadow top is Y=.08 and paths about Y=.124, so model feet embed slightly in the shared ground as existing placement code does. Raising models needs a coordinated gameplay placement change; none was made here.

## Validation and reproduction

`VALIDATION.json` records dimensions, Part/light counts, pivot reconstruction, allowed classes, Seat attribute, conservative OBB checks against actual existing landscape geometry, object/object checks and path footprint results. All four XML models and assembled layout converted successfully to binary through Rojo. `previews/` contains individual renders and an assembled park view.

Run `python3 source/validate_render.py` from this kit's parent workspace. Requirements: Python3, Pillow, numpy; Rojo at `/Users/erland/.local/gst-tools/rojo`. The assembled layout/validation reads the sibling `roblox-park-kit/source/build_park.py` without changing it. `build_objects.py` alone exports individual XML models independently. Renderer uses CPU rasterization; no Blender or external meshes required.

Not tested inside Roblox Studio: check R15 sitting/leg clearance, walking to both sides of the bench, prompts, cartridge raycasts, and phone performance after integration. Offline checks do not replace these play tests. Current config mismatch is explicitly retained as an integration finding rather than exported as intersecting geometry.
