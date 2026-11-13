# Cartoon building concepts — batch 2, #359 / #26

Four original 1024×1024 PNG concept views, three-quarter front/right: Garage, Office, Skyscraper (three storeys), Pawnshop. Bright chunky silhouettes, warm windows, smooth surfaces, no texture noise or letters. Built-in image_gen; exact prompts and unmodified originals retained in PROMPTS.md and source/. PREVIEW.png compares the four buildings.

These are design references for Dev 1 to build in Studio, as requested by the latest #26 brief (10 November 09:28:55Z). They are not RBXM models and do not replace current live buildings. This supersedes the earlier same-day request for Astra to directly model the three buildings; no duplicate model work is started here.

Modeling handoff: keep current template names, plot footprint, purchase/door/desk coordinates, pivots and clearances from the live place. Adapt these facade concepts around those constraints. Target at most 150 native parts per building, scripts excluded, pivot at base center, no volume intersections. Part count and layout cannot be validated from a PNG.

| Concept | Main forms | Main palette |
|---|---|---|
| concept_garage.png | gable roof, broad open portal, computer sign | orange roof, teal frames, warm cream walls |
| concept_office.png | two floors, broad window bays, controller emblem | teal roof, blue structural edges, cream walls |
| concept_skyscraper.png | three visible floors, broad entrance, star emblem | violet roof, blue edges, pale lavender walls |
| concept_pawnshop.png | kiosk, open counter, large blank cartridge sign | coral roof, teal posts, golden trim |

The blank cartridge sign is a shape cue; localized shop text remains a runtime GUI, not lettering baked into art. Window glow is a lighting direction, not a demand for dozens of lights. Round bevels and roof curves can be simplified to wedges/cylinders while retaining the silhouette. Interiors visible through windows are composition cues, not a floor plan.

VALIDATION.md/json describe offline image checks. Studio modeling, geometry checks, mobile FPS and owner acceptance remain pending.
